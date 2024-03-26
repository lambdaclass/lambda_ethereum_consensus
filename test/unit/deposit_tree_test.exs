defmodule Unit.DepositTreeTest do
  @moduledoc false

  use ExUnit.Case

  alias Types.Eth1Data
  alias LambdaEthereumConsensus.SszEx
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias Types.DepositData
  alias Types.DepositTree
  alias Types.DepositTreeSnapshot

  doctest DepositTree

  # Testcases taken from EIP-4881
  @snapshot_1 %DepositTreeSnapshot{
    finalized: [
      Base.decode16!("7AF7DA533B0DC64B690CB0604F5A81E40ED83796DD14037EA3A55383B8F0976A")
    ],
    deposit_root:
      Base.decode16!("253F73460B66BA0B490A8F17029566B03C0690A584E262ACC2BE97C969BC65A6"),
    deposit_count: 1,
    execution_block_hash:
      Base.decode16!("AB6F0411B911F0D66539663DC6B41ED58BB4870CD3AE879E25C7BEE8CD6D6F22"),
    execution_block_height: 2
  }

  @deposit_data_2 %DepositData{
    pubkey:
      Base.decode16!(
        "B89BEBC699769726A318C8E9971BD3171297C61AEA4A6578A7A4F94B547DCBA5BAC16A89108B6B6A1FE3695D1A874A0B"
      ),
    withdrawal_credentials:
      Base.decode16!("0000000000000000000000000000000000000000000000000000000000000000"),
    amount: 32_000_000_000,
    signature:
      Base.decode16!(
        "B24D74BD23B52C41567305B6AECDC73DD53AEA59FA997C0D6205531CE70CC32282DBF9963DDE89297522FDC2C541EB0909472145805953A2298AA56160784C23B3905ED0EC17C4775B61CECB922A0D0E5241521387FC38184AFE735C2CE399AD"
      )
  }

  @snapshot_2 %DepositTreeSnapshot{
    finalized: [
      Base.decode16!("B6A04FB079B0153E6E555FD79BB89187C9386B2230F4020BD81558FECA702982")
    ],
    deposit_root:
      Base.decode16!("072080F22BF66504D6AA2B978C581E34637912AC191442AF4F090DC5773D8936"),
    deposit_count: 2,
    execution_block_hash:
      Base.decode16!("4E41A313CB3461E3154E76F87EC1BDA35A48876529EAF3B99E335F43280C8D66"),
    execution_block_height: 3
  }

  test "initialize deposit tree from snapshot" do
    root = DepositTree.from_snapshot(@snapshot_1) |> DepositTree.get_root()

    expected_root =
      Base.decode16!("253F73460B66BA0B490A8F17029566B03C0690A584E262ACC2BE97C969BC65A6")

    assert root == expected_root
  end

  test "update tree with a deposit" do
    root =
      DepositTree.from_snapshot(@snapshot_1)
      |> DepositTree.push_leaf(@deposit_data_2)
      |> DepositTree.get_root()

    expected_root =
      Base.decode16!("072080F22BF66504D6AA2B978C581E34637912AC191442AF4F090DC5773D8936")

    assert root == expected_root
  end

  test "generated proof is valid" do
    index = 1

    tree =
      DepositTree.from_snapshot(@snapshot_1)
      |> DepositTree.push_leaf(@deposit_data_2)

    deposit_root = DepositTree.get_root(tree)

    data_root = SszEx.hash_tree_root!(@deposit_data_2)

    assert {:ok, {leaf, proof}} = DepositTree.get_proof(tree, index)
    assert data_root == leaf

    depth = Constants.deposit_contract_tree_depth() + 1

    assert Predicates.valid_merkle_branch?(data_root, proof, depth, index, deposit_root)
  end

  test "update and finalize tree equals new from snapshot" do
    eth1_data = %Eth1Data{
      deposit_root: @snapshot_2.deposit_root,
      deposit_count: @snapshot_2.deposit_count,
      block_hash: @snapshot_2.execution_block_hash
    }

    tree =
      DepositTree.from_snapshot(@snapshot_1)
      |> DepositTree.push_leaf(@deposit_data_2)
      |> DepositTree.finalize(eth1_data, @snapshot_2.execution_block_height)

    assert tree == DepositTree.from_snapshot(@snapshot_2)
  end
end
