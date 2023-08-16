use rustler::{Binary, NifMap};

use crate::gen_struct;

gen_struct!(
    #[derive(NifMap)]
    pub(crate) struct Checkpoint {
        epoch: u64,
        root: Binary<'a>,
    }
);

gen_struct!(
    #[derive(NifMap)]
    pub(crate) struct Fork {
        previous_version: Binary<'a>,
        current_version: Binary<'a>,
        epoch: u64,
    }
);
