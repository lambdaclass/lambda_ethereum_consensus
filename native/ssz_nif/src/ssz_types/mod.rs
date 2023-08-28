//! # SSZ Types
//!
//! Structs that implement [`ssz::Encode`] and [`ssz::Decode`].

mod beacon_chain;

type Bytes4 = [u8; 4];
type Bytes20 = [u8; 20];
type Bytes32 = [u8; 32];
type Bytes48 = [u8; 48];
type Bytes96 = [u8; 96];

type Slot = u64;
type Epoch = u64;
type CommitteeIndex = u64;
type ValidatorIndex = u64;
type Gwei = u64;
pub type Root = Bytes32;
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
use ssz_types::{typenum, VariableList};

/*| Name | SSZ equivalent | Description |
| - | - | - |
| `Slot` | `uint64` | a slot number |
| `Epoch` | `uint64` | an epoch number |
| `CommitteeIndex` | `uint64` | a committee index at a slot |
| `ValidatorIndex` | `uint64` | a validator registry index |
| `Gwei` | `uint64` | an amount in Gwei |
| `Root` | `Bytes32` | a Merkle root |
| `Hash32` | `Bytes32` | a 256-bit hash |
| `Version` | `Bytes4` | a fork version number |
| `DomainType` | `Bytes4` | a domain type |
| `ForkDigest` | `Bytes4` | a digest of the current fork data |
| `Domain` | `Bytes32` | a signature domain |
| `BLSPubkey` | `Bytes48` | a BLS12-381 public key |
| `BLSSignature` | `Bytes96` | a BLS12-381 signature |
| `ParticipationFlags` | `uint8` | a succinct representation of 8 boolean participation flags |
| `Transaction` | `ByteList[MAX_BYTES_PER_TRANSACTION]` | either a [typed transaction envelope](https://eips.ethereum.org/EIPS/eip-2718#opaque-byte-array-rather-than-an-rlp-array) or a legacy transaction |
| `ExecutionAddress` | `Bytes20` | Address of account on the execution layer |
| `WithdrawalIndex` | `uint64` | an index of a `Withdrawal` | */
