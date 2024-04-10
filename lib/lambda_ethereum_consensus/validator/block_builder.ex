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
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.BlockStates
  alias LambdaEthereumConsensus.Utils.BitVector
  alias LambdaEthereumConsensus.Utils.Randao
  alias LambdaEthereumConsensus.Validator.BuildBlockRequest
  alias Types.Eth1Data
  alias Types.ExecutionPayload

  alias Types.BeaconBlock
  alias Types.BeaconState
  alias Types.SignedBeaconBlock

  require Logger

  @spec build_block(LambdaEthereumConsensus.Validator.BuildBlockRequest.t()) ::
          {:error, any()} | {:ok, Types.SignedBeaconBlock.t()}
  def build_block(%BuildBlockRequest{} = block_request) do
    parent_root = block_request.parent_root
    proposed_slot = block_request.slot

    pre_state = BlockStates.get_state!(parent_root)

    with {:ok, execution_payload} <-
           pre_state
           |> StateTransition.process_slots(proposed_slot)
           |> build_execution_block(parent_root) do
      construct_block(
        pre_state,
        block_request |> Map.merge(fetch_operations_for_block()),
        execution_payload,
        fetch_eth1_data(proposed_slot, pre_state)
      )
    end
  end

  @spec construct_block(
          BeaconState.t(),
          BuildBlockRequest.t(),
          ExecutionPayload.t(),
          Eth1Data.t()
        ) ::
          {:ok, SignedBeaconBlock.t()} | {:error, String.t()}
  defp construct_block(
         %BeaconState{} = state,
         %BuildBlockRequest{} = request,
         %ExecutionPayload{} = execution_payload,
         %Eth1Data{} = eth1_data
       ) do
    with {:ok, block_request} <- BuildBlockRequest.validate(request, state) do
      block = %BeaconBlock{
        slot: block_request.slot,
        proposer_index: block_request.proposer_index,
        parent_root: block_request.parent_root,
        state_root: <<0::256>>,
        body: construct_block_body(state, block_request, execution_payload, eth1_data)
      }

      seal_block(state, block, block_request.privkey)
    end
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

  defp construct_block_body(state, request, execution_payload, eth1_data) do
    %Types.BeaconBlockBody{
      randao_reveal: get_epoch_signature(state, request.slot, request.privkey),
      eth1_data: eth1_data,
      graffiti: request.graffiti_message,
      proposer_slashings: request.proposer_slashings,
      attester_slashings: request.attester_slashings,
      attestations: request.attestations,
      deposits: [],
      voluntary_exits: request.voluntary_exits,
      bls_to_execution_changes: request.bls_to_execution_changes,
      blob_kzg_commitments: [],
      sync_aggregate: get_sync_aggregate(),
      execution_payload: execution_payload
    }
  end

  @spec seal_block(BeaconState.t(), BeaconBlock.t(), Bls.privkey()) ::
          {:ok, SignedBeaconBlock.t()} | {:error, String.t()}
  defp seal_block(pre_state, block, privkey) do
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

  @spec build_execution_block(BeaconState.t(), Types.root()) ::
          {:error, any()} | {:ok, Types.ExecutionPayload.t()}
  defp build_execution_block(state, head_root) do
    head_block = Blocks.get_block!(head_root)
    finalized_block = Blocks.get_block!(state.finalized_checkpoint.root)

    forkchoice_state = %{
      finalized_block_hash: finalized_block.body.execution_payload.block_hash,
      head_block_hash: head_block.body.execution_payload.block_hash,
      # TODO calculate safe block
      safe_block_hash: finalized_block.body.execution_payload.block_hash
    }

    payload_attributes = %{
      timestamp: Misc.compute_timestamp_at_slot(state, state.slot),
      prev_randao: Randao.get_randao_mix(state.randao_mixes, Accessors.get_current_epoch(state)),
      suggested_fee_recipient: <<0::160>>,
      # TODO: add withdrawals
      withdrawals: [],
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
         :ok <- Process.sleep(3000),
         {:ok, execution_payload} <-
           ExecutionClient.get_payload(payload_id) do
      {:ok, execution_payload}
    end
  end

  defp fetch_eth1_data(slot, head_state) do
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
  end
end
