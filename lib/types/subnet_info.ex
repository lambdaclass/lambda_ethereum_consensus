defmodule Types.SubnetInfo do
  @moduledoc """
  Struct to hold subnet attestations for easier db storing:
  - data: An attestation data.
  - attestations: List of all the collected Attestations.
  """
  alias LambdaEthereumConsensus.Store.Db

  defstruct [:data, :attestations]

  @type t :: %__MODULE__{
          data: Types.AttestationData.t(),
          attestations: list(Types.Attestation.t())
        }

  @subnet_prefix "subnet"

  @doc """
  Creates a SubnetInfo from an Attestation and stores it into the database.
  The attestation is typically built by a validator before starting to collect others' attestations.
  This attestation will be used to filter other added attestations.
  """
  @spec new_subnet_with_attestation(non_neg_integer(), Types.Attestation.t()) :: :ok
  def new_subnet_with_attestation(subnet_id, %Types.Attestation{data: data} = attestation) do
    new_subnet_info = %__MODULE__{data: data, attestations: [attestation]}
    persist_subnet_info(subnet_id, new_subnet_info)
  end

  @doc """
  Removes the associated SubnetInfo from the database and returns all the collected attestations.
  """
  @spec stop_collecting(non_neg_integer()) ::
          {:ok, list(Types.Attestation.t())} | {:error, String.t()}
  def stop_collecting(subnet_id) do
    case fetch_subnet_info(subnet_id) do
      {:ok, subnet_info} ->
        delete_subnet(subnet_id)
        {:ok, subnet_info.attestations}

      :not_found ->
        {:error, "subnet not joined"}
    end
  end

  @doc """
  Adds a new Attestation to the SubnetInfo if the attestation's data matches the base one.
  Assumes that the SubnetInfo already exists.
  """
  @spec add_attestation!(non_neg_integer(), Types.Attestation.t()) :: :ok
  def add_attestation!(subnet_id, attestation) do
    subnet_info = fetch_subnet_info!(subnet_id)

    if subnet_info.data == attestation.data do
      new_subnet_info = %__MODULE__{
        subnet_info
        | attestations: [attestation | subnet_info.attestations]
      }

      persist_subnet_info(subnet_id, new_subnet_info)
    end
  end

  ##########################
  ### Database Calls
  ##########################

  @spec persist_subnet_info(non_neg_integer(), t()) :: :ok
  defp persist_subnet_info(subnet_id, subnet_info) do
    key = @subnet_prefix <> Integer.to_string(subnet_id)
    value = encode(subnet_info)

    :telemetry.span([:subnet, :persist], %{}, fn ->
      {Db.put(
         key,
         value
       ), %{}}
    end)
  end

  @spec fetch_subnet_info(non_neg_integer()) :: {:ok, t()} | :not_found
  defp fetch_subnet_info(subnet_id) do
    result =
      :telemetry.span([:subnet, :fetch], %{}, fn ->
        {Db.get(@subnet_prefix <> Integer.to_string(subnet_id)), %{}}
      end)

    case result do
      {:ok, binary} -> {:ok, decode(binary)}
      :not_found -> result
    end
  end

  @spec fetch_subnet_info!(non_neg_integer()) :: t()
  defp fetch_subnet_info!(subnet_id) do
    {:ok, subnet_info} = fetch_subnet_info(subnet_id)
    subnet_info
  end

  @spec delete_subnet(non_neg_integer()) :: :ok
  defp delete_subnet(subnet_id), do: Db.delete(@subnet_prefix <> Integer.to_string(subnet_id))

  @spec encode(t()) :: binary()
  defp encode(%__MODULE__{} = subnet_info) do
    {subnet_info.data, subnet_info.attestations} |> :erlang.term_to_binary()
  end

  @spec decode(binary()) :: t()
  defp decode(bin) do
    {data, attestations} = :erlang.binary_to_term(bin)
    %__MODULE__{data: data, attestations: attestations}
  end
end
