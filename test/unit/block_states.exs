defmodule BlockStatesTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.Store.BlockStates
  alias Types.BeaconState
  alias Types.StateInfo

  setup_all do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.put(:config, MinimalConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))
  end

  setup %{tmp_dir: tmp_dir} do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.put(:config, MinimalConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))

    start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: tmp_dir})
    start_link_supervised!(LambdaEthereumConsensus.Store.BlockStates)
    :ok
  end

  @tag :tmp_dir
  test "Encoded field is calculated if not provided" do
    {encoded, decoded} = get_state()

    {:ok, state_info_1} = StateInfo.from_beacon_state(decoded, encoded: encoded)
    {:ok, state_info_2} = StateInfo.from_beacon_state(decoded)

    assert state_info_1 == state_info_2
  end

  @tag :tmp_dir
  test "Save and load state" do
    {encoded, decoded} = get_state()

    {:ok, state_info} = StateInfo.from_beacon_state(decoded, encoded: encoded)

    BlockStates.store_state_info(state_info)
    loaded_state = BlockStates.get_state_info(state_info.block_root)

    assert state_info == loaded_state
  end

  defp get_state() do
    {:ok, encoded} =
      File.read!("test/fixtures/validator/proposer/beacon_state.ssz_snappy")
      |> :snappyer.decompress()

    {:ok, decoded} = SszEx.decode(encoded, BeaconState)
    {encoded, decoded}
  end
end
