// NOTE: the package **must** be named main
package main

/*
#include <string.h>
#include "utils.h"
*/
import "C"

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net"
	"os"
	"runtime/cgo"
	"strings"
	"time"
	"unsafe"

	"github.com/btcsuite/btcd/btcec/v2"
	gcrypto "github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/p2p/discover"
	"github.com/ethereum/go-ethereum/p2p/enode"
	"github.com/ethereum/go-ethereum/p2p/enr"
	"github.com/libp2p/go-libp2p"
	pubsub "github.com/libp2p/go-libp2p-pubsub"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	"github.com/libp2p/go-libp2p/core/protocol"
	"github.com/libp2p/go-libp2p/p2p/muxer/mplex"
	"github.com/multiformats/go-multiaddr"
)

// NOTE: this is needed to build it as an archive (.a)
func main() {}

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

// Taken from Prysm
func convertFromInterfacePrivKey(privkey crypto.PrivKey) (*ecdsa.PrivateKey, error) {
	secpKey, ok := privkey.(*crypto.Secp256k1PrivateKey)
	if !ok {
		return nil, errors.New("could not cast to Secp256k1PrivateKey")
	}
	rawKey, err := secpKey.Raw()
	if err != nil {
		return nil, err
	}
	privKey := new(ecdsa.PrivateKey)
	k := new(big.Int).SetBytes(rawKey)
	privKey.D = k
	privKey.Curve = gcrypto.S256() // Temporary hack, so libp2p Secp256k1 is recognized as geth Secp256k1 in disc v5.1.
	privKey.X, privKey.Y = gcrypto.S256().ScalarBaseMult(rawKey)
	return privKey, nil
}

