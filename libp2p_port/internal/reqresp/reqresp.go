package reqresp

import (
	"context"
	"fmt"
	"io"
	"libp2p_port/internal/utils"
	"os"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
	"github.com/libp2p/go-libp2p/p2p/muxer/mplex"
	"github.com/libp2p/go-libp2p/p2p/security/noise"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
	"github.com/multiformats/go-multiaddr"
)

type Listener struct {
	hostHandle host.Host
}

func NewListener(config *utils.Config) Listener {
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
	}

	h, err := libp2p.New(optionsSlice...)
	utils.PanicIfError(err)
	return Listener{hostHandle: h}
}

func (l *Listener) AddPeer(id string, addrs []string, ttl int64) {
	for _, addr := range addrs {
		maddr, err := multiaddr.NewMultiaddr(addr)
		// TODO: return error to caller
		utils.PanicIfError(err)
		l.hostHandle.Peerstore().AddAddr(peer.ID(id), maddr, time.Duration(ttl))
	}
}

func (l *Listener) SendRequest(peerId string, protocolId string, message []byte) ([]byte, error) {
	ctx := context.TODO()
	stream, err := l.hostHandle.NewStream(ctx, peer.ID(peerId), protocol.ID(protocolId))
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

func (l *Listener) SetHandler(protocolId string, handler []byte) {
	l.hostHandle.SetStreamHandler(protocol.ID(protocolId), func(stream network.Stream) {
		fmt.Fprintf(os.Stderr, "got stream\n")
	})
}
