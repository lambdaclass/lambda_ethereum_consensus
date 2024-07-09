defmodule LambdaEthereumConsensus.Beacon.BeaconNode do
  @moduledoc false

  use Supervisor
  require Logger

  alias LambdaEthereumConsensus.Beacon.StoreSetup
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.StateTransition.Cache
  alias LambdaEthereumConsensus.Store.BlockStates
  alias LambdaEthereumConsensus.Validator.ValidatorManager
  alias Types.BeaconState

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_) do
    store = StoreSetup.setup!()
    deposit_tree_snapshot = StoreSetup.get_deposit_snapshot!()

    LambdaEthereumConsensus.P2P.Metadata.init()

    Cache.initialize_cache()

    libp2p_args = get_libp2p_args()

    time = :os.system_time(:second)

    ForkChoice.init_store(store, time)

    validator_manager =
      get_validator_manager(
        deposit_tree_snapshot,
        store.head_slot,
        store.head_root
      )

    children =
      [
        {LambdaEthereumConsensus.Beacon.Clock, {store.genesis_time, time}},
        {LambdaEthereumConsensus.Libp2pPort, libp2p_args},
        LambdaEthereumConsensus.Beacon.SyncBlocks,
        {Task.Supervisor, name: PruneStatesSupervisor},
        {Task.Supervisor, name: PruneBlocksSupervisor},
        {Task.Supervisor, name: PruneBlobsSupervisor}
      ] ++ validator_manager

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp get_validator_manager(nil, _, _) do
    Logger.warning("Deposit data not found. Validator will be disabled.")
    []
  end

  defp get_validator_manager(snapshot, slot, head_root) do
    %BeaconState{eth1_data_votes: votes} = BlockStates.get_state_info!(head_root).beacon_state
    LambdaEthereumConsensus.Execution.ExecutionChain.init(snapshot, votes)
    # TODO: move checkpoint sync outside and move this to application.ex
    [
      {ValidatorManager, {slot, head_root}}
    ]
  end

  defp get_libp2p_args() do
    config = Application.fetch_env!(:lambda_ethereum_consensus, :libp2p)
    port = Keyword.fetch!(config, :port)
    bootnodes = Keyword.fetch!(config, :bootnodes)

    listen_addr = Keyword.fetch!(config, :listen_addr) |> Enum.map(&parse_listen_addr/1)

    if Enum.empty?(bootnodes) do
      Logger.warning("No bootnodes configured.")
    end

    [
      listen_addr: listen_addr,
      enable_discovery: true,
      discovery_addr: "0.0.0.0:#{port}",
      bootnodes: bootnodes,
      join_init_topics: true,
      enable_request_handlers: true
    ]
  end

  defp parse_listen_addr(addr) do
    case String.split(addr, ":") do
      [ip, port] ->
        "/ip4/#{ip}/tcp/#{port}"

      _ ->
        Logger.error("Invalid listen address: #{addr}")
        Logger.flush()
        System.halt(2)
    end
  end
end
