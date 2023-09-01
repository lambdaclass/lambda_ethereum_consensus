use rustler::Binary;
use ssz::Decode;
use ssz_types::{typenum::Unsigned, BitList, BitVector, FixedVector, VariableList};
use std::fmt::{Debug, Display};

use crate::ssz_types::Uint256;

#[derive(Debug)]
pub struct FromElxError(String);

impl Display for FromElxError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{e}", e = self.0)
    }
}

impl FromElxError {
    fn from_display<T: Display>(t: T) -> Self {
        t.to_string().into()
    }

    fn from_debug<T: Debug>(t: T) -> Self {
        format!("{t:?}").into()
    }
}

impl From<String> for FromElxError {
    fn from(t: String) -> Self {
        Self(t)
    }
}

pub(crate) trait FromElx<T>
where
    Self: Sized,
{
    fn from(value: T) -> Result<Self, FromElxError>;
}

macro_rules! trivial_impl {
    ($t:ty) => {
        impl FromElx<$t> for $t {
            fn from(value: $t) -> Result<Self, FromElxError> {
                Ok(value)
            }
        }
    };
}

trivial_impl!(bool);
trivial_impl!(u8);
trivial_impl!(u16);
trivial_impl!(u32);
trivial_impl!(u64);

impl<'a, const N: usize> FromElx<Binary<'a>> for [u8; N] {
    fn from(value: Binary<'a>) -> Result<Self, FromElxError> {
        let v: Result<Self, _> = value.as_slice().try_into();
        v.map_err(FromElxError::from_display)
    }
}

impl<Elx, Ssz> FromElx<Vec<Elx>> for Vec<Ssz>
where
    Ssz: FromElx<Elx>,
{
    fn from(value: Vec<Elx>) -> Result<Self, FromElxError> {
        // for each root, convert to a slice of 32 bytes
        value.into_iter().map(FromElx::from).collect()
    }
}
impl<'a, N: Unsigned> FromElx<Binary<'a>> for FixedVector<u8, N> {
    fn from(value: Binary<'a>) -> Result<Self, FromElxError> {
        FixedVector::new(value.as_slice().to_vec()).map_err(FromElxError::from_debug)
    }
}

impl<Ssz, Elx, N> FromElx<Vec<Elx>> for FixedVector<Ssz, N>
where
    Ssz: FromElx<Elx>,
    N: Unsigned,
{
    fn from(value: Vec<Elx>) -> Result<Self, FromElxError> {
        let v: Result<Vec<_>, _> = value.into_iter().map(FromElx::from).collect();
        FixedVector::new(v?).map_err(FromElxError::from_debug)
    }
}

impl<Ssz, Elx, N> FromElx<Vec<Elx>> for VariableList<Ssz, N>
where
    Ssz: FromElx<Elx>,
    N: Unsigned,
{
    fn from(value: Vec<Elx>) -> Result<Self, FromElxError> {
        let v: Result<Vec<_>, _> = value.into_iter().map(FromElx::from).collect();
        VariableList::new(v?).map_err(FromElxError::from_debug)
    }
}

impl<'a, N: Unsigned> FromElx<Binary<'a>> for BitList<N> {
    fn from(value: Binary<'a>) -> Result<Self, FromElxError> {
        Decode::from_ssz_bytes(&value).map_err(FromElxError::from_debug)
    }
}

impl<'a, N: Unsigned> FromElx<Binary<'a>> for BitVector<N> {
    fn from(value: Binary<'a>) -> Result<Self, FromElxError> {
        Decode::from_ssz_bytes(&value).map_err(FromElxError::from_debug)
    }
}

impl<'a, N: Unsigned> FromElx<Binary<'a>> for VariableList<u8, N> {
    fn from(value: Binary<'a>) -> Result<Self, FromElxError> {
        VariableList::new(value.as_slice().to_vec()).map_err(FromElxError::from_debug)
    }
}

impl<'a> FromElx<Binary<'a>> for Uint256 {
    fn from(value: Binary<'a>) -> Result<Self, FromElxError> {
        const N: usize = 256 / 8;
        let mut v: [u8; 32] = [0; N];
        if value.len() > 0 {
            let len = v.len().min(value.len());
            v[..len].copy_from_slice(&value[..len]);
        }
        Ok(Uint256(v))
    }
}
