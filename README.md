# lambda_ethereum_consensus

## Prerequisites
### Direct
Install directly through offocial mirrors
- [elixir](https://elixir-lang.org/install.html)
- [erlang](https://www.erlang.org/downloads)
- [golang](https://go.dev/doc/install)

### Alternative (recommended)
Use tool version manager **asdf** to follow this repo's exact versions located in `.tool-versions`
- [tool manager asdf](https://github.com/asdf-vm/asdf)

After installing **asdf**, add the necessary plugins to handle the tools.
```shell
asdf plugin add elixir
asdf plugin add erlang
asdf plugin add golang
```
Finally, install the tools' version on `.tool-version`.
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
