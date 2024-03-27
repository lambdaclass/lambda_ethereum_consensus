defmodule LambdaEthereumConsensus.Validator.Proposer do
  @moduledoc """
  Validator proposer duties.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Utils.BitVector

  alias Types.BeaconState

  @spec construct_block(BeaconState.t(), Types.validator_index(), Bls.privkey()) ::
          {:ok, Types.SignedBeaconBlock.t()}
  def construct_block(%BeaconState{} = state, proposer_index, privkey) do
    # NOTE: the state is at the start of the block's slot
    block = %Types.BeaconBlock{
      slot: state.slot,
      proposer_index: proposer_index,
      parent_root:
        <<123, 234, 141, 179, 46, 87, 30, 35, 136, 140, 35, 5, 42, 50, 198, 192, 151, 177, 18,
          239, 141, 142, 107, 105, 107, 140, 88, 112, 50, 69, 47, 228>>,
      state_root:
        <<173, 81, 100, 66, 197, 84, 137, 102, 200, 161, 182, 241, 222, 150, 201, 211, 80, 154,
          64, 171, 115, 238, 58, 66, 103, 74, 220, 170, 8, 126, 22, 61>>,
      body: %Types.BeaconBlockBody{
        randao_reveal: get_epoch_signature(state, privkey),
        eth1_data: get_eth1_data(),
        graffiti:
          <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0>>,
        proposer_slashings: [],
        attester_slashings: [],
        attestations: [],
        deposits: [],
        voluntary_exits: [],
        bls_to_execution_changes: [],
        blob_kzg_commitments: [],
        sync_aggregate: get_sync_aggregate(),
        execution_payload: get_execution_payload()
      }
    }

    signed_block = %Types.SignedBeaconBlock{
      message: block,
      signature: get_block_signature(state, block, privkey)
    }

    {:ok, signed_block}
  end

  @spec get_epoch_signature(BeaconState.t(), Bls.privkey()) ::
          Types.bls_signature()
  def get_epoch_signature(state, privkey) do
    epoch = Misc.compute_epoch_at_slot(state.slot)
    domain = Accessors.get_domain(state, Constants.domain_randao(), epoch)
    signing_root = Misc.compute_signing_root(epoch, TypeAliases.epoch(), domain)
    {:ok, signature} = Bls.sign(privkey, signing_root)
    signature
  end

  @spec get_block_signature(BeaconState.t(), Types.BeaconBlock.t(), Bls.privkey()) ::
          Types.bls_signature()
  def get_block_signature(state, block, privkey) do
    domain = Accessors.get_domain(state, Constants.domain_beacon_proposer())
    signing_root = Misc.compute_signing_root(block, domain)
    {:ok, signature} = Bls.sign(privkey, signing_root)
    signature
  end

  defp get_eth1_data do
    %Types.Eth1Data{
      deposit_root:
        <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0>>,
      deposit_count: 64,
      block_hash:
        <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0>>
    }
  end

  defp get_execution_payload do
    %Types.ExecutionPayload{
      parent_hash:
        <<212, 46, 177, 5, 71, 181, 49, 8, 203, 152, 49, 250, 205, 230, 188, 78, 249, 162, 232,
          114, 146, 86, 123, 101, 230, 11, 67, 235, 239, 164, 41, 159>>,
      fee_recipient: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
      state_root: "                                ",
      receipts_root:
        <<29, 204, 77, 232, 222, 199, 93, 122, 171, 133, 181, 103, 182, 204, 212, 26, 211, 18, 69,
          27, 148, 138, 116, 19, 240, 161, 66, 253, 64, 212, 147, 71>>,
      logs_bloom:
        <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
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
      sync_committee_signature:
        <<192, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0>>
    }
  end
end
