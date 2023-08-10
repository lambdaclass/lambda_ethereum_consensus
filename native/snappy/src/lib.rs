use rustler::{resource, Binary, Env, NewBinary, ResourceArc, Term};
use snap::read;
use std::{
    collections::VecDeque,
    io::{self, Read, Write},
    sync::Mutex,
};

// Standard max compressed payload in the Snappy framing format
const CHUNK_SIZE: usize = 1 << 16;

mod atoms {
    use rustler::atoms;

    atoms! {
        paused,
    }
}

#[derive(Default)]
struct StreamIterator {
    eof: bool,
    buffer: VecDeque<u8>,
}

impl io::Read for StreamIterator {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let len = self.buffer.read(buf)?;
        if !self.eof && len == 0 {
            Err(io::ErrorKind::WouldBlock.into())
        } else {
            Ok(len)
        }
    }
    fn read_exact(&mut self, buf: &mut [u8]) -> io::Result<()> {
        match self.buffer.len() {
            n if n < buf.len() => {
                if self.eof {
                    Err(io::ErrorKind::UnexpectedEof.into())
                } else {
                    Err(io::ErrorKind::WouldBlock.into())
                }
            }
            _ => self.buffer.read_exact(buf),
        }
    }
}

struct AsyncDecompressorInner(read::FrameDecoder<StreamIterator>);

impl Default for AsyncDecompressorInner {
    fn default() -> Self {
        Self(read::FrameDecoder::new(StreamIterator::default()))
    }
}

impl AsyncDecompressorInner {
    pub fn feed(&mut self, buf: &[u8]) {
        let decoder = self.0.get_mut();
        if buf.is_empty() {
            decoder.eof = true;
        } else {
            decoder.buffer.extend(buf);
        }
    }

    pub fn decompress(&mut self) -> io::Result<Vec<u8>> {
        let mut buffer = vec![0; CHUNK_SIZE];
        let len = self.0.read(&mut buffer)?;
        buffer.truncate(len);
        Ok(buffer)
    }
}

#[derive(Default)]
struct AsyncDecompressor(Mutex<AsyncDecompressorInner>);

fn bytes_to_binary<'env>(env: Env<'env>, bytes: &[u8]) -> Binary<'env> {
    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(bytes).unwrap();
    binary.into()
}

/// Creates a decompressor that can be fed an asynchronous stream of data
#[rustler::nif]
fn decompressor_new() -> Result<ResourceArc<AsyncDecompressor>, String> {
    Ok(ResourceArc::new(AsyncDecompressor::default()))
}

/// Feed data to the decompressor
#[rustler::nif]
fn decompressor_feed(arc: ResourceArc<AsyncDecompressor>, b: Binary) {
    // This cannot fail because mutex poisoning would crash the VM
    let mut decompressor = arc.0.lock().unwrap();
    decompressor.feed(&b);
}

/// Process and return all available data. Can
#[rustler::nif]
fn decompressor_read<'env>(
    env: Env<'env>,
    arc: ResourceArc<AsyncDecompressor>,
) -> Result<Term<'env>, String> {
    // This cannot fail because mutex poisoning would crash the VM
    let mut decompressor = arc.0.lock().unwrap();
    match decompressor.decompress() {
        Ok(bytes) => Ok(bytes_to_binary(env, &bytes).to_term(env)),
        // We use interrupted to signal that we need more data
        Err(e) if e.kind() == io::ErrorKind::WouldBlock => Ok(atoms::paused().to_term(env)),
        Err(e) => Err(e.to_string()),
    }
}

fn load(env: Env, _term: Term) -> bool {
    resource!(AsyncDecompressor, env);
    true
}

rustler::init!(
    "Elixir.Snappy",
    [decompressor_new, decompressor_feed, decompressor_read],
    load = load
);
