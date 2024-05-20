defmodule Keystore do
  @moduledoc """
  [ERC-2335](https://eips.ethereum.org/EIPS/eip-2335) compliant keystore.
  """

  @secret_key_bytes 32
  @salt_bytes 32
  @derived_key_size 32
  @iv_size 16
  @checksum_message_size 32

  @spec decode_from_files!(Path.t(), Path.t()) :: {Types.bls_pubkey(), Bls.privkey()}
  def decode_from_files!(json, password) do
    password = File.read!(password)
    File.read!(json) |> decode_str!(password)
  end

  @spec decode_str!(String.t(), String.t()) :: {Types.bls_pubkey(), Bls.privkey()}
  def decode_str!(json, password) do
    decoded_json = Jason.decode!(json)
    # We only support version 4 (the only one)
    %{"version" => 4} = decoded_json
    validate_empty_path!(decoded_json["path"])

    privkey = decrypt!(decoded_json["crypto"], password)

    pubkey = Map.fetch!(decoded_json, "pubkey") |> parse_binary!()

    if Bls.derive_pubkey(privkey) != {:ok, pubkey} do
      raise("Keystore secret and public keys don't form a valid pair")
    end

    {pubkey, privkey}
  end

  # TODO: support keystore paths
  defp validate_empty_path!(path) when byte_size(path) > 0,
    do: raise("Only empty-paths are supported")

  defp validate_empty_path!(_), do: :ok

  defp decrypt!(%{"kdf" => kdf, "checksum" => checksum, "cipher" => cipher}, password) do
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
    salt = parse_binary!(hex_salt)

    if byte_size(salt) != @salt_bytes do
      raise "Invalid salt size: #{byte_size(salt)}"
    end

    log_n = n |> :math.log2() |> trunc()
    Scrypt.hash(password, salt, log_n, r, p, @derived_key_size)
  end

  # TODO: support pbkdf2
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
    message = parse_binary!(hex_message)

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
    iv = parse_binary!(hex_iv)

    if byte_size(iv) != @iv_size do
      raise "Invalid IV size: #{byte_size(iv)}"
    end

    {iv, parse_binary!(hex_message)}
  end

  defp parse_binary!(hex), do: Base.decode16!(hex, case: :mixed)

  defp sanitize_password(password),
    do: password |> String.normalize(:nfkd) |> String.replace(~r/[\x00-\x1f\x80-\x9f\x7f]/, "")
end
