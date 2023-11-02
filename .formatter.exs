# Used by "mix format"
[
  inputs:
    ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    |> Enum.reject(&(&1 =~ "lib/proto"))
    |> Enum.reject(&(&1 =~ "test/generated"))
]
