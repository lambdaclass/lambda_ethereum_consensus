# BitVectors and BitLists by example

## Representing integers

Computers use transistors to store data. These electrical components only have two possible states: `clear` or `set`. Numerically, we represent the clear state as a `0` and the set state as `1`. Using 1s and 0s, we can represent any integer number using the binary system, the same way we use the decimal system in our daily lives.

As an example, let's take the number 259. For its decimal representation, we use the digits 2, 5, and 9, because each digit, or coefficient, represents a power of 10:

$$ 259 = 200 + 50 + 9 = 2*10^2 + 5*10^1 + 9*10^0 $$

If we wanted to do the same in the binary, we would use powers of two, and each symbol (or bit) can only be 0 or 1.

$$ 259 = 256 + 2 + 1 = 1*2^{8} + 1*2^{1} + 1*2^0 $$

All other bits are 0. This results in the following binary number:

```
100000011
```

In written form, similar to our decimal system of representation, the symbols "to the left" represent the most significant digits, and the ones to the right, the least significant ones.

### Big-endian byte order

Most CPUs can only address bits in groups of 8, called bytes. That is, when we refer to an address in memory, we refer to the whole byte, and the next address corresponds to the next byte. This means that to represent this number, we'll need two bytes, organized as follows:

```
00000001 00000011
```

We can also think about this as the byte array `bytes = [1, 3]`. Here, the least significant byte is the one with the highest index `bytes[1] = 3` and the most significant byte is the one with the lowest index `bytes[0] = 1`.

This ordering of bytes, which is similar to the written form, is called `big-endian`.

### Little-endian byte order

In this representation, we reverse the bytes around. 259 is represented as follows:

```
00000011 00000001
```

Representing it as a byte array, we get `bytes = [3, 1]`. The lowest index, `bytes[0] = 3` means the lowest significant byte, and the highest index, `bytes[1] = 1` is the most significant byte. So, while little-endian is less readable, it is frequently used to represent integers as binaries because of this property.

### "Little-endian bit order"

Why would we need a third representation? Let's first pose the problem. Imagine we have a fixed amount of validators, equal to 9, and we want to represent whether they attested in a block or not. If the validators 0, 1, and 8 attested, we may represent this with a boolean array, as follows:

```
[true, true, false, false, false, false, false, false, true]
```

However, this representation has a problem: each boolean takes up one full byte. For a million validators, which is in the order of magnitude of the validator set of mainnet, that means a total attestation size of 64KB per block, which is half its size. We can instead use the fact that a boolean and a bit both have two states and represent this as a binary instead:

```
11000000 10000000
```

This way we reduce the amount of bytes needed by a factor of 8. In this case, we completed the second byte because if we send this over the network we always need to send full bytes, but this effect is diluted when dealing with thousands of bytes.

If we wanted to represent a number with this, as we're addressing by bits instead of bytes, we'd follow the convention that the least significant bit is the one with the lowest index, thus why this is called little-endian-*bit*-order. That is, in general:

$$ \sum_{i} arr[i]*2^i = 2^0 + 2^1 + 2^8 = 259 $$

If you look closely, this is the same number we used in the examples for the classical byte orders!

Summarizing all representations:

```
00000001 00000011: big-endian
00000011 00000001: little-endian byte order
11000000 10000000: little-endian bit order
```

If we want to convert from each order to each other:

- Little-endian byte order to big-endian: reverse the bytes.
- Little-endian bit order to big-endian: reverse the bits of the whole number.
- Little-endian bit order to little-endian byte order: reverse the bits of each byte. This is equivalent to reversing all bits (converting to big-endian) and then reversing the bytes (big-endian to little-endian byte order) but in a single step.

## Bit vectors

### Serialization (SSZ)

`bitvectors` are exactly that: a set of booleans with a fixed size. SSZ represents bit vectors as follows:

- Conceptually, a set is represented in little-endian bit ordering, padded with 0s at the end to get full bytes.
- When serializing, we convert from little-endian bit ordering to little-endian byte ordering.

If we want to represent that the validators with indices 0, 1, and 8 attested, we can use the following array:

```
[true, true, false, false, false, false, false, false, true]
```

Conceptually, this would be represented as the following string of bits:

```
110000001
```

Adding padding:

```
11000000 10000000
```

Moving it to little-endian byte order (we go byte by byte and reverse the bits):

```
00000011 00000001
```

This is how nodes send `bitvectors` over the network. We know that this array is of size 9 beforehand, so we know what bits are padding and should be ignored. For variable-sized bit arrays, we'll use `bitlists`, which we'll talk about later.

### Internal representation

There's a trick here: SSZ doesn't specify how to store a `bitvector` in memory after deserializing. We could, theoretically, read the serialized data, transform it from little-endian byte order to little-endian bit order, and use bit addressing (which Elixir supports) to get individual values. This would imply, however, going through each byte and reversing the bits, which is a costly operation. If we stuck with little-endian byte order without transforming it, addressing individual bits would be more complicated, and shifting (moving every bit to the left or right) would be tricky.

