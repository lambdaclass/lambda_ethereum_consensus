defmodule MinimalCapellaSpecTest do
  use ExUnit.Case, async: true
  use SpecTestUtils

  SpecTestUtils.generate_tests("minimal", "capella")
end

defmodule GeneralSpecTest do
  use ExUnit.Case, async: true
  use SpecTestUtils

  SpecTestUtils.generate_tests("general")
end

defmodule MainnetSpecTest do
  use ExUnit.Case, async: true
  use SpecTestUtils

  SpecTestUtils.generate_tests("mainnet")
end
