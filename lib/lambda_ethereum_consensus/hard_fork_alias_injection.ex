defmodule HardForkAliasInjection do
  @moduledoc false
  is_deneb = Application.compile_env!(:lambda_ethereum_consensus, :fork) == :deneb

  defmacro __using__(_opts) do
    if unquote(is_deneb) do
      quote do
        alias Types.BeaconBlockBodyDeneb, as: BeaconBlockBody
        alias Types.BeaconBlockDeneb, as: BeaconBlock
        alias Types.BeaconStateDeneb, as: BeaconState
        alias Types.ExecutionPayloadDeneb, as: ExecutionPayload
        alias Types.ExecutionPayloadHeaderDeneb, as: ExecutionPayloadHeader
        alias Types.SignedBeaconBlockDeneb, as: SignedBeaconBlock
      end
    else
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

      iex> HardForkAliasInjection.on_deneb(true, false)
      #{is_deneb}
  """
  if is_deneb do
    defmacro on_deneb(code, _default) do
      code
    end
  else
    defmacro on_deneb(_code, default) do
      default
    end
  end
end
