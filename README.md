# Lambda Ethereum Consensus Client

  [![CI](https://github.com/lambdaclass/lambda_ethereum_consensus/actions/workflows/ci.yml/badge.svg)](https://github.com/lambdaclass/lambda_ethereum_consensus/actions/workflows/ci.yml)
  [![Telegram chat](https://img.shields.io/endpoint?url=https%3A%2F%2Ftg.sumanjay.workers.dev%2Flambdaconsensus%2F&logo=telegram&label=chat&color=neon)](https://t.me/lambdaconsensus)

  ## Overview

  Lambda Ethereum Consensus Client is an Elixir-based Ethereum consensus layer client. It leverages the fault tolerance and distributed system capabilities of the BEAM VM as well as the succint and easy to understand syntax of Elixir.

  Besides pushing for client diversity in the Ethereum ecosystem, our goal is to create a clear landscape for anyone who is interested either in Ethereum or Elixir

  ### Why a Consensus Client?
  We built this client to contribute to [Ethereum’s client diversity](https://ethereum.org/en/developers/docs/nodes-and-clients/client-diversity/), which is essential for the resilience and decentralization of the network. 
  As stated on ethereum.org: *"Having many independently developed and maintained clients is vital for the health of a decentralized network."*

  ### Why Elixir?

  Elixir is a functional programming language that runs atop the Erlang Virtual Machine (BEAM). It offers enhanced readability, syntactic sugar, and reduced boilerplate, enabling developers to achieve more with fewer lines of code compared to Erlang. Like Erlang, Elixir compiles to bytecode that is interpreted by the VM. As a result, it inherits several notable properties, including:

  - Fault tolerance for increased reliability
  - High availability
  - Simplified construction of complex distributed systems
  - Predictable latency

  [Erlang](https://www.erlang.org/) and its VM were originally developed in 1986 for telecommunication systems that demanded unparalleled uptime and reliability. We recognize that these attributes could be immensely beneficial for an Ethereum client, particularly in the realm of consensus. This is why our current focus is on building a consensus layer (CL) rather than an execution layer (EL). Elixir may not be tailored for sheer performance, but it excels in delivering predictable latency and creating systems designed for continuous operation—qualities essential for the CL.

  Our aim is to infuse these strengths into the Ethereum consensus client ecosystem with our offering.

  We also have for objective to bootstart an Ethereum Elixir community, and to make Elixir a first-class citizen in the Ethereum ecosystem.

  ## Table of Contents

  - [Overview](#overview)
  - [Roadmap](#roadmap)
  - [Security](#security)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Installing and Running](#installing-and-running)
  - [Usage](#usage)
  - [Testing, Linting, and Formatting](#testing-linting-and-formatting)
  - [Docker](#docker)
  - [Testing Environment with Kurtosis](#testing-environment-with-kurtosis)
  - [Live Metrics](#live-metrics)
  - [Benchmarks](#benchmarks)
  - [Profiling](#profiling)
  - [Contributing](#contributing)
  - [License](#license)

  ## Roadmap

  This project is under active development and the roadmap can be split into two different goals:

  ### Electra support
  Our top priority right now is adding Electra support.

  We setted up 3 stages to track the progress of the upgrade
  | Status | Phase                                    | What & Why                                           | Key Steps                                                                 | Testing                                            |
  |:----:|:------------------------------------------|:------------------------------------------------------|:---------------------------------------------------------------------------|:---------------------------------------------------|
  | ✅   | [Phase 1: Beacon Chain Implementation](./electra-gap.md#phase-1-beacon-chain-implementation)     | Build the electra-upgraded beacon chain core         | • Apply electra-specific changes<br>• Run & pass full spec tests           | Run spec suite (`make spec-test`), aim for 0 failures |
  | ⌛   | [Phase 2: P2P & Sepolia Long-Running Sessions](./electra-gap.md#phase-2-p2p--sepolia-long-running-sessions)   | Ensure stability on Sepolia                          | • Implement the P2P changes <br> • Deploy the node on our server pointing to Sepolia<br>• Fix every issue we found that interrupts the node execution | Continuous uptime checks & up-to-date block processing for 72+ hrs in Sepolia|
  | ⌛   | [Phase 3: Validator Upgrades](./electra-gap.md#phase-3-validator-upgrades) | Ensure validators duties on devnets              |• Implement the honest validator changes<br>• Make assertoor work<br> • Test via Kurtosis & Assertoor | Execute Kurtosis scenarios & Assertoor with continuous uptime checks and up-to-date validation duties for 72+ hrs on kurtosis   |

  For more details, see the [Implementation Gaps for electra Upgrade](./electra-gap.md).


  ### Road to the MVP
  Once an initial version of electra is in place we'll need to work on some missing component before reaching the MVP state: 

  #### Without Validators
  - [✅] Sync and run the node on Sepolia for validating state transitions 
  - [🏗️] Implementation of the Beacon API
  - [  ] Improve performance to process blocks and epochs for other networks (specially Holesky/Hoodi/Mainnet)

  #### With Validators
  - [🏗️] Run devnets using kurtosis handling validator duties for long running sessions
  - [ ] Run and handle validator duties in testnets (i.e. Holesky/Hoodi/Mainnet)



  ## Security

  We take security seriously. If you discover a vulnerability, please report it responsibly:

  - Use the **[GitHub "Report a Vulnerability" feature](../../security/advisories/new)**.
  - Alternatively, email **[security@lambdaclass.com](mailto:security@lambdaclass.com)**.

  Refer to our [Security Policy](./.github/SECURITY.md) for more details.

  ## Getting Started

  ### Prerequisites

  Install the following tools:

  - [Git](https://git-scm.com/)
  - [wget](https://www.gnu.org/software/wget/)
  - [CMake](https://cmake.org/)
  - [Elixir](https://elixir-lang.org/install.html)
  - [Erlang](https://www.erlang.org/downloads)
  - [Go](https://go.dev/doc/install)
  - [Rust](https://www.rust-lang.org/tools/install)
  - [Protoc](https://grpc.io/docs/protoc-installation/)

  You can install the necessary components directly from official sources or alternatively, use **asdf** for version management. 

  See [Prerequisites](./docs/PREREQUISITES.md) for detailed instructions.

  ## Installing and running

  There are Makefile targets for these tasks.

  > [!TIP]
  > You can list the available targets with `make help`

  > [!NOTE]
  > If `make deps` is failing with `protoc-gen-go: program not found or is not executable` you might need to run
  > ```Shell
  > export PATH=$PATH:~/go/bin
  > ```

  ```shell
  make deps # Installs dependencies
  make iex  # Runs a terminal with the application started
  ```

  The iex terminal can be closed by pressing ctrl+c two times.

  > [!WARNING]
  > The node isn't capable of syncing from genesis yet, and so requires using checkpoint-sync to start (see [Checkpoint Sync](#checkpoint-sync)).
  > In case checkpoint-sync is needed, `make iex` will end immediately with an error.


  For more details about installing dependecies, see [Installing](./docs/PREREQUISITES.md).

  ## Usage

  Here you'll find both basic and advanced usage examples.  
  For implementation details, refer to the [Architecture](./docs/ARCHITECTURE.md) documentation.

  ### Basic usage
  
  For basic usage check [Installing and running](#installing-and-running)

  ### Checkpoint Sync

  You can also sync from a checkpoint given by a trusted third-party.
  You can specify a URL to fetch it from with the "--checkpoint-sync-url" flag:

  ```shell
  iex -S mix run -- --checkpoint-sync-url <your_url_here>
  ```

  or you can specify mulitple urls by passing a comma separated list of urls:

  ```shell
  iex -S mix run -- --checkpoint-sync-url "<url1>, <url2>, ..."
  ```

  If multiple urls are provided the downloaded state will be compared for all urls and fail if even one of them differs from the rest

  Some public endpoints can be found in [eth-clients.github.io/checkpoint-sync-endpoints](https://eth-clients.github.io/checkpoint-sync-endpoints/).

  > [!IMPORTANT]
  > The data retrieved from the URL is stored in the DB once the node is initiated (i.e. the iex prompt shows).
  > Once this happens, following runs of `make iex` will start the node using that data.

  ### APIs
  #### Beacon API

  You can start the application with the Beacon API on the default port `4000` running:
  ```shell
  make start
  ```

  You can also specify a port with the "--beacon-api-port" flag:

  ```shell
  iex -S mix run --  --beacon-api-port <your_port_here>
  ```
  > [!WARNING]
  > In case checkpoint-sync is needed, following the instructions above will end immediately with an error (see [Checkpoint Sync](#checkpoint-sync)).
  >

  #### Key-Manager API

  Implemented following the [Ethereum specification](https://ethereum.github.io/keymanager-APIs/#/).

  You can start the application with the key manager API on the default port `5000` running:

  ```shell
  iex -S mix run -- --validator-api
  ```


  You can also specify a port with the "--validator-api-port" flag:

  ```shell
  iex -S mix run -- --validator-api-port <your_port_here>
  ```
  > [!WARNING]
  > In case checkpoint-sync is needed, following the instructions above will end immediately with an error (see [Checkpoint Sync](#checkpoint-sync)).
  >

  ### Tests, linting and formatting

  Our CI runs tests, linters, and also checks formatting and typing.
  To run these checks locally:

  ```shell
  make test      # Runs tests
  make spec-test # Runs all spec-tests
  make lint      # Runs linter and format-checker
  make dialyzer  # Runs type-checker
  ```

  Source code can be formatted using `make fmt`.
  This formats not only the Elixir code, but also the code under [`native/`](./native/).

  ### Consensus spec tests

  You can run all of them with:

  ```shell
  make spec-test
  ```

  Or only run those of a specific config with:

  ```shell
  make spec-test-config-`config`

  # Some examples
  make spec-test-config-mainnet
  make spec-test-config-minimal
  make spec-test-config-general
  ```

  Or by a single runner in all configs, with:

  ```shell
  make spec-test-runner-`runner`

  # Some examples
  make spec-test-runner-ssz_static
  make spec-test-runner-bls
  make spec-test-runner-operations
  ```

  The complete list of test runners can be found [here](https://github.com/ethereum/consensus-specs/tree/dev/tests/formats).

  If you want to specify both a config and a runner:

  ```shell
  make spec-test-mainnet-operations
  make spec-test-minimal-epoch_processing
  make spec-test-general-bls
  ```

  More advanced filtering (e.g. by fork or handler) will be re-added again, but if you want to only run a specific test, you can always do that manually with:

  ```shell
  mix test --no-start test/generated/<config>/<fork>/<runner>.exs:<line_of_your_testcase>
  ```
  You can put a "*" in any directory (e.g. config) you don't want to filter by, although that won't work if adding the line of the testcase.

  > [!NOTE]
  > We specify the `--no-start` flag to stop *ExUnit* from starting the application, to reduce resource consumption.

  ### Docker

  The repo includes a `Dockerfile` for the consensus client. It can be built with:

  ```bash
  docker build -t consensus .
  ```

  Then you run it with `docker run`, adding CLI flags as needed:

  ```bash
  docker run consensus --checkpoint-sync <url> --network <network> ...
  ```

  ## Testing Environment with Kurtosis

  We can test the process and transition of the Beacon state and execution of the consensus rules by connecting the node to Sepolia or even Mainnet. However, testing validators requires at least 32 ETH, which is hard to acquire even in Testnet, and being selected as a block proposer can be a never-ending task. For these reasons, and especially the ability to test multiple validators and completely different scenarios, the best approach currently is to use [`Kurtosis`](https://docs.kurtosis.com/). In combination with the [`ethereum-package`](https://github.com/lambdaclass/ethereum-package.git), kurtosis is a great way to simulate local testnets with a high level of control over the network participants.

  For more details, see [Testing](./docs/TESTING.md).

  ## Live Metrics

  When running the node, use the `--metrics` flag to enable metrics at [`http://localhost:9568/metrics`](http://localhost:9568/metrics) in Prometheus format.

  ### Grafana

  A docker-compose is available at [`metrics/`](./metrics) with a Grafana-Prometheus setup preloaded with dashboards that disponibilize the data.
  To run it, install [Docker Compose](https://docs.docker.com/compose/) and execute:

  ```shell
  make grafana-up
  ```

  After that, open [`http://localhost:3000/`](http://localhost:3000/) in a browser.
  The default username and password are both `admin`.

  To stop the containers run `make grafana-down`. For cleaning up the metrics data, run `make grafana-clean`.

  ## Benchmarks

  Several benchmarks are provided in the `/bench` directory. They are all standard elixir scripts, so they can be run as such. For example:

  ```bash
  mix run bench/byte_reversal.exs
  ```

  Some of the benchmarks require a state or blocks to be available in the db. For this, the easiest thing is to run `make checkpoint-sync` so an anchor state and block are downloaded for mainnet, and optimistic sync starts. If the benchmark requires additional blocks, maybe wait until the first chunk is downloaded and block processing is executed at least once.

  Some need to be executed with `--mode db` in order to not have the store replaced by the application. This needs to be added at the end, like so:

  ```bash
  mix run <script> --mode db
  ```

  A quick summary of the available benchmarks:

  - `deposit_tree`: measures the time of saving and loading an the "execution chain" state, mainly to test how much it costs to save and load a realistic deposit tree. Uses benchee. The conclusion was very low (the order of μs).
  - `byte_reversal`: compares three different methods for byte reversal as a bitlist/bitvector operation. This concludes that using numbers as internal representation for those types would be the most efficient. If we ever need to improve them, that would be a good starting point. 
  - `shuffling_bench`: compares different methods for shuffling: shuffling a list in one go vs computing each shuffle one by one. Shuffling the full list was proved to be 10x faster.
  - `block_processing`: builds a fork choice store with an anchor block and state. Uses the next block available to apply `on_block`, `on_attestation` and `on_attester_slashing` handlers. Runs these handlers 30 times. To run this, at least 2 blocks and a state must be available in the db. It also needs you to set the slot manually at the beginning of an epoch. Try it for the slot that appeared when you ran checkpoint sync (you'll see in the logs something along the lines of `[Checkpoint sync] Received beacon state and block slot=9597856`)
  - `multiple_block_processing`: _currently under revision_. Similar to block processing but with a range of slots so state transition is performed multiple times. The main advantage is that by performing more than one state transition it helps test caches and have a more average-case measurement.
  - `SSZ benchmarks`: they compare between our own library and the rust nif ssz library. To run any of these two benchmarks you previously need to have a BeaconState in the database.
    - `encode_decode_bench`: compares the libraries at encoding and decoding a Checkpoint and a BeaconState container. 
    - `hash_tree_root_bench`: compares the libraries at performing the hash tree root of a Beacon State and packed list of numbers.

  ## Profiling

  ### QCachegrind

  To install [QCachegrind](https://github.com/KDE/kcachegrind) via [Homebrew](https://formulae.brew.sh/formula/qcachegrind), run:

  ```sh
  brew install qcachegrind
  ```

  To build a qcachegrind profile, run, inside iex:

  ```elixir
  LambdaEthereumConsensus.Profile.build()
  ```

  Options and details are in the `Profile` package. After the profile trace is generated, you open it in qcachegrind with:

  ```shell
  qcachegrind callgrind.out.<trace_name>
  ```

  If you want to group the traces by function instead of process, you can use the following before viewing it in qcachegrind:

  ```shell
  grep -v "^ob=" callgrind.out.trace_name > callgrind.out.merged.trace_name
  ```

  ### etop

  Another useful tool to quickly diagnose processes taking too much CPU is `:etop`, similar to UNIX `top` command. This is installed by default in erlang, and included in the `:observer` extra application in `mix.exs`. You can run it with:

  ```elixir
  :etop.start()
  ```

  In particular, the `reds` metric symbolizes `reductions`, which can roughly be interpreted as the number of calls a function got.
  This can be used to identify infinite loops or busy waits.

  Also of note is the `:sort` option, that allows sorting the list by, for example, message queue size:

  ```elixir
  :etop.start(sort: :msg_q)
  ```

  _Note: If you want to use the `:observer` GUI and not just `etop`, you'll probably need `:wx` also set in your extra applications, there is an easy way to do this, just set the `EXTRA_APPLICATIONS` environment variable to `WX` (`export EXTRA_APPLICATIONS=WX`) before starting the node_

  ### eFlambè

  When optimizing code, it might be useful to have a graphic way to determine bottlenecks in the system.
  In that case, you can use [eFlambè](https://github.com/Stratus3D/eflambe) to generate flamegraphs of specific functions.
  The following code will capture information from 10 calls to `Handlers.on_block/2`, dumping it in different files named \<timestamp\>-eflambe-output.bggg.

  ```elixir
  :eflambe.capture({LambdaEthereumConsensus.ForkChoice, :on_block, 2}, 2)
  ```

  The files generated can be processed via common flamegraph tools.
  For example, using [Brendan Gregg's stack](https://github.com/brendangregg/FlameGraph):

  ```shell
  cat *-eflambe-output.bggg | flamegraph.pl - > flamegraph.svg
  ```


## Contributing

  Dream of becoming an Ethereum core developer? Eager to shape the protocol that will underpin tomorrow's world? Want to collaborate with a passionate team, learn, grow, and be a pivotal part of the Ethereum Elixir community?

  **Then you're in the right place! 🚀**

  See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

  Join our [Telegram chat](https://t.me/lambdaconsensus) for discussions.

  ## License

  This project is licensed under the [MIT License](./LICENSE).
