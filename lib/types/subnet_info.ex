defmodule Types.SubnetInfo do
  @moduledoc """
  Struct to hold subnet attestations for easier db storing:
  - data: An attestation data.
  - attestations: List with all the collected Attestations.
  """
  alias Types.Attestation
  alias Types.AttestationData
  alias Types.SubnetInfo

  defstruct [:data, :attestations]

  @type t :: %__MODULE__{
          data: AttestationData.t(),
          attestations: Attestation
        }

  @spec new_subnet_with_attestation(Attestation.t()) :: t()
  def new_subnet_with_attestation(attestation) do
    %SubnetInfo{data: attestation.data, attestations: [attestation]}
  end

  @spec aggregate_attestation(t(), Attestation.t()) :: t()
  def aggregate_attestation(subnet_info, attestation) do
    if subnet_info.data == attestation.data do
      %SubnetInfo{subnet_info | attestations: [attestation | subnet_info.attestations]}
    else
      subnet_info
    end
  end

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = subnet_info) do
    {subnet_info.data, subnet_info.attestations} |> :erlang.term_to_binary()
  end

  @spec decode(binary()) :: t()
  def decode(bin) do
    {data, attestations} = :erlang.binary_to_term(bin)
    %__MODULE__{data: data, attestations: attestations}
  end
end
