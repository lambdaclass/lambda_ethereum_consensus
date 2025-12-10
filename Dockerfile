# libp2p port
FROM golang:1.24 AS libp2p_builder
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

# Precompile rust crates
# bls nif
FROM rust:1.81.0 AS bls_nif_builder
LABEL stage=builder

RUN mkdir /bls_nif
WORKDIR /bls_nif

COPY ./native/bls_nif /bls_nif
RUN cargo build --release && \
    mv target/release/libbls_nif.so ./libbls_nif.so && \
    rm -rf target/

# snappy nif
FROM rust:1.81.0 AS snappy_nif_builder
LABEL stage=builder

RUN mkdir /snappy_nif
WORKDIR /snappy_nif

COPY ./native/snappy_nif /snappy_nif
RUN cargo build --release && \
    mv target/release/libsnappy_nif.so ./libsnappy_nif.so && \
    rm -rf target/

# ssz nif
FROM rust:1.81.0 AS ssz_nif_builder
LABEL stage=builder

RUN mkdir /ssz_nif
WORKDIR /ssz_nif

COPY ./native/ssz_nif /ssz_nif
RUN cargo build --release && \
    mv target/release/libssz_nif.so ./libssz_nif.so && \
    rm -rf target/

# Main image
FROM elixir:1.16.2-otp-26

RUN mkdir /consensus
WORKDIR /consensus

ENV MIX_ENV=prod
# To avoid recompiling rustler NIFs
ENV RUSTLER_SKIP_COMPILE=yes

# https://github.com/hexpm/hex/issues/1029#issuecomment-2124545292
RUN mix local.hex 2.0.6 --force

# Install dependencies
RUN apt-get update && apt-get install -y cmake protobuf-compiler

# Install protobuf for elixir
RUN mix escript.install --force hex protobuf

# Download openapi spec
COPY Makefile .oapi_version /consensus/
RUN make download-beacon-node-oapi

# Install rust
# NOTE: this is needed for some dependencies
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="${PATH}:/root/.cargo/bin:/root/.mix/escripts"

# Precompile elixir dependencies
COPY mix.exs mix.lock .fork_version ./
COPY ./config/config.exs /consensus/config/config.exs
RUN mix deps.get
RUN mix deps.compile

COPY . .
COPY --from=libp2p_builder /libp2p_port/libp2p_port /consensus/priv/native/libp2p_port
# TODO: only copy artifacts
# Copy precompiled rust crates. Rustler stores targets under _build
COPY --from=bls_nif_builder /bls_nif/libbls_nif.so /consensus/priv/native/libbls_nif.so
COPY --from=snappy_nif_builder /snappy_nif/libsnappy_nif.so /consensus/priv/native/libsnappy_nif.so
COPY --from=ssz_nif_builder /ssz_nif/libssz_nif.so /consensus/priv/native/libssz_nif.so

RUN protoc --elixir_out=. proto/libp2p.proto

RUN mix compile

ARG IEX_ARGS=""
ENV IEX_ARGS_VALUE=${IEX_ARGS}

# TODO: This could be an issue regarding OS signals, we should use JSONArgs but shell form is the
# only way to pass args to ENTRYPOINT, specially important because of the cookie. Best
# solution would be to move to releases and avoid starting the node manually through iex.
ENTRYPOINT iex $IEX_ARGS_VALUE -S mix run -- $0 $@
