# Lambda_Ethereum_Consensus

[![Telegram chat](https://img.shields.io/endpoint?url=https%3A%2F%2Ftg.sumanjay.workers.dev%2Flambdaconsensus%2F&logo=telegram&label=chat&color=neon)](https://t.me/lambdaconsensus)

## Why Elixir?

Elixir is a functional programming language that runs atop the Erlang Virtual Machine (BEAM). It offers enhanced readability, syntactic sugar, and reduced boilerplate, enabling developers to achieve more with fewer lines of code compared to Erlang. Like Erlang, Elixir compiles to bytecode that is interpreted by the VM. As a result, it inherits several notable properties, including:

- Fault tolerance for increased reliability
- High availability
- Simplified construction of complex distributed systems
- Predictable latency

[Erlang](https://www.erlang.org/) and its VM were originally developed in 1986 for telecommunication systems that demanded unparalleled uptime and reliability. We recognize that these attributes could be immensely beneficial for an Ethereum client, particularly in the realm of consensus. This is why our current focus is on building a consensus layer (CL) rather than an execution layer (EL). Elixir may not be tailored for sheer performance, but it excels in delivering predictable latency and creating systems designed for continuous operation—qualities essential for the CL.

Our aim is to infuse these strengths into the Ethereum consensus client ecosystem with our offering.

We also have for objective to bootstart an Ethereum Elixir community, and to make Elixir a first-class citizen in the Ethereum ecosystem.

## Prerequisites

### Direct Installation
You can install the necessary components directly from official sources:
- [Elixir](https://elixir-lang.org/install.html)
- [Erlang](https://www.erlang.org/downloads)
- [Go](https://go.dev/doc/install)

### Alternative (Recommended) Installation
For precise control over versions, it's recommended to use the **asdf** tool version manager and follow the versions specified in `.tool-versions` in this repository.
- [asdf tool version manager](https://asdf-vm.com/guide/getting-started.html)

After installing **asdf**, add the required plugins for managing the tools:
```shell
asdf plugin add elixir
asdf plugin add erlang
asdf plugin add golang
```
Finally, install the specific versions of these tools as specified in `.tool-versions`:
```shell
asdf install
```

## Installing and running

There are Makefile targets for these tasks.

```shell
make deps # Installs dependencies
make iex  # Runs a terminal with the application started
make test # Runs tests
```

The iex terminal can be closed by pressing ctrl+c two times.
