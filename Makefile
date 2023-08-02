.PHONY: iex deps test clean compile-native

BREW_PREFIX := $(shell brew --prefix)
ERLANG_INCLUDES = $(BREW_PREFIX)/Cellar/erlang/26.0.2/lib/erlang/usr/include/

GO_SOURCES = libp2p/main.go
GO_ARCHIVES := $(patsubst %.go,%.a,$(GO_SOURCES))
GO_HEADERS := $(patsubst %.go,%.h,$(GO_SOURCES))


libp2p/%.a libp2p/%.h: libp2p/%.go
	cd libp2p; go build -buildmode=c-archive $*.go

libp2p.so: $(GO_ARCHIVES) $(GO_HEADERS) libp2p/libp2p.c libp2p/utils.c
	gcc -Wall -Werror -dynamiclib -undefined dynamic_lookup -I $(ERLANG_INCLUDES) -o libp2p.so \
		libp2p/libp2p.c libp2p/utils.c $(GO_ARCHIVES)

clean:
	-rm $(GO_ARCHIVES) $(GO_HEADERS) libp2p.so

# Compile C and Go artifacts.
compile-native: libp2p.so

# Run an interactive terminal with the main supervisor setup.
iex:
	iex -S mix

# Install mix dependencies.
deps:
	mix deps.get

# Run tests
test: compile-native
	mix test
