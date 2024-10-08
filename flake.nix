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

          rustToolchain = pkgs.rust-bin.stable."1.71.1".default;
          otp = pkgs.beam.packages.erlang_26;

        in 
        {
          devShells.default = pkgs.mkShell {

            buildInputs =  [
              rustToolchain
              pkgs.go_1_21
              pkgs.gotools
              otp.erlang
              nixpkgs.legacyPackages.aarch64-darwin.elixir_1_16
              pkgs.elixir_ls
              pkgs.glibcLocales
              pkgs.protobuf3_24
            ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; [ libiconv ])
              ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk.frameworks; [
              CoreFoundation
              CoreServices
              Security
             ]);

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

