.PHONY: iex deps test spec-test lint clean compile-native compile-port fmt \
		clean-vectors download-vectors uncompress-vectors proto \
		spec-test-% spec-test spec-test-config-% spec-test-runner-% \
		spec-test-mainnet-% spec-test-minimal-% spec-test-general-% \
		clean-tests gen-spec compile-all download-beacon-node-oapi test-iex \
		sepolia holesky gnosis

# Delete current file when command fails
.DELETE_ON_ERROR:

FORK_VERSION_FILE = .fork_version
CONFIG_FILE = config/config.exs

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
compile-native: $(OUTPUT_DIR)/libp2p_nif.so $(OUTPUT_DIR)/libp2p_port

#🔨 compile-all: @ Compile the elixir project and its dependencies.
compile-all: $(CONFIG_FILE) compile-native $(PROTOBUF_EX_FILES) download-beacon-node-oapi
	mix compile

#🗑️ clean: @ Remove the build files.
clean:
	-mix clean
	-rm -rf test/generated
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
	iex -S mix run -- --beacon-api

#▶️ iex: @ Runs an interactive terminal with the main supervisor setup.
iex: compile-all
	iex -S mix

#▶️ test-iex: @ Runs an interactive terminal in the test environment. Useful to debug tests and tasks
test-iex:
	MIX_ENV=test iex -S mix run -- --mode db

#▶️ checkpoint-sync: @ Run an interactive terminal using checkpoint sync.
checkpoint-sync: compile-all
	iex -S mix run -- --checkpoint-sync-url https://mainnet-checkpoint-sync.stakely.io/

#▶️ sepolia: @ Run an interactive terminal using sepolia network
sepolia: compile-all
	iex -S mix run -- --checkpoint-sync-url https://sepolia.beaconstate.info --network sepolia

#▶️ holesky: @ Run an interactive terminal using holesky network
holesky: compile-all
	iex -S mix run -- --checkpoint-sync-url https://checkpoint-sync.holesky.ethpandaops.io --network holesky

#▶️ gnosis: @ Run an interactive terminal using gnosis network
gnosis: compile-all
	iex -S mix run -- --checkpoint-sync-url https://checkpoint.gnosischain.com --network gnosis

#🔴 test: @ Run tests
test: compile-all
	mix test --no-start --exclude spectest

#### BEACON NODE OAPI ####
OAPI_NAME = beacon-node-oapi
OAPI_VERSION := $(shell cat .oapi_version)
$(OAPI_NAME).json: .oapi_version
	curl -L -o "$@" \
		"https://ethereum.github.io/beacon-APIs/releases/${OAPI_VERSION}/beacon-node-oapi.json"

OPENAPI_JSON := $(OAPI_NAME).json 

download-beacon-node-oapi: ${OPENAPI_JSON}

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

# update config file to force re-compilation when fork changes
$(CONFIG_FILE): $(FORK_VERSION_FILE)
	touch $@

$(SPECTEST_ROOTDIR)/%_${SPECTEST_VERSION}.tar.gz:
	curl -L -o "$@" \
		"https://github.com/ethereum/consensus-spec-tests/releases/download/${SPECTEST_VERSION}/$*.tar.gz"

$(VECTORS_DIR)/%: $(SPECTEST_ROOTDIR)/%_${SPECTEST_VERSION}.tar.gz .spectest_version
	-rm -rf $@
	tar -xzmf "$<" -C $(SPECTEST_ROOTDIR)

$(SPECTEST_GENERATED_ROOTDIR): $(CONFIG_FILE) $(VECTORS_DIR)/mainnet $(VECTORS_DIR)/minimal $(VECTORS_DIR)/general test/spec/runners/*.ex test/spec/tasks/*.ex
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
spec-test: compile-all $(SPECTEST_GENERATED_ROOTDIR)
	mix test --no-start test/generated/*/*/*

#🔴 spec-test-config-%: @ Run all spec tests for a specific config (e.g. mainnet)
spec-test-config-%: compile-all $(SPECTEST_GENERATED_ROOTDIR)
	mix test --no-start test/generated/$*/*/*

#🔴 spec-test-runner-%: @ Run all spec tests for a specific runner (e.g. epoch_processing)
spec-test-runner-%: compile-all $(SPECTEST_GENERATED_ROOTDIR)
	mix test --no-start test/generated/*/*/$*.exs

#🔴 spec-test-mainnet-%: @ Run spec tests for mainnet config, for the specified runner.
spec-test-mainnet-%: compile-all $(SPECTEST_GENERATED_ROOTDIR)
	mix test --no-start test/generated/mainnet/*/$*.exs

#🔴 spec-test-minimal-%: @ Run spec tests for minimal config, for the specified runner.
spec-test-minimal-%:  compile-all $(SPECTEST_GENERATED_ROOTDIR)
	mix test --no-start test/generated/minimal/*/$*.exs

#🔴 spec-test-general-%: @ Run spec tests for general config, for the specified runner.
spec-test-general-%: compile-all $(SPECTEST_GENERATED_ROOTDIR)
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

#✅ dialyzer: @ Run dialyzer (static analysis tool).
dialyzer: compile-all
	mix dialyzer
