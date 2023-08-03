.PHONY: iex deps test

# Run an interactive terminal with the main supervisor setup.
iex:
	iex -S mix

# Install mix dependencies.
deps:
	mix deps.get

lint:
	mix credo --strict

# Run tests
test:
	mix test
