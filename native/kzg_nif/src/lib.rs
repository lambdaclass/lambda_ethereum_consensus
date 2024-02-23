use std::io::Write;
use std::path::Path;

use rustler::{Binary, Env, NewBinary};

pub use c_kzg::{Bytes32, Bytes48, Blob, KzgSettings, KzgCommitment, KzgProof, BYTES_PER_COMMITMENT, Error};

pub(crate) fn bytes_to_binary<'env>(env: Env<'env>, bytes: &[u8]) -> Binary<'env> {
    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(bytes).unwrap();
    binary.into()
}

fn get_trusted_setup() -> KzgSettings {
    let lib_path = std::env::current_dir().unwrap().join(file!());
    let src_path = lib_path.parent().unwrap();
    let main_path = src_path.parent().unwrap();
    let trusted_setup_path = main_path.join("native/kzg_nif/official_trusted_setup.txt");
    let trusted_setup_file: &Path = trusted_setup_path.as_path();
    assert!(trusted_setup_file.exists());
    KzgSettings::load_trusted_setup_file(trusted_setup_file).unwrap()
}

#[rustler::nif]     
fn blob_to_kzg_commitment<'env>(
    env: Env<'env>,
    blob: Binary,
) -> Result<Binary<'env>, String> {
    let blob = match Blob::from_bytes(blob.as_slice()) {
        Ok(blob) => blob,
        Err(e) => return Err(format!("{:?}", e))
    };
    let trusted_setup = get_trusted_setup();
    let kzg_commitment: Result<KzgCommitment, _>  = c_kzg::KzgCommitment::blob_to_kzg_commitment(&blob, &trusted_setup);
    let commitment = match kzg_commitment {
        Ok(commitment) => commitment.to_bytes().into_inner(),
        Err(e) => return Err(format!("{:?}", e))
    };
    Ok(bytes_to_binary(env, &commitment))
}

#[rustler::nif]
fn compute_kzg_proof<'env>(
    env: Env<'env>,
    blob: Binary,
    z: Binary
) -> Result<(Binary<'env>, Binary<'env>), String> {
    let blob = match Blob::from_bytes(blob.as_slice()) {
        Ok(blob) => blob,
        Err(e) => return Err(format!("{:?}", e))
    };
    let z_bytes = match Bytes32::from_bytes(z.as_slice()) {
        Ok(z_bytes) => z_bytes,
        Err(e) => return Err(format!("{:?}", e))
    };
    let trusted_setup = get_trusted_setup();
    let proof: Result<(KzgProof, Bytes32), _>  = c_kzg::KzgProof::compute_kzg_proof(&blob, &z_bytes, &trusted_setup);
    let proof = match proof {
        Ok(proof) => proof,
        Err(e) => return Err(format!("{:?}", e))
    };
    let (kzg_proof, y) = proof; 
    let kzg_proof = kzg_proof.to_bytes().into_inner();
    let y = y.as_slice();
    Ok((bytes_to_binary(env, &kzg_proof), bytes_to_binary(env, &y)))
}

#[rustler::nif]
fn compute_blob_kzg_proof<'env>(
    env: Env<'env>,
    blob: Binary,
    kzg_commitment: Binary
) -> Result<Binary<'env>, String> {
    let blob = match Blob::from_bytes(blob.as_slice()) {
        Ok(blob) => blob,
        Err(e) => return Err(format!("{:?}", e))
    };
    let commitment = match KzgCommitment::from_bytes(kzg_commitment.as_slice()) {
        Ok(commitment) => commitment,
        Err(e) => return Err(format!("{:?}", e))
    };
    let trusted_setup = get_trusted_setup();
    let kzg_proof: Result<KzgProof, Error>  = c_kzg::KzgProof::compute_blob_kzg_proof(&blob, &commitment.to_bytes(), &trusted_setup);
    let kzg_proof = match kzg_proof {
        Ok(proof) => proof,
        Err(e) => return Err(format!("{:?}", e))
    };
    Ok(bytes_to_binary(env, &kzg_proof.to_bytes().into_inner()))
}

