use crate::utils::helpers::bytes_to_binary;
use rustler::Binary;
use ssz::Encode;
use ssz_types::{typenum::Unsigned, BitList, BitVector, FixedVector};

pub(crate) trait FromLH<'a, T> {
    fn from(value: T, env: rustler::Env<'a>) -> Self;
}

macro_rules! trivial_impl {
    ($t:ty) => {
        impl<'a> FromLH<'a, $t> for $t {
            fn from(value: $t, _env: rustler::Env<'a>) -> Self {
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

impl<'a, const N: usize> FromLH<'a, [u8; N]> for Binary<'a> {
    fn from(value: [u8; N], env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value)
    }
}

impl<'a, N: Unsigned> FromLH<'a, FixedVector<u8, N>> for Binary<'a> {
    fn from(value: FixedVector<u8, N>, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value)
    }
}

impl<'a, Ssz, Elx, N> FromLH<'a, FixedVector<Ssz, N>> for Vec<Elx>
where
    Elx: FromLH<'a, Ssz>,
    N: Unsigned,
{
    fn from(value: FixedVector<Ssz, N>, env: rustler::Env<'a>) -> Self {
        let as_vec: Vec<_> = value.into();
        as_vec
            .into_iter()
            .map(|v: Ssz| FromLH::from(v, env))
            .collect()
    }
}

impl<'a, Ssz, Elx> FromLH<'a, Vec<Ssz>> for Vec<Elx>
where
    Elx: FromLH<'a, Ssz>,
{
    fn from(value: Vec<Ssz>, env: rustler::Env<'a>) -> Self {
        value.into_iter().map(|v| FromLH::from(v, env)).collect()
    }
}

impl<'a, N: Unsigned> FromLH<'a, BitVector<N>> for Binary<'a> {
    fn from(value: BitVector<N>, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value.as_ssz_bytes())
    }
}

impl<'a, N: Unsigned> FromLH<'a, BitList<N>> for Binary<'a> {
    fn from(value: BitList<N>, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value.as_ssz_bytes())
    }
}
