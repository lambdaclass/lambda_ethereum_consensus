use crate::utils::from_ssz::FromSsz;
use rustler::{Binary, Decoder, Encoder, Env, NewBinary, NifResult, Term};
use ssz::{Decode, Encode};

use std::{fmt::Debug, io::Write};
use tree_hash::{Hash256, MerkleHasher, TreeHash, TreeHashType};

use super::from_elx::{FromElx, FromElxError};

pub(crate) fn bytes_to_binary<'env>(env: Env<'env>, bytes: &[u8]) -> Binary<'env> {
    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(bytes).unwrap();
    binary.into()
}

pub(crate) fn encode_ssz<'a, Elx, Ssz>(value: Term<'a>) -> NifResult<Vec<u8>>
where
    Elx: Decoder<'a>,
    Ssz: Encode + FromElx<Elx>,
{
    if value.is_list() {
        let value_nif = Vec::<Elx>::decode(value)?;
        let value_ssz = value_nif
            .into_iter()
            .map(Ssz::from)
            .collect::<Result<Vec<_>, _>>()
            .map_err(to_nif_result)?;
        return Ok(value_ssz.as_ssz_bytes());
    }
    let value_nif = <Elx as Decoder>::decode(value)?;
    let value_ssz = Ssz::from(value_nif).map_err(to_nif_result)?;
    Ok(value_ssz.as_ssz_bytes())
}

fn to_nif_result(result: FromElxError) -> rustler::Error {
    rustler::Error::Term(Box::new(result.to_string()))
}

pub(crate) fn decode_ssz<'a, Elx, Ssz>((bytes, env): (&[u8], Env<'a>)) -> NifResult<Term<'a>>
where
    Elx: Encoder + FromSsz<'a, Ssz>,
    Ssz: Decode,
{
    let recovered_value = Ssz::from_ssz_bytes(bytes).map_err(debug_error_to_nif)?;
    let checkpoint = Elx::from(recovered_value, env);
    Ok(checkpoint.encode(env))
}

// TODO: this doesn't take into account the list's max size
pub(crate) fn list_decode_ssz<'a, Elx, Ssz>(args: (&[u8], Env<'a>)) -> NifResult<Term<'a>>
where
    Vec<Elx>: Encoder + FromSsz<'a, Vec<Ssz>>,
    Vec<Ssz>: Decode,
{
    decode_ssz::<Vec<Elx>, Vec<Ssz>>(args)
}

fn debug_error_to_nif(error: impl Debug) -> rustler::Error {
    rustler::Error::Term(Box::new(format!("{error:?}")))
}

pub(crate) fn hash_tree_root<'a, Elx, Ssz>(value: Term<'a>) -> NifResult<[u8; 32]>
where
    Elx: Decoder<'a>,
    Ssz: TreeHash + FromElx<Elx>,
{
    let value_nif = <Elx as Decoder>::decode(value)?;
    let value_ssz = Ssz::from(value_nif).map_err(to_nif_result)?;
    let hash = value_ssz.tree_hash_root();
    Ok(hash.0)
}

pub(crate) fn hash_list_tree_root<'a, Elx, Ssz>(
    (list, max_size): (Vec<Term<'a>>, usize),
) -> NifResult<[u8; 32]>
where
    Elx: Decoder<'a>,
    Ssz: TreeHash + FromElx<Elx>,
{
    let root = hash_vector_tree_root::<'a, Elx, Ssz>((list, max_size))?;
    let bytes = tree_hash::mix_in_length(&Hash256::from(root), max_size).0;
    Ok(bytes)
}

pub(crate) fn hash_vector_tree_root<'a, Elx, Ssz>(
    (list, max_size): (Vec<Term<'a>>, usize),
) -> NifResult<[u8; 32]>
where
    Elx: Decoder<'a>,
    Ssz: TreeHash + FromElx<Elx>,
{
    let v: NifResult<Vec<Elx>> = list.into_iter().map(Elx::decode).collect();
    let x: Vec<Ssz> = FromElx::from(v?).map_err(to_nif_result)?;
    Ok(vec_tree_hash_root(&x, max_size))
}

/// A helper function providing common functionality between the `TreeHash` implementations for
/// `FixedVector` and `VariableList`.
pub fn vec_tree_hash_root<T>(vec: &[T], size: usize) -> [u8; 32]
where
    T: TreeHash,
{
    let root = match T::tree_hash_type() {
        TreeHashType::Basic => {
            let mut hasher: MerkleHasher = MerkleHasher::with_leaves(
                (size + T::tree_hash_packing_factor() - 1) / T::tree_hash_packing_factor(),
            );

            for item in vec {
                hasher
                    .write(&item.tree_hash_packed_encoding())
                    .expect("ssz_types variable vec should not contain more elements than max");
            }

            hasher
                .finish()
                .expect("ssz_types variable vec should not have a remaining buffer")
        }
        TreeHashType::Container | TreeHashType::List | TreeHashType::Vector => {
            let mut hasher = MerkleHasher::with_leaves(size);

            for item in vec {
                hasher
                    .write(item.tree_hash_root().as_bytes())
                    .expect("ssz_types vec should not contain more elements than max");
            }

            hasher
                .finish()
                .expect("ssz_types vec should not have a remaining buffer")
        }
    };
    root.0
}
