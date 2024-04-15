defmodule Types.BlobsBundle do
  @moduledoc """
  Struct received by `ExecutionClient.get_payload`.
  """

  @enforce_keys [:blobs, :commitments, :proofs]
  defstruct [:blobs, :commitments, :proofs]

  @type t :: %__MODULE__{
          blobs: list(Types.blob()),
          commitments: list(Types.kzg_commitment()),
          proofs: list(Types.kzg_proof())
        }
end
