package proto_helpers

import (
	proto_defs "libp2p_port/internal/proto"
)

type Config struct {
	ListenAddr      []string
	EnableDiscovery bool
	DiscoveryAddr   string
	Bootnodes       []string
}

func ConfigFromInitArgs(initArgs *proto_defs.InitArgs) Config {
	return Config{
		ListenAddr:      initArgs.ListenAddr,
		EnableDiscovery: initArgs.EnableDiscovery,
		DiscoveryAddr:   initArgs.DiscoveryAddr,
		Bootnodes:       initArgs.Bootnodes,
	}
}

func JoinNotification(topic string) proto_defs.Notification {
	joinNotification := &proto_defs.Join{Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_Joined{Joined: joinNotification}}
}

func LeaveNofication(topic string) proto_defs.Notification {
	leaveNofication := &proto_defs.Leave{Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_Left{Left: leaveNofication}}
}

func GraftNotification(id []byte, topic string) proto_defs.Notification {
	graftNotification := &proto_defs.Graft{PeerId: id, Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_Grafted{Grafted: graftNotification}}
}

func PruneNotification(id []byte, topic string) proto_defs.Notification {
	pruneNotification := &proto_defs.Prune{PeerId: id, Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_Pruned{Pruned: pruneNotification}}
}

func GossipNotification(topic string, handler, msgId, message []byte) proto_defs.Notification {
	gossipSubNotification := &proto_defs.GossipSub{Topic: []byte(topic), Handler: handler, MsgId: msgId, Message: message}
	return proto_defs.Notification{N: &proto_defs.Notification_Gossip{Gossip: gossipSubNotification}}
}

func NewPeerNotification(id []byte) proto_defs.Notification {
	newPeerNotification := &proto_defs.NewPeer{PeerId: id}
	return proto_defs.Notification{N: &proto_defs.Notification_NewPeer{NewPeer: newPeerNotification}}
}

func RequestNotification(protocolId string, handler []byte, requestId string, message []byte) proto_defs.Notification {
	requestNotification := &proto_defs.Request{ProtocolId: []byte(protocolId), Handler: handler, RequestId: []byte(requestId), Message: message}
	return proto_defs.Notification{N: &proto_defs.Notification_Request{Request: requestNotification}}
}

func ResultNotification(from []byte, result []byte, err error) *proto_defs.Notification {
	var responseNotification *proto_defs.Result
	if err != nil {
		resultError := &proto_defs.Result_Error{Error: &proto_defs.ResultMessage{Message: [][]byte{[]byte(err.Error())}}}
		responseNotification = &proto_defs.Result{From: from, Result: resultError}
	} else {
		message := [][]byte{}
		if result != nil {
			message = [][]byte{result}
		}
		resultOk := &proto_defs.Result_Ok{Ok: &proto_defs.ResultMessage{Message: message}}
		responseNotification = &proto_defs.Result{From: from, Result: resultOk}
	}
	return &proto_defs.Notification{N: &proto_defs.Notification_Result{Result: responseNotification}}
}
