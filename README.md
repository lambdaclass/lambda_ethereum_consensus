# Lambda Ethereum Consensus Client

[![CI](https://github.com/lambdaclass/lambda_ethereum_consensus/actions/workflows/ci.yml/badge.svg)](https://github.com/lambdaclass/lambda_ethereum_consensus/actions/workflows/ci.yml)
[![Telegram chat](https://img.shields.io/endpoint?url=https%3A%2F%2Ftg.sumanjay.workers.dev%2Flambdaconsensus%2F&logo=telegram&label=chat&color=neon)](https://t.me/lambdaconsensus)

## Security

We take security seriously. If you discover a vulnerability in this project, please report it responsibly. 

- You can report vulnerabilities directly via the **[GitHub "Report a Vulnerability" feature](../../security/advisories/new)**.
- Alternatively, send an email to **[security@lambdaclass.com](mailto:security@lambdaclass.com)**.

For more details, please refer to our [Security Policy](./.github/SECURITY.md).


## Prerequisites

### Basic Tools

- [Git](https://git-scm.com/)
- [wget](https://www.gnu.org/software/wget/)
- [CMake](https://cmake.org/)

### Direct Installation

You can install the necessary components directly from official sources:

- [Elixir](https://elixir-lang.org/install.html)
- [Erlang](https://www.erlang.org/downloads)
- [Go](https://go.dev/doc/install)
- [Rust](https://www.rust-lang.org/tools/install)
- [Protoc](https://grpc.io/docs/protoc-installation/)

### Alternative (Recommended) Installation

For precise control over versions, it's recommended to use the **asdf** tool version manager and follow the versions specified in `.tool-versions` in this repository.

- [asdf tool version manager](https://asdf-vm.com/guide/getting-started.html)

After installing **asdf**, add the required plugins for managing the tools:

```shell
asdf plugin add elixir
asdf plugin add erlang
asdf plugin add golang
asdf plugin add rust
asdf plugin add protoc
```

Finally, install the specific versions of these tools as specified in `.tool-versions`:

```shell
asdf install
```

### Alternative (easier) Installation using Nix 
To create a sandbox environment with all the required tool chains, use Nix. Steps to get Nix working are as follows:

1. Install Nix from the official website: https://nixos.org/download.
2. To allow experimental features (nix develop and nix-command) you might need to do the following:

```shell
mkdir ~/.config/nix
echo "experimental-features = nix-command flakes " > ~/.config/nix/nix.conf
```

Alternatively, for a smoother experience you can use the following script from [Determinate Systems](https://zero-to-nix.com/start/install) that takes care of setting up everything for you:

```shell 
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

- Check if Nix has been successfully installed: `nix --version`.
- To launch the environment: `nix develop`.

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

### Checkpoint Sync

You can also sync from a checkpoint given by a trusted third-party.
You can specify a URL to fetch it from with the "--checkpoint-sync-url" flag:

```shell
iex -S mix run -- --checkpoint-sync-url <your_url_here>
```

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

To test the node locally, we can simulate other nodes and start from genesis using [`Kurtosis`](https://docs.kurtosis.com/) and the Lambda Class fork of [`ethereum-package`](https://github.com/lambdaclass/ethereum-package.git).

### Why Use Kurtosis
We can test the process and transition of the Beacon state and execution of the consensus rules by connecting the node to Sepolia or even Mainnet. However, testing validators requires at least 32 ETH, which is hard to acquire even in Testnet, and being selected as a block proposer can be a never-ending task. For these reasons, and especially the ability to test multiple validators and completely different scenarios, the best approach currently is to use [`Kurtosis`](https://docs.kurtosis.com/). In combination with the [`ethereum-package`](https://github.com/lambdaclass/ethereum-package.git), kurtosis is a great way to simulate local testnets with a high level of control over the network participants.

### Prerequisites
- [`Docker`](https://docs.docker.com/get-docker/)
- [`Kurtosis`](https://docs.kurtosis.com/install/#ii-install-the-cli)

### Consensus node setup + ethereum-package

As stated in the `ethereum-package` README:
> This is a Kurtosis package that will spin up a private Ethereum testnet over Docker or Kubernetes with multi-client support, Flashbot's mev-boost infrastructure for PBS-related testing/validation, and other useful network tools (transaction spammer, monitoring tools, etc). Kurtosis packages are entirely reproducible and composable, so this will work the same way over Docker or Kubernetes, in the cloud or locally on your machine.

After kurtosis is installed, we need to do three setup steps.

1. Download the lambdaclass ethereum-package fork submodule's content.
2. Copy our Grafana custom dashboards to be able to look at them
3. Build the Docker image of the service

We can accomplish all the steps with a simple.

```bash
make kurtosis.setup
```

or executed each at a time

```bash 
make kurtosis.setup.ethereum-package
# git submodule update --init --recursive

make kurtosis.setup.grafana
# cp -r ./metrics/grafana/provisioning/dashboards/* ./ethereum-package/static_files/grafana-config/dashboards/lambdaconsensus

make kurtosis.setup.lambdaconsensus
# docker build --build-arg IEX_ARGS="--sname lambdaconsensus --cookie secret" -t lambda_ethereum_consensus .

# alternatively, you could build the repo without the node config and cookie just by running
# docker build -t lambda_ethereum_consensus .
```

After that, we will be ready to tweak the configuration.

```bash
vim network_params.yaml
```

We have some sensible defaults for a simple network of 3 clients with 64 Validators each (ethereum-package default) and a slight tweak to the memory limit. Here is an example of the doc; all parameters are explained in [their documentation](https://github.com/ethpandaops/ethereum-package?tab=readme-ov-file#configuration).

```yaml
participants:
 - el_type: geth
    cl_type: lighthouse
    count: 2
 - el_type: geth
    cl_type: lambda
    cl_image: lambda_ethereum_consensus:latest
    use_separate_vc: false
    count: 1
    cl_max_mem: 4096
    keymanager_enabled: true
```

### Kurtosis Execution and Make tasks

For starting the local environment after the setup run:

```bash
# Using the make task
make kurtosis.start

# which executes
kurtosis run --enclave lambdanet ./ethereum-package --args-file network_params.yaml
```

Then, you can connect to the service (running docker instance) with the following:

```bash
# to connect to the instance
make kurtosis.connect

# you can specify the KURTOSIS_SERVICE if the config is different from the default provided:
make kurtosis.connect KURTOSIS_SERVICE=cl-6-lambda-geth
```

Once inside the service, you can connect to the node with a new IEX session running the following.

```bash
make kurtosis.connect.iex

# if you set a specific cookie, you can add it as an argument as before
make kurtosis.connect.iex KURTOSIS_COOKIE=my_secret

# which is just a convenient task over:
iex --sname client --remsh lambdaconsensus --cookie my_secret
```

Now you can check it is working, for example, by examining some constants:

```elixir
#Erlang/OTP 26 [erts-14.2.5] [source] [64-bit] [smp:8:1] [ds:8:1:10] [async-threads:1] [jit]

#Interactive Elixir (1.16.2) - press Ctrl+C to exit (type h() ENTER for help)

Constants.versioned_hash_version_kzg()
# <<1>>
```

### Kurtosis metrics

The [`ethereum-package`](https://github.com/lambdaclass/ethereum-package.git) has prometheus and grafana support built-in. Metrics are being picked up correctly by prometheus, and we have already copied our custom grafana dashboards during the setup step, so you can inspect all of that by accessing the home pages for any of the services (looking for the mapped docker ports). If you want to make changes to the dashboards and see them working with kurtosis afterward, you'll need to update them running again:

```bash
make kurtosis.setup.grafana
```

By default, `ethereum-package` shows it's dashboards in the home page, to see our custom dashboards it's needed to go to `Dashboards` in the left panel and then enter our own `lambdaconsensus` folder.

### Kurtosis cleanup

For a complete cleanup, you could execute the following task.

```bash
# Stop, remove and clean
make kurtosis.purge
```

Suppose the stop was made manually, the purge failed in some step, or the environment was inconsistent for other reasons. In that case, It is also possible to execute every cleanup task individually avoiding the ones not needed:

```bash
# kurtosis enclave stop lambdanet
make kurtosis.stop
# kurtosis enclave rm lambdanet
make kurtosis.remove
# kurtosis clean -a
make kurtosis.clean

# or do it all at once
make kurtosis.purge
```

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

## Why Elixir?

Elixir is a functional programming language that runs atop the Erlang Virtual Machine (BEAM). It offers enhanced readability, syntactic sugar, and reduced boilerplate, enabling developers to achieve more with fewer lines of code compared to Erlang. Like Erlang, Elixir compiles to bytecode that is interpreted by the VM. As a result, it inherits several notable properties, including:

- Fault tolerance for increased reliability
- High availability
- Simplified construction of complex distributed systems
- Predictable latency

[Erlang](https://www.erlang.org/) and its VM were originally developed in 1986 for telecommunication systems that demanded unparalleled uptime and reliability. We recognize that these attributes could be immensely beneficial for an Ethereum client, particularly in the realm of consensus. This is why our current focus is on building a consensus layer (CL) rather than an execution layer (EL). Elixir may not be tailored for sheer performance, but it excels in delivering predictable latency and creating systems designed for continuous operation—qualities essential for the CL.

Our aim is to infuse these strengths into the Ethereum consensus client ecosystem with our offering.

We also have for objective to bootstart an Ethereum Elixir community, and to make Elixir a first-class citizen in the Ethereum ecosystem.

## Contributor Package

Dream of becoming an Ethereum core developer? Eager to shape the protocol that will underpin tomorrow's world? Want to collaborate with a passionate team, learn, grow, and be a pivotal part of the Ethereum Elixir community?

**Then you're in the right place! 🚀**

### Getting Started

#### 1. **Installation**

- **Prerequisites**: Before diving in, ensure you have the necessary tools installed. Check out the [Prerequisites](#prerequisites) section for guidance.
  
- **Clone the Repository**:

  ```shell
  git clone [REPO_URL]
  cd lambda_ethereum_consensus
  ```

- **Setup**: Once you've cloned the repository, follow the steps in the [Installing and running](#installing-and-running) section to set up your environment.

#### 2. **Prerequisite Knowledge**

To contribute effectively, you'll need a foundational understanding of both the Ethereum protocol and the Elixir language, including the Erlang VM (BEAM). If you're new to these areas, we've curated a list of resources to get you started:

**Learning Elixir**:

- **Videos**:
  - [Intro to Elixir](https://youtube.com/playlist?list=PLJbE2Yu2zumA-p21bEQB6nsYABAO-HtF2)
  - [Hitchhiker's tour of the BEAM](https://www.youtube.com/watch?v=_Pwlvy3zz9M)
- **Blogs**:
  - [Zen of Erlang](https://ferd.ca/the-zen-of-erlang.html)
  - [Where Erlang Blooms](https://ferd.ca/rtb-where-erlang-blooms.html)
  - [What can I only do in Erlang](https://erlang.org/pipermail/erlang-questions/2014-November/081570.html)
  - [Stacking theory for systems design](https://medium.com/@jlouis666/stacking-theory-for-systems-design-2450e6300689)
  - [On Erlang States and Crashes](http://jlouisramblings.blogspot.com/2010/11/on-erlang-state-and-crashes.html)
  - [How Erlang does scheduling](http://jlouisramblings.blogspot.com/2013/01/how-erlang-does-scheduling.html)
- **Books**:
  - [Elixir in Action](https://www.manning.com/books/elixir-in-action-third-edition)
  - [Learn You Some Erlang](https://learnyousomeerlang.com/)

With this foundation you should have a basic understanding of the Elixir language and the Erlang VM. You can then start (or in parallel) learning about the Ethereum protocol.

**Learning Ethereum**:

- **Videos**:
  - [Basic technical details of Ethereum](https://youtu.be/gjwr-7PgpN8)
  - [Ethereum in 30 minutes](https://youtu.be/UihMqcj-cqc)
  - [Foundations of Blockchains](https://www.youtube.com/playlist?list=PLEGCF-WLh2RLOHv_xUGLqRts_9JxrckiA)
  - [Ethereum Foundation youtube channel](https://www.youtube.com/@EthereumFoundation)
  - [Ethereum youtube channel](https://www.youtube.com/@EthereumProtocol)
- **Posts**
  - [What happens when you send 1 DAI](https://www.notonlyowner.com/learn/what-happens-when-you-send-one-dai)
- **Books**:
  - [Inevitable Ethereum](https://inevitableeth.com/site/content)
- **Blogs**:
  - [Vitalik Buterin's blog](https://vitalik.ca/)
  - [Ethereum Foundation blog](https://blog.ethereum.org/)
  - [Ethereum Magicians forum](https://ethereum-magicians.org/)
  - [Ethresear.ch forum](https://ethresear.ch/)
  - [EIP's](https://eips.ethereum.org/)
  - [ACD & Related meetings](https://github.com/ethereum/pm)
- **Papers**:
  - [Ethereum Whitepaper](https://ethereum.org/en/whitepaper/)
  - [Ethereum Yellowpaper](https://ethereum.github.io/yellowpaper/paper.pdf)
    - [Yellow paper discussion](https://www.youtube.com/watch?v=e84V1MxRlYs)
    - [Yellow paper walkthrough](https://www.lucassaldanha.com/ethereum-yellow-paper-walkthrough-1/)
  - [Ethereum Beige Paper](https://github.com/chronaeon/beigepaper/blob/master/beigepaper.pdf)
  - [Ethereum Mauve Paper](https://cdn.hackaday.io/files/10879465447136/Mauve%20Paper%20Vitalik.pdf)

**Learning Ethereum Consensus**:

- **Books**:
  - [Eth2Book by Ben Edgington](https://eth2book.info). This book is indispensable for understanding the Ethereum consensus protocol. If you can read only one thing, read this.
- **Specifications**:
  - [Consensus specs](https://github.com/ethereum/consensus-specs)
  - [Vitalik Buterin's annotated specs](https://github.com/ethereum/annotated-spec)
  - [Eth2Book annotated specs](https://eth2book.info/capella/part3/)

While some of the resources listed might appear outdated, it's important to understand that the Ethereum protocol is continuously evolving. As such, there isn't a definitive, unchanging source of information. However, these resources, even if older, provide foundational knowledge that remains pertinent to understanding the protocol's core concepts.

Truly mastering the Ethereum protocol is a complex endeavor. The list provided here is just a starting point, and delving deeper will necessitate exploring a broader range of readings and resources. As you immerse yourself in the project, continuous learning and adaptation will be key.

If you come across any resource that you find invaluable and believe should be added to this list, please don't hesitate to suggest its inclusion.

#### 3. **Dive In**

With your newfound knowledge, explore the various areas of our project. Whether you're interested in the core consensus layer, networking, CLI, documentation, testing, or tooling, there's a place for you.

Start by browsing our [issues](https://github.com/lambdaclass/lambda_ethereum_consensus/issues), especially those tagged as `good first issue`. These are beginner-friendly and a great way to familiarize yourself with our codebase.

### How to contribute

Found an issue you're passionate about? Comment with `"I'd like to tackle this!"` to claim it. Once assigned, you can begin your work. After completing your contribution, submit a pull request for review. Our team and other contributors will be able to provide feedback, and once approved, your contribution will be merged.

Please adhere to the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification when crafting PR titles. Also, run `make fmt` to format source code according to the configured style guide. The repo enforces these automatically via GitHub Actions.

> [!IMPORTANT]  
> We believe in fostering an inclusive, welcoming, and respectful community. All contributors are expected to adhere to our [Code of Conduct](#code-of-conduct). Please familiarize yourself with its contents before participating.

### Communication

**Open communication** is key to the success of any project. We encourage all contributors to join our [Telegram chat](https://t.me/lambdaconsensus) for real-time discussions, updates, and collaboration.

**For more structured discussions or proposals**, consider opening an issue or a discussion on the GitHub repository.

### Recognition

We value every contribution, no matter how small. All contributors will be recognized in our project's documentation. Additionally, consistent and significant contributors may be offered more formal roles within the project over time.

### Support

If you encounter any issues or have questions, don't hesitate to reach out. Our team and the community are here to help. You can ask questions in our Telegram chat or open an issue on GitHub for technical challenges.

### Conclusion

Lambda Ethereum Consensus is more than just a project; it's a community-driven initiative to bring the power and reliability of Elixir to the Ethereum ecosystem. With your help, we can make this vision a reality. Dive in, contribute, learn, and let's shape the future of Ethereum together!

---

**Thank you for being a part of our journey. Let's build an amazing future for Ethereum together! 🚀🌍**

## Code of Conduct

### Our Pledge

We, as members, contributors, and leaders of open source communities and projects pledge to make participation in our community a harassment-free experience for everyone, regardless of age, body size, visible or invisible disability, ethnicity, sex characteristics, gender identity and expression, level of experience, education, socio-economic status, nationality, personal appearance, race, religion, or sexual identity and orientation.

We pledge to act and interact in ways that contribute to an open, welcoming, diverse, inclusive, and healthy community and project.

### Our Standards

Examples of behavior that contributes to a positive environment for our community include:

- Demonstrating empathy and kindness toward other people.
- Being respectful of differing opinions, viewpoints, and experiences.
- Giving and gracefully accepting constructive feedback.
- Accepting responsibility and apologizing to those affected by our mistakes, and learning from the experience.
- Focusing on what is best not just for us as individuals, but for the overall community and project.

Examples of unacceptable behavior include:

- The use of sexualized language or imagery, and sexual attention or advances of any kind.
- Trolling, insulting or derogatory comments, and personal or political attacks.
- Public or private harassment.
- Publishing others' private information, such as a physical or electronic address, without their explicit permission.
- Other conduct which could reasonably be considered inappropriate in a professional setting.

## Enforcement Responsibilities

Maintainers are responsible for clarifying and enforcing standards of acceptable behavior and will take appropriate and fair corrective action.

Project maintainers have the right and responsibility to remove, edit, or reject comments, commits, code, wiki edits, issues, and other contributions that are not aligned to this Code of Conduct, or to ban temporarily or permanently any contributor for behaviors that they deem inappropriate, threatening, offensive, or harmful.

## Enforcement

Instances of abusive, harassing, or otherwise unacceptable behavior may be reported with proof to the maintainers through Telegram. All complaints will be reviewed and investigated promptly, fairly and anonymously.

## Attribution

This Code of Conduct is adapted from the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct.html), version 2.1.

## Contributors

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://www.linkedin.com/in/paul-henrykajfasz/"><img src="https://avatars.githubusercontent.com/u/42912740?v=4?s=100" width="100px;" alt="Paul-Henry Kajfasz"/><br /><sub><b>Paul-Henry Kajfasz</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=phklive" title="Code">💻</a> <a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=phklive" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/MegaRedHand"><img src="https://avatars.githubusercontent.com/u/47506558?v=4?s=100" width="100px;" alt="Tomás"/><br /><sub><b>Tomás</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=MegaRedHand" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/mpaulucci"><img src="https://avatars.githubusercontent.com/u/1040971?v=4?s=100" width="100px;" alt="Martin Paulucci"/><br /><sub><b>Martin Paulucci</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=mpaulucci" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Arkenan"><img src="https://avatars.githubusercontent.com/u/6244161?v=4?s=100" width="100px;" alt="Tomás Arjovsky"/><br /><sub><b>Tomás Arjovsky</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=Arkenan" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/h3lio5"><img src="https://avatars.githubusercontent.com/u/47632450?v=4?s=100" width="100px;" alt="Akash S M"/><br /><sub><b>Akash S M</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=h3lio5" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/berwingan"><img src="https://avatars.githubusercontent.com/u/45144467?v=4?s=100" width="100px;" alt="berwin"/><br /><sub><b>berwin</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=berwingan" title="Code">💻</a> <a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=berwingan" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://f3r10.github.io/#/all-pages"><img src="https://avatars.githubusercontent.com/u/4682815?v=4?s=100" width="100px;" alt="Fernando Ledesma"/><br /><sub><b>Fernando Ledesma</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=f3r10" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/karasakalmt"><img src="https://avatars.githubusercontent.com/u/32202283?v=4?s=100" width="100px;" alt="Mete Karasakal"/><br /><sub><b>Mete Karasakal</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=karasakalmt" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://federicocarrone.com/"><img src="https://avatars.githubusercontent.com/u/569014?v=4?s=100" width="100px;" alt="Federico Carrone"/><br /><sub><b>Federico Carrone</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=unbalancedparentheses" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://godspowereze.com"><img src="https://avatars.githubusercontent.com/u/61994334?v=4?s=100" width="100px;" alt="Godspower Eze"/><br /><sub><b>Godspower Eze</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=Godspower-Eze" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/namn-grg"><img src="https://avatars.githubusercontent.com/u/97289118?v=4?s=100" width="100px;" alt="Naman Garg"/><br /><sub><b>Naman Garg</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=namn-grg" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/ayushm2003"><img src="https://avatars.githubusercontent.com/u/62571011?v=4?s=100" width="100px;" alt="Ayush"/><br /><sub><b>Ayush</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=ayushm2003" title="Documentation">📖</a> <a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=ayushm2003" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/sm-stack"><img src="https://avatars.githubusercontent.com/u/94497407?v=4?s=100" width="100px;" alt="Seungmin Jeon"/><br /><sub><b>Seungmin Jeon</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=sm-stack" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/manojkgorle"><img src="https://avatars.githubusercontent.com/u/65953961?v=4?s=100" width="100px;" alt="Manoj"/><br /><sub><b>Manoj</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=manojkgorle" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/avilagaston9"><img src="https://avatars.githubusercontent.com/u/72628438?v=4?s=100" width="100px;" alt="Avila Gastón"/><br /><sub><b>Avila Gastón</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=avilagaston9" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/guha-rahul"><img src="https://avatars.githubusercontent.com/u/52607971?v=4?s=100" width="100px;" alt="guha-rahul"/><br /><sub><b>guha-rahul</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=guha-rahul" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/artemd24"><img src="https://avatars.githubusercontent.com/u/19683603?v=4?s=100" width="100px;" alt="Artem"/><br /><sub><b>Artem</b></sub></a><br /><a href="https://github.com/lambdaclass/lambda_ethereum_consensus/commits?author=artemd24" title="Code">💻</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
