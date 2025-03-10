use std::io::Write;

use bls::{AggregatePublicKey, AggregateSignature, Hash256, PublicKey, SecretKey, Signature};
use rustler::{Binary, Env, NewBinary};

pub(crate) fn bytes_to_binary<'env>(env: Env<'env>, bytes: &[u8]) -> Binary<'env> {
    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(bytes).unwrap();
    binary.into()
}

// Deserialize a PublicKey from a slice of bytes.
// Faster than PublicKey::deserialize() as it doesn't validate the key
// Returns Error on invalid BLST encoding or on Infinity Public Key.
fn fast_public_key_deserialize(pk: &[u8]) -> Result<PublicKey, String> {
    if pk == &bls::INFINITY_PUBLIC_KEY[..] {
        Err("Infinity public Key".to_owned())
    } else {
        bls::impls::blst::types::PublicKey::from_bytes(pk)
            .map_err(|err| format!("BlstError({:?})", err))
            .and_then(|pk| {
                PublicKey::deserialize_uncompressed(pk.serialize().as_slice())
                    // This should never be an error as the pk is obtained from an uncompressed valid key
                    .map_err(|e| format!("Deserialization error: {:?}", e))
            })
    }
}

#[rustler::nif]
fn sign<'env>(
    env: Env<'env>,
    private_key: Binary,
    message: Binary,
) -> Result<Binary<'env>, String> {
    if message.len() != 32 {
        return Err(format!("Message must be 32 bytes long"));
    }
    let sk = match SecretKey::deserialize(private_key.as_slice()) {
        Ok(sk) => sk,
        Err(e) => return Err(format!("{:?}", e)),
    };

    let signature = sk.sign(Hash256::from_slice(message.as_slice()));
    let bytes = signature.serialize();

    Ok(bytes_to_binary(env, &bytes))
}

#[rustler::nif]
fn aggregate<'env>(env: Env<'env>, signatures: Vec<Binary>) -> Result<Binary<'env>, String> {
    match signatures.len() {
        0 => return Err(format!("Empty signature vector")),
        _ => {
            let sigs_result = signatures
                .iter()
                .map(|sig| Signature::deserialize(sig.as_slice()))
                .collect::<Result<Vec<Signature>, _>>();
            let sigs = sigs_result.map_err(|err| format!("{:?}", err))?;
            let aggr_sig = sigs
                .iter()
                .fold(AggregateSignature::infinity(), |mut a, b| {
                    a.add_assign(&b);
                    a
                });
            let bytes = aggr_sig.serialize();
            Ok(bytes_to_binary(env, &bytes))
        }
    }
}

#[rustler::nif]
fn verify<'env>(public_key: Binary, message: Binary, signature: Binary) -> Result<bool, String> {
    if message.len() != 32 {
        return Err(format!("Message must be 32 bytes long"));
    }
    let sig = Signature::deserialize(signature.as_slice()).map_err(|err| format!("{:?}", err))?;
    let pubkey =
        fast_public_key_deserialize(public_key.as_slice()).map_err(|err| format!("{:?}", err))?;

    Ok(sig.verify(&pubkey, Hash256::from_slice(message.as_slice())))
}

#[rustler::nif]
fn aggregate_verify<'env>(
    public_keys: Vec<Binary>,
    messages: Vec<Binary>,
    signature: Binary,
) -> Result<bool, String> {
    let aggregate_sig = AggregateSignature::deserialize(signature.as_slice())
        .map_err(|err| format!("{:?}", err))?;
    let pubkeys_result = public_keys
        .iter()
        .map(|pkb| fast_public_key_deserialize(pkb.as_slice()))
        .collect::<Result<Vec<PublicKey>, _>>();
    let pubkeys = pubkeys_result.map_err(|err| format!("{:?}", err))?;

    let pubkey_refs = pubkeys.iter().collect::<Vec<_>>();
    let msgs = messages
        .iter()
        .map(|message| Hash256::from_slice(message.as_slice()))
        .collect::<Vec<Hash256>>();
    Ok(aggregate_sig.aggregate_verify(&msgs, &pubkey_refs))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn fast_aggregate_verify<'env>(
    public_keys: Vec<Binary>,
    message: Binary,
    signature: Binary,
) -> Result<bool, String> {
    if message.len() != 32 {
        return Err(format!("Message must be 32 bytes long"));
    }
    let aggregate_sig = AggregateSignature::deserialize(signature.as_slice())
        .map_err(|err| format!("{:?}", err))?;
    let pubkeys_result = public_keys
        .iter()
        .map(|pkb| fast_public_key_deserialize(pkb.as_slice()))
        //.map(|pkb| PublicKey::deserialize(pkb.as_slice()))
        .collect::<Result<Vec<PublicKey>, _>>();
    let pubkeys = pubkeys_result.map_err(|err| format!("{:?}", err))?;

    let pubkey_refs = pubkeys.iter().collect::<Vec<_>>();
    Ok(aggregate_sig.fast_aggregate_verify(Hash256::from_slice(message.as_slice()), &pubkey_refs))
}

#[rustler::nif]
fn eth_fast_aggregate_verify<'env>(
    public_keys: Vec<Binary>,
    message: Binary,
    signature: Binary,
) -> Result<bool, String> {
    if message.len() != 32 {
        return Err(format!("Message must be 32 bytes long"));
    }
    let aggregate_sig = AggregateSignature::deserialize(signature.as_slice())
        .map_err(|err| format!("{:?}", err))?;
    let pubkeys_result = public_keys
        .iter()
        .map(|pkb| fast_public_key_deserialize(pkb.as_slice()))
        .collect::<Result<Vec<PublicKey>, _>>();
    let pubkeys = pubkeys_result.map_err(|err| format!("{:?}", err))?;

    let pubkey_refs = pubkeys.iter().collect::<Vec<_>>();
    Ok(aggregate_sig
        .eth_fast_aggregate_verify(Hash256::from_slice(message.as_slice()), &pubkey_refs))
}

#[rustler::nif]
fn eth_aggregate_pubkeys<'env>(
    env: Env<'env>,
    public_keys: Vec<Binary>,
) -> Result<Binary<'env>, String> {
    match public_keys.len() {
        0 => return Err(format!("Empty public key vector")),
        _ => {
            let pubkeys_result = public_keys
                .iter()
                .map(|pkb| fast_public_key_deserialize(pkb.as_slice()))
                .collect::<Result<Vec<PublicKey>, _>>();

            let pubkeys = pubkeys_result.map_err(|err| format!("{:?}", err))?;
            let pubkey_refs = pubkeys.into_iter().collect::<Vec<_>>();

            let agg_pubkey_bytes = AggregatePublicKey::aggregate(pubkey_refs.as_slice())
                .expect("error in aggregate")
                .to_public_key()
                .serialize();

            Ok(bytes_to_binary(env, &agg_pubkey_bytes))
        }
    }
}
#[rustler::nif]
fn key_validate<'env>(public_key: Binary) -> Result<bool, String> {
    let _pubkey = fast_public_key_deserialize(public_key.as_slice())?;

    Ok(true)
}
#[rustler::nif]
fn derive_pubkey<'env>(env: Env<'env>, private_key: Binary) -> Result<Binary<'env>, String> {
    let sk = match SecretKey::deserialize(private_key.as_slice()) {
        Ok(sk) => sk,
        Err(e) => return Err(format!("{:?}", e)),
    };
    let public_key = sk.public_key();
    let public_key_bytes = public_key.serialize();

    Ok(bytes_to_binary(env, &public_key_bytes))
}

rustler::init!("Elixir.Bls");
