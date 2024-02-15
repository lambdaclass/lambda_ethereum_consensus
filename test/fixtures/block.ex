defmodule Fixtures.Block do
  @moduledoc """
  Fixtures for blocks.
  """

  alias Fixtures.Random
  alias LambdaEthereumConsensus.Utils.BitVector

  @spec signed_beacon_block :: Types.SignedBeaconBlock.t()
  def signed_beacon_block do
    %Types.SignedBeaconBlock{
      message: beacon_block(),
      signature: Random.bls_signature()
    }
  end

  @spec beacon_block :: Types.BeaconBlock.t()
  def beacon_block do
    %Types.BeaconBlock{
      parent_root: Random.root(),
      slot: Random.uint64(),
      proposer_index: Random.uint64(),
      state_root: Random.root(),
      body: beacon_block_body()
    }
  end

  @spec beacon_block_body :: Types.BeaconBlockBody.t()
  def beacon_block_body do
    %Types.BeaconBlockBody{
      randao_reveal: Random.bls_signature(),
      eth1_data: eth1_data(),
      graffiti: Random.hash32(),
      proposer_slashings: [],
      attester_slashings: [],
      attestations: [],
      deposits: [],
      voluntary_exits: [],
      sync_aggregate: sync_aggregate(),
      execution_payload: execution_payload(),
      bls_to_execution_changes: []
    }
  end

  @spec eth1_data :: Types.Eth1Data.t()
  def eth1_data do
    %Types.Eth1Data{
      deposit_root: Random.root(),
      deposit_count: Random.uint64(),
      block_hash: Random.hash32()
    }
  end

  @spec sync_aggregate :: Types.SyncAggregate.t()
  def sync_aggregate do
    %Types.SyncAggregate{
      sync_committee_bits: Random.sync_committee_bits(),
      sync_committee_signature: Random.bls_signature()
    }
  end

  @spec execution_payload :: Types.ExecutionPayload.t()
  def execution_payload do
    %Types.ExecutionPayload{
      parent_hash: Random.hash32(),
      fee_recipient: Random.execution_address(),
      state_root: Random.root(),
      receipts_root: Random.root(),
      logs_bloom: :binary.bin_to_list(Random.binary(256)),
      prev_randao: Random.hash32(),
      block_number: Random.uint64(),
      gas_limit: Random.uint64(),
      gas_used: Random.uint64(),
      timestamp: Random.uint64(),
      extra_data: :binary.bin_to_list(Random.binary(30)),
      base_fee_per_gas: Random.uint64(),
      block_hash: Random.binary(32),
      transactions: [],
      withdrawals: []
    }
  end

  @spec fork :: Types.Fork.t()
  def fork do
    %Types.Fork{
      previous_version: Random.binary(4),
      current_version: Random.binary(4),
      epoch: Random.uint64()
    }
  end

  @spec beacon_block_header :: Types.BeaconBlockHeader.t()
  def beacon_block_header do
    %Types.BeaconBlockHeader{
      slot: Random.uint64(),
      proposer_index: Random.uint64(),
      parent_root: Random.root(),
      state_root: Random.root(),
      body_root: Random.root()
    }
  end

  @spec checkpoint :: Types.Checkpoint.t()
  def checkpoint do
    %Types.Checkpoint{
      epoch: Random.uint64(),
      root: Random.root()
    }
  end

  @spec sync_committee :: Types.SyncCommittee.t()
  def sync_committee do
    %Types.SyncCommittee{
      pubkeys: [],
      aggregate_pubkey: Random.binary(48)
    }
  end

  @spec execution_payload_header :: Types.ExecutionPayloadHeader.t()
  def execution_payload_header do
    %Types.ExecutionPayloadHeader{
      parent_hash: Random.binary(32),
      fee_recipient: Random.binary(20),
      state_root: Random.root(),
      receipts_root: Random.root(),
      logs_bloom: [],
      prev_randao: Random.binary(32),
      block_number: Random.uint64(),
      gas_limit: Random.uint64(),
      gas_used: Random.uint64(),
      timestamp: Random.uint64(),
      extra_data: [],
      base_fee_per_gas: Random.uint256(),
      block_hash: Random.binary(32),
      transactions_root: Random.root(),
      withdrawals_root: Random.root()
    }
  end

  @spec beacon_state :: Types.BeaconState.t()
  def beacon_state do
    %Types.BeaconState{
      genesis_time: Random.uint64(),
      genesis_validators_root: Random.root(),
      slot: Random.uint64(),
      fork: fork(),
      latest_block_header: beacon_block_header(),
      block_roots: [],
      state_roots: [],
      historical_roots: [],
      eth1_data: eth1_data(),
      eth1_data_votes: [],
      eth1_deposit_index: Random.uint64(),
      validators: Aja.Vector.new(),
      balances: Aja.Vector.new(),
      randao_mixes: Aja.Vector.new(),
      slashings: [],
      previous_epoch_participation: Aja.Vector.new(),
      current_epoch_participation: Aja.Vector.new(),
      justification_bits: BitVector.to_bytes(BitVector.new(4)),
      previous_justified_checkpoint: checkpoint(),
      current_justified_checkpoint: checkpoint(),
      finalized_checkpoint: checkpoint(),
      inactivity_scores: [],
      current_sync_committee: sync_committee(),
      next_sync_committee: sync_committee(),
      latest_execution_payload_header: execution_payload_header(),
      next_withdrawal_index: Random.uint64(),
      next_withdrawal_validator_index: Random.uint64(),
      historical_summaries: []
    }
  end
end
