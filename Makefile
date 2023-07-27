.PHONY: iex deps test clean compile

BREW_PREFIX := $(shell brew --prefix)
ERLANG_INCLUDES = $(BREW_PREFIX)/Cellar/erlang/26.0.2/lib/erlang/usr/include/

GO_SOURCES = libp2p/main.go
GO_ARCHIVES := $(patsubst %.go,%.a,$(GO_SOURCES))
GO_HEADERS := $(patsubst %.go,%.h,$(GO_SOURCES))


%.a: %.go
	go build -buildmode=c-archive -o $@ $<

libp2p.so: libp2p/libp2p.c $(GO_ARCHIVES)
	gcc -Wall -Werror -dynamiclib -undefined dynamic_lookup -I $(ERLANG_INCLUDES) -o libp2p.so \
		libp2p/libp2p.c $(GO_ARCHIVES)

clean:
	-rm $(GO_ARCHIVES) $(GO_HEADERS) libp2p.so

# Compile C and Go artifacts.
compile: libp2p.so

# Run an interactive terminal with the main supervisor setup.
iex:
	iex -S mix

# Install mix dependencies.
deps:
	mix deps.get

# Run tests
test: compile
	mix test
