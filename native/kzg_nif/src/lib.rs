use std::io::Write;
use std::path::Path;
use std::sync::OnceLock;

use rustler::{Binary, Env, NewBinary};

pub use c_kzg::{Bytes32, Bytes48, Blob, KzgSettings, KzgCommitment, KzgProof, Cell, BYTES_PER_COMMITMENT, Error};

// Cache the trusted setup so we don't reload from disk on every NIF call.
// OnceLock is safe to use from multiple scheduler threads.
static TRUSTED_SETUP: OnceLock<KzgSettings> = OnceLock::new();

fn get_trusted_setup() -> &'static KzgSettings {
    TRUSTED_SETUP.get_or_init(|| {
        let lib_path = std::env::current_dir().unwrap().join(file!());
        let src_path = lib_path.parent().unwrap();
        let main_path = src_path.parent().unwrap();
        let trusted_setup_path = main_path.join("native/kzg_nif/official_trusted_setup.txt");
        let trusted_setup_file: &Path = trusted_setup_path.as_path();
        debug_assert!(trusted_setup_file.exists(), "Missing trusted setup file");
        // precompute=8 is recommended for cell proof performance (c-kzg v2 requirement)
        KzgSettings::load_trusted_setup_file(trusted_setup_file, 8).unwrap()
    })
}

pub(crate) fn bytes_to_binary<'env>(env: Env<'env>, bytes: &[u8]) -> Binary<'env> {
    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(bytes).unwrap();
    binary.into()
}

// ──────────────────────────────────────────────────────────────────────
// Existing blob/proof NIFs, rewritten for c-kzg v2 instance method API
// ──────────────────────────────────────────────────────────────────────

#[rustler::nif]
fn blob_to_kzg_commitment<'env>(
    env: Env<'env>,
    blob: Binary,
) -> Result<Binary<'env>, String> {
    let blob = Blob::from_bytes(blob.as_slice()).map_err(|e| format!("{:?}", e))?;
    let setup = get_trusted_setup();
    let commitment = setup
        .blob_to_kzg_commitment(&blob)
        .map_err(|e| format!("{:?}", e))?;
    Ok(bytes_to_binary(env, &commitment.to_bytes().into_inner()))
}

#[rustler::nif]
fn compute_kzg_proof<'env>(
    env: Env<'env>,
    blob: Binary,
    z: Binary
) -> Result<(Binary<'env>, Binary<'env>), String> {
    let blob = Blob::from_bytes(blob.as_slice()).map_err(|e| format!("{:?}", e))?;
    let z_bytes = Bytes32::from_bytes(z.as_slice()).map_err(|e| format!("{:?}", e))?;
    let setup = get_trusted_setup();
    let (kzg_proof, y) = setup
        .compute_kzg_proof(&blob, &z_bytes)
        .map_err(|e| format!("{:?}", e))?;
    Ok((
        bytes_to_binary(env, &kzg_proof.to_bytes().into_inner()),
        bytes_to_binary(env, y.as_slice()),
    ))
}

#[rustler::nif]
fn compute_blob_kzg_proof<'env>(
    env: Env<'env>,
    blob: Binary,
    kzg_commitment: Binary
) -> Result<Binary<'env>, String> {
    let blob = Blob::from_bytes(blob.as_slice()).map_err(|e| format!("{:?}", e))?;
    let commitment = KzgCommitment::from_bytes(kzg_commitment.as_slice())
        .map_err(|e| format!("{:?}", e))?;
    let setup = get_trusted_setup();
    let kzg_proof = setup
        .compute_blob_kzg_proof(&blob, &commitment.to_bytes())
        .map_err(|e| format!("{:?}", e))?;
    Ok(bytes_to_binary(env, &kzg_proof.to_bytes().into_inner()))
}

#[rustler::nif]
fn verify_kzg_proof(
    kzg_commitment: Binary,
    z: Binary,
    y: Binary,
    kzg_proof: Binary
) -> Result<bool, String> {
    let commitment = KzgCommitment::from_bytes(kzg_commitment.as_slice())
        .map_err(|e| format!("{:?}", e))?;
    let z_bytes = Bytes32::from_bytes(z.as_slice()).map_err(|e| format!("{:?}", e))?;
    let y_bytes = Bytes32::from_bytes(y.as_slice()).map_err(|e| format!("{:?}", e))?;
    let proof = KzgProof::from_bytes(kzg_proof.as_slice()).map_err(|e| format!("{:?}", e))?;
    let setup = get_trusted_setup();
    setup
        .verify_kzg_proof(&commitment.to_bytes(), &z_bytes, &y_bytes, &proof.to_bytes())
        .map_err(|e| format!("{:?}", e))
}

#[rustler::nif]
fn verify_blob_kzg_proof(
    blob: Binary,
    kzg_commitment: Binary,
    kzg_proof: Binary
) -> Result<bool, String> {
    let blob = Blob::from_bytes(blob.as_slice()).map_err(|e| format!("{:?}", e))?;
    let commitment = KzgCommitment::from_bytes(kzg_commitment.as_slice())
        .map_err(|e| format!("{:?}", e))?;
    let proof = KzgProof::from_bytes(kzg_proof.as_slice()).map_err(|e| format!("{:?}", e))?;
    let setup = get_trusted_setup();
    setup
        .verify_blob_kzg_proof(&blob, &commitment.to_bytes(), &proof.to_bytes())
        .map_err(|e| format!("{:?}", e))
}

