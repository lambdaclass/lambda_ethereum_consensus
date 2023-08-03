use ssz_rs::prelude::*;
use serde::{Serialize, Deserialize};

#[derive(PartialEq, Eq, Debug, Default, SimpleSerialize, Serialize, Deserialize)]
struct SingleFieldTestStruct {
    a: u8,
}

#[rustler::nif]
pub fn decode(bytes: Vec<u8>) -> SingleFieldTestStruct {
    let recovered_value: SingleFieldTestStruct = deserialize(&bytes).expect("can deserialize");
    return recovered_value;
}

#[rustler::nif]
pub fn encode(value: SingleFieldTestStruct) -> String {
    let encoding = serialize(&value).expect("can serialize");
    return enconding;
}

fn match_config(option: Atom) -> base64::Config {
    // omitted for brevity
}

rustler::init!("LambdaEthereumConsensus.Ssz", [add]);
