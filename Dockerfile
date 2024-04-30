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

# Install protobuf for elixir
RUN mix escript.install --force hex protobuf

# Download openapi spec
COPY Makefile .oapi_version /consensus/
RUN make download-beacon-node-oapi

# Install rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="${PATH}:/root/.cargo/bin:/root/.mix/escripts"

# Precompile rust crates. Rustler stores targets under _build
COPY ./native /consensus/native
RUN cd /consensus/native/bls_nif && cargo build --release \
    --target-dir="/consensus/_build/prod/lib/lambda_ethereum_consensus/native/bls_nif"
RUN cd /consensus/native/kzg_nif && cargo build --release \
    --target-dir="/consensus/_build/prod/lib/lambda_ethereum_consensus/native/kzg_nif"
RUN cd /consensus/native/snappy_nif && cargo build --release \
    --target-dir="/consensus/_build/prod/lib/lambda_ethereum_consensus/native/snappy_nif"
RUN cd /consensus/native/ssz_nif && cargo build --release \
    --target-dir="/consensus/_build/prod/lib/lambda_ethereum_consensus/native/ssz_nif"

# Precompile elixir dependencies
COPY mix.exs mix.lock .fork_version ./
COPY ./config/config.exs /consensus/config/config.exs
RUN mix deps.get
RUN mix deps.compile

COPY . .
COPY --from=libp2p_builder /libp2p_port/libp2p_port /consensus/priv/native/libp2p_port

RUN protoc --elixir_out=./lib proto/libp2p.proto

RUN mix compile

ENTRYPOINT [ "iex", "-S", "mix", "run", "--"]
