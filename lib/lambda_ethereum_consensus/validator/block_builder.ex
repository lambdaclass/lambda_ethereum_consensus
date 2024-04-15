defmodule LambdaEthereumConsensus.Validator.BlockBuilder do
  @moduledoc """
  Module that constructs a block from head block.
  """

  alias LambdaEthereumConsensus.Execution.ExecutionChain
  alias LambdaEthereumConsensus.Execution.ExecutionClient
  alias LambdaEthereumConsensus.P2P.Gossip.OperationsCollector
  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Operations
  alias LambdaEthereumConsensus.Store.BlobDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.BlockStates
  alias LambdaEthereumConsensus.Utils.BitVector
  alias LambdaEthereumConsensus.Utils.Randao
  alias LambdaEthereumConsensus.Validator.BuildBlockRequest
  alias Types.BeaconBlock
  alias Types.BeaconBlockHeader
  alias Types.BeaconState
  alias Types.BlobSidecar
  alias Types.Eth1Data
  alias Types.ExecutionPayload
  alias Types.SignedBeaconBlock
  alias Types.SignedBeaconBlockHeader

  require Logger

  @spec build_block(LambdaEthereumConsensus.Validator.BuildBlockRequest.t()) ::
          {:error, any()} | {:ok, Types.SignedBeaconBlock.t()}
  def build_block(%BuildBlockRequest{parent_root: parent_root, slot: proposed_slot} = request) do
    head_block = Blocks.get_block!(parent_root)
    head_hash = head_block.body.execution_payload.block_hash
    pre_state = BlockStates.get_state!(parent_root)

    with {:ok, mid_state} <- StateTransition.process_slots(pre_state, proposed_slot),
         {:ok, finalized_hash} <- get_finalized_block_hash(mid_state),
         {:ok, {execution_payload, blobs_bundle}} <-
           build_execution_block(mid_state, parent_root, head_hash, finalized_hash),
         {:ok, eth1_vote} <- fetch_eth1_data(proposed_slot, mid_state),
         {:ok, block_request} <-
           request
           |> Map.merge(fetch_operations_for_block())
           |> Map.put_new_lazy(:deposits, fn -> fetch_deposits(mid_state, eth1_vote) end)
           |> Map.put(:blob_kzg_commitments, blobs_bundle.commitments)
           |> BuildBlockRequest.validate(pre_state),
         {:ok, block} <-
           construct_beacon_block(
             mid_state,
             block_request,
             execution_payload,
             eth1_vote
           ),
         {:ok, signed_block} <- seal_block(pre_state, block, block_request.privkey),
         :ok <- store_blobs(signed_block, blobs_bundle) do
      {:ok, signed_block}
    end
  end

  @spec construct_beacon_block(
          BeaconState.t(),
          BuildBlockRequest.t(),
          ExecutionPayload.t(),
          Eth1Data.t()
        ) ::
          {:ok, BeaconBlock.t()} | {:error, String.t()}
  def construct_beacon_block(
        %BeaconState{} = state,
        %BuildBlockRequest{} = block_request,
        %ExecutionPayload{} = execution_payload,
        %Eth1Data{} = eth1_data
      ) do
    {:ok,
     %BeaconBlock{
       slot: block_request.slot,
       proposer_index: block_request.proposer_index,
       parent_root: block_request.parent_root,
       state_root: <<0::256>>,
       body: %Types.BeaconBlockBody{
         randao_reveal: get_epoch_signature(state, block_request.slot, block_request.privkey),
         eth1_data: eth1_data,
         graffiti: block_request.graffiti_message,
         proposer_slashings: block_request.proposer_slashings,
         attester_slashings: block_request.attester_slashings,
         attestations: block_request.attestations,
         deposits: block_request.deposits,
         voluntary_exits: block_request.voluntary_exits,
         bls_to_execution_changes: block_request.bls_to_execution_changes,
         blob_kzg_commitments: block_request.blob_kzg_commitments,
         sync_aggregate: get_sync_aggregate(),
         execution_payload: execution_payload
       }
     }}
  end

  @spec fetch_operations_for_block() :: %{
          proposer_slashings: [Types.ProposerSlashing.t()],
          attester_slashings: [Types.AttesterSlashing.t()],
          attestations: [Types.Attestation.t()],
          voluntary_exits: [Types.VoluntaryExit.t()],
          bls_to_execution_changes: [Types.SignedBLSToExecutionChange.t()]
        }
  defp fetch_operations_for_block do
    %{
      proposer_slashings:
        ChainSpec.get("MAX_PROPOSER_SLASHINGS") |> OperationsCollector.get_proposer_slashings(),
      attester_slashings:
        ChainSpec.get("MAX_ATTESTER_SLASHINGS") |> OperationsCollector.get_attester_slashings(),
      attestations: ChainSpec.get("MAX_ATTESTATIONS") |> OperationsCollector.get_attestations(),
      voluntary_exits:
        ChainSpec.get("MAX_VOLUNTARY_EXITS") |> OperationsCollector.get_voluntary_exits(),
      bls_to_execution_changes:
        ChainSpec.get("MAX_BLS_TO_EXECUTION_CHANGES")
        |> OperationsCollector.get_bls_to_execution_changes()
    }
  end

  defp fetch_deposits(state, eth1_vote) do
    %{eth1_data: eth1_data, eth1_deposit_index: range_start} = state

    processable_deposits = eth1_data.deposit_count - range_start
    range_end = min(processable_deposits, ChainSpec.get("MAX_DEPOSITS")) + range_start - 1

    ExecutionChain.get_deposits(eth1_data, eth1_vote, range_start..range_end)
  end

  @spec seal_block(BeaconState.t(), BeaconBlock.t(), Bls.privkey()) ::
          {:ok, SignedBeaconBlock.t()} | {:error, String.t()}
  def seal_block(pre_state, block, privkey) do
    wrapped_block = %SignedBeaconBlock{message: block, signature: <<0::768>>}

    with {:ok, post_state} <- StateTransition.state_transition(pre_state, wrapped_block, false) do
      %BeaconBlock{block | state_root: Ssz.hash_tree_root!(post_state)}
      |> sign_block(post_state, privkey)
      |> then(&{:ok, &1})
    end
  end

  defp sign_block(block, state, privkey) do
    signature = get_block_signature(state, block, privkey)
    %SignedBeaconBlock{message: block, signature: signature}
  end

  @spec get_epoch_signature(BeaconState.t(), Types.slot(), Bls.privkey()) ::
          Types.bls_signature()
  def get_epoch_signature(state, slot, privkey) do
    epoch = Misc.compute_epoch_at_slot(slot)
    domain = Accessors.get_domain(state, Constants.domain_randao(), epoch)
    signing_root = Misc.compute_signing_root(epoch, TypeAliases.epoch(), domain)
    {:ok, signature} = Bls.sign(privkey, signing_root)
    signature
  end

  @spec get_block_signature(BeaconState.t(), BeaconBlock.t(), Bls.privkey()) ::
          Types.bls_signature()
  def get_block_signature(state, block, privkey) do
    domain = Accessors.get_domain(state, Constants.domain_beacon_proposer())
    signing_root = Misc.compute_signing_root(block, domain)
    {:ok, signature} = Bls.sign(privkey, signing_root)
    signature
  end

  defp get_sync_aggregate do
    %Types.SyncAggregate{
      sync_committee_bits: ChainSpec.get("SYNC_COMMITTEE_SIZE") |> BitVector.new(),
      sync_committee_signature: <<192, 0::760>>
    }
  end

  @spec build_execution_block(BeaconState.t(), Types.root(), Types.hash32(), Types.hash32()) ::
          {:error, any()} | {:ok, {Types.ExecutionPayload.t(), Types.BlobsBundle.t()}}
  defp build_execution_block(state, head_root, head_payload_hash, finalized_payload_hash) do
    forkchoice_state = %{
      finalized_block_hash: finalized_payload_hash,
      head_block_hash: head_payload_hash,
      # TODO calculate safe block
      safe_block_hash: finalized_payload_hash
    }

    payload_attributes = %{
      timestamp: Misc.compute_timestamp_at_slot(state, state.slot),
      prev_randao: Randao.get_randao_mix(state.randao_mixes, Accessors.get_current_epoch(state)),
      suggested_fee_recipient: <<0::160>>,
      withdrawals: Operations.get_expected_withdrawals(state),
      parent_beacon_block_root: head_root
    }

    with {:ok, payload_id} <-
           ExecutionClient.notify_forkchoice_updated(
             forkchoice_state,
             payload_attributes
           ),
         # TODO: we need to balance a time that should be long enough to let the execution client
         # pack as many transactions as possible (more fees for us) while giving enough time to propagate
         # the block and have it included
         :ok <- Process.sleep(3000) do
      ExecutionClient.get_payload(payload_id)
    end
  end

  defp get_finalized_block_hash(state) do
    finalized_block = Blocks.get_block!(state.finalized_checkpoint.root)
    finalized_hash = finalized_block.body.execution_payload.block_hash
    {:ok, finalized_hash}
  end

  defp fetch_eth1_data(slot, head_state) do
    eth_vote =
      case ExecutionChain.get_eth1_vote(slot) do
        {:error, reason} ->
          # Default to the last eth1 data on error
          Logger.error("Failed to fetch eth1 vote: #{reason}")
          head_state.eth1_data

        {:ok, nil} ->
          head_state.eth1_data

        {:ok, eth1_data} ->
          eth1_data
      end

    {:ok, eth_vote}
  end

  @spec store_blobs(Types.SignedBeaconBlock.t(), Types.BlobsBundle.t()) :: :ok
  defp store_blobs(signed_block, blobs_bundle) do
    dbg(blobs_bundle)

    block = signed_block.message

    block_header = %BeaconBlockHeader{
      slot: block.slot,
      proposer_index: block.proposer_index,
      parent_root: block.parent_root,
      state_root: block.state_root,
      body_root: Ssz.hash_tree_root!(block.body)
    }

    signed_block_header = %SignedBeaconBlockHeader{
      message: block_header,
      signature: signed_block.signature
    }

    # dbg(block_header)

    sidecars =
      Enum.with_index(blobs_bundle.blobs, fn blob, index ->
        %BlobSidecar{
          index: index,
          blob: blob,
          kzg_commitment: blobs_bundle.commitments |> Enum.at(index),
          kzg_proof: blobs_bundle.proofs |> Enum.at(index),
          signed_block_header: signed_block_header,
          # TODO
          # compute_merkle_proof(
          #       block.body,
          #       get_generalized_index(BeaconBlockBody, 'blob_kzg_commitments', index),
          #    ),
          kzg_commitment_inclusion_proof: [<<0::256>>] |> Stream.cycle() |> Enum.take(17)
        }
      end)

    for blob_sidecar <- sidecars do
      dbg(blob_sidecar)
      BlobDb.store_blob(blob_sidecar)
    end

    :ok
  end
end
