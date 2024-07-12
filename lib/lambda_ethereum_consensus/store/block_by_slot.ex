defmodule LambdaEthereumConsensus.Store.BlockBySlot do
  alias LambdaEthereumConsensus.Store.KvSchema
  use KvSchema, prefix: "blockSlot"
  @type value_t :: Types.root() | <<>>

  ################################
  ### PUBLIC API
  ################################

  @doc """
  Checks if all the blocks between first_slot and last_slot are present in the db.
  This iterates through the db checking each one individually, although it only checks
  the keys, so it doesn't need to decode the values, making it a relatively cheap
  linear O(last_slot - first_slot) operation.
  """
  @spec all_present?(Types.slot(), Types.slot()) :: boolean()
  def all_present?(first_slot, last_slot) do
    fold_keys(last_slot, MapSet.new(), fn slot, set -> MapSet.put(set, slot) end,
      include_first: true
    )
    |> case do
      {:ok, available} ->
        Enum.all?(first_slot..last_slot, fn slot -> slot in available end)

      {:error, :invalid_iterator} ->
        false

      {:error, "Failed to start iterator for table" <> _} ->
        false
    end
  end

  ################################
  ### Schema implementation
  ################################

  @impl KvSchema
  @spec encode_key(Types.slot()) :: {:ok, binary()} | {:error, binary()}
  def encode_key(slot), do: {:ok, <<slot::64>>}

  @impl KvSchema
  @spec decode_key(binary()) :: {:ok, integer()} | {:error, binary()}
  def decode_key(<<slot::64>>), do: {:ok, slot}

  def decode_key(other) do
    {:error, "[Block by slot] Could not decode slot, not 64 bit integer: #{other}"}
  end

  @impl KvSchema
  @spec encode_value(value_t()) :: {:ok, value_t()} | {:error, binary()}
  def encode_value(root), do: check_root("Encoding", root)

  @impl KvSchema
  @spec decode_value(value_t()) :: {:ok, value_t()} | {:error, binary()}
  def decode_value(root), do: check_root("Decoding", root)

  ################################
  ### Private functions
  ################################

  defp check_root(_op, <<>>), do: {:ok, <<>>}
  defp check_root(_op, <<_::256>> = root), do: {:ok, root}
  defp check_root(op, other), do: {:error, "[Block by slot] #{op} error. Invalid root: #{other}"}
end
