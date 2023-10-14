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
	gossipSubNotification := &proto_defs.GossipSub{Topic: topic, Message: message}
	return proto_defs.Notification{N: &proto_defs.Notification_Gossip{Gossip: gossipSubNotification}}
}

func RequestNotification(protocolId string, handler []byte, messageId string, message []byte) proto_defs.Notification {
	requestNotification := &proto_defs.Request{ProtocolId: protocolId, Handler: handler, MessageId: messageId, Message: message}
	return proto_defs.Notification{N: &proto_defs.Notification_Request{Request: requestNotification}}
}

func ResultNotification(from []byte, result []byte, err error) proto_defs.Notification {
	message := result
	if err != nil {
		message = []byte(err.Error())
	}
	responseNotification := &proto_defs.Result{From: from, Success: err == nil, Message: message}
	return proto_defs.Notification{N: &proto_defs.Notification_Result{Result: responseNotification}}
}
