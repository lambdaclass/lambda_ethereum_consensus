use crate::{ssz_types::Root, utils::helpers::bytes_to_binary};
use ethereum_types::H256;
use rustler::Binary;

pub(crate) trait FromLH<'a, T> {
    fn from(value: T, env: rustler::Env<'a>) -> Self;
}

// macro_rules! trivial_impl {
//     ($t:ty => $u:ty) => {
//         impl<'a> FromLH<'a, $t> for $u {
//             fn from(value: $t, _env: rustler::Env<'a>) -> Self {
//                 value.into()
//             }
//         }
//     };
// }

impl<'a, T> FromLH<'a, T> for T {
    fn from(value: Self, _env: rustler::Env<'a>) -> Self {
        value
    }
}

impl<'a, const N: usize> FromLH<'a, [u8; N]> for Binary<'a> {
    fn from(value: [u8; N], env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value)
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

impl<'a> FromLH<'a, Vec<Root>> for Vec<Binary<'a>> {
    fn from(value: Vec<Root>, env: rustler::Env<'a>) -> Self {
        value
            .into_iter()
            .map(|root| bytes_to_binary(env, &root))
            .collect()
    }
}
