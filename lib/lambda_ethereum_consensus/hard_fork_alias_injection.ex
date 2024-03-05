defmodule HardForkAliasInjection do
  @moduledoc false
  is_deneb = Application.compile_env!(:lambda_ethereum_consensus, :fork) == :deneb

  defmacro __using__(_opts) do
    if unquote(is_deneb) do
      quote do
        alias Types.SignedBeaconBlockDeneb, as: SignedBeaconBlock
      end
    else
      quote do
        alias Types.SignedBeaconBlock
      end
    end
  end
end
