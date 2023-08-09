use rustler::{Binary, Env, NewBinary};
use std::io::{self, Read, Write};

struct LazyReader {}

impl io::Read for LazyReader {
    fn read(&mut self, _buf: &mut [u8]) -> io::Result<usize> {
        Err(io::ErrorKind::Interrupted.into())
    }
}

#[rustler::nif]
fn decompress_bytes<'env>(env: Env<'env>, b: Binary) -> Result<Binary<'env>, String> {
    let slice: &[u8] = &b;
    let rdr = snap::read::FrameDecoder::new(slice);
    // TODO: use io::Read::read instead, and handle io::ErrorKind::Interrupted
    let bytes: Result<Vec<_>, _> = rdr.bytes().collect();
    let bytes = bytes.map_err(|e| e.to_string())?;

    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(&bytes).unwrap();
    Ok(binary.into())
}

rustler::init!("Elixir.Snappy", [decompress_bytes]);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn it_works() {
        let mut reader = snap::read::FrameDecoder::new(LazyReader {});
        let mut buf = [0; 1];
        let byte = reader.read(&mut buf);
        assert!(byte.is_err());
        assert_eq!(byte.unwrap_err().kind(), io::ErrorKind::Interrupted);
    }
}
