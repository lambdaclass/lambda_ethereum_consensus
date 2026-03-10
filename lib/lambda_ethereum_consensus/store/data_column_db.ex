defmodule LambdaEthereumConsensus.Store.DataColumnDb do
  @moduledoc """
  Storage and retrieval of PeerDAS data column sidecars (Fulu / EIP-7594).

  Key layout:
  - `data_column_sidecar:<block_root><column_index>` → SSZ-encoded DataColumnSidecar
  - `data_column_root:<slot:u64><column_index:u8>` → block_root (for pruning by slot)
  """
  require Logger

  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils
  alias Types.DataColumnSidecar

  @sidecar_prefix "data_column_sidecar"
  @block_root_prefix "data_column_root"

  @doc """
  Stores a data column sidecar. Returns the block root.
  """
  @spec store_data_column(DataColumnSidecar.t()) :: Types.root()
  def store_data_column(
        %DataColumnSidecar{signed_block_header: %{message: block_header}} = sidecar
      ) do
    block_root = Ssz.hash_tree_root!(block_header)
    {:ok, encoded} = Ssz.to_ssz(sidecar)

    sidecar_key = sidecar_key(block_root, sidecar.index)
    Db.put(sidecar_key, encoded)

    root_key = block_root_key(block_header.slot, sidecar.index)
    Db.put(root_key, block_root)

    block_root
  end

  @spec get_data_column_sidecar(Types.root(), Types.column_index()) ::
          {:ok, DataColumnSidecar.t()} | {:error, String.t()} | :not_found
  def get_data_column_sidecar(block_root, column_index) do
    key = sidecar_key(block_root, column_index)

    with {:ok, encoded} <- Db.get(key) do
      Ssz.from_ssz(encoded, DataColumnSidecar)
    end
  end

  @doc """
  Checks whether a data column sidecar exists in the DB without deserializing it.
  """
  @spec has_column?(Types.root(), Types.column_index()) :: boolean()
  def has_column?(block_root, column_index) do
    key = sidecar_key(block_root, column_index)
    match?({:ok, _}, Db.get(key))
  end

  @spec prune_old_data_columns(non_neg_integer()) :: :ok | {:error, String.t()} | :not_found
  def prune_old_data_columns(current_finalized_slot) do
    slot =
      current_finalized_slot -
        ChainSpec.get("MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS") *
          ChainSpec.get("SLOTS_PER_EPOCH")

    Logger.info("[DataColumnDb] Pruning started.", slot: slot)
    last_finalized_key = block_root_key(slot, 0)

    with {:ok, it} <- Db.iterate(),
         {:ok, @block_root_prefix <> _, _value} <-
           Db.iterator_move(it, last_finalized_key),
         {:ok, keys_to_remove} <- get_root_keys_to_remove(it),
         :ok <- Db.iterator_close(it) do
      total_removed =
        keys_to_remove
        |> Enum.reduce_while(0, fn key, acc ->
          case remove_by_root_key(key) do
            :ok -> {:cont, acc + 1}
            _ -> {:halt, acc}
          end
        end)

      Logger.info("[DataColumnDb] Pruning finished. #{total_removed} columns removed.")
    end
  end

  defp get_root_keys_to_remove(keys \\ [], iterator) do
    case Db.iterator_move(iterator, :prev) do
      {:ok, <<@block_root_prefix, _rest::binary>> = root_key, _root} ->
        [root_key | keys] |> get_root_keys_to_remove(iterator)

      _ ->
        {:ok, keys}
    end
  end

  defp remove_by_root_key(root_key) do
    <<@block_root_prefix, _slot::unsigned-size(64), column_index>> = root_key

    with {:ok, block_root} <- Db.get(root_key) do
      Db.delete(root_key)
      Db.delete(sidecar_key(block_root, column_index))
    end
  end

  defp sidecar_key(block_root, column_index),
    do: @sidecar_prefix <> block_root <> <<column_index::unsigned-size(8)>>

  defp block_root_key(slot, column_index),
    do: Utils.get_key(@block_root_prefix, slot) <> <<column_index::unsigned-size(8)>>
end
