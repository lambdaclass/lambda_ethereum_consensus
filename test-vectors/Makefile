.PHONY: download clean

VERSION = v1.3.0

%_${VERSION}.tar.gz:
	curl -L -o "$@" \
		"https://github.com/ethereum/consensus-spec-tests/releases/download/${VERSION}/$*.tar.gz"

tests/%: %_${VERSION}.tar.gz
	tar -xzf "$<"

download: tests/minimal #tests/general tests/mainnet

clean:
	-rm -rf tests
	-rm -rf *.tar.gz
