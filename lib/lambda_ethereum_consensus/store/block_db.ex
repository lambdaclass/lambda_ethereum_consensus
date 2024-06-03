defmodule LambdaEthereumConsensus.Store.BlockDb do
  @moduledoc """
  Storage and retrieval of blocks.
  """
  require Logger
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils
  alias Types.SignedBeaconBlock

  @block_prefix "blockHash"
  @blockslot_prefix "blockSlot"

  defmodule BlockInfo do
    @moduledoc """
    Signed beacon block accompanied with its root and its processing status.
    Maps to what's saved on the blocks db.
    """
    @type block_status ::
            :pending
            | :invalid
            | :processing
            | :download
            | :download_blobs
            | :unknown
            | :transitioned

    @type t :: %__MODULE__{
            root: Types.root(),
            signed_block: Types.SignedBeaconBlock.t(),
            status: block_status()
          }
    defstruct [:root, :signed_block, :status]

    @spec from_block(SignedBeaconBlock.t(), block_status()) :: t()
    def from_block(signed_block, status \\ :pending) do
      {:ok, root} = Ssz.hash_tree_root(signed_block.message)
      from_block(signed_block, root, status)
    end

    @spec from_block(SignedBeaconBlock.t(), Types.root(), block_status()) :: t()
    def from_block(signed_block, root, status) do
      %__MODULE__{root: root, signed_block: signed_block, status: status}
    end
  end

  defguard is_status(atom)
           when atom in [
                  :pending,
                  :invalid,
                  :processing,
                  :download,
                  :download_blobs,
                  :unknown,
                  :transitioned
                ]

  def store_block_info(%BlockInfo{} = block_info) do
    {:ok, encoded_signed_block} = Ssz.to_ssz(block_info.signed_block)

    key = block_key(block_info.root)
    Db.put(key, :erlang.term_to_binary({encoded_signed_block, block_info.status}))

    # WARN: this overrides any previous mapping for the same slot
    # TODO: this should apply fork-choice if not applied elsewhere
    # TODO: handle cases where slot is empty
    slothash_key = block_root_by_slot_key(block_info.signed_block.message.slot)
    Db.put(slothash_key, block_info.root)
  end

  @spec get_block_info(Types.root()) ::
          {:ok, BlockInfo.t()} | {:error, String.t()} | :not_found
  def get_block_info(block_root) do
    with {:ok, data} <- Db.get(block_key(block_root)),
         {:ok, {encoded_signed_block, status}} <- :erlang.binary_to_term(data) |> validate_term(),
         {:ok, signed_block} <- Ssz.from_ssz(encoded_signed_block, SignedBeaconBlock) do
      {:ok, %BlockInfo{root: block_root, signed_block: signed_block, status: status}}
    end
  end

  @spec get_block_root_by_slot(Types.slot()) ::
          {:ok, Types.root()} | {:error, String.t()} | :not_found | :empty_slot
  def get_block_root_by_slot(slot) do
    key = block_root_by_slot_key(slot)
    block = Db.get(key)

    case block do
      {:ok, <<>>} -> :empty_slot
      _ -> block
    end
  end

  @spec get_block_info_by_slot(Types.slot()) ::
          {:ok, BlockInfo.t()} | {:error, String.t()} | :not_found | :empty_slot
  def get_block_info_by_slot(slot) do
    # WARN: this will return the latest block received for the given slot
    with {:ok, root} <- get_block_root_by_slot(slot) do
      get_block_info(root)
    end
  end

  @spec prune_blocks_older_than(non_neg_integer()) :: :ok | {:error, String.t()} | :not_found
  def prune_blocks_older_than(slot) do
    Logger.info("[BlockDb] Pruning started.", slot: slot)
    initial_key = slot |> block_root_by_slot_key()

    slots_to_remove =
      Stream.resource(
        fn -> init_keycursor(initial_key) end,
        &next_slot(&1, :prev),
        &close_cursor/1
      )
      |> Enum.to_list()

    slots_to_remove |> Enum.each(&remove_block_by_slot/1)
    Logger.info("[BlockDb] Pruning finished. #{Enum.count(slots_to_remove)} blocks removed.")
  end

  # Validates a term that came out of the first decoding step for a stored block info tuple.
  defp validate_term({encoded_signed_block, status})
       when is_binary(encoded_signed_block) and is_status(status) do
    {:ok, {encoded_signed_block, status}}
  end

  defp validate_term(other) do
    {:error, "Block decoding failed, decoded term is not the expected tuple: #{other}"}
  end

  @spec remove_block_by_slot(non_neg_integer()) :: :ok | :not_found
  defp remove_block_by_slot(slot) do
    slothash_key = block_root_by_slot_key(slot)

    with {:ok, block_root} <- Db.get(slothash_key) do
      key_block = block_key(block_root)
      Db.delete(slothash_key)
      Db.delete(key_block)
    end
  end

  defp init_keycursor(initial_key) do
    with {:ok, it} <- Db.iterate_keys(),
         {:ok, _key} <- Exleveldb.iterator_move(it, initial_key) do
      it
    else
      # DB is empty
      {:error, :invalid_iterator} -> nil
    end
  end

  defp next_slot(nil, _movement), do: {:halt, nil}

  defp next_slot(it, movement) do
    case Exleveldb.iterator_move(it, movement) do
      {:ok, @blockslot_prefix <> <<key::64>>} ->
        {[key], it}

      _ ->
        {:halt, it}
    end
  end

  defp close_cursor(nil), do: :ok
  defp close_cursor(it), do: :ok = Exleveldb.iterator_close(it)

  defp block_key(root), do: Utils.get_key(@block_prefix, root)
  defp block_root_by_slot_key(slot), do: Utils.get_key(@blockslot_prefix, slot)
end
