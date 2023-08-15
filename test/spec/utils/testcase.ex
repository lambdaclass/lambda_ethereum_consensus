defmodule SpecTestCase do
  @enforce_keys [:config, :fork, :runner, :handler, :suite, :case]
  defstruct [:config, :fork, :runner, :handler, :suite, :case]

  def new([config, fork, runner, handler, suite, cse]) do
    %SpecTestCase{
      config: config,
      fork: fork,
      runner: runner,
      handler: handler,
      suite: suite,
      case: cse
    }
  end

  def name(%SpecTestCase{
        config: config,
        fork: fork,
        runner: runner,
        handler: handler,
        suite: suite,
        case: cse
      }) do
    "c:#{config} f:#{fork} r:#{runner} h:#{handler} s:#{suite} -> #{cse}"
  end

  def dir(%SpecTestCase{
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
