.PHONY: iex deps test clean compile-native fmt \
		clean-vectors download-vectors uncompress-vectors

# Delete current file when command fails
.DELETE_ON_ERROR:

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


##### SPEC TEST VECTORS #####

SPECTEST_VERSION = $(shell cat .spectest_version)
SPECTEST_CONFIGS = general minimal mainnet

SPECTEST_DIRS = $(patsubst %,tests/%,$(SPECTEST_CONFIGS))
SPECTEST_TARS = $(patsubst %,%_${SPECTEST_VERSION}.tar.gz,$(SPECTEST_CONFIGS))

%_${SPECTEST_VERSION}.tar.gz:
	curl -L -o "$@" \
		"https://github.com/ethereum/consensus-spec-tests/releases/download/${SPECTEST_VERSION}/$*.tar.gz"

tests/%: %_${SPECTEST_VERSION}.tar.gz
	-rm -rf $@
	tar -xzmf  "$<"

download-vectors: $(SPECTEST_TARS)

clean-vectors:
	-rm -rf tests
	-rm *.tar.gz


##### TARGETS #####

clean:
	-rm $(GO_ARCHIVES) $(GO_HEADERS) $(OUTPUT_DIR)/*

# Compile C and Go artifacts.
compile-native: $(OUTPUT_DIR)/libp2p_nif.so

# Run an interactive terminal with the main supervisor setup.
iex: compile-native
	iex -S mix

# Install mix dependencies.
deps:
	mix deps.get

# Run tests
test: compile-native
	mix test --exclude spectest

spec-test: compile-native tests/minimal #$(SPECTEST_DIRS)
	mix test --only implemented_spectest

lint:
	mix format --check-formatted
	mix credo --strict

fmt:
	mix format
	cd native/libp2p_nif; go fmt
	cd native/snappy_nif; cargo fmt
	cd native/ssz_nif; cargo fmt