// Taken from Prysm
func convertToInterfacePubkey(pubkey *ecdsa.PublicKey) (crypto.PubKey, error) {
	xVal, yVal := new(btcec.FieldVal), new(btcec.FieldVal)
	if xVal.SetByteSlice(pubkey.X.Bytes()) {
		return nil, errors.New("X value overflows")
	}
	if yVal.SetByteSlice(pubkey.Y.Bytes()) {
		return nil, errors.New("Y value overflows")
	}
	newKey := crypto.PubKey((*crypto.Secp256k1PublicKey)(btcec.NewPublicKey(xVal, yVal)))
	// Zero out temporary values.
	xVal.Zero()
	yVal.Zero()
	return newKey, nil
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
	// TODO: move to Elixir side
	optionsSlice := make([]libp2p.Option, len(options)+2)
	for i := 0; i < len(options); i++ {
		optionsSlice[i] = cgo.Handle(options[i]).Value().(libp2p.Option)
	}
	// Needed to support mplex
	optionsSlice[len(options)] = libp2p.DefaultMuxers
	optionsSlice[len(options)+1] = libp2p.Muxer("/mplex/6.7.0", mplex.DefaultTransport)
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
func (h C.uintptr_t) HostSetStreamHandler(protoId string, procId []byte, callback C.send_message_t) {
	handle := cgo.Handle(h)
	host := handle.Value().(host.Host)
	// WARN: we clone the string/[]byte because the underlying buffer is owned by Elixir/C
	goProtoId := strings.Clone(protoId)
	goProcId := bytes.Clone(procId)
	handler := func(stream network.Stream) {
		C.run_callback(callback, unsafe.Pointer(&goProcId[0]), C.uintptr_t(cgo.NewHandle(stream)))
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

//export HostConnect
func (h C.uintptr_t) HostConnect(pid C.uintptr_t) int {
	host := cgo.Handle(h).Value().(host.Host)
	peerId := cgo.Handle(pid).Value().(peer.ID)
	addrInfo := host.Peerstore().PeerInfo(peerId)
	err := host.Connect(context.TODO(), addrInfo)
	if err != nil {
		// TODO: handle in better way
		// fmt.Fprintf(os.Stderr, "%s\n", err)
		return 1
	}
	return 0
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
	if err != nil && err != io.EOF {
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
	// TODO: return error
	handle := cgo.Handle(s)
	handle.Value().(network.Stream).Close()
}

//export StreamCloseWrite
func (s C.uintptr_t) StreamCloseWrite() {
	// TODO: return error
	handle := cgo.Handle(s)
	handle.Value().(network.Stream).CloseWrite()
}

//export StreamProtocol
func (s C.uintptr_t) StreamProtocol(buffer []byte) int {
	stream := cgo.Handle(s).Value().(network.Stream)
	return copy(buffer, stream.Protocol())
}

//export StreamProtocolLen
func (s C.uintptr_t) StreamProtocolLen() int {
	stream := cgo.Handle(s).Value().(network.Stream)
	return len(stream.Protocol())
}

/***************/
/** Discovery **/
/***************/

//export ListenV5
func ListenV5(strAddr string, strBootnodes []string) C.uintptr_t {
	udpAddr, err := net.ResolveUDPAddr("udp", strAddr)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	conn, err := net.ListenUDP("udp", udpAddr)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	intPrivKey, _, err := crypto.GenerateSecp256k1Key(rand.Reader)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	privKey, err := convertFromInterfacePrivKey(intPrivKey)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}

	bootnodes := make([]*enode.Node, 0, len(strBootnodes))

	for _, strBootnode := range strBootnodes {
		bootnode, err := enode.Parse(enode.ValidSchemes, strBootnode)
		bootnodes = append(bootnodes, bootnode)
		if err != nil {
			// TODO: handle in better way
			fmt.Fprintf(os.Stderr, "%s\n", err)
			return 0
		}
	}

	cfg := discover.Config{
		// These settings are required and configure the UDP listener:
		PrivateKey: privKey,

		// These settings are optional:
		// NetRestrict *netutil.Netlist  // list of allowed IP networks
		Bootnodes: bootnodes, // list of bootstrap nodes
		// Unhandled   chan<- ReadPacket // unhandled packets are sent on this channel
		// Log         log.Logger        // if set, log messages go here

		// V5ProtocolID configures the discv5 protocol identifier.
		// V5ProtocolID *[6]byte

		// ValidSchemes enr.IdentityScheme // allowed identity schemes
		// Clock        mclock.Clock
	}

	db, err := enode.OpenDB("")
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	localNode := enode.NewLocalNode(db, privKey)
	localNode.Set(enr.IP(udpAddr.IP))
	localNode.Set(enr.UDP(udpAddr.Port))
	localNode.Set(enr.TCP(udpAddr.Port))
	localNode.SetFallbackIP(udpAddr.IP)
	localNode.SetFallbackUDP(udpAddr.Port)

	listener, err := discover.ListenV5(conn, localNode, cfg)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(listener))
}

//export ListenerRandomNodes
func (l C.uintptr_t) ListenerRandomNodes() C.uintptr_t {
	listener := cgo.Handle(l).Value().(*discover.UDPv5)
	iter := listener.RandomNodes()
	return C.uintptr_t(cgo.NewHandle(iter))
}

//export IteratorNext
func (i C.uintptr_t) IteratorNext() bool {
	iterator := cgo.Handle(i).Value().(enode.Iterator)
	return iterator.Next()
}

//export IteratorNode
func (i C.uintptr_t) IteratorNode() C.uintptr_t {
	return callGetter(i, enode.Iterator.Node)
}

//export NodeTCP
func (n C.uintptr_t) NodeTCP() int {
	return cgo.Handle(n).Value().(*enode.Node).TCP()
}

//export NodeMultiaddr
func (n C.uintptr_t) NodeMultiaddr() C.uintptr_t {
	node := cgo.Handle(n).Value().(*enode.Node)
	var addrArr []multiaddr.Multiaddr
	if node.TCP() != 0 {
		str := fmt.Sprintf("/ip4/%s/tcp/%d", node.IP(), node.TCP())
		addr, err := multiaddr.NewMultiaddr(str)
		if err != nil {
			// TODO: handle in better way
			fmt.Fprintf(os.Stderr, "%s\n", err)
			return 0
		}
		addrArr = append(addrArr, addr)
	} else if node.UDP() != 0 {
		str := fmt.Sprintf("/ip4/%s/udp/%d/quic", node.IP(), node.UDP())
		addr, err := multiaddr.NewMultiaddr(str)
		if err != nil {
			// TODO: handle in better way
			fmt.Fprintf(os.Stderr, "%s\n", err)
			return 0
		}
		addrArr = append(addrArr, addr)
	} else {
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(addrArr))
}

//export NodeID
func (n C.uintptr_t) NodeID() C.uintptr_t {
	node := cgo.Handle(n).Value().(*enode.Node)
	key, err := convertToInterfacePubkey(node.Pubkey())
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	nodeID, err := peer.IDFromPublicKey(key)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(nodeID))
}

/***************/
/** GossipSub **/
/***************/

//export NewGossipSub
func NewGossipSub(h C.uintptr_t) C.uintptr_t {
	host := cgo.Handle(h).Value().(host.Host)
	// TODO: receive options by parameter
	heartbeat := 700 * time.Millisecond
	params := pubsub.DefaultGossipSubParams()
	params.D = 8
	params.Dlo = 6
	params.HeartbeatInterval = heartbeat
	params.FanoutTTL = 60 * time.Second
	params.HistoryLength = 6
	params.HistoryGossip = 3

	// TODO: add more options, especially WithMessageIdFn
	options := []pubsub.Option{
		pubsub.WithMessageSignaturePolicy(pubsub.StrictNoSign),
		pubsub.WithNoAuthor(),
		pubsub.WithGossipSubParams(params),
		pubsub.WithSeenMessagesTTL(550 * heartbeat),
		pubsub.WithMaxMessageSize(10 * (1 << 20)), // 10 MB
	}

	gsub, err := pubsub.NewGossipSub(context.TODO(), host, options...)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(gsub))
}

