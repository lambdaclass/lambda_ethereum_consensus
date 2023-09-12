defmodule HelloTest do
  use ExUnit.Case

  test "Can deserialize BeconBlockBody from operations" do
    compressed =
      File.read!(
        "../../tests/minimal/capella/operations/execution_payload/pyspec_tests/invalid_randomized_non_validated_execution_fields_first_payload__execution_invalid/execution_payload.ssz_snappy"
      )

    {:ok, decompressed} = :snappyer.decompress(compressed)
    {:ok, deserialized} = Ssz.from_ssz(decompressed, SszTypes.BeaconBlockBody, MinimalConfig)
    IO.inspect(deserialized)
  end
end
