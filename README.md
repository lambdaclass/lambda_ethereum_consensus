# Lambda Ethereum Consensus

## Prerequisites

### Direct Installation
You can install the necessary components directly from official sources:
- [Elixir](https://elixir-lang.org/install.html)
- [Erlang](https://www.erlang.org/downloads)
- [Go](https://go.dev/doc/install)

### Alternative (Recommended) Installation
For precise control over versions, it's recommended to use the **asdf** tool version manager and follow the versions specified in `.tool-versions` in this repository.
- [asdf tool version manager](https://github.com/asdf-vm/asdf)

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
