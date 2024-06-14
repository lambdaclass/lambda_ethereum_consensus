package reqresp

import (
	"context"
	"io"
	"libp2p_port/internal/port"
	"libp2p_port/internal/proto_helpers"
	"libp2p_port/internal/utils"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p"
	mplex "github.com/libp2p/go-libp2p-mplex"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
	"github.com/libp2p/go-libp2p/p2p/security/noise"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
	ma "github.com/multiformats/go-multiaddr"
)

type responseChannel = chan []byte

const RESP_TIMEOUT = time.Duration(10 * time.Second)

type Listener struct {
	hostHandle      host.Host
	port            *port.Port
	pendingMessages sync.Map
}

func NewListener(p *port.Port, config *proto_helpers.Config) Listener {
	ifaceKey, err := utils.ConvertToInterfacePrivkey(config.Privkey)
	utils.PanicIfError(err)
	// as per the spec
	optionsSlice := []libp2p.Option{
		libp2p.DefaultMuxers,
		libp2p.Muxer("/mplex/6.7.0", mplex.DefaultTransport),
		libp2p.Transport(tcp.NewTCPTransport),
		libp2p.Security(noise.ID, noise.New),
		libp2p.DisableRelay(),
		libp2p.NATPortMap(), // Allow to use UPnP
		libp2p.Ping(false),
		libp2p.ListenAddrStrings(config.ListenAddr...),
		libp2p.Identity(ifaceKey),
	}

	h, err := libp2p.New(optionsSlice...)
	utils.PanicIfError(err)
	return Listener{hostHandle: h, port: p}
}

func (l *Listener) Host() host.Host {
	return l.hostHandle
}

func (l *Listener) HostId() []byte {
	return []byte(l.hostHandle.ID())
}

func (l *Listener) GetAddresses() [][]byte {
	peerId := l.hostHandle.ID().String()
	listenAddresses := l.Host().Addrs()
	p2pAddresses := make([][]byte, len(listenAddresses))
	for i := range listenAddresses {
		p2pAddresses[i] = []byte(listenAddresses[i].String() + "/p2p/" + peerId)
	}
	return p2pAddresses
}

func (l *Listener) AddPeer(id []byte, addrs []string, ttl int64) {
	addrInfo := peer.AddrInfo{ID: peer.ID(id)}
	for _, addr := range addrs {
		maddr, err := ma.NewMultiaddr(addr)
		// TODO: return error to caller
		if err == nil {
			addrInfo.Addrs = append(addrInfo.Addrs, maddr)
		}
	}
	if len(addrInfo.Addrs) != 0 {
		l.AddPeerWithAddrInfo(addrInfo, ttl)
	}
}

func (l *Listener) AddPeerWithAddrInfo(addrInfo peer.AddrInfo, ttl int64) {
	l.hostHandle.Connect(context.TODO(), addrInfo)
	notification := proto_helpers.NewPeerNotification([]byte(addrInfo.ID))
	l.port.SendNotification(&notification)
}

func (l *Listener) SendRequest(from, peerId []byte, protocolId string, message []byte) {
	go sendAsyncRequest(l.hostHandle, *l.port, from, peer.ID(peerId), protocol.ID(protocolId), message)
}

func sendAsyncRequest(h host.Host, p port.Port, from []byte, peerId peer.ID, protocolId protocol.ID, message []byte) {
	response, err := sendRequest(h, peerId, protocolId, message)
	result := proto_helpers.ResponseNotification([]byte(from), response, err, string(protocolId), message)
	p.SendNotification(result)
}

func sendRequest(h host.Host, peerId peer.ID, protocolId protocol.ID, message []byte) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), RESP_TIMEOUT)
	defer cancel()

	stream, err := h.NewStream(ctx, peerId, protocolId)
	if err != nil {
		return nil, err
	}
	defer stream.Close()
	_, err = stream.Write(message)
	if err != nil {
		return nil, err
	}
	stream.CloseWrite()
	return io.ReadAll(stream)
}

func (l *Listener) SendResponse(requestId string, message []byte) {
	value, found := l.pendingMessages.LoadAndDelete(requestId)
	if !found {
		// TODO: return error
		panic("message not found")
	}
	value.(responseChannel) <- message
}

func (l *Listener) SetHandler(protocolId string, handler []byte) {
	l.hostHandle.SetStreamHandler(protocol.ID(protocolId), func(stream network.Stream) {
		defer stream.Close()
		id := string(stream.Protocol())
		request, err := io.ReadAll(stream)
		if err != nil {
			// TODO: we just ignore read errors for now
			return
		}
		requestId := stream.ID()
		responseChan := make(chan []byte)
		l.pendingMessages.Store(requestId, responseChan)
		notification := proto_helpers.RequestNotification(id, handler, requestId, request)
		l.port.SendNotification(&notification)
		response := <-responseChan
		_, err = stream.Write(response)
		if err != nil {
			// TODO: we just ignore write errors for now
			return
		}
	})
}
