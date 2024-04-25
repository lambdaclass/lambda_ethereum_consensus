# libp2p port
FROM golang:1.21.3 AS libp2p_builder
LABEL stage=builder

RUN mkdir /libp2p_port
WORKDIR /libp2p_port

COPY native/libp2p_port /libp2p_port

RUN go build -o libp2p_port


# Main image
FROM elixir:1.16.2-otp-26

RUN mkdir /consensus
WORKDIR /consensus

ENV MIX_ENV=prod

RUN mix local.hex --force

# Install dependencies
RUN apt-get update && apt-get install -y cmake

# Install rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="${PATH}:/root/.cargo/bin"

COPY . .
COPY --from=libp2p_builder /libp2p_port/libp2p_port /consensus/priv/native/libp2p_port

RUN mix deps.get
RUN mix compile

ENTRYPOINT [ "iex", "-S", "mix", "run", "--"]
