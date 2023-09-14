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
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math"
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
	"github.com/golang/snappy"
	"github.com/libp2p/go-libp2p"
	pubsub "github.com/libp2p/go-libp2p-pubsub"
	pb "github.com/libp2p/go-libp2p-pubsub/pb"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	"github.com/libp2p/go-libp2p/core/protocol"
	"github.com/libp2p/go-libp2p/p2p/muxer/mplex"
	"github.com/libp2p/go-libp2p/p2p/security/noise"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
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

// Only valid for post-Altair topics
func msgID(msg *pb.Message) string {
	if msg == nil || msg.Data == nil || msg.Topic == nil {
		// Should never happen
		msg := make([]byte, 20)
		copy(msg, "invalid")
		return string(msg)
	}
	h := sha256.New()
	data, err := snappy.Decode(nil, msg.Data)
	if err != nil {
		// MESSAGE_DOMAIN_INVALID_SNAPPY
		h.Write([]byte{0, 0, 0, 0})
		data = msg.Data
	} else {
		// MESSAGE_DOMAIN_VALID_SNAPPY
		h.Write([]byte{1, 0, 0, 0})
	}
	var topicLen [8]byte
	binary.LittleEndian.PutUint64(topicLen[:], uint64(len(*msg.Topic)))
	h.Write(topicLen[:])
	h.Write([]byte(*msg.Topic))
	h.Write(data)
	var digest []byte
	digest = h.Sum(digest)
	return string(digest[:20])
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
	optionsSlice := []libp2p.Option{
		libp2p.DefaultMuxers,
		libp2p.Muxer("/mplex/6.7.0", mplex.DefaultTransport),
		libp2p.Transport(tcp.NewTCPTransport),
		libp2p.Security(noise.ID, noise.New),
		libp2p.DisableRelay(),
		libp2p.NATPortMap(), // Allow to use UPnP
		libp2p.Ping(false),
	}
	for i := 0; i < len(options); i++ {
		optionsSlice = append(optionsSlice, cgo.Handle(options[i]).Value().(libp2p.Option))
	}

	h, err := libp2p.New(optionsSlice...)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "libp2p.New err: %s\n", err)
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
func (h C.uintptr_t) HostSetStreamHandler(protoId string, procId []byte, callback C.send_message1_t) {
	handle := cgo.Handle(h)
	host := handle.Value().(host.Host)
	// WARN: we clone the string/[]byte because the underlying buffer is owned by Elixir/C
	goProtoId := strings.Clone(protoId)
	goProcId := bytes.Clone(procId)
	handler := func(stream network.Stream) {
		C.run_callback1(callback, unsafe.Pointer(&goProcId[0]), unsafe.Pointer(cgo.NewHandle(stream)))
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
		fmt.Fprintf(os.Stderr, "host.NewStream err: %s\n", err)
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(stream))
}

