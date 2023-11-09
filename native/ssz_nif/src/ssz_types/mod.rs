//! # SSZ Types
//!
//! Structs that implement [`ssz::Encode`] and [`ssz::Decode`].

mod beacon_chain;
mod p2p;
mod validator;

pub(crate) use beacon_chain::*;
pub(crate) use p2p::*;
pub(crate) use validator::*;

pub(crate) mod config;

use ssz_derive::{Decode, Encode};
use ssz_types::{typenum, FixedVector, VariableList};

type Bytes4 = [u8; 4];
type Bytes20 = FixedVector<u8, typenum::U20>;
type Bytes32 = [u8; 32];
type Bytes48 = FixedVector<u8, typenum::U48>;
type Bytes96 = FixedVector<u8, typenum::U96>;

type Slot = u64;
type Epoch = u64;
type CommitteeIndex = u64;
type ValidatorIndex = u64;
type Gwei = u64;
pub(crate) type Root = Bytes32;
type Hash32 = Bytes32;
type Version = Bytes4;
#[allow(dead_code)]
type DomainType = Bytes4;
#[allow(dead_code)]
type ForkDigest = Bytes4;
type Domain = Bytes32;
type BLSPubkey = Bytes48;
type BLSSignature = Bytes96;
#[allow(dead_code)]
type ParticipationFlags = u8;
pub(crate) type Transaction =
    VariableList<u8, /* `MAX_BYTES_PER_TRANSACTION` */ typenum::U1073741824>;
type ExecutionAddress = Bytes20;
type WithdrawalIndex = u64;

// This type is a little-endian encoded uint256.
// We use this to because of Erlang's NIF limitations.
#[derive(Clone, Copy, Encode, Decode)]
#[ssz(struct_behaviour = "transparent")]
pub(crate) struct Uint256(pub(crate) [u8; 32]);

impl tree_hash::TreeHash for Uint256 {
    fn tree_hash_type() -> tree_hash::TreeHashType {
        <[u8; 32]>::tree_hash_type()
    }

    fn tree_hash_packed_encoding(&self) -> tree_hash::PackedEncoding {
        self.0.tree_hash_packed_encoding()
    }

    fn tree_hash_packing_factor() -> usize {
        <[u8; 32]>::tree_hash_packing_factor()
    }

    fn tree_hash_root(&self) -> tree_hash::Hash256 {
        self.0.tree_hash_root()
    }
}
