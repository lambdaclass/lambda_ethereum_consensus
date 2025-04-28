.PHONY: iex deps test spec-test lint clean compile-port fmt \
		clean-vectors download-vectors uncompress-vectors proto \
		spec-test-% spec-test spec-test-config-% spec-test-runner-% \
		spec-test-mainnet-% spec-test-minimal-% spec-test-general-% \
		clean-tests gen-spec compile-all download-beacon-node-oapi test-iex \
		sepolia holesky gnosis hoodi

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

OUTPUT_DIR = priv/native

# create directories if they don't exist
DIRS=$(OUTPUT_DIR)
$(info $(shell mkdir -p $(DIRS)))

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

GRAFANA_DASHBOARDS_DIR = ./metrics/grafana/provisioning/dashboards

# Root directory of ethereum-package
KURTOSIS_DIR ?= ./ethereum-package
# Grafana configuration directory for dashboards
KURTOSIS_GRAFANA_DASHBOARDS_DIR ?= $(KURTOSIS_DIR)/static_files/grafana-config/dashboards
# Secret cookie for the lambdaconsesus IEX node built for usage with kurtosis
KURTOSIS_COOKIE ?= secret
# Name of the kurtosis service pointing to the lambdaconsesus node
KURTOSIS_SERVICE ?= cl-3-lambda-geth
# Name of the enclave to be used with kurtosis
KURTOSIS_ENCLAVE ?= lambdanet

##### TARGETS #####

# 💻 kurtosis.setup: @ Setup the kurtosis environment
kurtosis.setup: kurtosis.setup.ethereum-package kurtosis.setup.grafana kurtosis.setup.lambdaconsensus

#💻 kurtosis.setup.ethereum-package: @ Downloads the lambda ethereum-package content
kurtosis.setup.ethereum-package:
	git submodule update --init --recursive

