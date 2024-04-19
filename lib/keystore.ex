defmodule Keystore do
  @moduledoc """
  [ERC-2335](https://eips.ethereum.org/EIPS/eip-2335) compliant keystore.
  """

  @secret_key_bytes 32
  @salt_bytes 32
  @derived_key_size 32
  @iv_size 16
  @checksum_message_size 32

  @spec from_json!(String.t()) :: {Types.bls_pubkey(), Bls.privkey()}
  def from_json!(json) do
    %{pubkey: hex_pubkey, version: 4} = Jason.decode!(json)
    pubkey = Base.decode16!(hex_pubkey, case: :mixed)
    privkey = ""
    {pubkey, privkey}
  end

  def decrypt!(password, %{"kdf" => kdf, "checksum" => checksum, "cipher" => cipher}) do
    password = sanitize_password(password)
    derived_key = derive_key!(kdf, password)

    {iv, cipher_message} = parse_cipher!(cipher)
    checksum_message = parse_checksum!(checksum)
    verify_password!(derived_key, cipher_message, checksum_message)
    secret = decrypt_secret(derived_key, iv, cipher_message)

    if byte_size(secret) != @secret_key_bytes do
      raise "Invalid secret length: #{byte_size(secret)}"
    end

    secret
  end

  defp derive_key!(%{"function" => "scrypt", "params" => params}, password) do
    %{"dklen" => @derived_key_size, "salt" => hex_salt, "n" => n, "p" => p, "r" => r} = params
    salt = parse_binary(hex_salt)

    if byte_size(salt) != @salt_bytes do
      raise "Invalid salt size: #{byte_size(salt)}"
    end

    log_n = n |> :math.log2() |> trunc()
    Scrypt.hash(password, salt, log_n, r, p, @derived_key_size)
  end

  defp derive_key!(%{"function" => "pbkdf2"} = drf, _password) do
    %{"dklen" => _dklen, "salt" => _salt, "c" => _c, "prf" => "hmac-sha256"} = drf
  end

  defp decrypt_secret(derived_key, iv, cipher_message) do
    <<key::binary-size(16), _::binary>> = derived_key
    :crypto.crypto_one_time(:aes_128_ctr, key, iv, cipher_message, false)
  end

  defp verify_password!(derived_key, cipher_message, checksum_message) do
    dk_slice = derived_key |> binary_part(16, 16)

    pre_image = dk_slice <> cipher_message
    checksum = :crypto.hash(:sha256, pre_image)

    if checksum != checksum_message do
      raise "Invalid password"
    end
  end

  defp parse_checksum!(%{"function" => "sha256", "message" => hex_message}) do
    message = parse_binary(hex_message)

    if byte_size(message) != @checksum_message_size do
      "Invalid checksum size: #{byte_size(message)}"
    end

    message
  end

  defp parse_cipher!(%{
         "function" => "aes-128-ctr",
         "params" => %{"iv" => hex_iv},
         "message" => hex_message
       }) do
    iv = parse_binary(hex_iv)

    if byte_size(iv) != @iv_size do
      raise "Invalid IV size: #{byte_size(iv)}"
    end

    {iv, parse_binary(hex_message)}
  end

  defp parse_binary(hex), do: Base.decode16!(hex, case: :mixed)

  defp sanitize_password(password),
    do: password |> String.normalize(:nfkd) |> String.replace(~r/[\x00-\x1f\x80-\x9f\x7f]/, "")
end
