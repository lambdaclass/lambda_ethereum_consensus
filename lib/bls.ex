defmodule Bls do
  @moduledoc """
  BLS signature verification.
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "bls_nif"

  @type privkey() :: <<_::256>>

  @spec sign(privkey(), binary()) :: {:ok, Types.bls_signature()} | {:error, any()}
  def sign(_private_key, _message) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec aggregate([Types.bls_signature()]) :: {:ok, Types.bls_signature()} | {:error, any()}
  def aggregate(_signatures) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec verify(Types.bls_pubkey(), binary(), Types.bls_signature()) ::
          {:ok, boolean} | {:error, binary()}
  def verify(_public_key, _message, _signature) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec fast_aggregate_verify([Types.bls_pubkey()], binary(), Types.bls_signature()) ::
          {:ok, boolean} | {:error, binary()}
  def fast_aggregate_verify(_public_keys, _message, _signature) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec eth_fast_aggregate_verify([Types.bls_pubkey()], binary(), Types.bls_signature()) ::
          {:ok, boolean} | {:error, binary()}
  def eth_fast_aggregate_verify(_public_keys, _message, _signature) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec aggregate_verify([Types.bls_pubkey()], [binary()], Types.bls_signature()) ::
          {:ok, boolean} | {:error, binary()}
  def aggregate_verify(_public_keys, _messages, _signature) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec eth_aggregate_pubkeys([Types.bls_pubkey()]) ::
          {:ok, Types.bls_pubkey()} | {:error, any()}
  def eth_aggregate_pubkeys(_public_keys) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec key_validate(Types.bls_pubkey()) ::
          {:ok, boolean} | {:error, binary()}
  def key_validate(_public_key) do
    :erlang.nif_error(:nif_not_loaded)
  end

  ##### Helpers #####
  @doc """
  Same as ``Bls.verify``, but treats errors as invalid signatures.
  """
  @spec valid?(Types.bls_pubkey(), binary(), Types.bls_signature()) :: boolean()
  def valid?(public_key, message, signature) do
    case Bls.verify(public_key, message, signature) do
      {:ok, bool} -> bool
      {:error, _} -> false
    end
  end

  ##### Helpers #####
  @doc """
  Same as ``Bls.fast_aggregate_verify``, but treats errors as invalid signatures.
  """
  @spec fast_aggregate_valid?([Types.bls_pubkey()], binary(), Types.bls_signature()) :: boolean()
  def fast_aggregate_valid?(public_keys, message, signature) do
    case Bls.fast_aggregate_verify(public_keys, message, signature) do
      {:ok, bool} -> bool
      {:error, _} -> false
    end
  end
end
