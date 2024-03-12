defmodule Types.StatusMessage do
  @moduledoc """
  Struct definition for `StatusMessage`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :fork_digest,
    :finalized_root,
    :finalized_epoch,
    :head_root,
    :head_slot
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          fork_digest: Types.fork_digest(),
          finalized_root: Types.root(),
          finalized_epoch: Types.epoch(),
          head_root: Types.root(),
          head_slot: Types.slot()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      fork_digest: TypeAliases.fork_digest(),
      finalized_root: TypeAliases.root(),
      finalized_epoch: TypeAliases.epoch(),
      head_root: TypeAliases.root(),
      head_slot: TypeAliases.slot()
    ]
  end
end
