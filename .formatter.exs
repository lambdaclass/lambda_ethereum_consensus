# Used by "mix format"
[
  inputs:
    (["{mix,.formatter}.exs", "{config,lib}/**/*.{ex,exs}"] ++
       (Path.wildcard("test/*") -- ["test/generated"]))
    |> Enum.map(&(&1 <> "/**/*.{ex,exs}"))
]
