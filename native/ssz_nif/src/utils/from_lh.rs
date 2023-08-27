use crate::utils::helpers::bytes_to_binary;
use ethereum_types::{H160, H256, U256};
use lighthouse_types::{
    BitList, Epoch, ExecutionBlockHash, FixedVector, PublicKeyBytes, SignatureBytes, Slot,
    Unsigned, VariableList,
};
use rustler::Binary;
use ssz::Encode;

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

impl<'a> FromLH<'a, SignatureBytes> for Binary<'a> {
    fn from(value: SignatureBytes, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value.serialize())
    }
}

impl<'a, N: Unsigned> FromLH<'a, BitList<N>> for Binary<'a> {
    fn from(value: BitList<N>, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, value.into_bytes().as_slice())
    }
}

impl<'a, Elx, Lh, N> FromLH<'a, FixedVector<Lh, N>> for Vec<Elx>
where
    Elx: FromLH<'a, Lh> + ToOwned,
    N: Unsigned,
{
    fn from(value: FixedVector<Lh, N>, env: rustler::Env<'a>) -> Self {
        let v: Vec<_> = value.into();
        v.into_iter().map(|x| Elx::from(x, env)).collect::<Vec<_>>()
    }
}

impl<'a> FromLH<'a, ExecutionBlockHash> for Binary<'a> {
    fn from(value: ExecutionBlockHash, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value.as_ssz_bytes())
    }
}

impl<'a> FromLH<'a, H160> for Binary<'a> {
    fn from(value: H160, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value.as_ssz_bytes())
    }
}

impl<'a> FromLH<'a, U256> for Binary<'a> {
    fn from(value: U256, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value.as_ssz_bytes())
    }
}

impl<'a> FromLH<'a, U256> for u64 {
    fn from(value: U256, _env: rustler::Env<'a>) -> Self {
        u64::try_from(value).unwrap()
    }
}

impl<'a, Elx, Lh, N> FromLH<'a, VariableList<Lh, N>> for Vec<Elx>
where
    Elx: FromLH<'a, Lh>,
    N: Unsigned,
{
    fn from(value: VariableList<Lh, N>, env: rustler::Env<'a>) -> Self {
        value.into_iter().map(|lh| FromLH::from(lh, env)).collect()
    }
}

impl<'a, N> FromLH<'a, VariableList<u8, N>> for Binary<'a>
where
    N: Unsigned,
{
    fn from(value: VariableList<u8, N>, env: rustler::Env<'a>) -> Self {
        bytes_to_binary(env, &value)
    }
}
