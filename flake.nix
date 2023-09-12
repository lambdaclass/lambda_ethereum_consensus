{
  description = "Example Rust development environment for Zero to Nix";

  # Flake inputs
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # also valid: "nixpkgs"
    rust-overlay.url = "github:oxalica/rust-overlay"; # A helper for Rust + Nix
    flake-utils.url = "github:numtide/flake-utils";
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

          rustToolchain = pkgs.rust-bin.stable.latest.default;

          elixir = pkgs.erlangR25.elixir.override {
          version = "1.15";
          sha256 = pkgs.lib.fakeSha256;
        };

        erlang = pkgs.erlangR25.override {
          version = "25.3";
          sha256 = pkgs.lib.fakeSha256;
        };

        in 
        {
          devShells.default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              pkg-config
              protobuf
            ];

            packages = with pkgs; [
              rustToolchain
            ] ++ lib.optionals stdenv.isDarwin [
              darwin.apple_sdk.frameworks.Security
            ];
          };
        }
    );
#     let
#       # Overlays enable you to customize the Nixpkgs attribute set
#       overlays = [
#         # Makes a `rust-bin` attribute available in Nixpkgs
#         (import rust-overlay)
#         # Provides a `rustToolchain` attribute for Nixpkgs that we can use to
#         # create a Rust environment
#         (self: super: {
#           rustToolchain = super.rustToolchain.stable.latest.default;
#         })
#       ];

#       # Systems supported
#       allSystems = [
#         "x86_64-linux" # 64-bit Intel/AMD Linux
#         "aarch64-linux" # 64-bit ARM Linux
#         "x86_64-darwin" # 64-bit Intel macOS
#         "aarch64-darwin" # 64-bit ARM macOS
#       ];

#       # Helper to provide system-specific attributes
#       forAllSystems = f: nixpkgs.lib.genAttrs allSystems (system: f {
#         pkgs = import nixpkgs { inherit overlays system; };

#         elixir = pkgs.erlangR25.elixir.override {
#           version = "1.15";
#           sha256 = pkgs.lib.fakeSha256;
#         };

#         erlang = pkgs.erlangR25.override {
#           version = "25.3";
#           sha256 = pkgs.lib.fakeSha256;
#         };

#       });
#     in
#     {
#       # Development environment output
#       devShells = forAllSystems ({ pkgs }: {
#         default = pkgs.mkShell {
#           # The Nix packages provided in the environment
#           buildInputs = (with pkgs; [
#             # The package provided by our custom overlay. Includes cargo, Clippy, cargo-fmt,
#             # rustdoc, rustfmt, and other tools.
#             rustToolchain
#             go_1_20 # Go 1.20
#             gotools # Go tools like goimports, godoc, an others
#             elixir
#             erlang
#             elixir_ls
#             glibcLocales
#           ]) ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; [ libiconv ])
#              ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
#               CoreFoundation
#               CoreServices
#               Security
#              ]);
#         };
#       });
#     };
}