#[rustler::nif]
fn verify_blob_kzg_proof_batch(
    blobs: Vec<Binary>,
    kzg_commitments: Vec<Binary>,
    kzg_proofs: Vec<Binary>
) -> Result<bool, String> {
    let blobs = blobs
        .iter()
        .map(|b| Blob::from_bytes(b.as_slice()))
        .collect::<Result<Vec<Blob>, _>>()
        .map_err(|e| format!("{:?}", e))?;

    let commitments = kzg_commitments
        .iter()
        .map(|c| KzgCommitment::from_bytes(c.as_slice()).map(|k| k.to_bytes()))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("{:?}", e))?;

    let proofs = kzg_proofs
        .iter()
        .map(|p| KzgProof::from_bytes(p.as_slice()).map(|k| k.to_bytes()))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("{:?}", e))?;

    let setup = get_trusted_setup();
    setup
        .verify_blob_kzg_proof_batch(&blobs, &commitments, &proofs)
        .map_err(|e| format!("{:?}", e))
}

// ──────────────────────────────────────────────────────────────────────
// New Fulu / PeerDAS (EIP-7594) cell NIF functions
// ──────────────────────────────────────────────────────────────────────

/// Compute all 128 cells and their KZG proofs from a single blob.
/// Returns `{cells, proofs}` where each is a list of 128 binaries.
#[rustler::nif]
fn compute_cells_and_kzg_proofs<'env>(
    env: Env<'env>,
    blob: Binary,
) -> Result<(Vec<Binary<'env>>, Vec<Binary<'env>>), String> {
    let blob = Blob::from_bytes(blob.as_slice()).map_err(|e| format!("{:?}", e))?;
    let setup = get_trusted_setup();
    let (cells, proofs) = setup
        .compute_cells_and_kzg_proofs(&blob)
        .map_err(|e| format!("{:?}", e))?;

    let cell_binaries: Vec<Binary<'env>> = cells
        .iter()
        .map(|c| bytes_to_binary(env, &c.to_bytes()))
        .collect();
    let proof_binaries: Vec<Binary<'env>> = proofs
        .iter()
        .map(|p| bytes_to_binary(env, p.as_ref()))
        .collect();

    Ok((cell_binaries, proof_binaries))
}

/// Batch-verify KZG cell proofs.
/// Each element of `cell_indices` is a column index (0..NUMBER_OF_COLUMNS).
#[rustler::nif]
fn verify_cell_kzg_proof_batch(
    commitments: Vec<Binary>,
    cell_indices: Vec<u64>,
    cells: Vec<Binary>,
    proofs: Vec<Binary>,
) -> Result<bool, String> {
    let commitments = commitments
        .iter()
        .map(|c| Bytes48::from_bytes(c.as_slice()))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("{:?}", e))?;

    let cells = cells
        .iter()
        .map(|c| Cell::from_bytes(c.as_slice()))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("{:?}", e))?;

    let proofs = proofs
        .iter()
        .map(|p| Bytes48::from_bytes(p.as_slice()))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("{:?}", e))?;

    let setup = get_trusted_setup();
    setup
        .verify_cell_kzg_proof_batch(&commitments, &cell_indices, &cells, &proofs)
        .map_err(|e| format!("{:?}", e))
}

/// Recover all 128 cells and proofs from a subset of available cells.
/// `cell_indices` must contain the indices of the provided `cells`.
/// Returns the full 128 cells and proofs after erasure recovery.
#[rustler::nif]
fn recover_cells_and_kzg_proofs<'env>(
    env: Env<'env>,
    cell_indices: Vec<u64>,
    cells: Vec<Binary>,
) -> Result<(Vec<Binary<'env>>, Vec<Binary<'env>>), String> {
    let cells = cells
        .iter()
        .map(|c| Cell::from_bytes(c.as_slice()))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("{:?}", e))?;

    let setup = get_trusted_setup();
    let (recovered_cells, recovered_proofs) = setup
        .recover_cells_and_kzg_proofs(&cell_indices, &cells)
        .map_err(|e| format!("{:?}", e))?;

    let cell_binaries: Vec<Binary<'env>> = recovered_cells
        .iter()
        .map(|c| bytes_to_binary(env, &c.to_bytes()))
        .collect();
    let proof_binaries: Vec<Binary<'env>> = recovered_proofs
        .iter()
        .map(|p| bytes_to_binary(env, p.as_ref()))
        .collect();

    Ok((cell_binaries, proof_binaries))
}

rustler::init!(
    "Elixir.Kzg",
    [
        blob_to_kzg_commitment,
        compute_kzg_proof,
        verify_kzg_proof,
        compute_blob_kzg_proof,
        verify_blob_kzg_proof,
        verify_blob_kzg_proof_batch,
        compute_cells_and_kzg_proofs,
        verify_cell_kzg_proof_batch,
        recover_cells_and_kzg_proofs
    ]
);
