package proto_helpers

import (
	proto_defs "libp2p_port/internal/proto"
	"libp2p_port/internal/utils"
)

func ConfigFromInitArgs(initArgs *proto_defs.InitArgs) utils.Config {
	return utils.Config{
		ListenAddr: initArgs.ListenAddr,
	}
}

func GossipNotification(topic string, message []byte) proto_defs.Notification {
	gossip_sub_notification := &proto_defs.GossipSub{Topic: topic, Message: message}
	return proto_defs.Notification{N: &proto_defs.Notification_Gossip{Gossip: gossip_sub_notification}}
}

func ResponseNotification(from []byte, result []byte, err error) proto_defs.Notification {
	message := result
	if err != nil {
		message = []byte(err.Error())
	}
	response_notification := &proto_defs.Result{From: from, Success: err != nil, Message: message}
	return proto_defs.Notification{N: &proto_defs.Notification_Result{Result: response_notification}}
}
