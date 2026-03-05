{
  description = "Nix development environment for LambdaClass Ethereum Consensus Client.";

  # Flake inputs
  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay"; # a helper for Rust + Nix
    flake-utils.url  = "github:numtide/flake-utils";
  };

  # Flake outputs
  outputs = { self, nixpkgs, rust-overlay, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
        let 
          overlays = [ (import rust-overlay) ];
          pkgs = import nixpkgs {
            inherit system overlays;
          };

          rustToolchain = pkgs.rust-bin.stable."1.93.1".default;
          otp = pkgs.beam.packages.erlang_28;

        in 
        {
          devShells.default = pkgs.mkShell {

            buildInputs =  [
              rustToolchain
              pkgs.go_1_26
              pkgs.gotools
              otp.erlang
              otp.elixir_1_19
              pkgs.elixir-ls
              pkgs.glibcLocales
              pkgs.protobuf
              pkgs.cmake
            ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; [ libiconv ]);

            shellHook = ''
              if [ -f ~/.git-prompt.sh ]; then
                GIT_PS1_SHOWUPSTREAM="auto"
                GIT_PS1_SHOWCOLORHINTS="yes"
                source ~/.git-prompt.sh
                export PROMPT_COMMAND='__git_ps1 "\u@\h:\W" "\\\$ ";'
              fi

              export PATH="$HOME/go/bin:$HOME/.mix/escripts:$PATH"
            '';
          };
        }
    );
}

