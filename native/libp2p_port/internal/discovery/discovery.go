package discovery

import (
	"crypto/rand"
	"fmt"
	"libp2p_port/internal/port"
	"libp2p_port/internal/proto_helpers"
	"libp2p_port/internal/reqresp"
	"libp2p_port/internal/utils"
	"net"

	"github.com/ethereum/go-ethereum/p2p/discover"
	"github.com/ethereum/go-ethereum/p2p/enode"
	"github.com/ethereum/go-ethereum/p2p/enr"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
)

type Discoverer struct {
	port           *port.Port
	discv5_service *discover.UDPv5
}

func NewDiscoverer(p *port.Port, listener *reqresp.Listener, config *proto_helpers.Config) Discoverer {
	if !config.UseDiscv5 {
		return Discoverer{}
	}
	udpAddr, err := net.ResolveUDPAddr("udp", config.DiscoveryAddr)
	utils.PanicIfError(err)
	conn, err := net.ListenUDP("udp", udpAddr)
	utils.PanicIfError(err)
	intPrivKey, _, err := crypto.GenerateSecp256k1Key(rand.Reader)
	utils.PanicIfError(err)
	privKey, err := utils.ConvertFromInterfacePrivKey(intPrivKey)
	utils.PanicIfError(err)

	bootnodes := make([]*enode.Node, 0, len(config.Bootnodes))

	for _, strBootnode := range config.Bootnodes {
		bootnode, err := enode.Parse(enode.ValidSchemes, strBootnode)
		utils.PanicIfError(err)
		bootnodes = append(bootnodes, bootnode)
	}

	cfg := discover.Config{
		PrivateKey: privKey,
		Bootnodes:  bootnodes, // list of bootstrap nodes
	}

	db, err := enode.OpenDB("")
	utils.PanicIfError(err)

	localNode := enode.NewLocalNode(db, privKey)
	localNode.Set(enr.IP(udpAddr.IP))
	localNode.Set(enr.UDP(udpAddr.Port))
	localNode.Set(enr.TCP(udpAddr.Port))
	localNode.SetFallbackIP(udpAddr.IP)
	localNode.SetFallbackUDP(udpAddr.Port)

	discv5_service, err := discover.ListenV5(conn, localNode, cfg)
	utils.PanicIfError(err)

	go lookForPeers(discv5_service.RandomNodes(), listener)

	return Discoverer{port: p, discv5_service: discv5_service}
}

func lookForPeers(iter enode.Iterator, listener *reqresp.Listener) {
	for iter.Next() {
		node := iter.Node()
		var addrArr []string
		if node.TCP() != 0 {
			str := fmt.Sprintf("/ip4/%s/tcp/%d", node.IP(), node.TCP())
			addrArr = append(addrArr, str)
		} else if node.UDP() != 0 {
			str := fmt.Sprintf("/ip4/%s/udp/%d/quic", node.IP(), node.UDP())
			addrArr = append(addrArr, str)
		} else {
			continue
		}
		key, err := utils.ConvertToInterfacePubkey(node.Pubkey())
		if err != nil {
			continue
		}
		nodeID, err := peer.IDFromPublicKey(key)
		if err != nil {
			continue
		}

		listener.AddPeer([]byte(nodeID), addrArr, peerstore.PermanentAddrTTL)
	}
}
