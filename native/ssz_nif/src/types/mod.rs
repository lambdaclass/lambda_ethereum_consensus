//! # Types
//!
//! To add a new type, add the struct definition (with [`rustler`] types)
//! in the corresponding module. You may need to add some [`FromElx`] and
//! [`FromLH`] implementations to convert between the types.

mod beacon_chain;
pub(crate) use beacon_chain::*;
