defmodule Types.BlockInfo do
  @moduledoc """
  Signed beacon block accompanied with its root and its processing status.
  Maps to what's saved on the blocks db.
  """

  alias Types.SignedBeaconBlock

  @type block_status ::
          :pending
          | :invalid
          | :download
          | :download_blobs
          | :unknown
          | :transitioned

  @type t :: %__MODULE__{
          root: Types.root(),
          signed_block: Types.SignedBeaconBlock.t() | nil,
          status: block_status()
        }
  defstruct [:root, :signed_block, :status]

  defguard is_status(atom)
           when atom in [
                  :pending,
                  :invalid,
                  :processing,
                  :download,
                  :download_blobs,
                  :unknown,
                  :transitioned
                ]

  @spec from_block(SignedBeaconBlock.t(), block_status()) :: t()
  def from_block(signed_block, status \\ :pending) do
    {:ok, root} = Ssz.hash_tree_root(signed_block.message)
    from_block(signed_block, root, status)
  end

  @spec from_block(SignedBeaconBlock.t(), Types.root(), block_status()) :: t()
  def from_block(signed_block, root, status) do
    %__MODULE__{root: root, signed_block: signed_block, status: status}
  end

  @spec change_status(t(), block_status()) :: t()
  def change_status(%__MODULE__{} = block_info, new_status) when is_status(new_status) do
    %__MODULE__{block_info | status: new_status}
  end

  @spec encode(t()) :: {:ok, binary()} | {:error, binary()}
  def encode(%__MODULE__{} = block_info) do
    with {:ok, encoded_signed_block} <- encode_signed_block(block_info.signed_block) do
      {:ok, :erlang.term_to_binary({encoded_signed_block, block_info.status})}
    end
  end

  @spec decode(Types.root(), binary()) :: {:error, binary()} | {:ok, t()}
  def decode(block_root, data) do
    with {:ok, {encoded_signed_block, status}} <- validate_term(:erlang.binary_to_term(data)),
         {:ok, signed_block} <- decode_signed_block(encoded_signed_block) do
      {:ok, %__MODULE__{root: block_root, signed_block: signed_block, status: status}}
    end
  end

  defp encode_signed_block(nil), do: {:ok, nil}
  defp encode_signed_block(%SignedBeaconBlock{} = block), do: Ssz.to_ssz(block)

  defp decode_signed_block(nil), do: {:ok, nil}

  defp decode_signed_block(data) when is_binary(data) do
    Ssz.from_ssz(data, SignedBeaconBlock)
  end

  # Validates a term that came out of the first decoding step for a stored block info tuple.
  defp validate_term({encoded_signed_block, status})
       when (is_binary(encoded_signed_block) or is_nil(encoded_signed_block)) and
              is_status(status) do
    {:ok, {encoded_signed_block, status}}
  end

  defp validate_term(other) do
    {:error, "Block decoding failed, decoded term is not the expected tuple: #{other}"}
  end
end
