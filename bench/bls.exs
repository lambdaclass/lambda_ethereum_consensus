public_key =
    Base.decode16!(
      "a491d1b0ecd9bb917989f0e74f0dea0422eac4a873e5e2644f368dffb9a6e20fd6e10c1b77654d067c0618f6e5a7f79a",
      case: :mixed
    )
message =
  Base.decode16!(
    "0000000000000000000000000000000000000000000000000000000000000000",
    case: :mixed
  )
signature =
  Base.decode16!(
    "b6ed936746e01f8ecf281f020953fbf1f01debd5657c4a383940b020b26507f6076334f91e2366c96e9ab279fb5158090352ea1c5b0c9274504f4f0e7053af24802e51e4568d164fe986834f41e55c8e850ce1f98458c0cfc9ab380b55285a55",
    case: :mixed
  )

pk = [public_key]
pk_10 = List.duplicate(public_key, 10)
pk_100 = List.duplicate(public_key, 100)
pk_500 = List.duplicate(public_key, 500)
pk_2048 = List.duplicate(public_key, 2048)

Benchee.run(
  %{
    "1" => fn -> Bls.fast_aggregate_valid?(pk, message, signature) end,
    "10" => fn -> Bls.fast_aggregate_valid?(pk_10, message, signature) end,
    "100" => fn -> Bls.fast_aggregate_valid?(pk_100, message, signature) end,
    "500" => fn -> Bls.fast_aggregate_valid?(pk_500, message, signature) end,
    "2048" => fn -> Bls.fast_aggregate_valid?(pk_2048, message, signature) end,
  },
  warmup: 2,
  time: 5
)
