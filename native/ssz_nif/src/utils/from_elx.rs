use ethereum_types::H256;
use rustler::Binary;
use ssz::Decode;

pub(crate) trait FromElx<T> {
    fn from(value: T) -> Self;
}

macro_rules! trivial_impl {
    ($t:ty => $u:ty) => {
        impl FromElx<$t> for $u {
            fn from(value: $t) -> Self {
                value.into()
            }
        }
    };
}

impl<T> FromElx<T> for T {
    fn from(value: Self) -> Self {
        value
    }
}

impl<'a> FromElx<Binary<'a>> for [u8; 32] {
    fn from(value: Binary<'a>) -> Self {
        value.as_slice().try_into().unwrap()
    }
}

impl<'a> FromElx<Binary<'a>> for H256 {
    fn from(value: Binary) -> Self {
        H256::from_slice(value.as_slice())
    }
}

impl<'a> FromElx<Binary<'a>> for [u8; 4] {
    fn from(value: Binary) -> Self {
        // length is checked from the Elixir side
        value.as_slice().try_into().unwrap()
    }
}
