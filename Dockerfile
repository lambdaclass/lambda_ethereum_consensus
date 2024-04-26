# libp2p port
FROM golang:1.21.3 AS libp2p_builder
LABEL stage=builder

# Install dependencies
RUN apt-get update && apt-get install -y protobuf-compiler
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest

RUN mkdir /libp2p_port
WORKDIR /libp2p_port

COPY native/libp2p_port /libp2p_port
COPY proto/libp2p.proto /libp2p_port/proto/libp2p.proto

RUN protoc --go_out=./ proto/libp2p.proto

RUN go mod download
RUN go build -o libp2p_port

# Main image
FROM elixir:1.16.2-otp-26

RUN mkdir /consensus
WORKDIR /consensus

ENV MIX_ENV=prod

RUN mix local.hex --force

# Install dependencies
RUN apt-get update && apt-get install -y cmake protobuf-compiler

# Install rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="${PATH}:/root/.cargo/bin"

COPY . .
COPY --from=libp2p_builder /libp2p_port/libp2p_port /consensus/priv/native/libp2p_port


RUN mix escript.install --force hex protobuf
RUN mix deps.get

RUN protoc --elixir_out=./lib proto/libp2p.proto

RUN make download-beacon-node-oapi

RUN mix compile

ENTRYPOINT [ "iex", "-S", "mix", "run", "--"]
