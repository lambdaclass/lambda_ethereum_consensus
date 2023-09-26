defmodule SpecTestCase do
  @moduledoc """
  Helper methods for deriving test case metadata.
  """
  @enforce_keys [:config, :fork, :runner, :handler, :suite, :case]
  defstruct [:config, :fork, :runner, :handler, :suite, :case]

  @type t :: %__MODULE__{
          config: binary,
          fork: binary,
          runner: binary,
          handler: binary,
          suite: binary,
          case: binary
        }

  def new([config, fork, runner, handler, suite, cse]) do
    %__MODULE__{
      config: config,
      fork: fork,
      runner: runner,
      handler: handler,
      suite: suite,
      case: cse
    }
  end

  def name(%__MODULE__{
        config: config,
        fork: fork,
        runner: runner,
        handler: handler,
        suite: suite,
        case: cse
      }) do
    "c:#{config} f:#{fork} r:#{runner} h:#{handler} s:#{suite} -> #{cse}"
  end

  def dir(%__MODULE__{
        config: config,
        fork: fork,
        runner: runner,
        handler: handler,
        suite: suite,
        case: cse
      }) do
    "tests/#{config}/#{fork}/#{runner}/#{handler}/#{suite}/#{cse}"
  end
end
