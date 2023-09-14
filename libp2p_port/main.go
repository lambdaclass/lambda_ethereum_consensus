package main

import (
	"io"

	"libp2p_port/internal/port"
	libp2p "libp2p_port/internal/proto"
	"libp2p_port/internal/proto_helpers"
	gossipsub "libp2p_port/internal/subscriptions"
)

func HandleCommand(command *libp2p.Command, subscriber *gossipsub.Subscriber) libp2p.Notification {
	switch c := command.C.(type) {
	case *libp2p.Command_Subscribe:
		subscriber.Subscribe(c.Subscribe.Name)
		return proto_helpers.ResponseNotification(command.Id, true, "")
	case *libp2p.Command_Unsubscribe:
		subscriber.Unsubscribe(c.Unsubscribe.Name)
		return proto_helpers.ResponseNotification(command.Id, true, "")
	default:
		return proto_helpers.ResponseNotification(command.Id, false, "Invalid command.")
	}
}

func CommandServer() {
	port := port.NewPort()
	subscriber := gossipsub.NewSubscriber(port)
	command := libp2p.Command{}
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
