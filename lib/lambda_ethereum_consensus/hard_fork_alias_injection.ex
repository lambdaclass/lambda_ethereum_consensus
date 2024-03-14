defmodule HardForkAliasInjection do
  @moduledoc false
  is_deneb = Application.compile_env!(:lambda_ethereum_consensus, :fork) == :deneb

  if is_deneb do
    defmacro __using__(_opts) do
      quote do
        alias Types.BeaconBlockBodyDeneb, as: BeaconBlockBody
        alias Types.BeaconBlockDeneb, as: BeaconBlock
        alias Types.BeaconStateDeneb, as: BeaconState
        alias Types.ExecutionPayloadDeneb, as: ExecutionPayload
        alias Types.ExecutionPayloadHeaderDeneb, as: ExecutionPayloadHeader
        alias Types.SignedBeaconBlockDeneb, as: SignedBeaconBlock
      end
    end
  else
    defmacro __using__(_opts) do
      quote do
        alias Types.BeaconBlock
        alias Types.BeaconBlockBody
        alias Types.BeaconState
        alias Types.ExecutionPayload
        alias Types.ExecutionPayloadHeader
        alias Types.SignedBeaconBlock
      end
    end
  end

  @compile {:inline, deneb?: 0}
  def deneb?, do: unquote(is_deneb)

  @doc """
  Compiles to the first argument if on deneb, otherwise to the second argument.

  ## Examples

      iex> HardForkAliasInjection.on_deneb(do: true, else: false)
      #{is_deneb}

      iex> HardForkAliasInjection.on_deneb(do: true)
      #{if is_deneb, do: true, else: nil}
  """
  if is_deneb do
    defmacro on_deneb(do: do_clause) do
      do_clause
    end

    defmacro on_deneb(do: do_clause, else: _else_clause) do
      do_clause
    end
  else
    defmacro on_deneb(do: _do_clause) do
      nil
    end

    defmacro on_deneb(do: _do_clause, else: else_clause) do
      else_clause
    end
  end
end
