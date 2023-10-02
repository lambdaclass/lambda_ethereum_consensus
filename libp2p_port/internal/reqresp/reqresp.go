package reqresp

import (
	"fmt"
	"libp2p_port/internal/utils"
	"os"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/protocol"
	"github.com/libp2p/go-libp2p/p2p/muxer/mplex"
	"github.com/libp2p/go-libp2p/p2p/security/noise"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
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

func (l *Listener) SetHandler(protocolId string, handler []byte) {
	l.hostHandle.SetStreamHandler(protocol.ID(protocolId), func(stream network.Stream) {
		fmt.Fprintf(os.Stderr, "got stream\n")
	})
}
