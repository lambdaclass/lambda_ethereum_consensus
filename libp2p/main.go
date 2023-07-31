// NOTE: the package **must** be named main
package main

/*
#include <string.h>
#include "utils.h"
*/
import "C"

import (
	"context"
	"runtime/cgo"
	"time"
	"unsafe"

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

/***********/
/* Helpers */
/***********/

func callGetter[T any, R any](h C.uintptr_t, g func(T) R) C.uintptr_t {
	recver := cgo.Handle(h).Value().(T)
	prop := g(recver)
	return C.uintptr_t(cgo.NewHandle(prop))
}

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
func ListenAddrStrings(listenAddr string) C.uintptr_t {
	// TODO: this function is variadic
	addr := libp2p.ListenAddrStrings(listenAddr)
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

//export HostClose
func (h C.uintptr_t) HostClose() {
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
	return callGetter(h, host.Host.Peerstore)
}

//export ID
func (h C.uintptr_t) ID() C.uintptr_t {
	return callGetter(h, host.Host.ID)
}

//export Addrs
func (h C.uintptr_t) Addrs() C.uintptr_t {
	return callGetter(h, host.Host.Addrs)
}

//export NewStream
func (h C.uintptr_t) NewStream(pid C.uintptr_t, protoId *C.char) C.uintptr_t {
	host := cgo.Handle(h).Value().(host.Host)
	peerId := cgo.Handle(pid).Value().(peer.ID)
	stream, err := host.NewStream(context.TODO(), peerId, protocol.ID(C.GoString(protoId)))
	if err != nil {
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(stream))
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

/******************/
/* Stream methods */
/******************/

//export StreamRead
func (s C.uintptr_t) StreamRead(len uint, buffer *C.char) int {
	stream := cgo.Handle(s).Value().(network.Stream)
	goBuffer := make([]byte, len)
	n, err := stream.Read(goBuffer)
	C.memcpy(unsafe.Pointer(buffer), unsafe.Pointer(&goBuffer[0]), C.size_t(n))
	if err != nil {
		return -1
	}
	return n
}

//export StreamWrite
func (s C.uintptr_t) StreamWrite(len uint, buffer *C.char) int {
	stream := cgo.Handle(s).Value().(network.Stream)
	goBuffer := C.GoBytes(unsafe.Pointer(buffer), C.int(len))
	n, err := stream.Write(goBuffer)
	if err != nil {
		return -1
	}
	return n
}

//export StreamClose
func (s C.uintptr_t) StreamClose() {
	handle := cgo.Handle(s)
	defer handle.Delete()
	stream := handle.Value().(network.Stream)
	stream.Close()
}

// NOTE: this is needed to build it as an archive (.a)
func main() {}
