if [ ! -f ~/.mix/escripts/protoc-gen-elixir ]; then
    mix escript.install hex protobuf
fi

go install google.golang.org/protobuf/cmd/protoc-gen-go@latest

if command -v asdf &> /dev/null; then
  asdf reshim
fi

