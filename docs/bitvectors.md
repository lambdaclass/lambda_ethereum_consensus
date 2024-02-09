# BitVectors and BitLists by example

## Representing integers

Everything in a computer, be it in memory, or disc, or when sent over the network, needs to eventually be represented in binary form. There's two classical ways to do so:

### Big-endian byte order

Big-endian can be thought of as "you represent it as you read it". For example, let's represent the number 259 in big-endian. To represent it as a binary we decompose it into powers of two:

$$259 = 256 + 2 + 1 = 2^{8} + 2^{1} + 2^0$$

That means that we'll have the bits representing the power of 0, the power of 1 and the power of 8 set to 1. The rest, will be clear (value = 0).

```
0000001 00000011
```

Similar to our decimal system of representation, the symbols to the left represent the most significant values, and the ones to the left, the least significant ones.

Note that this we need two bytes to represent it. This is most CPUs can address bytes, but not bits. That is, when we refer to an address in memory, we refer to the whole byte, and the next address corresponds to the next byte.

We can also think about this number as the byte array `be = [1, 3]`. Here, the least significant byte is the one with the highest index `be[1] = 3` and the most significant byte is the one with the lowest index `be[0] = 1`.

### Little-endian byte order

In this representation, we reverse the bytes around. 259 is represented as follows:

```
00000011 00000001
```

In this representation, thinking of it as a byte array, we get `le = [3, 1]`. The lowest index, `le[0] = 3` means the lowest significant byte, and the highest index, `le[1] = 1` is the most significant byte. So while little endian is less readable, it is frequently used to represent integers as binaries because of this property.

## Bit vectors

### Little endian bit order

Why would we need a third representation? Let's first pose the problem. We want to represent a set of booleans. Imagine we have a fixed amount of validators, equal to 9, and we want to represent wether they attested in a block or not. We may represent this as follows:

```
[true, true, false, false, false, false, false, false, true]
```

However, this representation has a problem: each boolean takes one full byte. For a million validators, which is the order of magnitude of the validator set in mainnet, that would take around 1MB, just for to track attestations on a single slot. We may benefit from the fact that a boolean and a bit both have two states and represent this as a binary instead:

```
11000000 10000000
```

So this way we reduce the amount of bytes needed by a factor of 8. In this case we completed the second byte because if we send this over the network we always need to send full bytes, but this effect is diluted when dealing with thousands of bytes.

If we wanted to represent a number with this, as we're addressing by bits instead of bytes, we'd say that the least significant bit is the one with the lowest index, thus why this is called little-endian-*bit*-order. That is, in general:

$$\sum_{i} arr[i]*2^i = 2^0 + 2^1 + 2^8 = 259$$

If you look closely, this is the same number we used in the examples for the classical byte orders! The same way that little-endian byte order was big endian but reversing the bytes, little-endian bit order is big endian but reversing bit by bit.

### Serialization

The way SSZ represents bit vectors is as follows:

1. Conceptually, a set is represented in little-endian bit ordering.
2. Padding is added so we have full bytes.
3. When serializing, we convert from little-endian bit ordering to little-endian byte ordering.

So if we want to represent the following array:

```
[true, true, false, false, false, false, false, false, true]
```

Which means that the validators with index 0, 1 and 8 attested, this would be represented as follows conceptually:

```
110000001
```

Adding padding:

```
11000000 10000000
```

Moving it to little endian byte order (we go byte by byte and reverse the bits):

```
00000011 00000001
```

Which is what I'll send over the network. This is what SSZ calls `bitvectors`, which is a binary representing an array of booleans of constant size. We know that this array is of size 9 beforehand, so we know what bits are padding and should be ignored. For variable sized bit arrays we'll use `bitlists`, which we'll talk about later.

### Internal representation

There's a trick here: SSZ doesn't specify how to store this in memory after deserializing. We could, theoretically, read the serialized data, transform it from little-endian byte order to little-endian bit order, and use bit addressing (which elixir supports) to get individual values. This would imply, however, going through each byte and reversing the bits, which is a costly operation. If we stuck with little-endian byte order, addressing individual bits would be more complicated, and shifting (moving every bit to the left or right) would be tricky.

For this reason, we represent bitvectors in our node as big-endian binaries. That means that we reverse the bytes (a relatively cheap operation) and, for bit addressing, we just use the complementary index. An example:

If we are still representing the number 259 (validators with index 0, 1 and 8 attested) we'll have the two following representations (note, elixir has a `bitstring` type that lets you address bit by bit and store an amount of bits that's not a multiple of 8):

```
110000001 -> little-endian bit order
100000011 -> big-endian
```

If we watch closely, we confirm something we said before: this are bit-mirrored representations. That means that if I want to know if the validator 0 voted, in the little-endian bit order we address `bitvector[i]`, and in the other case, we just use `bitvector[N-i]`, where `N=9` as it is the size of the vector.

A possible optimization (we'd need to benchmark it) would be to represent the array as the number 259 directly, and use bitwise operations to address bits or shift.

This is the code that performs that:

```elixir
def new(bitstring, size) when is_bitstring(bitstring) do
  # Change the byte order from little endian to big endian (reverse bytes).
  encoded_size = bit_size(bitstring)
  <<num::integer-little-size(encoded_size)>> = bitstring
  <<num::integer-size(size)>>
end
```

It reads the input as a little-endian number, and then represents it as big-endian.

## Bitlists

### Sentinel bits

In reality, there's not a fixed amount of validators, if someone deposits 32ETH in the deposit contract, a new validator will join the set. `bitlists` are used to represent boolean arrays of variable size like this one. Conceptually, they use the little-endian bit order too, but they use a strategy called `sentinel bit` to mark where it ends. Let's imagine, again, that we're representing the same set of 9 validators as before. We start with the following 9 bits:

```
110000001
```

To serialize this and send it over the network, I do the following:

1. Add an extra bit = 1:

```
1100000011
```

2. Add padding to complete the full bytes

```
11000000 11000000
```

3. Move to little-endian byte order (reverse bits within each byte):

```
00000011 00000011
```

When deserializing, we'll look closely at the last byte, and realize that there's 6 trailing 0s (padding), and discard those and the 7th bit (the sentinel 1).

### Edge case: already a multiple of 8

We need to take into account that it might be the case that we already have a multiple of 8 as the number of booleans we're representing. For instance, let's suppose that we have 8 validators and only the first and the second one attested. In little-endian bit ordering, that is:

```
11000000
```

When adding the trailing bit and padding, it will look like this:

```
11000000 10000000
```

This means that the sentinel bit is, effectively, adding a full new byte. After reversing the bits:

```
00000011 00000001
```

When parsing this, we still take care about the last byte, but we will realize that it's comprised of 7 trailing 0s and a sentinel bit, so we'll discard it fully. 

This also shows the importance of the sentinel bit: if it wasn't for it it wouldn't be obvious to the parser that `00000011` represented 8 elements: it could be a set of two validators where both voted.

### Internal representation

For bitlists, in this client we do the same as with bitvectors. We represent them using big endian, for the same reasons. That is, the first thing we do is reverse the bytes, and then remove the first zeroes of the first byte. The code doing that is the following:

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

We see that we perform two things at the same time:

1. We read as a little endian and then represent it as big endian.
2. we remove the trailing bits of the last byte, which after reversing, is the first one.
