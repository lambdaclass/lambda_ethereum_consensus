// NOTE: the package **must** be named main
package main

import "C"

import (
	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
)

var h host.Host

//export MyFunction
func MyFunction(a, b int) int {
	return a + 2*b
}

//export New
func New() int {
	var err error
	h, err = libp2p.New()
	if err != nil {
		return 1
	}
	return 0
}

// NOTE: this is needed to build it as an archive (.a)
func main() {}
