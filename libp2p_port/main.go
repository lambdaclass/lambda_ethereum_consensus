package main

import (
	"io"

	"libp2p_port/internal/port"
	proto_defs "libp2p_port/internal/proto"
	"libp2p_port/internal/proto_helpers"
	gossipsub "libp2p_port/internal/subscriptions"
)

func HandleCommand(command *proto_defs.Command, subscriber *gossipsub.Subscriber) proto_defs.Notification {
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

func CommandServer() {
	port := port.NewPort()
	subscriber := gossipsub.NewSubscriber(port)
	command := proto_defs.Command{}
	for {
		err := port.ReadCommand(&command)
		if err == io.EOF {
			break
		}
		reply := HandleCommand(&command, &subscriber)
		port.SendNotification(&reply)
	}
}

func main() {
	CommandServer()
}
