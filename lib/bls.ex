defmodule Bls do
  @moduledoc """
  BLS signature verification.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "bls_nif"

  @spec sign(binary(), binary()) :: {:ok, SszTypes.bls_signature()} | {:error, any()}
  def sign(_private_key, _message) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec aggregate([SszTypes.bls_signature()]) :: {:ok, SszTypes.bls_signature()} | {:error, any()}
  def aggregate(_signatures) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec verify(SszTypes.bls_pubkey(), binary(), SszTypes.bls_signature()) ::
          {:ok, boolean} | {:error, binary()}
  def verify(_public_key, _message, _signature) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec fast_aggregate_verify([SszTypes.bls_pubkey()], binary(), SszTypes.bls_signature()) ::
          {:ok, boolean} | {:error, binary()}
  def fast_aggregate_verify(_public_keys, _message, _signature) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec eth_fast_aggregate_verify([SszTypes.bls_pubkey()], binary(), SszTypes.bls_signature()) ::
          {:ok, boolean} | {:error, binary()}
  def eth_fast_aggregate_verify(_public_keys, _message, _signature) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec aggregate_verify([SszTypes.bls_pubkey()], [binary()], SszTypes.bls_signature()) ::
          {:ok, boolean} | {:error, binary()}
  def aggregate_verify(_public_keys, _messages, _signature) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec eth_aggregate_pubkeys([SszTypes.bls_pubkey()]) ::
          {:ok, SszTypes.bls_pubkey()} | {:error, any()}
  def eth_aggregate_pubkeys(_public_keys) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def key_validate(_public_key) do
    :erlang.nif_error(:nif_not_loaded)
  end

  ##### Helpers #####
  @doc """
  Same as ``Bls.verify``, but treats errors as invalid signatures.
  """
  @spec valid?(SszTypes.bls_pubkey(), binary(), SszTypes.bls_signature()) :: boolean()
  def valid?(public_key, message, signature) do
    case Bls.verify(public_key, message, signature) do
      {:ok, bool} -> bool
      {:error, _} -> false
    end
  end
end
