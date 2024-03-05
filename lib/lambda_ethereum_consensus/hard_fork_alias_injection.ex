defmodule HardForkAliasInjection do
  @moduledoc false
  is_deneb = Application.compile_env!(:lambda_ethereum_consensus, :fork) == :deneb

  defmacro __using__(_opts) do
    if unquote(is_deneb) do
      quote do
        alias Types.BeaconBlockDeneb, as: BeaconBlock
        alias Types.BeaconBlockBodyDeneb, as: BeaconBlockBody
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

  defmacro is_deneb, do: unquote(is_deneb)
end