//export HostConnect
func (h C.uintptr_t) HostConnect(pid C.uintptr_t, procId []byte, callback C.send_message1_t) {
	host := cgo.Handle(h).Value().(host.Host)
	peerId := cgo.Handle(pid).Value().(peer.ID)
	addrInfo := host.Peerstore().PeerInfo(peerId)
	goProcId := bytes.Clone(procId)
	go func() {
		err := host.Connect(context.Background(), addrInfo)
		var errorMsg *C.char
		if err != nil {
			errorMsg = C.CString(err.Error())
		}
		C.run_callback1(callback, unsafe.Pointer(&goProcId[0]), unsafe.Pointer(errorMsg))
	}()
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
		//fmt.Fprintf(os.Stderr, "stream.Read err: %s\n", err)
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
		//fmt.Fprintf(os.Stderr, "stream.Write err: %s\n", err)
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
		fmt.Fprintf(os.Stderr, "net.ResolveUDPAddr err: %s\n", err)
		return 0
	}
	conn, err := net.ListenUDP("udp", udpAddr)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "net.ListenUDP err: %s\n", err)
		return 0
	}
	intPrivKey, _, err := crypto.GenerateSecp256k1Key(rand.Reader)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "crypto.GenerateSecp256k1Key err: %s\n", err)
		return 0
	}
	privKey, err := convertFromInterfacePrivKey(intPrivKey)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "convertFromInterfacePrivKey err: %s\n", err)
		return 0
	}

	bootnodes := make([]*enode.Node, 0, len(strBootnodes))

	for _, strBootnode := range strBootnodes {
		bootnode, err := enode.Parse(enode.ValidSchemes, strBootnode)
		bootnodes = append(bootnodes, bootnode)
		if err != nil {
			// TODO: handle in better way
			fmt.Fprintf(os.Stderr, "enode.Parse err: %s\n", err)
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
		fmt.Fprintf(os.Stderr, "enode.OpenDB err: %s\n", err)
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
		fmt.Fprintf(os.Stderr, "discover.ListenV5 err: %s\n", err)
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
			fmt.Fprintf(os.Stderr, "multiaddr.NewMultiaddr err: %s\n", err)
			return 0
		}
		addrArr = append(addrArr, addr)
	} else if node.UDP() != 0 {
		str := fmt.Sprintf("/ip4/%s/udp/%d/quic", node.IP(), node.UDP())
		addr, err := multiaddr.NewMultiaddr(str)
		if err != nil {
			// TODO: handle in better way
			fmt.Fprintf(os.Stderr, "multiaddr.NewMultiaddr err: %s\n", err)
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
		fmt.Fprintf(os.Stderr, "convertToInterfacePubkey err: %s\n", err)
		return 0
	}
	nodeID, err := peer.IDFromPublicKey(key)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "peer.IDFromPublicKey err: %s\n", err)
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
	gsubParams := pubsub.DefaultGossipSubParams()
	gsubParams.D = 8
	gsubParams.Dlo = 6
	gsubParams.HeartbeatInterval = heartbeat
	gsubParams.FanoutTTL = 60 * time.Second
	gsubParams.HistoryLength = 6
	gsubParams.HistoryGossip = 3

	thresholds := &pubsub.PeerScoreThresholds{
		GossipThreshold:             -4000,
		PublishThreshold:            -8000,
		GraylistThreshold:           -16000,
		AcceptPXThreshold:           100,
		OpportunisticGraftThreshold: 5,
	}
	scoreParams := &pubsub.PeerScoreParams{
		Topics:        make(map[string]*pubsub.TopicScoreParams),
		TopicScoreCap: 32.72,
		AppSpecificScore: func(p peer.ID) float64 {
			return 0
		},
		AppSpecificWeight:           1,
		IPColocationFactorWeight:    -35.11,
		IPColocationFactorThreshold: 10,
		IPColocationFactorWhitelist: nil,
		BehaviourPenaltyWeight:      -15.92,
		BehaviourPenaltyThreshold:   6,
		BehaviourPenaltyDecay:       math.Pow(0.01, 1/float64(10*32)),
		DecayInterval:               12 * time.Second,
		DecayToZero:                 0.01,
		RetainScore:                 100 * 32 * 12 * time.Second,
	}

	// TODO: add more options, especially WithMessageIdFn
	options := []pubsub.Option{
		pubsub.WithMessageSignaturePolicy(pubsub.StrictNoSign),
		pubsub.WithNoAuthor(),
		pubsub.WithMessageIdFn(msgID),
		pubsub.WithPeerScore(scoreParams, thresholds),
		pubsub.WithGossipSubParams(gsubParams),
		pubsub.WithSeenMessagesTTL(550 * heartbeat),
		pubsub.WithMaxMessageSize(10 * (1 << 20)), // 10 MB
	}

	gsub, err := pubsub.NewGossipSub(context.TODO(), host, options...)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "pubsub.NewGossipSub err: %s\n", err)
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
		fmt.Fprintf(os.Stderr, "psub.Join err: %s\n", err)
		return 0
	}
	return C.uintptr_t(cgo.NewHandle(topic))
}

//export TopicSubscribe
func (tp C.uintptr_t) TopicSubscribe(procId []byte, callback C.send_message1_t) C.uintptr_t {
	// WARN: we clone the string/bytes because the underlying buffer is owned by Elixir/C
	topic := cgo.Handle(tp).Value().(*pubsub.Topic)
	goProcId := bytes.Clone(procId)

	sub, err := topic.Subscribe()
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "topic.Subscribe err: %s\n", err)
		return 0
	}
	go asyncFetchMessages(sub, goProcId, callback)
	return C.uintptr_t(cgo.NewHandle(sub))
}

// Reads messages from the subscription and sends them to the subscribed process
func asyncFetchMessages(sub *pubsub.Subscription, procId []byte, callback C.send_message1_t) {
	for {
		msg, err := sub.Next(context.Background())
		if err == pubsub.ErrSubscriptionCancelled {
			// Subscription has been cancelled
			C.run_callback1(callback, unsafe.Pointer(&procId[0]), nil)
			return
		} else if err != nil {
			// This shouldn't happen
			panic(err)
		}
		if !C.run_callback1(callback, unsafe.Pointer(&procId[0]), unsafe.Pointer(cgo.NewHandle(msg))) {
			sub.Cancel()
			return
		}
	}
}

//export TopicPublish
func (tp C.uintptr_t) TopicPublish(data []byte) int {
	// WARN: we clone the string because the underlying buffer is owned by Elixir
	topic := cgo.Handle(tp).Value().(*pubsub.Topic)
	err := topic.Publish(context.TODO(), data)
	if err != nil {
		// TODO: handle in better way
		fmt.Fprintf(os.Stderr, "topic.Publish err: %s\n", err)
		return 1
	}
	return 0
}

//export SubscriptionCancel
func (sub C.uintptr_t) SubscriptionCancel() {
	// WARN: we clone the string because the underlying buffer is owned by Elixir
	subscription := cgo.Handle(sub).Value().(*pubsub.Subscription)
	subscription.Cancel()
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
