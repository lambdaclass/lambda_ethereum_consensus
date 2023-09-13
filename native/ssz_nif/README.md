# Simple SerialiZe NIF implementation

## Adding a new type

In order to add a new SSZ container to the repo, we need to modify the NIF. Here's the how-to:

*Note that you can start from whichever side you are most comfortable with.*

Rust side (`native/ssz_nif`):

1. Look for the container definition in the [official consensus specs](https://github.com/ethereum/consensus-specs/tree/dev).
2. Add the struct definition to the corresponding module under `native/ssz_nif/src/ssz_types` (e.g. `beacon_chain.rs` for containers defined in `beacon-chain.md`) with `#[derive(Encode, Decode, TreeHash)]`.
3. Do the same under `native/ssz_nif/src/elx_types`, but surrounding it with the `gen_struct` macro, and adding `#[derive(NifStruct)]` and `#[module …]` attributes (you can look at `beacon_chain.rs` for examples).
4. Translate the types used (`Epoch`, `Slot`, etc.) to ones that implement *rustler* traits (you can look at [this cheat sheet](https://rustler-web.onrender.com/docs/cheat-sheet), or at the already implemented containers).
5. If it fails because `FromElx` or `FromSsz` are not implemented for types X and Y, add those implementations in `utils/from_elx.rs` and `utils/from_ssz.rs` respectively.
6. Add the type name to the list in `to_ssz_rs`, `from_ssz_rs`, and `hash_tree_root_rs`.
7. Check that it compiles correctly.

Elixir side:

1. Add a new file and module with the container's name under `lib/ssz_types`. The module should be prefixed with `SszTypes.` (you can use an existing one as a template).
2. Add the struct definition and `t` type. You should try to mimic types used in the official spec, like those in `lib/ssz_types/mod.ex` (feel free to add any that are missing).
3. Remove the implemented struct's name from the `@disabled` list in the `SSZStaticTestRunner` module (file `test/spec/runners/ssz_static.ex`).
4. Check that it compiles correctly.

After implementing everything, check that spec-tests pass by running `make spec-test`. Before this, you should have all the project dependencies installed (this is explained in the main readme).

## Containers with constants

Some SSZ containers depend on variable configuration, for example `HistoricalBatch`. In these cases, we should implement the functionality for the "minimal" and "mainnet" presets, and map the test handlers with their corresponding structs inside the config modules from [`test/spec/configs`](../../test/spec/configs).
