defmodule Bls do
  @moduledoc """
  BLS signature verification.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "bls_nif"

  @spec sign(binary(), binary()) :: SSZTypes.BLSSignature.t()
  def sign(_private_key, _message) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def verify(_public_key, _message, _signature) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def fast_aggregate_verify(_public_keys, _messages, _signature) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def aggregate_verify(_public_keys, _messages, _signature) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def key_validate(_public_key) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
