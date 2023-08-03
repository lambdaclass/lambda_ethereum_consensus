.PHONY: iex deps test clean compile-native

ERLANG_DIR := $(shell asdf where erlang)
ERLANG_INCLUDES = $(ERLANG_DIR)/usr/include/

LIBP2P_DIR = native/libp2p_nif
OUTPUT_DIR = priv/native

GO_SOURCES = $(LIBP2P_DIR)/main.go
GO_ARCHIVES := $(patsubst %.go,%.a,$(GO_SOURCES))
GO_HEADERS := $(patsubst %.go,%.h,$(GO_SOURCES))


$(LIBP2P_DIR)/%.a $(LIBP2P_DIR)/%.h: $(LIBP2P_DIR)/%.go
	cd $(LIBP2P_DIR); go build -buildmode=c-archive $*.go

$(OUTPUT_DIR)/libp2p_nif.so: $(GO_ARCHIVES) $(GO_HEADERS) $(LIBP2P_DIR)/libp2p.c $(LIBP2P_DIR)/utils.c
	gcc -Wall -Werror -dynamiclib -undefined dynamic_lookup -I $(ERLANG_INCLUDES) -o $(OUTPUT_DIR)/libp2p_nif.so \
		$(LIBP2P_DIR)/libp2p.c $(LIBP2P_DIR)/utils.c $(GO_ARCHIVES)

clean:
	-rm $(GO_ARCHIVES) $(GO_HEADERS) $(OUTPUT_DIR)/*

# Compile C and Go artifacts.
compile-native: $(OUTPUT_DIR)/libp2p_nif.so

# Run an interactive terminal with the main supervisor setup.
iex:
	iex -S mix

# Install mix dependencies.
deps:
	mix deps.get

# Run tests
test: compile-native
	mix test
