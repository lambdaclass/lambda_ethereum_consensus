defmodule RewardsTestRunner do
  @moduledoc """
  Runner for rewards test cases. `run_test_case/1` is the main entrypoint.
  """
  use ExUnit.CaseTemplate
  use TestRunner
  alias SszTypes.BeaconState

  @disabled [
    # "basic",
    # "leak",
    # "random"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: fork, handler: handler}) do
    fork != "capella" or Enum.member?(@disabled, handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    pre_state =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/pre.ssz_snappy",
        SszTypes.BeaconState
      )

    %{rewards: rewards, penalties: penalties} =
      SpecTestUtils.read_ssz_ex_from_file!(
        case_dir <> "/source_deltas.ssz_snappy",
        Deltas
      )

    source_deltas = Enum.zip(rewards, penalties)

    %{rewards: rewards, penalties: penalties} =
      SpecTestUtils.read_ssz_ex_from_file!(
        case_dir <> "/target_deltas.ssz_snappy",
        Deltas
      )

    target_deltas = Enum.zip(rewards, penalties)

    %{rewards: rewards, penalties: penalties} =
      SpecTestUtils.read_ssz_ex_from_file!(
        case_dir <> "/head_deltas.ssz_snappy",
        Deltas
      )

    head_deltas = Enum.zip(rewards, penalties)

    %{rewards: rewards, penalties: penalties} =
      SpecTestUtils.read_ssz_ex_from_file!(
        case_dir <> "/inactivity_penalty_deltas.ssz_snappy",
        Deltas
      )

    inactivity_penalty_deltas = Enum.zip(rewards, penalties)

    deltas =
      Enum.zip([source_deltas, target_deltas, head_deltas, inactivity_penalty_deltas])

    calculated_deltas =
      Constants.participation_flag_weights()
      |> Stream.with_index()
      |> Stream.map(fn {weight, index} ->
        BeaconState.get_flag_index_deltas(pre_state, weight, index)
      end)
      |> Stream.concat([BeaconState.get_inactivity_penalty_deltas(pre_state)])
      |> Stream.zip()
      |> Enum.to_list()

    assert deltas === calculated_deltas
  end
end

defmodule Deltas do
  @moduledoc """
  Struct definition for `Deltas`.
  """
  @behaviour LambdaEthereumConsensus.Container

  fields = [
    :rewards,
    :penalties
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          rewards: list(SszTypes.gwei()),
          penalties: list(SszTypes.gwei())
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:rewards, {:list, {:int, 64}, 1_099_511_627_776}},
      {:penalties, {:list, {:int, 64}, 1_099_511_627_776}}
    ]
  end
end
