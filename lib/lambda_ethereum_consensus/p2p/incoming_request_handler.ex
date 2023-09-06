defmodule LambdaEthereumConsensus.P2P.IncomingRequestHandler do
  use GenServer

  @moduledoc """
  This module handles Req/Resp domain requests.
  """

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

    case handle_req(protocol, stream) do
      :ok -> :ok
      x -> IO.puts("[#{protocol}] Request error: #{inspect(x)}")
    end

    Libp2p.stream_close(stream)

    {:noreply, state}
  end

  def handle_req(@prefix <> "status/1/ssz_snappy", stream) do
    try_parse_and_print("Status", stream)
  end

  def handle_req(@prefix <> "goodbye/1/ssz_snappy", stream) do
    with {:ok, <<8, snappy_code_le::binary>>} <- Libp2p.stream_read(stream),
         {:ok, code_le} <- Snappy.decompress(snappy_code_le),
         :ok <-
           code_le
           |> :binary.decode_unsigned(:little)
           |> then(&IO.puts("[Goodbye] reason: #{&1}")),
         {:ok, payload} <-
           <<0, 0, 0, 0, 0, 0, 0, 0>>
           |> Snappy.compress() do
      Libp2p.stream_write(stream, <<0, 8>> <> payload)
      Libp2p.stream_close_write(stream)
    end
  end

  def handle_req(@prefix <> "ping/1/ssz_snappy", stream) do
    try_parse_and_print("Ping", stream)
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

  def handle_req(protocol, _stream) do
    IO.puts("Unsupported protocol: #{protocol}")
  end

  defp parse_request(<<header, encoded_payload::binary>>) do
    {:ok, {header, encoded_payload}}
  end

  defp parse_request(bin), do: {:error, bin}

  defp try_parse_and_print(tag, stream) do
    with {:ok, bin} <-
           Libp2p.stream_read(stream),
         {:ok, {size, req}} <- parse_request(bin),
         {:ok, decompressed} <-
           Snappy.decompress(req),
         ^size <-
           byte_size(decompressed) do
      decompressed
      |> Base.encode16()
      |> then(&"#{tag}: #{&1}")
      |> IO.puts()
    end
  end
end
