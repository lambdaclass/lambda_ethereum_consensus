defmodule SszTypes.SigningData do
  @moduledoc """
  Struct definition for `SigningData`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :object_root,
    :domain
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          object_root: SszTypes.root(),
          domain: SszTypes.domain()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:object_root, {:bytes, 32}},
      {:domain, {:bytes, 32}}
    ]
  end
end
