use rustler::Binary;
use ssz::Decode;
use ssz_types::{typenum::Unsigned, BitList, BitVector, FixedVector, VariableList};

pub(crate) trait FromElx<T> {
    fn from(value: T) -> Self;
}

macro_rules! trivial_impl {
    ($t:ty) => {
        impl FromElx<$t> for $t {
            fn from(value: $t) -> Self {
                value
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
    fn from(value: Binary<'a>) -> Self {
        value.as_slice().try_into().unwrap()
    }
}

impl<Elx, Ssz> FromElx<Vec<Elx>> for Vec<Ssz>
where
    Ssz: FromElx<Elx>,
{
    fn from(value: Vec<Elx>) -> Self {
        // for each root, convert to a slice of 32 bytes
        value.into_iter().map(FromElx::from).collect()
    }
}
impl<'a, N: Unsigned> FromElx<Binary<'a>> for FixedVector<u8, N> {
    fn from(value: Binary<'a>) -> Self {
        FixedVector::new(value.as_slice().to_vec()).unwrap()
    }
}

impl<Ssz, Elx, N> FromElx<Vec<Elx>> for FixedVector<Ssz, N>
where
    Ssz: FromElx<Elx>,
    N: Unsigned,
{
    fn from(value: Vec<Elx>) -> Self {
        FixedVector::new(value.into_iter().map(FromElx::from).collect()).unwrap()
    }
}

impl<Ssz, Elx, N> FromElx<Vec<Elx>> for VariableList<Ssz, N>
where
    Ssz: FromElx<Elx>,
    N: Unsigned,
{
    fn from(value: Vec<Elx>) -> Self {
        VariableList::new(value.into_iter().map(FromElx::from).collect()).unwrap()
    }
}

impl<'a, N: Unsigned> FromElx<Binary<'a>> for BitList<N> {
    fn from(value: Binary<'a>) -> Self {
        Decode::from_ssz_bytes(&value).unwrap()
    }
}

impl<'a, N: Unsigned> FromElx<Binary<'a>> for BitVector<N> {
    fn from(value: Binary<'a>) -> Self {
        Decode::from_ssz_bytes(&value).unwrap()
    }
}

impl<'a, N: Unsigned> FromElx<Binary<'a>> for VariableList<u8, N> {
    fn from(value: Binary<'a>) -> Self {
        VariableList::new(Binary::as_slice(&value).to_vec()).unwrap()
    }
}
