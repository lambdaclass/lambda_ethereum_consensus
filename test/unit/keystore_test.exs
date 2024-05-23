defmodule Unit.KeystoreTest do
  use ExUnit.Case

  @eip_password "testpassword"
  @eip_secret Base.decode16!("000000000019D6689C085AE165831E934FF763AE46A2A6C172B3F1B60A8CE26F")
  @pubkey Base.decode16!(
            "9612D7A727C9D0A22E185A1C768478DFE919CADA9266988CB32359C11F2B7B27F4AE4040902382AE2910C15E2B420D07"
          )

  # Taken from lighthouse
  @scrypt_json ~s({
        "crypto": {
            "kdf": {
                "function": "scrypt",
                "params": {
                    "dklen": 32,
                    "n": 262144,
                    "p": 1,
                    "r": 8,
                    "salt": "d4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3"
                },
                "message": ""
            },
            "checksum": {
                "function": "sha256",
                "params": {},
                "message": "149aafa27b041f3523c53d7acba1905fa6b1c90f9fef137568101f44b531a3cb"
            },
            "cipher": {
                "function": "aes-128-ctr",
                "params": {
                    "iv": "264daa3f303d7259501c93d997d84fe6"
                },
                "message": "54ecc8863c0550351eee5720f3be6a5d4a016025aa91cd6436cfec938d6a8d30"
            }
        },
        "pubkey": "9612d7a727c9d0a22e185a1c768478dfe919cada9266988cb32359c11f2b7b27f4ae4040902382ae2910c15e2b420d07",
        "uuid": "1d85ae20-35c5-4611-98e8-aa14a633906f",
        "path": "",
        "version": 4
    })

  # Taken from lighthouse, minus "path": "m/12381/60/0/0",
  @pbkdf2_json ~s({
            "crypto": {
                "kdf": {
                    "function": "pbkdf2",
                    "params": {
                        "dklen": 32,
                        "c": 262144,
                        "prf": "hmac-sha256",
                        "salt": "d4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3"
                    },
                    "message": ""
                },
                "checksum": {
                    "function": "sha256",
                    "params": {},
                    "message": "18b148af8e52920318084560fd766f9d09587b4915258dec0676cba5b0da09d8"
                },
                "cipher": {
                    "function": "aes-128-ctr",
                    "params": {
                        "iv": "264daa3f303d7259501c93d997d84fe6"
                    },
                    "message": "a9249e0ca7315836356e4c7440361ff22b9fe71e2e2ed34fc1eb03976924ed48"
                }
            },
            "pubkey": "9612d7a727c9d0a22e185a1c768478dfe919cada9266988cb32359c11f2b7b27f4ae4040902382ae2910c15e2b420d07",
            "uuid": "64625def-3331-4eea-ab6f-782f3ed16a83",
            "version": 4
        })

  test "eip scrypt test vector" do
    {pubkey, privkey} = Keystore.decode_str!(@scrypt_json, @eip_password)

    assert privkey == @eip_secret
    assert pubkey == @pubkey

    digest = :crypto.hash(:sha256, "test message")
    {:ok, signature} = Bls.sign(privkey, digest)
    assert Bls.valid?(pubkey, digest, signature)
  end

  test "eip pbkdf2 test vector" do
    {pubkey, privkey} = Keystore.decode_str!(@pbkdf2_json, @eip_password)

    assert privkey == @eip_secret
    assert pubkey == @pubkey

    digest = :crypto.hash(:sha256, "test message")
    {:ok, signature} = Bls.sign(privkey, digest)
    assert Bls.valid?(pubkey, digest, signature)
  end

  test "eip scrypt without pubkey test vector" do
    scrypt_json =
        Jason.decode!(@pbkdf2_json)
        |> Map.delete("pubkey")
        |> Jason.encode!()

    {pubkey, privkey} = Keystore.decode_str!(scrypt_json, @eip_password)

    assert privkey == @eip_secret
    assert pubkey == @pubkey

    digest = :crypto.hash(:sha256, "test message")
    {:ok, signature} = Bls.sign(privkey, digest)
    assert Bls.valid?(pubkey, digest, signature)
  end

  test "eip pbkdf2 without pubkey test vector" do
    pbkdf2_json =
        Jason.decode!(@pbkdf2_json)
        |> Map.delete("pubkey")
        |> Jason.encode!()

    {pubkey, privkey} = Keystore.decode_str!(pbkdf2_json, @eip_password)

    assert privkey == @eip_secret
    assert pubkey == @pubkey

    digest = :crypto.hash(:sha256, "test message")
    {:ok, signature} = Bls.sign(privkey, digest)
    assert Bls.valid?(pubkey, digest, signature)
  end
end
