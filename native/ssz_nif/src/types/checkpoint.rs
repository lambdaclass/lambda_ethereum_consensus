use ethereum_types::H256;
use lighthouse_types::Checkpoint as LHCheckpoint;
use rustler::{Binary, Env, NifMap};

use crate::bytes_to_binary;

#[derive(NifMap, Clone)]
pub(crate) struct Checkpoint<'a> {
    epoch: u64,
    root: Binary<'a>,
}

impl<'a> Checkpoint<'a> {
    pub fn from(checkpoint: LHCheckpoint, env: Env<'a>) -> Self {
        Self {
            epoch: checkpoint.epoch.into(),
            root: bytes_to_binary(env, &checkpoint.root.as_bytes()),
        }
    }
}

impl Into<LHCheckpoint> for Checkpoint<'_> {
    fn into(self) -> LHCheckpoint {
        let root = H256::from_slice(&self.root.as_slice());
        LHCheckpoint {
            epoch: self.epoch.into(),
            root,
        }
    }
}
