defmodule Unit.ReqRespTest do
  alias Fixtures.Block
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.P2P.ReqResp
  alias LambdaEthereumConsensus.Utils.BitVector
  alias Types.BeaconBlocksByRangeRequest

  use ExUnit.Case
  # TODO: try not to use patch
  use Patch
  doctest ReqResp

  setup do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.merge(config: MainnetConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))
  end

  defp assert_decode_equals(message, ssz_schema, expected) do
    request = Base.decode16!(message)
    assert ReqResp.decode_response_chunk(request, ssz_schema) == {:ok, expected}
    <<0>> <> rest = request
    assert ReqResp.decode_request(rest, ssz_schema) == {:ok, expected}
  end

  defp assert_u64(message, expected),
    do: assert_decode_equals(message, TypeAliases.uint64(), expected)

  def assert_metadata(message, expected),
    do: assert_decode_equals(message, Types.Metadata, expected)

  test "Ping 0",
    do: assert_u64("0008FF060000734E61507059010C0000290398070000000000000000", 0)

  test "Ping 1",
    do: assert_u64("0008FF060000734E61507059010C00000175DE410100000000000000", 1)

  test "Ping 5",
    do: assert_u64("0008FF060000734E61507059010C0000EAB2043E0500000000000000", 5)

  test "Ping 67",
    do: assert_u64("0008FF060000734E61507059010C0000B18525A04300000000000000", 67)

  test "Ping error" do
    msg =
      "011CFF060000734E6150705900220000EF99F84B1C6C4661696C656420746F20756E636F6D7072657373206D657373616765"
      |> Base.decode16!()

    expected_result = {:error, {1, {:ok, "Failed to uncompress message"}}}

    assert ReqResp.decode_response_chunk(msg, TypeAliases.uint64()) == expected_result
  end

  test "GetMetadata 0" do
    assert_metadata(
      "0011FF060000734E6150705901150000F1D17CFF0008000000000000FFFFFFFFFFFFFFFF0F",
      %Types.Metadata{
        seq_number: 2048,
        attnets: BitVector.new(0xFFFFFFFFFFFFFFFF, 64),
        syncnets: BitVector.new(0xF, 4)
      }
    )
  end

  test "GetMetadata 1" do
    assert_metadata(
      "0011FF060000734E6150705901150000CD11E7D53A03000000000000FFFFFFFFFFFFFFFF0F",
      %Types.Metadata{
        seq_number: 826,
        attnets: BitVector.new(0xFFFFFFFFFFFFFFFF, 64),
        syncnets: BitVector.new(0xF, 4)
      }
    )
  end

  test "GetMetadata 2" do
    assert_metadata(
      "0011FF060000734E61507059000A0000B3A056EA1100003E0100",
      %Types.Metadata{
        seq_number: 0,
        attnets: BitVector.new(0, 64),
        syncnets: BitVector.new(0, 4)
      }
    )
  end

  test "BeaconBlocksByRange round trip" do
    count = 5
    request = %BeaconBlocksByRangeRequest{start_slot: 15_125, count: count}
    context_bytes = "abcd"
    patch(BeaconChain, :get_fork_digest, context_bytes)
    blocks = Enum.map(1..count, fn _ -> Block.signed_beacon_block() end)

    result =
      ReqResp.encode_request(request)
      |> ReqResp.decode_request(BeaconBlocksByRangeRequest)

    assert result == {:ok, request}

    response =
      Enum.map(blocks, &{:ok, {&1, context_bytes}})
      |> ReqResp.encode_response()
      |> ReqResp.decode_response()

    assert response == {:ok, blocks}
  end

  test "BeaconBlocksByRoot round trip" do
    count = 5
    request = Enum.map(1..count, &<<&1::256>>)
    context_bytes = "abcd"
    patch(BeaconChain, :get_fork_digest, context_bytes)
    blocks = Enum.map(1..count, fn _ -> Block.signed_beacon_block() end)

    result =
      ReqResp.encode_request({request, TypeAliases.beacon_blocks_by_root_request()})
      |> ReqResp.decode_request(TypeAliases.beacon_blocks_by_root_request())

    assert result == {:ok, request}

    response =
      Enum.map(blocks, &{:ok, {&1, context_bytes}})
      |> ReqResp.encode_response()
      |> ReqResp.decode_response()

    assert response == {:ok, blocks}
  end
end
