defmodule Unit.ReqRespTest do
  alias Fixtures.Block
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.P2P.ReqResp
  alias LambdaEthereumConsensus.Utils.BitVector
  alias Types.BeaconBlocksByRangeRequest
  alias Types.BeaconBlocksByRootRequest
  alias Types.BlobIdentifier
  alias Types.BlobSidecarsByRootRequest
  alias Types.SignedBeaconBlock

  use ExUnit.Case
  # TODO: try not to use patch
  use Patch
  doctest ReqResp

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

  defp assert_complex_request_roundtrip(%request_type{} = request, response) do
    [%response_type{} | _] = response
    context_bytes = "abcd"
    patch(BeaconChain, :get_fork_digest, context_bytes)
    payloads = Enum.map(response, fn x -> {:ok, {x, context_bytes}} end)

    decoded_request = ReqResp.encode_request(request) |> ReqResp.decode_request(request_type)
    assert decoded_request == {:ok, request}

    decoded_response = ReqResp.encode_response(payloads) |> ReqResp.decode_response(response_type)
    assert decoded_response == {:ok, payloads}
  end

  # TODO: fix this
  @tag :skip
  test "BeaconBlocksByRange round trip" do
    count = 5
    request = %BeaconBlocksByRangeRequest{start_slot: 15_125, count: count}
    response = Enum.map(1..count, fn _ -> Block.signed_beacon_block() end)
    assert_complex_request_roundtrip(request, response)
  end

  # TODO: fix this
  @tag :skip
  test "BeaconBlocksByRoot round trip" do
    count = 5
    request = %BeaconBlocksByRootRequest{body: Enum.map(1..count, &<<&1::256>>)}
    response = Enum.map(1..count, fn _ -> Block.signed_beacon_block() end)
    assert_complex_request_roundtrip(request, response)
  end

  # TODO: fix this
  @tag :skip
  test "BlobSidecarsByRange round trip" do
    count = 1
    request = %BeaconBlocksByRangeRequest{start_slot: 15_125, count: count}

    # TODO: generate randomly
    response =
      [
        %Types.BlobSidecar{
          index: 1,
          blob: <<152_521_252::(4096*32)*8>>,
          kzg_commitment: <<57_888::48*8>>,
          kzg_proof: <<6122::48*8>>,
          signed_block_header: Block.signed_beacon_block_header(),
          kzg_commitment_inclusion_proof: [<<1551::32*8>>] |> Stream.cycle() |> Enum.take(17)
        }
      ]

    assert_complex_request_roundtrip(request, response)
  end

  # TODO: fix this
  @tag :skip
  test "BlobSidecarsByRoot round trip" do
    count = 1

    request = %BlobSidecarsByRootRequest{
      body: Enum.map(1..count, &%BlobIdentifier{block_root: <<&1::256>>, index: &1})
    }

    # TODO: generate randomly
    response =
      [
        %Types.BlobSidecar{
          index: 1,
          blob: <<152_521_252::(4096*32)*8>>,
          kzg_commitment: <<57_888::48*8>>,
          kzg_proof: <<6122::48*8>>,
          signed_block_header: Block.signed_beacon_block_header(),
          kzg_commitment_inclusion_proof: [<<1551::32*8>>] |> Stream.cycle() |> Enum.take(17)
        }
      ]

    assert_complex_request_roundtrip(request, response)
  end
end
