defmodule Types.EnrForkId do
  @moduledoc """
  Struct definition for `ENRForkID`.
  """
  alias LambdaEthereumConsensus.Container
  use Container

  fields = [
    :fork_digest,
    :next_fork_version,
    :next_fork_epoch
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          fork_digest: Types.fork_digest(),
          next_fork_version: Types.version(),
          next_fork_epoch: Types.epoch()
        }

  @impl Container
  def schema do
    [
      fork_digest: TypeAliases.fork_digest(),
      next_fork_version: TypeAliases.version(),
      next_fork_epoch: TypeAliases.epoch()
    ]
  end
end
