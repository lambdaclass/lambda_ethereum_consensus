package main

import (
	"io"

	"libp2p_port/internal/port"
	proto_defs "libp2p_port/internal/proto"
	"libp2p_port/internal/proto_helpers"
	"libp2p_port/internal/reqresp"
	gossipsub "libp2p_port/internal/subscriptions"
)

func handleCommand(command *proto_defs.Command, listener *reqresp.Listener, subscriber *gossipsub.Subscriber) proto_defs.Notification {
	switch c := command.C.(type) {
	case *proto_defs.Command_SetHandler:
		listener.SetHandler(c.SetHandler.ProtocolId, c.SetHandler.Handler)
		return proto_helpers.ResponseNotification(command.From, true, "")
	case *proto_defs.Command_Subscribe:
		subscriber.Subscribe(c.Subscribe.Name)
		return proto_helpers.ResponseNotification(command.From, true, "")
	case *proto_defs.Command_Unsubscribe:
		subscriber.Unsubscribe(c.Unsubscribe.Name)
		return proto_helpers.ResponseNotification(command.From, true, "")
	default:
		return proto_helpers.ResponseNotification(command.From, false, "Invalid command.")
	}
}

func commandServer() {
	portInst := port.NewPort()
	initArgs := proto_defs.InitArgs{}
	err := portInst.ReadInitArgs(&initArgs)
	if err == io.EOF {
		return
	}
	config := proto_helpers.ConfigFromInitArgs(&initArgs)

	listener := reqresp.NewListener(&config)
	subscriber := gossipsub.NewSubscriber(portInst, &config)
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
