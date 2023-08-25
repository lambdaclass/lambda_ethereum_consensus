use ethereum_types::{H160, H256, U256};
use lighthouse_types::{
    BitList, Epoch, EthSpec, ExecutionBlockHash, FixedVector, MainnetEthSpec, PublicKeyBytes, Slot,
    Unsigned, VariableList,
};
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

trivial_impl!(u64 => Epoch);
trivial_impl!(u64 => Slot);

impl<T> FromElx<T> for T {
    fn from(value: Self) -> Self {
        value
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

impl<'a> FromElx<Binary<'a>> for PublicKeyBytes {
    fn from(value: Binary<'a>) -> Self {
        // length is checked from the Elixir side
        PublicKeyBytes::deserialize(value.as_slice()).unwrap()
    }
}

impl<'a, N: Unsigned> FromElx<Binary<'a>> for BitList<N> {
    fn from(value: Binary<'a>) -> Self {
        // TODO: remove unwrap?
        Self::from_ssz_bytes(&value).unwrap()
    }
}

impl<'a, Elx, Lh, N> FromElx<Vec<Elx>> for FixedVector<Lh, N>
where
    Lh: FromElx<Elx>,
    N: Unsigned,
{
    fn from(value: Vec<Elx>) -> Self {
        // TODO: remove unwrap?
        Self::new(value.into_iter().map(FromElx::from).collect()).unwrap()
    }
}

impl<'a> FromElx<Binary<'a>> for ExecutionBlockHash {
    fn from(value: Binary<'a>) -> Self {
        ExecutionBlockHash::from_ssz_bytes(&value).unwrap()
    }
}

impl<'a> FromElx<Binary<'a>> for H160 {
    fn from(value: Binary<'a>) -> Self {
        H160::from_ssz_bytes(&value).unwrap()
    }
}

impl<'a> FromElx<Binary<'a>> for U256 {
    fn from(value: Binary<'a>) -> Self {
        U256::from_ssz_bytes(&value).unwrap()
    }
}

impl<'a> FromElx<u64> for U256 {
    fn from(value: u64) -> Self {
        U256::try_from(value).unwrap()
    }
}

impl<'a> FromElx<Binary<'a>> for VariableList<u8, <MainnetEthSpec as EthSpec>::MaxExtraDataBytes> {
    fn from(value: Binary<'a>) -> Self {
        VariableList::from_ssz_bytes(&value).unwrap()
    }
}

impl<'a> FromElx<Vec<u8>> for VariableList<u8, <MainnetEthSpec as EthSpec>::MaxExtraDataBytes> {
    fn from(value: Vec<u8>) -> Self {
        VariableList::from_ssz_bytes(&value).unwrap()
    }
}

// impl<'a> FromElx<Vec<Vec<u8>>>
//     for VariableList<
//         VariableList<u8, <MainnetEthSpec as EthSpec>::MaxBytesPerTransaction>,
//         <MainnetEthSpec as EthSpec>::MaxTransactionsPerPayload,
//     >
// {
//     fn from(value: Vec<Vec<u8>>) -> Self {}
// }

// impl<'a> FromElx<Vec<Vec<u8>>>
//     for VariableList<
//         VariableList<u8, <MainnetEthSpec as EthSpec>::MaxBytesPerTransaction>,
//         <MainnetEthSpec as EthSpec>::MaxTransactionsPerPayload,
//     >
// {
//     fn from(value: Vec<Vec<u8>>) -> Self {

// let inner_lists = value
//     .into_iter()
//     .map(|inner_vec| VariableList(inner_vec))
//     .collect();
// VariableList(inner_lists)

//         let inner = value
//             .into_iter()
//             .map(|vec|  VariableList<u8, <MainnetEthSpec as EthSpec>::MaxBytesPerTransaction> = VariableList})
//             .collect();
//     }
// }
