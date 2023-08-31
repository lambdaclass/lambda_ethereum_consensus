use crate::utils::helpers::bytes_to_binary;
use ethereum_types::U256;
use rustler::Binary;
use ssz::Encode;
use ssz_types::{typenum::Unsigned, BitList, BitVector, FixedVector, VariableList};

pub(crate) trait FromSsz<'a, T> {
    fn from(value: T, env: rustler::Env<'a>) -> Self;
}

macro_rules! trivial_impl {
    ($t:ty) => {
        impl<'a> FromSsz<'a, $t> for $t {
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

impl<'a, const N: usize> FromSsz<'a, [u8; N]> for Binary<'a> {
    fn from(value: [u8; N], env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value)
    }
}

impl<'a, N: Unsigned> FromSsz<'a, FixedVector<u8, N>> for Binary<'a> {
    fn from(value: FixedVector<u8, N>, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value)
    }
}

impl<'a, Ssz, Elx, N> FromSsz<'a, FixedVector<Ssz, N>> for Vec<Elx>
where
    Elx: FromSsz<'a, Ssz>,
    N: Unsigned,
{
    fn from(value: FixedVector<Ssz, N>, env: rustler::Env<'a>) -> Self {
        let as_vec: Vec<_> = value.into();
        as_vec
            .into_iter()
            .map(|v: Ssz| FromSsz::from(v, env))
            .collect()
    }
}

impl<'a, Ssz, Elx, N> FromSsz<'a, VariableList<Ssz, N>> for Vec<Elx>
where
    Elx: FromSsz<'a, Ssz>,
    N: Unsigned,
{
    fn from(value: VariableList<Ssz, N>, env: rustler::Env<'a>) -> Self {
        let as_vec: Vec<_> = value.into();
        as_vec
            .into_iter()
            .map(|v: Ssz| FromSsz::from(v, env))
            .collect()
    }
}

impl<'a, Ssz, Elx> FromSsz<'a, Vec<Ssz>> for Vec<Elx>
where
    Elx: FromSsz<'a, Ssz>,
{
    fn from(value: Vec<Ssz>, env: rustler::Env<'a>) -> Self {
        value.into_iter().map(|v| FromSsz::from(v, env)).collect()
    }
}

impl<'a, N: Unsigned> FromSsz<'a, BitVector<N>> for Binary<'a> {
    fn from(value: BitVector<N>, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value.as_ssz_bytes())
    }
}

impl<'a, N: Unsigned> FromSsz<'a, BitList<N>> for Binary<'a> {
    fn from(value: BitList<N>, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value.as_ssz_bytes())
    }
}

impl<'a, N> FromSsz<'a, VariableList<u8, N>> for Binary<'a>
where
    N: Unsigned,
{
    fn from(value: VariableList<u8, N>, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value)
    }
}

impl<'a> FromSsz<'a, U256> for Binary<'a> {
    fn from(value: U256, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value.as_ssz_bytes())
    }
}
