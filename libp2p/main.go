// NOTE: the package **must** be named main
package main

/*
#include <stdint.h> // for uintptr_t
*/
import "C"
import (
	"runtime/cgo"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
)

//export MyFunction
func MyFunction(a, b int) int {
	return a + 2*b
}

//export New
func New() C.uintptr_t {
	h, err := libp2p.New()
	if err != nil {
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(h))
}

//export Close
func (h C.uintptr_t) Close() {
	handle := cgo.Handle(h)
	defer handle.Delete()
	handle.Value().(host.Host).Close()
}

// NOTE: this is needed to build it as an archive (.a)
func main() {}
