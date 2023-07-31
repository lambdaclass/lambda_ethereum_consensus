// NOTE: the package **must** be named main
package main

/*
#include "utils.h"
*/
import "C"

import (
	"runtime/cgo"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	"github.com/libp2p/go-libp2p/core/protocol"
	"github.com/multiformats/go-multiaddr"
)

//export PermanentAddrTTL
const PermanentAddrTTL = peerstore.PermanentAddrTTL

/*********/
/* Tests */
/*********/

//export MyFunction
func MyFunction(a, b int) int {
	return a + 2*b
}

//export TestSendMessage
func TestSendMessage(procId C.erl_pid_t) {
	go func() {
		// wait for 500 ms
		time.Sleep(500 * time.Millisecond)
		C.go_test_send_message(procId)
	}()
}

/*********/
/* Utils */
/*********/

//export ListenAddrStrings
func ListenAddrStrings(listenAddr *C.char) C.uintptr_t {
	addr := libp2p.ListenAddrStrings(C.GoString(listenAddr))
	return C.uintptr_t(cgo.NewHandle(addr))
}

/****************/
/* Host methods */
/****************/

//export New
func New(len uint, options *C.uintptr_t) C.uintptr_t {
	// TODO: pass options
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
func (h C.uintptr_t) SetStreamHandler(protoId *C.char, procId C.erl_pid_t) {
	handle := cgo.Handle(h)
	host := handle.Value().(host.Host)
	handler := func(stream network.Stream) {
		// NOTE: the stream handle should be deleted when calling Stream.Close()
		C.send_message(procId, C.uintptr_t(cgo.NewHandle(stream)))
	}
	host.SetStreamHandler(protocol.ID(C.GoString(protoId)), handler)
}

//export Peerstore
func (h C.uintptr_t) Peerstore() C.uintptr_t {
	host := cgo.Handle(h).Value().(host.Host)
	return C.uintptr_t(cgo.NewHandle(host.Peerstore()))
}

/*********************/
/* Peerstore methods */
/*********************/

//export AddAddrs
func (ps C.uintptr_t) AddAddrs(id, addrs C.uintptr_t, ttl uint64) {
	psv := cgo.Handle(ps).Value().(peerstore.Peerstore)
	idv := cgo.Handle(id).Value().(peer.ID)
	addrsv := cgo.Handle(addrs).Value().([]multiaddr.Multiaddr)
	psv.AddAddrs(idv, addrsv, time.Duration(ttl))
}

// NOTE: this is needed to build it as an archive (.a)
func main() {}
