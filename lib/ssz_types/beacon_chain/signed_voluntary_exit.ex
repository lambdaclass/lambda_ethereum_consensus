defmodule SszTypes.SignedVoluntaryExit do
  @moduledoc """
  Struct definition for `SignedVoluntaryExit`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :message,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          message: SszTypes.VoluntaryExit.t(),
          signature: SszTypes.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:message, SszTypes.VoluntaryExit},
      {:signature, {:bytes, 96}}
    ]
  end
end
