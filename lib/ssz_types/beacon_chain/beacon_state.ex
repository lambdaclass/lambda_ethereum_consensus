defmodule SszTypes.BeaconState do
  @moduledoc """
  Struct definition for `BeaconState`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  @default_execution_payload_header %SszTypes.ExecutionPayloadHeader{
    parent_hash: <<0::256>>,
    fee_recipient: <<0::160>>,
    state_root: <<0::256>>,
    receipts_root: <<0::256>>,
    logs_bloom: <<0::2048>>,
    prev_randao: <<0::256>>,
    block_number: 0,
    gas_limit: 0,
    gas_used: 0,
    timestamp: 0,
    extra_data: "",
    base_fee_per_gas: 0,
    block_hash: <<0::256>>,
    transactions_root: <<0::256>>,
    withdrawals_root: <<0::256>>
  }

  fields = [
    :genesis_time,
    :genesis_validators_root,
    :slot,
    :fork,
    :latest_block_header,
    :block_roots,
    :state_roots,
    :historical_roots,
    :eth1_data,
    :eth1_data_votes,
    :eth1_deposit_index,
    :validators,
    :balances,
    :randao_mixes,
    :slashings,
    :previous_epoch_participation,
    :current_epoch_participation,
    :justification_bits,
    :previous_justified_checkpoint,
    :current_justified_checkpoint,
    :finalized_checkpoint,
    :inactivity_scores,
    :current_sync_committee,
    :next_sync_committee,
    :latest_execution_payload_header,
    :next_withdrawal_index,
    :next_withdrawal_validator_index,
    :historical_summaries
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # Versioning
          genesis_time: SszTypes.uint64(),
          genesis_validators_root: SszTypes.root(),
          slot: SszTypes.slot(),
          fork: SszTypes.Fork.t(),
          # History
          latest_block_header: SszTypes.BeaconBlockHeader.t(),
          block_roots: list(SszTypes.root()),
          state_roots: list(SszTypes.root()),
          # Frozen in Capella, replaced by historical_summaries
          historical_roots: list(SszTypes.root()),
          # Eth1
          eth1_data: SszTypes.Eth1Data.t(),
          eth1_data_votes: list(SszTypes.Eth1Data.t()),
          eth1_deposit_index: SszTypes.uint64(),
          # Registry
          validators: list(SszTypes.Validator.t()),
          balances: list(SszTypes.gwei()),
          # Randomness
          randao_mixes: list(SszTypes.bytes32()),
          # Slashings
          # Per-epoch sums of slashed effective balances
          slashings: list(SszTypes.gwei()),
          # Participation
          previous_epoch_participation: list(SszTypes.participation_flags()),
          current_epoch_participation: list(SszTypes.participation_flags()),
          # Finality
          # Bit set for every recent justified epoch
          justification_bits: SszTypes.bitvector(),
          previous_justified_checkpoint: SszTypes.Checkpoint.t(),
          current_justified_checkpoint: SszTypes.Checkpoint.t(),
          finalized_checkpoint: SszTypes.Checkpoint.t(),
          # Inactivity
          inactivity_scores: list(SszTypes.uint64()),
          # Sync
          current_sync_committee: SszTypes.SyncCommittee.t(),
          next_sync_committee: SszTypes.SyncCommittee.t(),
          # Execution
          # [Modified in Capella]
          latest_execution_payload_header: SszTypes.ExecutionPayloadHeader.t(),
          # Withdrawals
          # [New in Capella]
          next_withdrawal_index: SszTypes.withdrawal_index(),
          # [New in Capella]
          next_withdrawal_validator_index: SszTypes.withdrawal_index(),
          # Deep history valid from Capella onwards
          # [New in Capella]
          historical_summaries: list(SszTypes.HistoricalSummary.t())
        }

  @doc """
  Checks if state is pre or post merge
  """
  @spec is_merge_transition_complete(SszTypes.BeaconState.t()) :: boolean()
  def is_merge_transition_complete(state) do
    state.latest_execution_payload_header != @default_execution_payload_header
  end
end
