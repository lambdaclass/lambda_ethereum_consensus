use crate::utils::gen_struct;
use rustler::{Binary, NifMap};

gen_struct!(
    #[derive(NifMap)]
    /// Corresponds to [`lighthouse_types::Checkpoint`]
    pub(crate) struct Checkpoint {
        epoch: u64,
        root: Binary<'a>,
    }
);

gen_struct!(
    #[derive(NifMap)]
    /// Corresponds to [`lighthouse_types::Fork`]
    pub(crate) struct Fork {
        previous_version: Binary<'a>,
        current_version: Binary<'a>,
        epoch: u64,
    }
);

gen_struct!(
    #[derive(NifMap)]
    /// Corresponds to [`lighthouse_types::ForkData`]
    pub(crate) struct ForkData {
        current_version: Binary<'a>,
        genesis_validators_root: Binary<'a>,
    }
);
