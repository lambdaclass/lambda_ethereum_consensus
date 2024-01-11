.PHONY: iex deps test spec-test lint clean compile-native compile-port fmt \
		clean-vectors download-vectors uncompress-vectors proto \
		spec-test-% spec-test spec-test-config-% spec-test-runner-% \
		spec-test-mainnet-% spec-test-minimal-% spec-test-general-% \
		clean-tests gen-spec compile-all

# Delete current file when command fails
.DELETE_ON_ERROR:

##### NATIVE COMPILATION #####

### NIF

default: help
#❓ help: @ Displays this message
help:
	@grep -E '[a-zA-Z\.\-\%]+:.*?@ .*$$' $(firstword $(MAKEFILE_LIST))| tr -d '#'  | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}'

# magic from sym_num https://elixirforum.com/t/where-is-erl-nif-h-header-file-required-for-nif/27142/5
ERLANG_INCLUDES := $(shell erl -eval 'io:format("~s", \
		[lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])] \
		)' -s init stop -noshell)

LIBP2P_DIR = native/libp2p_nif
OUTPUT_DIR = priv/native

# create directories if they don't exist
DIRS=$(OUTPUT_DIR)
$(info $(shell mkdir -p $(DIRS)))

GO_SOURCES := $(LIBP2P_DIR)/go_src/main.go
GO_ARCHIVES := $(patsubst %.go,%.a,$(GO_SOURCES))
GO_HEADERS := $(patsubst %.go,%.h,$(GO_SOURCES))

CFLAGS = -Wall -Werror
CFLAGS += -Wl,-undefined -Wl,dynamic_lookup -fPIC -shared
CFLAGS += -I$(ERLANG_INCLUDES)

$(LIBP2P_DIR)/go_src/%.a $(LIBP2P_DIR)/go_src/%.h: $(LIBP2P_DIR)/go_src/%.go
	cd $(LIBP2P_DIR)/go_src; \
	go build -buildmode=c-archive $*.go

$(OUTPUT_DIR)/libp2p_nif.so: $(GO_ARCHIVES) $(GO_HEADERS) $(LIBP2P_DIR)/libp2p.c $(LIBP2P_DIR)/go_src/utils.c
	gcc $(CFLAGS) -I $(LIBP2P_DIR)/go_src -o $@ \
		$(LIBP2P_DIR)/libp2p.c $(LIBP2P_DIR)/go_src/utils.c $(GO_ARCHIVES)

### PORT

PROTOBUF_EX_FILES := proto/libp2p.pb.ex
PROTOBUF_GO_FILES := native/libp2p_port/internal/proto/libp2p.pb.go

$(PROTOBUF_GO_FILES): proto/libp2p.proto
	protoc --go_out=./native/libp2p_port $<

$(PROTOBUF_EX_FILES): proto/libp2p.proto
	protoc --elixir_out=. $<

PORT_SOURCES := $(shell find native/libp2p_port -type f)

$(OUTPUT_DIR)/libp2p_port: $(PORT_SOURCES) $(PROTOBUF_GO_FILES)
	cd native/libp2p_port; go build -o ../../$@

##### TARGETS #####

#💻 nix: @ Start a nix environment.
nix:
	nix develop

#💻 nix-zsh: @ Start a nix environment using zsh as a console.
nix-zsh:
	nix develop -c zsh

#🔄 deps: @ Install mix dependencies.
deps:
	sh scripts/install_protos.sh
	$(MAKE) proto

	cd native/libp2p_port; \
	go get && go install
	mix deps.get

#📝 proto: @ Generate protobuf code
proto: $(PROTOBUF_EX_FILES) $(PROTOBUF_GO_FILES)

#🔨 compile-native: @ Compile C and Go artifacts.
compile-native: proto $(OUTPUT_DIR)/libp2p_nif.so $(OUTPUT_DIR)/libp2p_port

#🔨 compile-all: @ Compile the elixir project and its dependencies.
compile-all: compile-native
	mix compile

