alias ChainSpec
alias Kzg

# BLS12-381 Fr modulus
modulus =
  0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000001

rand_field_element = fn ->
  int =
    :crypto.strong_rand_bytes(64)
    |> :binary.decode_unsigned(:big)
    |> rem(modulus)

  <<int::unsigned-size(256)>>
end

ok! = fn
  {:ok, value} -> value
  other -> raise "expected {:ok, _}, got #{inspect(other)}"
end

fe_per_blob = ChainSpec.get("FIELD_ELEMENTS_PER_BLOB")

rand_blob = fn ->
  for _ <- 1..fe_per_blob, into: <<>> do
    rand_field_element.()
  end
end

z = rand_field_element.()
blob = rand_blob.()

commitment = blob |> Kzg.blob_to_kzg_commitment() |> ok!.()
proof = blob |> Kzg.compute_blob_kzg_proof(commitment) |> ok!.()

# Only did 4 blobs, we don't have all day...
batch =
  Enum.map(1..4, fn _ ->
    b = rand_blob.()
    c = b |> Kzg.blob_to_kzg_commitment() |> ok!.()
    p = b |> Kzg.compute_blob_kzg_proof(c) |> ok!.()
    {b, c, p}
  end)

blobs = Enum.map(batch, fn {b, _, _} -> b end)
commitments = Enum.map(batch, fn {_, c, _} -> c end)
proofs = Enum.map(batch, fn {_, _, p} -> p end)

Benchee.run(
  %{
    "blob_to_kzg_commitment" => fn -> Kzg.blob_to_kzg_commitment(blob) end,
    "compute_blob_kzg_proof" => fn -> Kzg.compute_blob_kzg_proof(blob, commitment) end,
    "verify_blob_kzg_proof" => fn -> Kzg.verify_blob_kzg_proof(blob, commitment, proof) end,
    "verify_blob_kzg_proof_batch (4)" => fn ->
      Kzg.verify_blob_kzg_proof_batch(blobs, commitments, proofs)
    end,
    "compute_kzg_proof (z)" => fn -> Kzg.compute_kzg_proof(blob, z) end
  },
  warmup: 2,
  time: 5
)
