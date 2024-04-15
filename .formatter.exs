# Used by "mix format"
[
  inputs:
    ["{mix,.formatter,.recode}.exs", "{config,lib,bench}/**/*.{ex,exs}"] ++
      ((Path.wildcard("test/*") -- ["test/generated"]) |> Enum.map(&(&1 <> "/**/*.{ex,exs}"))),
  plugins: [Recode.FormatterPlugin]
]
