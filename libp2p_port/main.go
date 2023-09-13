package main

import (
	"bufio"
	"io"
	"os"

	"libp2p_port/internal/port"
	libp2p "libp2p_port/internal/proto"
	"libp2p_port/internal/proto_helpers"
	gossipsub "libp2p_port/internal/subscriptions"
)

func HandleCommand(command *libp2p.Command, subscriber *gossipsub.Subscriber) libp2p.Notification {
	switch c := command.C.(type) {
	case *libp2p.Command_Subscribe:
		subscriber.Subscribe(c.Subscribe.Name)
		return proto_helpers.ResponseNotification(true, "")
	case *libp2p.Command_Unsubscribe:
		subscriber.Unsubscribe(c.Unsubscribe.Name)
		return proto_helpers.ResponseNotification(true, "")
	default:
		return proto_helpers.ResponseNotification(false, "Invalid command.")
	}
}

func CommandServer() {
	subscriber := gossipsub.Subscriber{}
	port_reader := bufio.NewReader(os.Stdin)
	command := libp2p.Command{}
	for {
		err := port.ReadCommand(port_reader, &command)
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
