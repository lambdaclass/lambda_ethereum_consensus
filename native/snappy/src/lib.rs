use std::io::{Read, Write};

use rustler::{Binary, Env, NewBinary};
use snap::read;

fn bytes_to_binary<'env>(env: Env<'env>, bytes: &[u8]) -> Binary<'env> {
    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(bytes).unwrap();
    binary.into()
}

#[rustler::nif]
fn decompress<'env>(env: Env<'env>, bin: Binary) -> Result<Binary<'env>, String> {
    let mut decoder = read::FrameDecoder::new(&bin[..]);
    let mut buffer = Vec::with_capacity(bin.len());
    decoder
        .read_to_end(&mut buffer)
        .map_err(|e| e.to_string())?;
    Ok(bytes_to_binary(env, &buffer))
}

rustler::init!("Elixir.Snappy", [decompress]);
