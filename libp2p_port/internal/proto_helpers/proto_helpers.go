package proto_helpers

import (
	proto_defs "libp2p_port/internal/proto"
	"libp2p_port/internal/utils"
)

func ConfigFromInitArgs(initArgs *proto_defs.InitArgs) utils.Config {
	config := utils.Config{}
	config.ListenAddress = initArgs.ListenAddress
	return config
}

func GossipNotification(topic string, message string) proto_defs.Notification {
	gossip_sub_notification := &proto_defs.GossipSub{Topic: topic, Message: message}
	return proto_defs.Notification{N: &proto_defs.Notification_Gossip{Gossip: gossip_sub_notification}}
}

func ResponseNotification(id string, success bool, message string) proto_defs.Notification {
	response_notification := &proto_defs.Response{Id: id, Success: success, Message: message}
	return proto_defs.Notification{N: &proto_defs.Notification_Response{Response: response_notification}}
}
