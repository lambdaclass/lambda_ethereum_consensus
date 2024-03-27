defmodule LambdaEthereumConsensus.Validator.Proposer do
  @moduledoc """
  Validator proposer duties.
  """
  alias LambdaEthereumConsensus.P2P.Gossip.OperationsCollector
  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Utils.BitVector
  alias LambdaEthereumConsensus.Validator.BlockRequest

  alias Types.BeaconBlock
  alias Types.BeaconState
  alias Types.SignedBeaconBlock

  @spec construct_block(BeaconState.t(), BlockRequest.t(), Bls.privkey()) ::
          {:ok, SignedBeaconBlock.t()} | {:error, String.t()}
  def construct_block(%BeaconState{} = state, %BlockRequest{} = request, privkey) do
    with {:ok, block_request} <- BlockRequest.validate(request, state) do
      block = %BeaconBlock{
        slot: block_request.slot,
        proposer_index: block_request.proposer_index,
        parent_root: Misc.get_latest_block_hash(state),
        state_root: <<0::256>>,
        body: construct_block_body(state, block_request, privkey)
      }

      seal_block(state, block, privkey)
    end
  end

  @spec fetch_operations_for_block() :: %{
          proposer_slashings: [Types.ProposerSlashing.t()],
          attester_slashings: [Types.AttesterSlashing.t()],
          attestations: [Types.Attestation.t()],
          voluntary_exits: [Types.VoluntaryExit.t()],
          bls_to_execution_changes: [Types.SignedBLSToExecutionChange.t()]
        }
  def fetch_operations_for_block do
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

  defp construct_block_body(state, request, privkey) do
    %Types.BeaconBlockBody{
      randao_reveal: get_epoch_signature(state, request.slot, privkey),
      eth1_data: request.eth1_data,
      graffiti: request.graffiti_message,
      proposer_slashings: request.proposer_slashings,
      attester_slashings: request.attester_slashings,
      attestations: request.attestations,
      deposits: [],
      voluntary_exits: request.voluntary_exits,
      bls_to_execution_changes: request.bls_to_execution_changes,
      blob_kzg_commitments: [],
      sync_aggregate: get_sync_aggregate(),
      execution_payload: get_execution_payload()
    }
  end

  @spec seal_block(BeaconState.t(), BeaconBlock.t(), Bls.privkey()) :: {:ok, BeaconBlock.t()}
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

  defp get_execution_payload do
    %Types.ExecutionPayload{
      parent_hash:
        <<212, 46, 177, 5, 71, 181, 49, 8, 203, 152, 49, 250, 205, 230, 188, 78, 249, 162, 232,
          114, 146, 86, 123, 101, 230, 11, 67, 235, 239, 164, 41, 159>>,
      fee_recipient: <<0::160>>,
      state_root: "                                ",
      receipts_root:
        <<29, 204, 77, 232, 222, 199, 93, 122, 171, 133, 181, 103, 182, 204, 212, 26, 211, 18, 69,
          27, 148, 138, 116, 19, 240, 161, 66, 253, 64, 212, 147, 71>>,
      logs_bloom: <<0::2048>>,
      prev_randao:
        <<218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218,
          218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218, 218>>,
      block_number: 1,
      gas_limit: 30_000_000,
      gas_used: 0,
      timestamp: 6,
      extra_data: "",
      base_fee_per_gas: 1_000_000_000,
      block_hash:
        <<140, 253, 138, 145, 253, 25, 211, 25, 133, 168, 106, 67, 9, 119, 177, 247, 197, 188, 20,
          36, 18, 109, 135, 83, 175, 220, 222, 84, 168, 70, 6, 62>>,
      transactions: [],
      withdrawals: [],
      blob_gas_used: 0,
      excess_blob_gas: 0
    }
  end

  defp get_sync_aggregate do
    %Types.SyncAggregate{
      sync_committee_bits: ChainSpec.get("SYNC_COMMITTEE_SIZE") |> BitVector.new(),
      sync_committee_signature: <<192, 0::760>>
    }
  end
end
