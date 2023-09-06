use std::io::Write;

use bls::{AggregateSignature, PublicKey, SecretKey};
use rustler::{Binary, Env, NewBinary};
use types::Hash256;

pub(crate) fn bytes_to_binary<'env>(env: Env<'env>, bytes: &[u8]) -> Binary<'env> {
    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(bytes).unwrap();
    binary.into()
}

#[rustler::nif]
fn sign<'env>(
    env: Env<'env>,
    private_key: Binary,
    message: Binary,
) -> Result<Binary<'env>, String> {
    let sk = match SecretKey::deserialize(private_key.as_slice()) {
        Ok(sk) => sk,
        Err(e) => return Err(format!("{:?}", e)),
    };

    let signature = sk.sign(Hash256::from_slice(message.as_slice()));
    let bytes = signature.serialize();

    Ok(bytes_to_binary(env, &bytes))
}

#[rustler::nif]
fn fast_aggregate_verify<'env>(
    public_keys: Vec<Binary>,
    message: Binary,
    signature: Binary,
) -> Result<bool, String> {
    let aggregate_sig = AggregateSignature::deserialize(signature.as_slice())
        .map_err(|err| format!("{:?}", err))?;
    let pubkeys_result = public_keys
        .iter()
        .map(|pkb| PublicKey::deserialize(pkb.as_slice()))
        .collect::<Result<Vec<PublicKey>, _>>();
    let pubkeys = pubkeys_result.map_err(|err| format!("{:?}", err))?;

    let pubkey_refs = pubkeys.iter().collect::<Vec<_>>();
    Ok(aggregate_sig.fast_aggregate_verify(Hash256::from_slice(message.as_slice()), &pubkey_refs))
}

rustler::init!("Elixir.Bls", [sign, fast_aggregate_verify]);
