package discovery

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"libp2p_port/internal/port"
	"libp2p_port/internal/proto_helpers"
	"libp2p_port/internal/reqresp"
	"libp2p_port/internal/utils"
	"net"

	"github.com/ethereum/go-ethereum/p2p/discover"
	"github.com/ethereum/go-ethereum/p2p/enode"
	"github.com/ethereum/go-ethereum/p2p/enr"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	ma "github.com/multiformats/go-multiaddr"
	"github.com/pkg/errors"
)

type Discoverer struct {
	port           *port.Port
	discv5_service *discover.UDPv5
	forkUpdates    chan [4]byte
}

func NewDiscoverer(p *port.Port, listener *reqresp.Listener, config *proto_helpers.Config) Discoverer {
	udpAddr, err := net.ResolveUDPAddr("udp", config.DiscoveryAddr)
	utils.PanicIfError(err)
	conn, err := net.ListenUDP("udp", udpAddr)
	utils.PanicIfError(err)

	bootnodes := make([]*enode.Node, 0, len(config.Bootnodes))

	for _, strBootnode := range config.Bootnodes {
		bootnode, err := enode.Parse(enode.ValidSchemes, strBootnode)
		utils.PanicIfError(err)
		bootnodes = append(bootnodes, bootnode)
	}

	cfg := discover.Config{
		PrivateKey: config.Privkey,
		Bootnodes:  bootnodes, // list of bootstrap nodes
	}

	db, err := enode.OpenDB("")
	utils.PanicIfError(err)

	localNode := enode.NewLocalNode(db, config.Privkey)
	localNode.Set(enr.IP(udpAddr.IP))
	localNode.Set(enr.UDP(udpAddr.Port))
	localNode.Set(enr.TCP(udpAddr.Port))
	localNode.SetFallbackIP(udpAddr.IP)
	localNode.SetFallbackUDP(udpAddr.Port)

	updateEnr(localNode, config.InitialEnr)

	discv5_service, err := discover.ListenV5(conn, localNode, cfg)
	utils.PanicIfError(err)

	forkUpdates := make(chan [4]byte, 1)
	forkUpdates <- [4]byte(config.InitialEnr.Eth2[:4])

	go lookForPeers(discv5_service.RandomNodes(), listener, forkUpdates)

	return Discoverer{port: p, discv5_service: discv5_service, forkUpdates: forkUpdates}
}

func lookForPeers(iter enode.Iterator, listener *reqresp.Listener, forkUpdates chan [4]byte) {
	currentForkDigest := <-forkUpdates
	for iter.Next() {
		node := iter.Node()
		updateForkDigest(currentForkDigest[:], forkUpdates)
		if !filterPeer(node, currentForkDigest[:]) {
			continue
		}
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
		go func() {
			listener.AddPeer([]byte(nodeID), addrArr, peerstore.PermanentAddrTTL)
		}()
	}
}

func updateForkDigest(currentForkDigest []byte, forkUpdates chan [4]byte) {
	select {
	case newForkDigest := <-forkUpdates:
		copy(currentForkDigest, newForkDigest[:])
	default:
		return
	}
}

// Taken from Prysm: https://github.com/prysmaticlabs/prysm/blob/d5057cfb42fe501e4381177aaa4f45ac6086651f/beacon-chain/p2p/discovery.go#L267

// filterPeer validates each node that we retrieve from our dht. We
// try to ascertain that the peer can be a valid protocol peer.
// Validity Conditions:
//  1. The local node is still actively looking for peers to
//     connect to.
//  2. Peer has a valid IP and TCP port set in their enr.
//  3. ~Peer hasn't been marked as 'bad'~
//  4. ~Peer is not currently active or connected.~
//  5. ~Peer is ready to receive incoming connections.~
//  6. Peer's fork digest in their ENR matches that of
//     our localnodes.
func filterPeer(node *enode.Node, currentForkDigest []byte) bool {
	// Ignore nil node entries passed in.
	if node == nil {
		return false
	}
	// ignore nodes with no ip address stored.
	if node.IP() == nil {
		return false
	}
	nodeENR := node.Record()
	// do not dial nodes with their tcp ports not set
	if err := nodeENR.Load(enr.WithEntry("tcp", new(enr.TCP))); err != nil {
		return false
	}
	// Decide whether or not to connect to peer that does not
	// match the proper fork ENR data with our local node.
	sszEncodedForkEntry := make([]byte, 16)
	entry := enr.WithEntry("eth2", &sszEncodedForkEntry)
	nodeENR.Load(entry)
	forkDigest := sszEncodedForkEntry[:4]
	return bytes.Equal(currentForkDigest, forkDigest)
}

