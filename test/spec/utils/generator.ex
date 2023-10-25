defmodule SpecTestGenerator do
  @moduledoc """
  Generator for running the spec tests.
  """

  # To filter tests, use:
  #  (only spectests) ->
  #   mix test --only spectest
  #  (only general) ->
  #   mix test --only config:general
  #  (only ssz_generic) ->
  #   mix test --only runner:ssz_generic
  #  (one specific test) ->
  #   mix test --only test:"test c:`config` f:`fork` r:`runner h:`handler` s:suite` -> `case`"
  #
  # Tests are too many to run all at the same time. We should pin a
  # `config` (and `fork` in the case of `minimal`).
end
