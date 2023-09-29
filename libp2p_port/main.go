package main

import (
	"io"

	"libp2p_port/internal/p2p"
	"libp2p_port/internal/port"
	proto_defs "libp2p_port/internal/proto"
	"libp2p_port/internal/proto_helpers"
	gossipsub "libp2p_port/internal/subscriptions"
)

func handleCommand(command *proto_defs.Command, listener *p2p.Listener, subscriber *gossipsub.Subscriber) proto_defs.Notification {
	switch c := command.C.(type) {
	case *proto_defs.Command_Subscribe:
		subscriber.Subscribe(c.Subscribe.Name)
		return proto_helpers.ResponseNotification(command.Id, true, "")
	case *proto_defs.Command_Unsubscribe:
		subscriber.Unsubscribe(c.Unsubscribe.Name)
		return proto_helpers.ResponseNotification(command.Id, true, "")
	default:
		return proto_helpers.ResponseNotification(command.Id, false, "Invalid command.")
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

	listener := p2p.NewListener(&config)
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
