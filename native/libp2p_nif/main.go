// NOTE: the package **must** be named main
package main

/*
#include <string.h>
#include "utils.h"
*/
import "C"

import (
	"context"
	"fmt"
	"os"
	"runtime/cgo"
	"strings"
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

/***********/
/* Helpers */
/***********/

func callGetter[T any, R any](h C.uintptr_t, g func(T) R) C.uintptr_t {
	recver := cgo.Handle(h).Value().(T)
	prop := g(recver)
	return C.uintptr_t(cgo.NewHandle(prop))
}

/*********/
/* Utils */
/*********/

//export DeleteHandle
func DeleteHandle(h C.uintptr_t) {
	cgo.Handle(h).Delete()
}

//export ListenAddrStrings
func ListenAddrStrings(listenAddr string) C.uintptr_t {
	// TODO: this function is variadic
	// WARN: we clone the string because the underlying buffer is owned by Elixir
	goListenAddr := strings.Clone(listenAddr)
	addr := libp2p.ListenAddrStrings(goListenAddr)
	return C.uintptr_t(cgo.NewHandle(addr))
}

/****************/
/* Host methods */
/****************/

//export HostNew
func HostNew(options []C.uintptr_t) C.uintptr_t {
	optionsSlice := make([]libp2p.Option, len(options))
	for i := 0; i < len(options); i++ {
		optionsSlice[i] = cgo.Handle(options[i]).Value().(libp2p.Option)
	}
	h, err := libp2p.New(optionsSlice...)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(h))
}

//export HostClose
func (h C.uintptr_t) HostClose() {
	handle := cgo.Handle(h)
	handle.Value().(host.Host).Close()
}

//export HostSetStreamHandler
func (h C.uintptr_t) HostSetStreamHandler(protoId string, procId C.erl_pid_t, callback C.send_message_t) {
	handle := cgo.Handle(h)
	host := handle.Value().(host.Host)
	// WARN: we clone the string because the underlying buffer is owned by Elixir
	goProtoId := protocol.ID(strings.Clone(protoId))
	handler := func(stream network.Stream) {
		C.run_callback(callback, procId, C.uintptr_t(cgo.NewHandle(stream)))
	}
	host.SetStreamHandler(protocol.ID(goProtoId), handler)
}

//export HostNewStream
func (h C.uintptr_t) HostNewStream(pid C.uintptr_t, protoId string) C.uintptr_t {
	host := cgo.Handle(h).Value().(host.Host)
	peerId := cgo.Handle(pid).Value().(peer.ID)
	// WARN: we clone the string because the underlying buffer is owned by Elixir
	goProtoId := protocol.ID(strings.Clone(protoId))
	// TODO: revisit context.TODO() and add multi-protocol support
	stream, err := host.NewStream(context.TODO(), peerId, goProtoId)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(stream))
}

//export HostPeerstore
func (h C.uintptr_t) HostPeerstore() C.uintptr_t {
	return callGetter(h, host.Host.Peerstore)
}

//export HostID
func (h C.uintptr_t) HostID() C.uintptr_t {
	return callGetter(h, host.Host.ID)
}

//export HostAddrs
func (h C.uintptr_t) HostAddrs() C.uintptr_t {
	return callGetter(h, host.Host.Addrs)
}

/*********************/
/* Peerstore methods */
/*********************/

//export PeerstoreAddAddrs
func (ps C.uintptr_t) PeerstoreAddAddrs(id, addrs C.uintptr_t, ttl uint64) {
	psv := cgo.Handle(ps).Value().(peerstore.Peerstore)
	idv := cgo.Handle(id).Value().(peer.ID)
	addrsv := cgo.Handle(addrs).Value().([]multiaddr.Multiaddr)
	psv.AddAddrs(idv, addrsv, time.Duration(ttl))
}

/******************/
/* Stream methods */
/******************/

//export StreamRead
func (s C.uintptr_t) StreamRead(buffer []byte) int {
	stream := cgo.Handle(s).Value().(network.Stream)
	n, err := stream.Read(buffer)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return -1
	}
	return n
}

//export StreamWrite
func (s C.uintptr_t) StreamWrite(data []byte) int {
	stream := cgo.Handle(s).Value().(network.Stream)
	n, err := stream.Write(data)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return -1
	}
	return n
}

//export StreamClose
func (s C.uintptr_t) StreamClose() {
	handle := cgo.Handle(s)
	handle.Value().(network.Stream).Close()
}

// NOTE: this is needed to build it as an archive (.a)
func main() {}
