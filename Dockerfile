# libp2p port
FROM golang:1.21.3 AS libp2p_builder
LABEL stage=builder

RUN mkdir /libp2p_port
WORKDIR /libp2p_port

COPY native/libp2p_port /libp2p_port

RUN go build -o libp2p_port


# Main image
FROM elixir:1.16.2-otp-26

RUN mkdir /app
WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force

RUN apt update && apt install -y cmake

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="${PATH}:/root/.cargo/bin"

COPY . .
COPY --from=libp2p_builder /libp2p_port/libp2p_port /app/priv/native/libp2p_port

RUN mix deps.get

RUN mix compile

CMD ["sh"]
# CMD ["iex", "-S", "mix", "run", "--", "--checkpoint-sync-url", "https://sepolia.checkpoint-sync.ethpandaops.io/", "--network", "sepolia", "--metrics", "--validator-file", "validator_sepolia.txt"]
