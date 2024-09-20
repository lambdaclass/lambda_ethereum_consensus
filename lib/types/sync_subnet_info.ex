defmodule Types.SyncSubnetInfo do
  @moduledoc """
  Struct to hold subnet messages for easier db storing:
  - data: A Sync Committee message data (slot + root).
  - messages: List of all the collected SyncCommitteeMessages.

  TODO: This module borrows almost all of its logic from AttSubnetInfo,
  this could be refactored to a common module if needed in the future.
  """
  alias LambdaEthereumConsensus.Store.Db

  defstruct [:data, :messages]

  @type t :: %__MODULE__{
          data: {Types.slot(), Types.root()},
          messages: list(Types.SyncCommitteeMessage.t())
        }

  @subnet_prefix "sync_subnet"

  @doc """
  Creates a SubnetInfo from an SyncCommitteeMessage and stores it into the database.
  The message is typically built by a validator before starting to collect others' messages.
  This message will be used to filter other added messages.
  """
  @spec new_subnet_with_message(non_neg_integer(), Types.SyncCommitteeMessage.t()) :: :ok
  def new_subnet_with_message(
        subnet_id,
        %Types.SyncCommitteeMessage{slot: slot, beacon_block_root: root} = message
      ) do
    new_subnet_info = %__MODULE__{data: {slot, root}, messages: [message]}
    persist_subnet_info(subnet_id, new_subnet_info)
  end

  @doc """
  Removes the associated SubnetInfo from the database and returns all the collected messages.
  """
  @spec stop_collecting(non_neg_integer()) ::
          {:ok, list(Types.SyncCommitteeMessage.t())} | {:error, String.t()}
  def stop_collecting(subnet_id) do
    case fetch_subnet_info(subnet_id) do
      {:ok, subnet_info} ->
        delete_subnet(subnet_id)
        {:ok, subnet_info.messages}

      :not_found ->
        {:error, "subnet not joined"}
    end
  end

  @doc """
  Adds a new SyncCommitteeMessage to the SubnetInfo if the message's data matches the base one.
  """
  @spec add_message!(non_neg_integer(), Types.SyncCommitteeMessage.t()) :: :ok
  def add_message!(subnet_id, %Types.SyncCommitteeMessage{} = message) do
    %{slot: slot, beacon_block_root: root} = message

    with {:ok, subnet_info} <- fetch_subnet_info(subnet_id),
         {^slot, ^root} <- subnet_info.data do
      new_subnet_info = %__MODULE__{
        subnet_info
        | messages: [message | subnet_info.messages]
      }

      persist_subnet_info(subnet_id, new_subnet_info)
    end
  end

  ##########################
  ### Database Calls
  ##########################

  @spec persist_subnet_info(non_neg_integer(), t()) :: :ok
  defp persist_subnet_info(subnet_id, subnet_info) do
    key = @subnet_prefix <> Integer.to_string(subnet_id)
    value = encode(subnet_info)

    :telemetry.span([:db, :latency], %{}, fn ->
      {Db.put(
         key,
         value
       ), %{module: @subnet_prefix, action: "persist"}}
    end)
  end

  @spec fetch_subnet_info(non_neg_integer()) :: {:ok, t()} | :not_found
  defp fetch_subnet_info(subnet_id) do
    result =
      :telemetry.span([:db, :latency], %{}, fn ->
        {Db.get(@subnet_prefix <> Integer.to_string(subnet_id)),
         %{module: @subnet_prefix, action: "fetch"}}
      end)

    case result do
      {:ok, binary} -> {:ok, decode(binary)}
      :not_found -> result
    end
  end

  @spec delete_subnet(non_neg_integer()) :: :ok
  defp delete_subnet(subnet_id), do: Db.delete(@subnet_prefix <> Integer.to_string(subnet_id))

  @spec encode(t()) :: binary()
  defp encode(%__MODULE__{} = subnet_info) do
    {subnet_info.data, subnet_info.messages} |> :erlang.term_to_binary()
  end

  @spec decode(binary()) :: t()
  defp decode(bin) do
    {data, messages} = :erlang.binary_to_term(bin)
    %__MODULE__{data: data, messages: messages}
  end
end
