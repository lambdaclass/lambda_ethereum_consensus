defmodule Kzg do
  @moduledoc """
  KZG functions
  """

  alias KZG, as: CKZG

  require Logger

  @bytes_per_blob 4096 * 32
  @bytes_per_commitment 48
  @bytes_per_proof 48
  @trusted_setup_path Path.expand("config/kzg/official_trusted_setup.txt", File.cwd!())

  @type commitment :: <<_::384>>
  @type proof :: <<_::384>>

  @spec blob_to_kzg_commitment(Types.blob()) :: {:ok, commitment()} | {:error, atom()}
  def blob_to_kzg_commitment(blob) do
    with :ok <- ensure_blob_size(blob) do
      with_settings(fn s -> CKZG.blob_to_kzg_commitment(blob, s) end)
    end
  end

  @spec compute_kzg_proof(Types.blob(), Types.bytes32()) ::
          {:ok, {proof(), Types.bytes32()}} | {:error, atom()}
  def compute_kzg_proof(blob, z) do
    with :ok <- ensure_blob_size(blob),
         :ok <- ensure_bytes32(z) do
      with_settings(fn s -> CKZG.compute_kzg_proof(blob, z, s) end)
    end
  end

  @spec verify_kzg_proof(commitment(), Types.bytes32(), Types.bytes32(), proof()) ::
          {:ok, boolean} | {:error, atom()}
  def verify_kzg_proof(commitment, z, y, proof) do
    with :ok <- ensure_commitment_size(commitment),
         :ok <- ensure_bytes32(z),
         :ok <- ensure_bytes32(y),
         :ok <- ensure_proof_size(proof) do
      with_settings(fn s -> CKZG.verify_kzg_proof(commitment, z, y, proof, s) end)
    end
  end

  @spec compute_blob_kzg_proof(Types.blob(), commitment()) ::
          {:ok, proof()} | {:error, atom()}
  def compute_blob_kzg_proof(blob, commitment) do
    with :ok <- ensure_blob_size(blob),
         :ok <- ensure_commitment_size(commitment) do
      with_settings(fn s -> CKZG.compute_blob_kzg_proof(blob, commitment, s) end)
    end
  end

  @spec verify_blob_kzg_proof(Types.blob(), commitment(), proof()) ::
          {:ok, boolean} | {:error, atom()}
  def verify_blob_kzg_proof(blob, commitment, proof) do
    with :ok <- ensure_blob_size(blob),
         :ok <- ensure_commitment_size(commitment),
         :ok <- ensure_proof_size(proof) do
      with_settings(fn s ->
        CKZG.verify_blob_kzg_proof(blob, commitment, proof, s)
      end)
    end
  end

  @spec verify_blob_kzg_proof_batch(
          [Types.blob()],
          [commitment()],
          [proof()]
        ) ::
          {:ok, boolean} | {:error, atom()}
  def verify_blob_kzg_proof_batch(blobs, kzg_commitments, kzg_proofs) do
    with :ok <- ensure_all_blob_sizes(blobs),
         :ok <- ensure_all_commitment_sizes(kzg_commitments),
         :ok <- ensure_all_proof_sizes(kzg_proofs),
         :ok <- ensure_batch_lengths_match(blobs, kzg_commitments, kzg_proofs) do
      blobs_bin = IO.iodata_to_binary(blobs)
      commitments_bin = IO.iodata_to_binary(kzg_commitments)
      proofs_bin = IO.iodata_to_binary(kzg_proofs)

      with_settings(fn settings ->
        CKZG.verify_blob_kzg_proof_batch(blobs_bin, commitments_bin, proofs_bin, settings)
      end)
    end
  end

  ################
  ### Wrappers ###
  ################

  @spec blob_kzg_proof_batch_valid?(
          list(Types.blob()),
          list(commitment()),
          list(proof())
        ) :: boolean()
  def blob_kzg_proof_batch_valid?(blobs, kzg_commitments, kzg_proofs) do
    case verify_blob_kzg_proof_batch(blobs, kzg_commitments, kzg_proofs) do
      {:ok, result} -> result
      {:error, _} -> false
    end
  end

  defp settings() do
    :persistent_term.get({__MODULE__, :settings}, fn -> load_settings() end)
  end

  defp load_settings() do
    {:ok, settings} = CKZG.load_trusted_setup(@trusted_setup_path, 0)
    :persistent_term.put({__MODULE__, :settings}, settings)
    settings
  end

  defp reset_settings() do
    Logger.warning("[KZG] Resetting settings resource")
    :persistent_term.erase({__MODULE__, :settings})
    load_settings()
  end

  defp with_settings(fun) do
    case fun.(settings()) do
      {:error, :failed_get_settings_resource} -> fun.(reset_settings())
      other -> other
    end
  end

  defp ensure_blob_size(<<_::binary-size(@bytes_per_blob)>>), do: :ok
  defp ensure_blob_size(_), do: {:error, :invalid_blob_length}

  defp ensure_bytes32(<<_::binary-size(32)>>), do: :ok
  defp ensure_bytes32(_), do: {:error, :invalid_field_element_length}

  defp ensure_commitment_size(<<_::binary-size(@bytes_per_commitment)>>), do: :ok
  defp ensure_commitment_size(_), do: {:error, :invalid_commitment_length}

  defp ensure_proof_size(<<_::binary-size(@bytes_per_proof)>>), do: :ok
  defp ensure_proof_size(_), do: {:error, :invalid_proof_length}

  defp ensure_all_blob_sizes(list) when is_list(list) do
    if Enum.all?(list, &match?(<<_::binary-size(@bytes_per_blob)>>, &1)),
      do: :ok,
      else: {:error, :invalid_blob_length}
  end

  defp ensure_all_commitment_sizes(list) when is_list(list) do
    if Enum.all?(list, &match?(<<_::binary-size(@bytes_per_commitment)>>, &1)),
      do: :ok,
      else: {:error, :invalid_commitment_length}
  end

  defp ensure_all_proof_sizes(list) when is_list(list) do
    if Enum.all?(list, &match?(<<_::binary-size(@bytes_per_proof)>>, &1)),
      do: :ok,
      else: {:error, :invalid_proof_length}
  end

  defp ensure_batch_lengths_match(blobs, commitments, proofs) do
    case {length(blobs), length(commitments), length(proofs)} do
      {same, same, same} -> :ok
      _ -> {:error, :invalid_batch_length}
    end
  end
end
