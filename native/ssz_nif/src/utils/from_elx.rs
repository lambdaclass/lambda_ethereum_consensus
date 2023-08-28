use crate::ssz_types::*;
use ethereum_types::H256;
use rustler::Binary;

pub(crate) trait FromElx<T> {
    fn from(value: T) -> Self;
}

// macro_rules! trivial_impl {
//     ($t:ty => $u:ty) => {
//         impl FromElx<$t> for $u {
//             fn from(value: $t) -> Self {
//                 value.into()
//             }
//         }
//     };
// }

impl<T> FromElx<T> for T {
    fn from(value: Self) -> Self {
        value
    }
}

impl<'a, const N: usize> FromElx<Binary<'a>> for [u8; N] {
    fn from(value: Binary<'a>) -> Self {
        value.as_slice().try_into().unwrap()
    }
}

impl<'a> FromElx<Binary<'a>> for H256 {
    fn from(value: Binary) -> Self {
        H256::from_slice(value.as_slice())
    }
}

impl<'a> FromElx<Vec<Binary<'a>>> for Vec<Root> {
    fn from(value: Vec<Binary>) -> Self {
        // for each root, convert to a slice of 32 bytes
        value
            .into_iter()
            .map(|root| root.as_slice().try_into().unwrap())
            .collect()
    }
}
