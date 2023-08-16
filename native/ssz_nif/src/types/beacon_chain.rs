use rustler::{Binary, NifMap};

use crate::gen_struct;

gen_struct!(
    #[derive(NifMap)]
    pub(crate) struct Checkpoint {
        epoch: u64,
        root: Binary<'a>,
    }
);