#[rustler::nif]
fn verify_kzg_proof<'env>(
    kzg_commitment: Binary,
    z: Binary,
    y: Binary,
    kzg_proof: Binary
) -> Result<bool, String> {
    let commitment = match KzgCommitment::from_bytes(kzg_commitment.as_slice()) {
        Ok(commitment) => commitment,
        Err(e) => return Err(format!("{:?}", e))
    };
    let z_bytes = match Bytes32::from_bytes(z.as_slice()) {
        Ok(z_bytes) => z_bytes,
        Err(e) => return Err(format!("{:?}", e))
    };
    let y_bytes = match Bytes32::from_bytes(y.as_slice()) {
        Ok(z_bytes) => z_bytes,
        Err(e) => return Err(format!("{:?}", e))
    };
    let proof = match KzgProof::from_bytes(kzg_proof.as_slice()) {
        Ok(proof) => proof,
        Err(e) => return Err(format!("{:?}", e))
    };
    let trusted_setup = get_trusted_setup();
    match c_kzg::KzgProof::verify_kzg_proof(&commitment.to_bytes(), &z_bytes, &y_bytes, &proof.to_bytes(), &trusted_setup) {
        Ok(status) => Ok(status),
        Err(e) => Err(format!("{:?}", e))
    }
}

#[rustler::nif]
fn verify_blob_kzg_proof<'env>(
    blob: Binary,
    kzg_commitment: Binary,
    kzg_proof: Binary
) -> Result<bool, String> {
    let blob = match Blob::from_bytes(blob.as_slice()) {
        Ok(blob) => blob,
        Err(e) => return Err(format!("{:?}", e))
    };
    let commitment = match KzgCommitment::from_bytes(kzg_commitment.as_slice()) {
        Ok(commitment) => commitment,
        Err(e) => return Err(format!("{:?}", e))
    };
    let proof = match KzgProof::from_bytes(kzg_proof.as_slice()) {
        Ok(proof) => proof,
        Err(e) => return Err(format!("{:?}", e))
    };
    let trusted_setup = get_trusted_setup();
    match c_kzg::KzgProof::verify_blob_kzg_proof(&blob, &commitment.to_bytes(), &proof.to_bytes(), &trusted_setup) {
        Ok(status) => Ok(status),
        Err(e) => Err(format!("{:?}", e))
    }
}

#[rustler::nif]
fn verify_blob_kzg_proof_batch<'env>(
    blobs: Vec<Binary>,
    kzg_commitments: Vec<Binary>,
    kzg_proofs: Vec<Binary>
) -> Result<bool, String> {
    let blob_results = blobs.iter().map(|blob| Blob::from_bytes(blob.as_slice())).collect::<Result<Vec<Blob>, _>>();
    let blobs = blob_results.map_err(|err| format!("{:?}", err))?;

    let commitments_results = kzg_commitments.iter().map(|commitment| KzgCommitment::from_bytes(commitment.as_slice())).collect::<Result<Vec<KzgCommitment>, _>>();
    let commitments = commitments_results.map_err(|err| format!("{:?}", err))?;
    let commitments = commitments.iter().map(|commitment| commitment.to_bytes()).collect::<Vec<_>>();


    let proof_results = kzg_proofs.iter().map(|proof| KzgProof::from_bytes(proof.as_slice())).collect::<Result<Vec<KzgProof>, _>>();
    let proofs = proof_results.map_err(|err| format!("{:?}", err))?;
    let proofs = proofs.iter().map(|proof| proof.to_bytes()).collect::<Vec<_>>();

    let trusted_setup = get_trusted_setup();
    match c_kzg::KzgProof::verify_blob_kzg_proof_batch(&blobs, &commitments, &proofs, &trusted_setup) {
        Ok(status) => Ok(status),
        Err(e) => Err(format!("{:?}", e))
    }
}

rustler::init!(
    "Elixir.Kzg",
    [
        blob_to_kzg_commitment,
        compute_kzg_proof,
        verify_kzg_proof,
        compute_blob_kzg_proof,
        verify_blob_kzg_proof,
        verify_blob_kzg_proof_batch
    ]
);