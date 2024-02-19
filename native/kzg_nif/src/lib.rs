use std::io::Write;

use rustler::{Binary, Env, NewBinary};

pub(crate) fn bytes_to_binary<'env>(env: Env<'env>, bytes: &[u8]) -> Binary<'env> {
    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(bytes).unwrap();
    binary.into()
}

#[rustler::nif]
fn blob_to_kzg_commitment<'env>(
    env: Env<'env>,
    blobs: Binary,
) -> Result<Binary<'env>, String> {
    let test_bytes = [255, 255];
    Ok(bytes_to_binary(env, &test_bytes))
}

rustler::init!(
    "Elixir.Kzg",
    [
        blob_to_kzg_commitment,
        // compute_kzg_proof,
        // verify_kzg_proof,
        // compute_blob_kzg_proof,
        // verify_blob_kzg_proof,
        // verify_blob_kzg_proof_batch,
    ]
);