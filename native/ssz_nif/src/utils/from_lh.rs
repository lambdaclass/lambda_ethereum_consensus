use crate::utils::helpers::bytes_to_binary;
use ethereum_types::H256;
use lighthouse_types::Epoch;
use rustler::Binary;

pub(crate) trait FromLH<'a, T> {
    fn from(value: T, env: rustler::Env<'a>) -> Self;
}

macro_rules! impl_int {
    ($t:ty => $u:ty) => {
        impl<'a> FromLH<'a, $t> for $u {
            fn from(value: $t, _env: rustler::Env<'a>) -> Self {
                value.into()
            }
        }
    };
}

impl_int!(Epoch => u64);

impl<'a> FromLH<'a, H256> for Binary<'a> {
    fn from(value: H256, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, value.as_bytes())
    }
}
