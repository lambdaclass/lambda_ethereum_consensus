# Simple SerialiZe NIF implementation

## Adding a new type

In order to add a new SSZ container to the repo, we need to modify the NIF. Here's the how-to:

*Note that you can start from whichever side you are most comfortable with.*

Rust side (`native/ssz_nif`):

1. Look for the struct definition in the *[lighthouse_types](https://github.com/sigp/lighthouse/tree/stable/consensus/types)* crate (it should have the same name as in the [spec](https://github.com/ethereum/consensus-specs/tree/dev)).
2. Add the struct definition to the corresponding module under `native/ssz_nif/src/types`, surrounding it with `gen_struct` and adding the `#[derive(NifStruct)]` and `#[module …]` attributes (you can look at `beacon_chain.rs` for examples).
3. If the lighthouse struct uses generics, you’ll have to alias it in `native/ssz_nif/src/lh_types.rs`, and use that same name for your struct.
4. Translate the types used (`Epoch`, `[u64; 32]`, etc.) to ones that implement *rustler* traits (you can look at [this cheat sheet](https://rustler-web.onrender.com/docs/cheat-sheet), or at the already implemented containers). These types should be equivalent to the ones used in [the official spec](https://github.com/ethereum/consensus-specs/tree/dev).
5. If it fails because `FromElx` or `FromLH` are not implemented for types X and Y, add those implementations in `utils/from_elx.rs` and `utils/from_lh.rs` respectively.
6. Add the type name to the list in `to_ssz` and `from_ssz`.
7. Check that it compiles correctly.

Elixir side:

1. Add a new file and module with the container's name under `lib/ssz_types`. The module should be prefixed with `SszTypes.` (you can use an existing one as a template).
2. Add the struct definition and `t` type. You should try to mimic types used in the official spec, like those in `lib/ssz_types/mod.ex` (feel free to add any that are missing).
3. Add the implemented struct's name to the `@enabled` list in the `SSZStaticTestRunner` module (file `test/spec/runners/ssz_static.ex`).
4. Check that spec-tests pass, running `make spec-test`. For this, you should have all the project dependencies installed (this is explained in the main readme).

## Some things to keep in mind

- Some SSZ containers depend on the configuration: "mainnet", "minimal". Their names should be suffixed with the configuration name. For example: [`HistoricalBatch`](../../lib/ssz_types/pending_attestation.ex).
- Since we run spec-tests with the "minimal" configurations and the target configuration is "mainnet", those two should be prioritized. If the constants they depend on are different (you can check this by comparing their values in [the spec](https://github.com/ethereum/consensus-specs/tree/dev/configs)), two containers need to be implemented: one for "mainnet", and another for "minimal". Also, the container names should be mapped in the corresponding spec-test config (e.g: [mainnet](../../test/spec/configs/mainnet.ex), [minimal](../../test/spec/configs/minimal.ex)) An example of this is [`HistoricalBatch`](../../lib/ssz_types/historical_batch.ex).