//export PubSubJoin
func (ps C.uintptr_t) PubSubJoin(topicStr string) C.uintptr_t {
	// WARN: we clone the string because the underlying buffer is owned by Elixir
	goTopicStr := strings.Clone(topicStr)
	psub := cgo.Handle(ps).Value().(*pubsub.PubSub)
	topic, err := psub.Join(goTopicStr)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(topic))
}

//export TopicSubscribe
func (tp C.uintptr_t) TopicSubscribe() C.uintptr_t {
	// WARN: we clone the string because the underlying buffer is owned by Elixir
	topic := cgo.Handle(tp).Value().(*pubsub.Topic)
	sub, err := topic.Subscribe()
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(sub))
}

//export TopicPublish
func (tp C.uintptr_t) TopicPublish(data []byte) int {
	// WARN: we clone the string because the underlying buffer is owned by Elixir
	topic := cgo.Handle(tp).Value().(*pubsub.Topic)
	err := topic.Publish(context.TODO(), data)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "%s\n", err)
		return 1
	}
	return 0
}

//export SubscriptionNext
func (sub C.uintptr_t) SubscriptionNext(cErr **C.char) C.uintptr_t {
	// WARN: we clone the string because the underlying buffer is owned by Elixir
	subscription := cgo.Handle(sub).Value().(*pubsub.Subscription)
	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Microsecond)
	defer cancel()
	message, err := subscription.Next(ctx)

	if err == nil {
		return C.uintptr_t(cgo.NewHandle(message))
	} else if err != context.DeadlineExceeded {
		*cErr = C.CString(err.Error())
	}
	return 0
}

//export MessageData
func (m C.uintptr_t) MessageData(buffer []byte) int {
	msg := cgo.Handle(m).Value().(*pubsub.Message)
	return copy(buffer, msg.Data)
}

//export MessageDataLen
func (m C.uintptr_t) MessageDataLen() int {
	msg := cgo.Handle(m).Value().(*pubsub.Message)
	return len(msg.Data)
}
