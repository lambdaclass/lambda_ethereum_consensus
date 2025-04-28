# Testing with Kurtosis


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
