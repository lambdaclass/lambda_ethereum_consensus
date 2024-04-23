FROM golang:1.21.3 AS go_builder

RUN mkdir /libp2p_port
WORKDIR /libp2p_port

COPY native/libp2p_port /libp2p_port/

FROM elixir:1.16.2-otp-26

RUN mkdir /app
WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force

# copy release to app container
COPY . .
COPY --from=go_builder /libp2p_port /app/priv/native/libp2p_port

RUN apt update && apt install -y cmake

RUN mix deps.get

# TODO: the leveldb build script from eleveldb doesn't work
RUN mix compile

# CMD ["sh"]
CMD ["iex", "-S", "mix", "run", "--", "--checkpoint-sync-url", "https://sepolia.checkpoint-sync.ethpandaops.io/", "--network", "sepolia", "--metrics", "--validator-file", "validator_sepolia.txt"]
