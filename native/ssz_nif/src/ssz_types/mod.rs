#![allow(unused)]

//! # SSZ Types
//!
//! Structs that implement [`ssz::Encode`] and [`ssz::Decode`].

mod beacon_chain;

type Bytes4 = [u8; 4];
type Bytes20 = [u8; 20];
type Bytes32 = [u8; 32];
type Bytes48 = [u8; 48];
type Bytes96 = FixedVector<u8, typenum::U96>;

type Slot = u64;
type Epoch = u64;
type CommitteeIndex = u64;
type ValidatorIndex = u64;
type Gwei = u64;
type Root = Bytes32;
type Hash32 = Bytes32;
type Version = Bytes4;
type DomainType = Bytes4;
type ForkDigest = Bytes4;
type Domain = Bytes32;
type BLSPubkey = Bytes48;
type BLSSignature = Bytes96;
type ParticipationFlags = u8;
type Transaction = VariableList<u8, /* `MAX_BYTES_PER_TRANSACTION` */ typenum::U1073741824>;
type ExecutionAddress = Bytes20;
type WithdrawalIndex = u64;

pub(crate) use beacon_chain::*;
use ssz_types::{typenum, FixedVector, VariableList};