For this reason, we represent bitvectors in our node as big-endian binaries. That means that we reverse the bytes (a relatively cheap operation) and, for bit addressing, we just use the complementary index. An example:

If we are still representing the number 259 (validators with index 0, 1, and 8 attested) we'll have the two following representations (note, elixir has a `bitstring` type that lets you address bit by bit and store a number of bits that's not a multiple of 8):

```
110000001 -> little-endian bit order
100000011 -> big-endian
```

If we watch closely, we confirm something we said before: these are bit-mirrored representations. That means that if I want to know if the validator I voted, in the little-endian bit order, we address `bitvector[i]`, and in the big-endian order, we just use `bitvector[N-i]`, where `N=9` as it's the size of the vector.

This is the code that performs this conversion:

```elixir
def new(bitstring, size) when is_bitstring(bitstring) do
  # Change the byte order from little endian to big endian (reverse bytes).
  encoded_size = bit_size(bitstring)
  <<num::integer-little-size(encoded_size)>> = bitstring
  <<num::integer-size(size)>>
end
```

It reads the input as a little-endian number and then constructs a big-endian binary representation of it.

Instead of using Elixir's bitstrings, a possible optimization (we'd need to benchmark it) would be to represent the array as the number 259 directly and use bitwise operations to address bits or shift.

## Bitlists

### Sentinel bits

In reality, there isn't a fixed amount of validators. If someone deposits 32ETH in the deposit contract, a new validator will join the set. `bitlists` are used to represent boolean arrays of variable size like this one. Conceptually, they use the little-endian bit order too, but they use a strategy called `sentinel bit` to mark where it ends. Let's imagine, again, that we're representing the same set of 9 validators as before. We start with the following 9 bits:

```
110000001
```

To serialize this and send it over the network, we do the following:

1. Add an extra (sentinel) bit, equal to 1:

```
1100000011
```

2. Add padding to complete the full byte:

```
11000000 11000000
```

3. Transform to little-endian byte order (reverse bits within each byte):

```
00000011 00000011
```

When deserializing, we'll look closely at the last byte, realize that there are 6 trailing 0s (padding), and discard those along with the 7th bit (the sentinel 1).

### Edge case: already a multiple of 8

It might be the case that we already have a multiple of 8 as the number of booleans we're representing. For instance, let's suppose that we have 8 validators and only the first and the second ones attested. In little-endian bit order, that is:

```
11000000
```

When adding the trailing bit and padding, it will look like this:

```
11000000 10000000
```

This means that the sentinel bit is, effectively, adding a new full byte. After serializing:

```
00000011 00000001
```

When parsing this, we still pay attention to the last byte, but we will realize that it's comprised of 7 trailing 0s and a sentinel bit, so we'll discard it entirely.

This also shows the importance of the sentinel bit: if it wasn't for it it wouldn't be obvious to the parser that `00000011` represents 8 elements: it could be a set of two validators where both voted (`11`).

### Internal representation

For `bitlists`, in this client we do the same as with `bitvectors`, and for the same reasons: we represent them using big-endian. The code doing that is the following:

```elixir
def new(bitstring) when is_bitstring(bitstring) do
  # Change the byte order from little endian to big endian (reverse bytes).
  num_bits = bit_size(bitstring)
  len = length_of_bitlist(bitstring)

  <<pre::integer-little-size(num_bits - 8), last_byte::integer-little-size(@bits_per_byte)>> =
  bitstring

  decoded = <<remove_trailing_bit(<<last_byte>>)::bitstring, pre::integer-size(num_bits - 8)>>
  {decoded, len}
end

@spec remove_trailing_bit(binary()) :: bitstring()
defp remove_trailing_bit(<<1::1, rest::7>>), do: <<rest::7>>
defp remove_trailing_bit(<<0::1, 1::1, rest::6>>), do: <<rest::6>>
defp remove_trailing_bit(<<0::2, 1::1, rest::5>>), do: <<rest::5>>
defp remove_trailing_bit(<<0::3, 1::1, rest::4>>), do: <<rest::4>>
defp remove_trailing_bit(<<0::4, 1::1, rest::3>>), do: <<rest::3>>
defp remove_trailing_bit(<<0::5, 1::1, rest::2>>), do: <<rest::2>>
defp remove_trailing_bit(<<0::6, 1::1, rest::1>>), do: <<rest::1>>
defp remove_trailing_bit(<<0::7, 1::1>>), do: <<0::0>>
defp remove_trailing_bit(<<0::8>>), do: <<0::0>>

# This last case should never happen, the last byte should always
# have a sentinel bit.
```

We see that the code performs two things at the same time:

1. It parses the little-endian byte ordered binary and then represents it as big-endian.
2. It removes the trailing bits and sentinel of the last byte, which after reversing, is the first one.