// SerializeENR takes the enr record in its key-value form and serializes it.
func serializeENR(record *enr.Record) (string, error) {
	if record == nil {
		return "", errors.New("could not serialize nil record")
	}
	buf := bytes.NewBuffer([]byte{})
	if err := record.EncodeRLP(buf); err != nil {
		return "", errors.Wrap(err, "could not encode ENR record to bytes")
	}
	enrString := base64.RawURLEncoding.EncodeToString(buf.Bytes())
	return "enr:" + enrString, nil
}

func (d *Discoverer) GetAddresses() [][]byte {
	if d == nil {
		return [][]byte{}
	}
	addrs, err := convertToUdpMultiAddr(d.discv5_service.Self())
	utils.PanicIfError(err)
	serializedAddresses := make([][]byte, len(addrs))
	for i := range addrs {
		serializedAddresses[i] = []byte(addrs[i].String())
	}
	return serializedAddresses
}

func (d *Discoverer) GetEnr() []byte {
	if d == nil {
		return []byte{}
	}
	record := d.discv5_service.LocalNode().Node().Record()
	enr, err := serializeENR(record)
	utils.PanicIfError(err)
	return []byte(enr)
}

func (d *Discoverer) UpdateEnr(enr proto_helpers.Enr) {
	if d == nil {
		return
	}
	localNode := d.discv5_service.LocalNode()
	updateEnr(localNode, enr)
	d.forkUpdates <- [4]byte(enr.Eth2[:4])
}

func updateEnr(localNode *enode.LocalNode, e proto_helpers.Enr) {
	localNode.Set(enr.WithEntry("eth2", e.Eth2))
	localNode.Set(enr.WithEntry("attnets", e.Attnets))
	localNode.Set(enr.WithEntry("syncnets", e.Syncnets))
}

func convertToAddrInfo(node *enode.Node) (*peer.AddrInfo, ma.Multiaddr, error) {
	multiAddr, err := convertToSingleMultiAddr(node)
	if err != nil {
		return nil, nil, err
	}
	info, err := peer.AddrInfoFromP2pAddr(multiAddr)
	if err != nil {
		return nil, nil, err
	}
	return info, multiAddr, nil
}

func convertToSingleMultiAddr(node *enode.Node) (ma.Multiaddr, error) {
	pubkey := node.Pubkey()
	assertedKey, err := utils.ConvertToInterfacePubkey(pubkey)
	if err != nil {
		return nil, errors.Wrap(err, "could not get pubkey")
	}
	id, err := peer.IDFromPublicKey(assertedKey)
	if err != nil {
		return nil, errors.Wrap(err, "could not get peer id")
	}
	return multiAddressBuilderWithID(node.IP().String(), "tcp", uint(node.TCP()), id)
}

func convertToUdpMultiAddr(node *enode.Node) ([]ma.Multiaddr, error) {
	pubkey := node.Pubkey()
	assertedKey, err := utils.ConvertToInterfacePubkey(pubkey)
	if err != nil {
		return nil, errors.Wrap(err, "could not get pubkey")
	}
	id, err := peer.IDFromPublicKey(assertedKey)
	if err != nil {
		return nil, errors.Wrap(err, "could not get peer id")
	}

	var addresses []ma.Multiaddr
	var ip4 enr.IPv4
	var ip6 enr.IPv6
	if node.Load(&ip4) == nil {
		address, ipErr := multiAddressBuilderWithID(net.IP(ip4).String(), "udp", uint(node.UDP()), id)
		if ipErr != nil {
			return nil, errors.Wrap(ipErr, "could not build IPv4 address")
		}
		addresses = append(addresses, address)
	}
	if node.Load(&ip6) == nil {
		address, ipErr := multiAddressBuilderWithID(net.IP(ip6).String(), "udp", uint(node.UDP()), id)
		if ipErr != nil {
			return nil, errors.Wrap(ipErr, "could not build IPv6 address")
		}
		addresses = append(addresses, address)
	}

	return addresses, nil
}

func multiAddressBuilderWithID(ipAddr, protocol string, port uint, id peer.ID) (ma.Multiaddr, error) {
	parsedIP := net.ParseIP(ipAddr)
	if parsedIP.To4() == nil && parsedIP.To16() == nil {
		return nil, errors.Errorf("invalid ip address provided: %s", ipAddr)
	}
	if id.String() == "" {
		return nil, errors.New("empty peer id given")
	}
	if parsedIP.To4() != nil {
		return ma.NewMultiaddr(fmt.Sprintf("/ip4/%s/%s/%d/p2p/%s", ipAddr, protocol, port, id.String()))
	}
	return ma.NewMultiaddr(fmt.Sprintf("/ip6/%s/%s/%d/p2p/%s", ipAddr, protocol, port, id.String()))
}
