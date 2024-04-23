defmodule Types.ProposerSlashing do
  @moduledoc """
  Struct definition for `ProposerSlashing`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :signed_header_1,
    :signed_header_2
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          signed_header_1: Types.SignedBeaconBlockHeader.t(),
          signed_header_2: Types.SignedBeaconBlockHeader.t()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:signed_header_1, Types.SignedBeaconBlockHeader},
      {:signed_header_2, Types.SignedBeaconBlockHeader}
    ]
  end
end
