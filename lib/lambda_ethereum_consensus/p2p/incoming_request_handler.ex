defmodule LambdaEthereumConsensus.P2P.IncomingRequestHandler do
  use GenServer

  @moduledoc """
  This module handles Req/Resp domain requests.
  """
  require Logger
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.Store.BlockStore
  alias LambdaEthereumConsensus.Store.StateStore

  @prefix "/eth2/beacon_chain/req/"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(_opts) do
    [
      "status/1",
      "goodbye/1",
      "ping/1",
      "beacon_blocks_by_range/2",
      "metadata/2"
    ]
    |> Stream.map(&Enum.join([@prefix, &1, "/ssz_snappy"]))
    |> Stream.map(&Libp2pPort.set_handler/1)
    |> Enum.each(fn :ok -> nil end)

    {:ok, nil}
  end

  @impl true
  def handle_info({:request, {@prefix <> name, message_id, message}}, state) do
    Logger.debug("'#{name}' request received")

    case handle_req(name, message_id, message) do
      :ok -> :ok
      :not_implemented -> :ok
      {:error, error} -> Logger.error("[#{name}] Request error: #{inspect(error)}")
    end

    {:noreply, state}
  end

  @spec handle_req(String.t(), String.t(), binary()) ::
          :ok | :not_implemented | {:error, binary()}
  def handle_req("status/1/ssz_snappy", message_id, message) do
    # hardcoded response from random peer
    current_status = %SszTypes.StatusMessage{
      fork_digest: Base.decode16!("BBA4DA96"),
      finalized_root:
        Base.decode16!("7715794499C07D9954DD223EC2C6B846D3BAB27956D093000FADC1B8219F74D4"),
      finalized_epoch: 228_168,
      head_root:
        Base.decode16!("D62A74AE0F933224133C5E6E1827A2835A1E705F0CDFEE3AD25808DDEA5572DB"),
      head_slot: 7_301_450
    }

    with <<84, snappy_status::binary>> <- message,
         {:ok, ssz_status} <- Snappy.decompress(snappy_status),
         {:ok, status} <- Ssz.from_ssz(ssz_status, SszTypes.StatusMessage),
         status
         |> inspect(limit: :infinity)
         |> then(&"[Status] '#{&1}'")
         |> Logger.debug(),
         {:ok, payload} <- Ssz.to_ssz(current_status),
         {:ok, payload} <- Snappy.compress(payload) do
      Libp2pPort.send_response(message_id, <<0, 84>> <> payload)
    end
  end

  def handle_req("goodbye/1/ssz_snappy", message_id, message) do
    with <<8, snappy_code_le::binary>> <- message,
         {:ok, code_le} <- Snappy.decompress(snappy_code_le),
         :ok <-
           code_le
           |> :binary.decode_unsigned(:little)
           |> then(&Logger.debug("[Goodbye] reason: #{&1}")),
         {:ok, payload} <-
           <<0, 0, 0, 0, 0, 0, 0, 0>>
           |> Snappy.compress() do
      Libp2pPort.send_response(message_id, <<0, 8>> <> payload)
    else
      # Ignore read errors, since some peers eagerly disconnect.
      {:error, "failed to read"} ->
        Logger.debug("[Goodbye] failed to read")
        :ok

      "" ->
        Logger.debug("[Goodbye] empty message")
        :ok
    end
  end

  def handle_req("ping/1/ssz_snappy", message_id, message) do
    # Values are hardcoded
    with <<8, seq_number_le::binary>> <- message,
         {:ok, decompressed} <-
           Snappy.decompress(seq_number_le),
         decompressed
         |> :binary.decode_unsigned(:little)
         |> then(&"[Ping] seq_number: #{&1}")
         |> Logger.debug(),
         {:ok, payload} <-
           <<0, 0, 0, 0, 0, 0, 0, 0>>
           |> Snappy.compress() do
      Libp2pPort.send_response(message_id, <<0, 8>> <> payload)
    end
  end

  def handle_req("metadata/2/ssz_snappy", message_id, _message) do
    # Values are hardcoded
    with {:ok, payload} <-
           <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
           |> Snappy.compress() do
      Libp2pPort.send_response(message_id, <<0, 17>> <> payload)
    end
  end

  def handle_req("beacon_blocks_by_range/2/ssz_snappy", message_id, message) do
    with <<24, snappy_blocks_by_range_request::binary>> <- message,
         {:ok, ssz_blocks_by_range_request} <- Snappy.decompress(snappy_blocks_by_range_request),
         {:ok, blocks_by_range_request} <-
           Ssz.from_ssz(ssz_blocks_by_range_request, SszTypes.BeaconBlocksByRangeRequest),
         blocks_by_range_request
         |> inspect(limit: :infinity)
         |> then(&"[Received BlocksByRange Request] '#{&1}'")
         |> Logger.debug() do
      ## TODO: there should be check that the `start_slot` is not older than the `oldest_slot_with_block`
      %SszTypes.BeaconBlocksByRangeRequest{start_slot: start_slot, count: count} =
        blocks_by_range_request

      slot_coverage = start_slot + count

      blocks =
        start_slot..slot_coverage
        |> Enum.reduce([], fn slot, current_blocks ->
          with {:ok, state} <- StateStore.get_state_by_slot(slot) do
            BlockStore.get_blocks(state.block_roots)
          else
            {:error, _} -> current_blocks
            :not_found -> current_blocks
          end
        end)

      blocks_by_range_response = %SszTypes.BeaconBlocksByRangeResponse{body: blocks}

      with {:ok, payload} <- Ssz.to_ssz(blocks_by_range_response),
           {:ok, payload} <- Snappy.compress(payload) do
        ## TODO: Change length (Length is hardcoded for now)
        Libp2pPort.send_response(message_id, <<0, 8>> <> payload)
      end
    end
  end

  def handle_req(protocol, _message_id, _message) do
    # This should never happen, since Libp2p only accepts registered protocols
    Logger.error("Unsupported protocol: #{protocol}")
    :ok
  end
end
