// NOTE: the package **must** be named main
package main

/*
#include "utils.h"
*/
import "C"

import (
	"runtime/cgo"
	"unsafe"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/protocol"
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

//export SetStreamHandler
func (h C.uintptr_t) SetStreamHandler(proto_id *C.char, proc_id unsafe.Pointer) {
	handle := cgo.Handle(h)
	host := handle.Value().(host.Host)
	handler := func(stream network.Stream) {
		C.send_message(proc_id, C.uintptr_t(cgo.NewHandle(stream)))
	}
	host.SetStreamHandler(protocol.ID(C.GoString(proto_id)), handler)
}

// NOTE: this is needed to build it as an archive (.a)
func main() {}
