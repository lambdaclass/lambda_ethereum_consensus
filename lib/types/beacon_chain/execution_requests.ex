defmodule Types.ExecutionRequests do
  @moduledoc """
  Struct definition for `ExecutionRequests`.
  Added in Electra fork.
  """

  use LambdaEthereumConsensus.Container

  @enforce_keys [:deposits, :withdrawals, :consolidations]
  defstruct [:deposits, :withdrawals, :consolidations]

  @type t :: %__MODULE__{
          deposits: list(Types.DepositRequest.t()),
          withdrawals: list(Types.WithdrawalRequest.t()),
          consolidations: list(Types.ConsolidationRequest.t())
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:deposits,
       {:list, Types.DepositRequest, ChainSpec.get("MAX_DEPOSIT_REQUESTS_PER_PAYLOAD")}},
      {:withdrawals,
       {:list, Types.WithdrawalRequest, ChainSpec.get("MAX_WITHDRAWAL_REQUESTS_PER_PAYLOAD")}},
      {:consolidations,
       {:list, Types.ConsolidationRequest, ChainSpec.get("MAX_CONSOLIDATION_REQUESTS_PER_PAYLOAD")}}
    ]
  end
end