# 💻 kurtosis.setup.grafana: @ Copies the grafana dashboards to the ethereum-package folder under grafana-config
kurtosis.setup.grafana:
	[ -d  $(KURTOSIS_GRAFANA_DASHBOARDS_DIR)/lambdaconsensus ] && \
		rm $(KURTOSIS_GRAFANA_DASHBOARDS_DIR)/lambdaconsensus/* || \
		mkdir $(KURTOSIS_GRAFANA_DASHBOARDS_DIR)/lambdaconsensus
	cp -r $(GRAFANA_DASHBOARDS_DIR)/* $(KURTOSIS_GRAFANA_DASHBOARDS_DIR)/lambdaconsensus

#💻 kurtosis.setup.lambdaconsensus: @ Builds the node Docker for the kurtosis environment
kurtosis.setup.lambdaconsensus:
	docker build --build-arg IEX_ARGS="--sname lambdaconsensus --cookie $(KURTOSIS_COOKIE)" -t lambda_ethereum_consensus .

#💻 kurtosis.start: @ Starts the kurtosis environment
kurtosis.start:
	kurtosis run --enclave $(KURTOSIS_ENCLAVE) $(KURTOSIS_DIR) --args-file network_params.yaml

#💻 kurtosis.build-and-start: @ Builds the lambdaconsensus Docker image and starts the kurtosis environment.
kurtosis.clean-start: kurtosis.clean kurtosis.setup.lambdaconsensus kurtosis.start

#💻 kurtosis.stop: @ Stops the kurtosis environment
kurtosis.stop:
	kurtosis enclave stop $(KURTOSIS_ENCLAVE)

#💻 kurtosis.remove: @ Removes the kurtosis environment
kurtosis.remove:
	kurtosis enclave rm $(KURTOSIS_ENCLAVE)

#💻 kurtosis.clean: @ Clean the kurtosis environment
kurtosis.clean:
	kurtosis clean -a

#💻 kurtosis.purge: @ Purge the kurtosis environment
kurtosis.purge: kurtosis.stop kurtosis.remove kurtosis.clean

#💻 kurtosis.connect: @ Connects to the client running in kurtosis, KURTOSIS_SERVICE could be given
kurtosis.connect:
	kurtosis service shell $(KURTOSIS_ENCLAVE) $(KURTOSIS_SERVICE)

#💻 kurtosis.connect.iex: @ Connects to iex ONCE INSIDE THE KURTOSIS SERVICE
kurtosis.connect.iex:
	iex --sname client --remsh lambdaconsensus --cookie $(KURTOSIS_COOKIE)

#💻 kurtosis.assertoor: @ Execute the assertoor network params in .github
kurtosis.assertoor: kurtosis.clean kurtosis.setup.lambdaconsensus
	kurtosis run --enclave $(KURTOSIS_ENCLAVE) $(KURTOSIS_DIR) --args-file .github/config/assertoor/network-params.yml

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

#🔨 compile-port: @ Compile Go artifacts.
compile-port: $(OUTPUT_DIR)/libp2p_port

#🔨 compile-all: @ Compile the elixir project and its dependencies.
compile-all: $(CONFIG_FILE) compile-port $(PROTOBUF_EX_FILES) download-beacon-node-oapi
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

##################
# NODE RUNNERS
DISCOVERY_PORT ?= 9009
METRICS_PORT ?= 9568
MODE ?= full

#▶️ mainnet: @ Run an interactive terminal using checkpoint sync for mainnet.
mainnet: compile-all
	iex -S mix run -- --checkpoint-sync-url https://mainnet-checkpoint-sync.stakely.io/ --metrics --metrics-port $(METRICS_PORT) --discovery-port $(DISCOVERY_PORT) --mode $(MODE)

#▶️ mainnet.logfile: @ Run an interactive terminal using checkpoint sync for mainnet with a log file.
mainnet.logfile: compile-all
	iex -S mix run -- --checkpoint-sync-url https://mainnet-checkpoint-sync.stakely.io/ --metrics --metrics-port $(METRICS_PORT)  --log-file ./logs/mainnet.log --discovery-port $(DISCOVERY_PORT) --mode $(MODE)

#▶️ sepolia: @ Run an interactive terminal using sepolia network
sepolia: compile-all
	iex -S mix run -- --checkpoint-sync-url https://sepolia.beaconstate.info --network sepolia --metrics --metrics-port $(METRICS_PORT)  --discovery-port $(DISCOVERY_PORT) --mode $(MODE)

#▶️ sepolia.logfile: @ Run an interactive terminal using sepolia network with a log file
sepolia.logfile: compile-all
	iex -S mix run -- --checkpoint-sync-url https://sepolia.beaconstate.info --network sepolia --metrics --metrics-port $(METRICS_PORT)  --log-file ./logs/sepolia.log --discovery-port $(DISCOVERY_PORT) --mode $(MODE)

#▶️ holesky: @ Run an interactive terminal using holesky network
holesky: compile-all
	iex -S mix run -- --checkpoint-sync-url https://checkpoint-sync.holesky.ethpandaops.io --network holesky --metrics --metrics-port $(METRICS_PORT) --discovery-port $(DISCOVERY_PORT) --mode $(MODE)

#▶️ holesky.logfile: @ Run an interactive terminal using holesky network with a log file
holesky.logfile: compile-all
	iex -S mix run -- --checkpoint-sync-url https://checkpoint-sync.holesky.ethpandaops.io --network holesky --log-file ./logs/holesky.log --metrics --metrics-port $(METRICS_PORT) --discovery-port $(DISCOVERY_PORT) --mode $(MODE)

#▶️ gnosis: @ Run an interactive terminal using gnosis network
gnosis: compile-all
	iex -S mix run -- --checkpoint-sync-url https://checkpoint.gnosischain.com --network gnosis --metrics --metrics-port $(METRICS_PORT) --discovery-port $(DISCOVERY_PORT) --mode $(MODE)

#▶️ gnosis.logfile: @ Run an interactive terminal using gnosis network with a log file
gnosis.logfile: compile-all
	iex -S mix run -- --checkpoint-sync-url https://checkpoint.gnosischain.com --network gnosis --metrics --metrics-port $(METRICS_PORT) --log-file ./logs/gnosis.log --discovery-port $(DISCOVERY_PORT) --mode $(MODE)

#▶️ hoodi: @ Run an interactive terminal using hoodi network
hoodi: compile-all
	iex -S mix run -- --checkpoint-sync-url https://checkpoint-sync.hoodi.ethpandaops.io --network hoodi --metrics --metrics-port $(METRICS_PORT) --discovery-port $(DISCOVERY_PORT) --mode $(MODE)

#▶️ hoodi.logfile: @ Run an interactive terminal using hoodi network with a log file
hoodi.logfile: compile-all
	iex -S mix run -- --checkpoint-sync-url https://checkpoint-sync.hoodi.ethpandaops.io --network hoodi --metrics --metrics-port $(METRICS_PORT) --log-file ./logs/hoodi.log --discovery-port $(DISCOVERY_PORT) --mode $(MODE)

#▶️ checkpoint-sync: @ Run an interactive terminal using checkpoint sync for mainnet.
checkpoint-sync: mainnet

#🔴 test: @ Run tests
test: compile-all
	mix test --no-start --exclude spectest

#🔴 test.wip: @ Run tests with the wip tag
test.wip: compile-all
	mix test --no-start --only wip

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
	mix recode --no-autocorrect
	mix format --check-formatted
	mix credo --strict
	mix dialyzer --no-check

#✅ fmt: @ Format all code (Go, rust and elixir).
fmt:
	mix format
	gofmt -l -w native/libp2p_port
	cd native/snappy_nif; cargo fmt
	cd native/ssz_nif; cargo fmt
	cd native/bls_nif; cargo fmt

#✅ dialyzer: @ Run dialyzer (static analysis tool).
dialyzer: compile-all
	mix dialyzer