#🗑️ clean: @ Remove the build files.
clean:
	-mix clean
	-rm $(GO_ARCHIVES) $(GO_HEADERS) $(OUTPUT_DIR)/*

#📊 grafana-up: @ Start grafana server.
grafana-up:
	cd metrics/ && docker compose up -d

#📊 grafana-down: @ Stop grafana server.
grafana-down:
	cd metrics/ && docker compose down

#🗑️ grafana-clean: @ Remove the grafana data.
grafana-clean:
	cd metrics/ && docker compose down -v

#▶️ start: @ Start application with Beacon API.
start: compile-all
	iex -S mix phx.server

#▶️ iex: @ Runs an interactive terminal with the main supervisor setup.
iex: compile-all
	iex -S mix

#▶️ checkpoint-sync: @ Run an interactive terminal using checkpoint sync.
checkpoint-sync: compile-all
	iex -S mix run -- --checkpoint-sync https://sync-mainnet.beaconcha.in/

#🔴 test: @ Run tests
test: compile-all
	mix test --no-start --exclude spectest

##### SPEC TEST VECTORS #####

SPECTEST_VERSION := $(shell cat .spectest_version)
SPECTEST_CONFIGS = general minimal mainnet

SPECTEST_ROOTDIR = test/spec/vectors
SPECTEST_GENERATED_ROOTDIR = test/generated
VECTORS_DIR = $(SPECTEST_ROOTDIR)/tests
# create directory if it doesn't exist
$(info $(shell mkdir -p $(SPECTEST_ROOTDIR)))

SPECTEST_DIRS := $(patsubst %,$(SPECTEST_ROOTDIR)/tests/%,$(SPECTEST_CONFIGS))
SPECTEST_GENERATED := $(patsubst %,$(SPECTEST_GENERATED_ROOTDIR)/%,$(SPECTEST_CONFIGS))
SPECTEST_TARS := $(patsubst %,$(SPECTEST_ROOTDIR)/%_${SPECTEST_VERSION}.tar.gz,$(SPECTEST_CONFIGS))

$(SPECTEST_ROOTDIR)/%_${SPECTEST_VERSION}.tar.gz:
	curl -L -o "$@" \
		"https://github.com/ethereum/consensus-spec-tests/releases/download/${SPECTEST_VERSION}/$*.tar.gz"

$(VECTORS_DIR)/%: $(SPECTEST_ROOTDIR)/%_${SPECTEST_VERSION}.tar.gz
	-rm -rf $@
	tar -xzmf "$<" -C $(SPECTEST_ROOTDIR)

$(SPECTEST_GENERATED_ROOTDIR): $(VECTORS_DIR)/mainnet $(VECTORS_DIR)/minimal $(VECTORS_DIR)/general lib/spec/runners/*.ex lib/mix/tasks/generate_spec_tests.ex
	mix generate_spec_tests

#⬇️ download-vectors: @ Download the spec test vectors files.
download-vectors: $(SPECTEST_TARS)

#🗑️ clean-vectors: @ Remove the downloaded spec test vectors.
clean-vectors:
	-rm -rf $(SPECTEST_ROOTDIR)/tests
	-rm $(SPECTEST_ROOTDIR)/*.tar.gz

#📝 gen-spec: @ Generate the spec tests.
gen-spec: $(SPECTEST_GENERATED_ROOTDIR)


#🗑️ clean-tests: @ Remove the generated spec tests.
clean-tests:
	-rm -r test/generated


#🔴 spec-test: @ Run all spec tests
spec-test: compile-all $(PROTOBUF_EX_FILES) $(SPECTEST_GENERATED_ROOTDIR)
	mix test --no-start test/generated/*/*/*

#🔴 spec-test-config-%: @ Run all spec tests for a specific config (e.g. mainnet)
spec-test-config-%: compile-all $(PROTOBUF_EX_FILES) $(SPECTEST_GENERATED_ROOTDIR)
	mix test --no-start test/generated/$*/*/*

#🔴 spec-test-runner-%: @ Run all spec tests for a specific runner (e.g. epoch_processing)
spec-test-runner-%: compile-all $(PROTOBUF_EX_FILES) $(SPECTEST_GENERATED_ROOTDIR)
	mix test --no-start test/generated/*/*/$*.exs

#🔴 spec-test-mainnet-%: @ Run spec tests for mainnet config, for the specified runner.
spec-test-mainnet-%: compile-all $(PROTOBUF_EX_FILES) $(SPECTEST_GENERATED_ROOTDIR)
	mix test --no-start test/generated/mainnet/*/$*.exs

#🔴 spec-test-minimal-%: @ Run spec tests for minimal config, for the specified runner.
spec-test-minimal-%: compile-all $(PROTOBUF_EX_FILES) $(SPECTEST_GENERATED_ROOTDIR)
	mix test --no-start test/generated/minimal/*/$*.exs

#🔴 spec-test-general-%: @ Run spec tests for general config, for the specified runner.
spec-test-general-%: compile-all $(PROTOBUF_EX_FILES) $(SPECTEST_GENERATED_ROOTDIR)
	mix test --no-start test/generated/general/*/$*.exs

#✅ lint: @ Check formatting and linting.
lint:
	mix format --check-formatted
	mix credo --strict

#✅ fmt: @ Format all code (Go, rust and elixir).
fmt:
	mix format
	gofmt -l -w native/libp2p_nif/go_src
	gofmt -l -w native/libp2p_port
	cd native/snappy_nif; cargo fmt
	cd native/ssz_nif; cargo fmt
	cd native/bls_nif; cargo fmt
