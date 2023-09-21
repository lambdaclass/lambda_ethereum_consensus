defmodule LambdaEthereumConsensus.P2P.IncomingRequestHandler do
  use GenServer

  @moduledoc """
  This module handles Req/Resp domain requests.
  """
  require Logger

  @prefix "/eth2/beacon_chain/req/"

  def start_link([host]) do
    GenServer.start_link(__MODULE__, host)
  end

  @impl true
  def init(host) do
    [
      "status/1",
      "goodbye/1",
      "ping/1",
      "beacon_blocks_by_range/2",
      "metadata/2"
    ]
    |> Stream.map(&Enum.join([@prefix, &1, "/ssz_snappy"]))
    |> Stream.map(&Libp2p.host_set_stream_handler(host, &1))
    |> Enum.each(fn :ok -> nil end)

    {:ok, host}
  end

  @impl true
  def handle_info({:req, {:ok, stream}}, state) do
    {:ok, protocol} = Libp2p.stream_protocol(stream)

    @prefix <> name = protocol
    Logger.debug("'#{name}' request received")

    case handle_req(protocol, stream) do
      :ok -> :ok
      x -> Logger.error("[#{protocol}] Request error: #{inspect(x)}")
    end

    Libp2p.stream_close(stream)

    {:noreply, state}
  end

  def handle_req(@prefix <> "status/1/ssz_snappy", stream) do
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

    with {:ok, <<84, snappy_status::binary>>} <- Libp2p.stream_read(stream),
         {:ok, ssz_status} <- Snappy.decompress(snappy_status),
         {:ok, status} <- Ssz.from_ssz(ssz_status, SszTypes.StatusMessage),
         status
         |> inspect(limit: :infinity)
         |> then(&"[Status] '#{&1}'")
         |> Logger.debug(),
         {:ok, payload} <- Ssz.to_ssz(current_status),
         {:ok, payload} <- Snappy.compress(payload) do
      Libp2p.stream_write(stream, <<0, 84>> <> payload)
      Libp2p.stream_close_write(stream)
    end
  end

  def handle_req(@prefix <> "goodbye/1/ssz_snappy", stream) do
    with {:ok, <<8, snappy_code_le::binary>>} <- Libp2p.stream_read(stream),
         {:ok, code_le} <- Snappy.decompress(snappy_code_le),
         :ok <-
           code_le
           |> :binary.decode_unsigned(:little)
           |> then(&Logger.debug("[Goodbye] reason: #{&1}")),
         {:ok, payload} <-
           <<0, 0, 0, 0, 0, 0, 0, 0>>
           |> Snappy.compress() do
      Libp2p.stream_write(stream, <<0, 8>> <> payload)
      Libp2p.stream_close_write(stream)
    else
      # Ignore read errors, since some peers eagerly disconnect.
      {:error, "failed to read"} ->
        Logger.debug("[Goodbye] failed to read")
        :ok
    end
  end

  def handle_req(@prefix <> "ping/1/ssz_snappy", stream) do
    # Values are hardcoded
    with {:ok, <<8, seq_number_le::binary>>} <-
           Libp2p.stream_read(stream),
         {:ok, decompressed} <-
           Snappy.decompress(seq_number_le),
         decompressed
         |> :binary.decode_unsigned(:little)
         |> then(&"[Ping] seq_number: #{&1}")
         |> Logger.debug(),
         {:ok, payload} <-
           <<0, 0, 0, 0, 0, 0, 0, 0>>
           |> Snappy.compress(),
         :ok <- Libp2p.stream_write(stream, <<0, 8>> <> payload) do
      Libp2p.stream_close_write(stream)
    end
  end

  def handle_req(@prefix <> "metadata/2/ssz_snappy", stream) do
    # Values are hardcoded
    with {:ok, payload} <-
           <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
           |> Snappy.compress(),
         :ok <- Libp2p.stream_write(stream, <<0, 17>> <> payload) do
      Libp2p.stream_close_write(stream)
    end
  end

  def handle_req(@prefix <> "beacon_blocks_by_range/2/ssz_snappy", _stream), do: nil

  def handle_req(protocol, _stream) do
    # This should never happen, since Libp2p only accepts registered protocols
    Logger.error("Unsupported protocol: #{protocol}")
  end
end
