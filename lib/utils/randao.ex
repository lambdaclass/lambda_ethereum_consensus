defmodule LambdaEthereumConsensus.Utils.Randao do
  @moduledoc """
  This module provides utility functions for randao mixes
  """

  alias Types.BeaconState

  @spec get_randao_mix_index(Types.epoch()) :: Types.epoch()
  defp get_randao_mix_index(epoch), do: rem(epoch, ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR"))

  @doc """
  Replaces the randao mix to a new one at given epoch
  """
  @spec replace_randao_mix(Aja.Vector.t(Types.bytes32()), Types.epoch(), Types.bytes32()) ::
          Aja.Vector.t(Types.bytes32())
  def replace_randao_mix(randao_mixes, epoch, randao_mix),
    do: Aja.Vector.replace_at!(randao_mixes, get_randao_mix_index(epoch), randao_mix)

  @doc """
  Return the randao mix at a recent ``epoch``.
  """
  @spec get_randao_mix(BeaconState.t(), Types.epoch()) :: Types.bytes32()
  def get_randao_mix(%BeaconState{randao_mixes: randao_mixes}, epoch) do
    index = get_randao_mix_index(epoch)
    Aja.Vector.at!(randao_mixes, index)
  end
end
