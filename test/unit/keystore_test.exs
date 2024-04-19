defmodule Unit.KeystoreTest do
  use ExUnit.Case

  @eip_password "testpassword"
  @eip_secret Base.decode16!("000000000019D6689C085AE165831E934FF763AE46A2A6C172B3F1B60A8CE26F")

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
      "description": "This is a test keystore that uses scrypt to secure the secret.",
      "pubkey": "9612d7a727c9d0a22e185a1c768478dfe919cada9266988cb32359c11f2b7b27f4ae4040902382ae2910c15e2b420d07",
      "path": "m/12381/60/3141592653/589793238",
      "uuid": "1d85ae20-35c5-4611-98e8-aa14a633906f",
      "version": 4
  })

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
              "message": "8a9f5d9912ed7e75ea794bc5a89bca5f193721d30868ade6f73043c6ea6febf1"
          },
          "cipher": {
              "function": "aes-128-ctr",
              "params": {
                  "iv": "264daa3f303d7259501c93d997d84fe6"
              },
              "message": "cee03fde2af33149775b7223e7845e4fb2c8ae1792e5f99fe9ecf474cc8c16ad"
          }
      },
      "description": "This is a test keystore that uses PBKDF2 to secure the secret.",
      "pubkey": "9612d7a727c9d0a22e185a1c768478dfe919cada9266988cb32359c11f2b7b27f4ae4040902382ae2910c15e2b420d07",
      "path": "m/12381/60/0/0",
      "uuid": "64625def-3331-4eea-ab6f-782f3ed16a83",
      "version": 4
  })

  test "eip scrypt test vector" do
    %{"crypto" => crypto} = Jason.decode!(@scrypt_json)
    secret = Keystore.decrypt!(@eip_password, crypto)
    assert secret == @eip_secret
  end
end
