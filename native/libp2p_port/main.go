package main

import (
	"errors"
	"io"

	"libp2p_port/internal/discovery"
	"libp2p_port/internal/port"
	proto_defs "libp2p_port/internal/proto"
	"libp2p_port/internal/proto_helpers"
	"libp2p_port/internal/reqresp"
	gossipsub "libp2p_port/internal/subscriptions"
)

func handleCommand(command *proto_defs.Command, listener *reqresp.Listener, subscriber *gossipsub.Subscriber, discoverer *discovery.Discoverer) *proto_defs.Notification {
	switch c := command.C.(type) {
	case *proto_defs.Command_GetNodeIdentity:
		identity := getNodeIdentity(listener, discoverer)
		return proto_helpers.NodeIdentityNotification(command.From, identity)
	case *proto_defs.Command_AddPeer:
		listener.AddPeer(c.AddPeer.Id, c.AddPeer.Addrs, c.AddPeer.Ttl)
	case *proto_defs.Command_SendRequest:
		listener.SendRequest(command.From, c.SendRequest.Id, c.SendRequest.ProtocolId, c.SendRequest.Message)
		return nil // No response
	case *proto_defs.Command_SendResponse:
		listener.SendResponse(c.SendResponse.RequestId, c.SendResponse.Message)
	case *proto_defs.Command_SetHandler:
		listener.SetHandler(c.SetHandler.ProtocolId, command.From)
	case *proto_defs.Command_Subscribe:
		err := subscriber.Subscribe(c.Subscribe.Name, command.From)
		return proto_helpers.ResultNotification(command.From, nil, err)
	case *proto_defs.Command_Leave:
		subscriber.Leave(c.Leave.Name)
	case *proto_defs.Command_ValidateMessage:
		subscriber.Validate(c.ValidateMessage.MsgId, int(c.ValidateMessage.Result))
	case *proto_defs.Command_Publish:
		subscriber.Publish(c.Publish.Topic, c.Publish.Message)
	case *proto_defs.Command_UpdateEnr:
		discoverer.UpdateEnr(proto_helpers.LoadEnr(c.UpdateEnr))
	case *proto_defs.Command_Join:
		subscriber.Join(c.Join.Name)
	default:
		return proto_helpers.ResultNotification(command.From, nil, errors.New("invalid command"))
	}
	// Default, OK empty response
	return proto_helpers.ResultNotification(command.From, nil, nil)
}

func getNodeIdentity(listener *reqresp.Listener, discoverer *discovery.Discoverer) *proto_defs.NodeIdentity {
	peerId := listener.HostId()
	// TODO: pass only raw peer ID
	// Pretty-printed peer ID
	prettyPeerId := []byte(listener.Host().ID().String())
	enr := discoverer.GetEnr()
	p2pAddresses := listener.GetAddresses()
	discoveryAddresses := discoverer.GetDiscoveryAddresses()

	return &proto_defs.NodeIdentity{PeerId: []byte(peerId), Enr: enr, P2PAddresses: p2pAddresses, DiscoveryAddresses: discoveryAddresses, PrettyPeerId: prettyPeerId}
}

func commandServer() {
	portInst := port.NewPort()
	initArgs := proto_defs.InitArgs{}
	err := portInst.ReadInitArgs(&initArgs)
	if err == io.EOF {
		return
	}
	config := proto_helpers.ConfigFromInitArgs(&initArgs)

	listener := reqresp.NewListener(portInst, &config)

	var discoverer *discovery.Discoverer
	if config.EnableDiscovery {
		tmp := discovery.NewDiscoverer(portInst, &listener, &config)
		discoverer = &tmp
	}
	subscriber := gossipsub.NewSubscriber(portInst, listener.Host())
	command := proto_defs.Command{}
	for {
		err := portInst.ReadCommand(&command)
		if err == io.EOF {
			break
		}
		reply := handleCommand(&command, &listener, &subscriber, discoverer)
		portInst.SendNotification(reply)
	}
}

func main() {
	commandServer()
}
