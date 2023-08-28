//! # Elixir Types
//!
//! To add a new type, add the struct definition (with [`rustler`] types)
//! in the corresponding module. You may need to add some [`FromElx`] and
//! [`FromLH`] implementations to convert between the types.

mod beacon_chain;
pub(crate) use beacon_chain::*;
use rustler::Binary;

type Bytes4<'a> = Binary<'a>;
type Bytes20<'a> = Binary<'a>;
type Bytes32<'a> = Binary<'a>;
type Bytes48<'a> = Binary<'a>;
type Bytes96<'a> = Binary<'a>;

type Slot = u64;
type Epoch = u64;
type CommitteeIndex = u64;
type ValidatorIndex = u64;
type Gwei = u64;
type Root<'a> = Bytes32<'a>;
type Hash32<'a> = Bytes32<'a>;
type Version<'a> = Bytes4<'a>;
type DomainType<'a> = Bytes4<'a>;
type ForkDigest<'a> = Bytes4<'a>;
type Domain<'a> = Bytes32<'a>;
type BLSPubkey<'a> = Bytes48<'a>;
type BLSSignature<'a> = Bytes96<'a>;
type ParticipationFlags = u8;
type Transaction<'a> = Binary<'a>; // max size: 1073741824
type ExecutionAddress<'a> = Bytes20<'a>;
type WithdrawalIndex = u64;
