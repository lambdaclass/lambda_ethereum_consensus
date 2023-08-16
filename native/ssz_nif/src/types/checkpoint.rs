use ethereum_types::H256;
use lighthouse_types::Checkpoint;
use rustler::{NifMap, Binary, Env};

use crate::bytes_to_binary;

#[derive(
    NifMap,
    Clone
)]
pub(crate) struct CheckpointNif<'a> {
    epoch: u64,
    root: Binary<'a>,
}

impl<'a> CheckpointNif<'a> {
  pub fn from(checkpoint: Checkpoint, env: Env<'a>) -> Self {
    Self {
        epoch: checkpoint.epoch.into(),
        root: bytes_to_binary(env, &checkpoint.root.as_bytes()),
    }
  }
}

impl Into<Checkpoint> for CheckpointNif<'_> {
    fn into(self) -> Checkpoint {
        let root = H256::from_slice(&self.root.as_slice());
        Checkpoint {
            epoch: self.epoch.into(),
            root,
        }
    }
}
