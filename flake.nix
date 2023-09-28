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

          elixir = pkgs.beam.packages.erlang_25.elixir_1_15;

        in 
        {
          devShells.default = pkgs.mkShell {

            buildInputs =  [
              rustToolchain
              pkgs.go_1_20
              pkgs.gotools
              elixir
              pkgs.elixir_ls
              pkgs.glibcLocales
            ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; [ libiconv ])
              ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk.frameworks; [
              CoreFoundation
              CoreServices
              Security
             ]);
          };
        }
    );
}

