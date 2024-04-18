FROM elixir:1.16.2

RUN mkdir /app
WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force

# copy release to app container
COPY . .

RUN chown -R nobody: /app
USER nobody

RUN make deps

CMD ["iex", "-S", "mix", "run", "--", "--checkpoint-sync-url", "https://sepolia.checkpoint-sync.ethpandaops.io/", "--network", "sepolia", "--metrics", "--validator-file", "validator_sepolia.txt"]
