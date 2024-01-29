defmodule LambdaEthereumConsensus.Utils.Randao do
  @moduledoc """
  This module provides utility functions for randao mixes
  """
  def get_randao_mix_index(epoch), do: rem(epoch, ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR"))

  def replace_randao_mix(randao_mixes, epoch, randao_mix),
    do: Aja.Vector.replace_at!(randao_mixes, get_randao_mix_index(epoch), randao_mix)
end
