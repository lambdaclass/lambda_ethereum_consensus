# Prerequisites

## Basic Tools

- [Git](https://git-scm.com/)
- [wget](https://www.gnu.org/software/wget/)
- [CMake](https://cmake.org/)

## Direct Installation

You can install the necessary components directly from official sources:

- [Elixir](https://elixir-lang.org/install.html)
- [Erlang](https://www.erlang.org/downloads)
- [Go](https://go.dev/doc/install)
- [Rust](https://www.rust-lang.org/tools/install)
- [Protoc](https://grpc.io/docs/protoc-installation/)

## Alternative (Recommended) Installation

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

## Alternative (easier) Installation using Nix 
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
