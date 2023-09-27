defmodule Unit.HelperTest do
  alias LambdaEthereumConsensus.Beacon.HelperFunctions
  use ExUnit.Case

  test "compute fork digest" do
    current_version = "A62EF32B" |> Base.decode16!()

    genesis_validators_root =
      "CD80AAEEBDD7EE26480B3EE111747BBD13B8BF0F9488AB4E634CF8EAE536479C" |> Base.decode16!()

    expected_root =
      "E1AB31601852DF2FA3ED26E678E9FBC175B07C5B5C54E1BFA275D3DFC47D3A71" |> Base.decode16!()

    expected_digest = "E1AB3160" |> Base.decode16!()

    assert expected_root ==
             HelperFunctions.compute_fork_data_root(current_version, genesis_validators_root)

    assert expected_digest ==
             HelperFunctions.compute_fork_digest(current_version, genesis_validators_root)
  end
end
