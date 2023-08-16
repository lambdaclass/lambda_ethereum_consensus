use ethereum_types::H256;
use lighthouse_types::Epoch;
use rustler::Binary;

pub(crate) trait FromElx<T> {
    fn from(value: T) -> Self;
}

macro_rules! impl_int {
    ($t:ty => $u:ty) => {
        impl FromElx<$t> for $u {
            fn from(value: $t) -> Self {
                value.into()
            }
        }
    };
}

impl_int!(u64 => Epoch);

impl<'a> FromElx<Binary<'a>> for H256 {
    fn from(value: Binary) -> Self {
        H256::from_slice(&value.as_slice())
    }
}
