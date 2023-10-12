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

func handleCommand(command *proto_defs.Command, listener *reqresp.Listener, subscriber *gossipsub.Subscriber) proto_defs.Notification {
	switch c := command.C.(type) {
	case *proto_defs.Command_GetId:
		return proto_helpers.ResultNotification(command.From, []byte(listener.HostId()), nil)
	case *proto_defs.Command_AddPeer:
		listener.AddPeer(c.AddPeer.Id, c.AddPeer.Addrs, c.AddPeer.Ttl)
	case *proto_defs.Command_SendRequest:
		response, err := listener.SendRequest(c.SendRequest.Id, c.SendRequest.ProtocolId, c.SendRequest.Message)
		return proto_helpers.ResultNotification(command.From, response, err)
	case *proto_defs.Command_SendResponse:
		listener.SendResponse(c.SendResponse.MessageId, c.SendResponse.Message)
	case *proto_defs.Command_SetHandler:
		listener.SetHandler(c.SetHandler.ProtocolId, c.SetHandler.Handler)
	case *proto_defs.Command_Subscribe:
		subscriber.Subscribe(c.Subscribe.Name)
	case *proto_defs.Command_Unsubscribe:
		subscriber.Unsubscribe(c.Unsubscribe.Name)
	default:
		return proto_helpers.ResultNotification(command.From, []byte{}, errors.New("Invalid command."))
	}
	// Default, OK empty response
	return proto_helpers.ResultNotification(command.From, []byte{}, nil)
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
	if config.EnableDiscovery {
		discovery.NewDiscoverer(portInst, &listener, &config)
	}
	subscriber := gossipsub.NewSubscriber(portInst, listener.Host())
	command := proto_defs.Command{}
	for {
		err := portInst.ReadCommand(&command)
		if err == io.EOF {
			break
		}
		reply := handleCommand(&command, &listener, &subscriber)
		portInst.SendNotification(&reply)
	}
}

func main() {
	commandServer()
}
