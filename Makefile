.PHONY: iex deps test clean compile-native


##### NATIVE COMPILATION #####

# magic from sym_num https://elixirforum.com/t/where-is-erl-nif-h-header-file-required-for-nif/27142/5
ERLANG_INCLUDES := $(shell erl -eval 'io:format("~s", \
		[lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])] \
		)' -s init stop -noshell)

LIBP2P_DIR = native/libp2p_nif
OUTPUT_DIR = priv/native

# create directories if they don't exist
DIRS=$(OUTPUT_DIR)
$(info $(shell mkdir -p $(DIRS)))

GO_SOURCES = $(LIBP2P_DIR)/main.go
GO_ARCHIVES := $(patsubst %.go,%.a,$(GO_SOURCES))
GO_HEADERS := $(patsubst %.go,%.h,$(GO_SOURCES))

CFLAGS = -Wall -Werror
CFLAGS += -Wl,-undefined -Wl,dynamic_lookup -fPIC -shared
CFLAGS += -I$(ERLANG_INCLUDES)

$(LIBP2P_DIR)/%.a $(LIBP2P_DIR)/%.h: $(LIBP2P_DIR)/%.go
	cd $(LIBP2P_DIR); \
	go get; \
	go install; \
	go build -buildmode=c-archive $*.go

$(OUTPUT_DIR)/libp2p_nif.so: $(GO_ARCHIVES) $(GO_HEADERS) $(LIBP2P_DIR)/libp2p.c $(LIBP2P_DIR)/utils.c
	gcc $(CFLAGS) -o $@ \
		$(LIBP2P_DIR)/libp2p.c $(LIBP2P_DIR)/utils.c $(GO_ARCHIVES)


##### TARGETS #####

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
	mix test --trace
