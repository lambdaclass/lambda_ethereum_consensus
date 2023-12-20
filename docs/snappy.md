# Metadata request example

After sending a *GetMetadata* request to a peer, I get as a response:

`0011ff060000734e6150705901150000cd11e7d53a03000000000000ffffffffffffffff0f`

## *GetMetadata* request header

Decoding it with the protocol described in the consensus specs (**Req/Resp interaction**), we get:

```elixir
# Status (success)
"00"
# Optional header (uncompressed length: 17)
"11"
# Encoded data
"ff060000734e6150705901150000cd11e7d53a03000000000000ffffffffffffffff0f"
```

## *Snappy* framing format

We can interpret the encoded data with the Snappy framing format described in [google/snappy](https://github.com/google/snappy/blob/main/framing_format.txt).
Then we get:

```elixir
### Chunk start ###
# Chunk type (stream identifier)
"ff"
# Chunk size in LE (6)
"060000"
# Chunk data ("sNaPpY" in ASCII)
"734e61507059"

### Chunk start ###
# Chunk type (uncompressed data)
"01"
# Chunk size in LE (21)
"150000"
# CRC-32C checksum (4 bytes; little-endian)
"cd11e7d5"
# SSZ encoded payload (uncompressed)
"3a03000000000000ffffffffffffffff0f"
```

## *SSZ*

Decoding the payload with [simpleserialize.com](https://simpleserialize.com/), we find the received message:

```json
{
  "seq_number": "826",
  "attnets": "0xffffffffffffffff",
  "syncnets": "0x0f"
}
```
