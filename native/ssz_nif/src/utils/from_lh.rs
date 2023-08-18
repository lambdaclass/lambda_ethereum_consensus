use crate::utils::helpers::bytes_to_binary;
use ethereum_types::H256;
use lighthouse_types::{BitList, Epoch, PublicKeyBytes, Slot, Unsigned};
use rustler::Binary;

pub(crate) trait FromLH<'a, T> {
    fn from(value: T, env: rustler::Env<'a>) -> Self;
}

macro_rules! trivial_impl {
    ($t:ty => $u:ty) => {
        impl<'a> FromLH<'a, $t> for $u {
            fn from(value: $t, _env: rustler::Env<'a>) -> Self {
                value.into()
            }
        }
    };
}

trivial_impl!(Epoch => u64);
trivial_impl!(Slot => u64);

impl<'a, T> FromLH<'a, T> for T {
    fn from(value: Self, _env: rustler::Env<'a>) -> Self {
        value
    }
}

impl<'a> FromLH<'a, H256> for Binary<'a> {
    fn from(value: H256, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, value.as_bytes())
    }
}

impl<'a> FromLH<'a, [u8; 4]> for Binary<'a> {
    fn from(value: [u8; 4], env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value)
    }
}

impl<'a> FromLH<'a, PublicKeyBytes> for Binary<'a> {
    fn from(value: PublicKeyBytes, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, value.as_serialized())
    }
}

impl<'a, N: Unsigned> FromLH<'a, BitList<N>> for Binary<'a> {
    fn from(value: BitList<N>, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, value.as_slice())
    }
}
