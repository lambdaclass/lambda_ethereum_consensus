defmodule Fixtures.Block do
  def beacon_block() do
    %SszTypes.BeaconBlock{
      parent_root: RandomBinary.root(),
      slot: 1,
      proposer_index: 1,
      state_root: RandomBinary.root(),
      body: beacon_block_body()
    }
  end

  def beacon_block_body() do
    %SszTypes.BeaconBlockBody{
      randao_reveal: RandomBinary.bls_signature(),
      eth1_data: eth1_data(),
      graffiti: RandomBinary.hash(),
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

  def eth1_data() do
    %SszTypes.Eth1Data{
      deposit_root: RandomBinary.root(),
      deposit_count: 1,
      block_hash: RandomBinary.hash()
    }
  end

  @spec sync_aggregate :: SszTypes.SyncAggregate.t()
  def sync_aggregate() do
    %SszTypes.SyncAggregate{
      sync_committee_bits: RandomBinary.sync_committee_bits(),
      sync_committee_signature: RandomBinary.bls_signature()
    }
  end

  @spec execution_payload :: SszTypes.ExecutionPayload.t()
  def execution_payload() do
    %SszTypes.ExecutionPayload{
      parent_hash: RandomBinary.hash(),
      fee_recipient: RandomBinary.execution_address(),
      state_root: RandomBinary.root(),
      receipts_root: RandomBinary.root(),
      logs_bloom: RandomBinary.generate(256),
      prev_randao: RandomBinary.hash(),
      block_number: 256,
      gas_limit: 256,
      gas_used: 256,
      timestamp: 256,
      extra_data: RandomBinary.generate(30),
      base_fee_per_gas: 256,
      block_hash: RandomBinary.generate(32),
      transactions: [],
      withdrawals: []
    }
  end
end

defmodule RandomBinary do
  @doc """
  Generate a random binary of n bytes.
  """
  @spec generate(integer()) :: binary()
  def generate(n) when is_integer(n) and n > 0 do
    :crypto.strong_rand_bytes(n)
  end

  def hash() do
    generate(32)
  end

  def root() do
    generate(32)
  end

  def bls_signature() do
    generate(96)
  end

  def sync_committee_bits() do
    generate(64)
  end

  def execution_address() do
    generate(20)
  end
end
