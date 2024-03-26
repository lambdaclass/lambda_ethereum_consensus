defmodule Types.DepositTree do
  @moduledoc """
  Struct definition for a deposit snapshot, as defined in EIP 4881.
  """

  alias Types.DepositTreeSnapshot
  alias Types.Deposit

  fields = [:snapshot, :non_finalized_deposits]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # Max size is 33
          snapshot: DepositTreeSnapshot.t(),
          non_finalized_deposits: list(Deposit.t())
        }

  def from_snapshot(snapshot) do
    %__MODULE__{
      snapshot: snapshot,
      non_finalized_deposits: []
    }
  end
end
