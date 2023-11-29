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

func AddPeerNotification() proto_defs.Notification {
	return proto_defs.Notification{N: &proto_defs.Notification_AddPeer{}}
}

func RemovePeerNotification() proto_defs.Notification {
	return proto_defs.Notification{N: &proto_defs.Notification_RemovePeer{}}
}

func JoinNotification(topic string) proto_defs.Notification {
	joinNotification := &proto_defs.Join{Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_Joined{Joined: joinNotification}}
}

func LeaveNofication(topic string) proto_defs.Notification {
	leaveNofication := &proto_defs.Leave{Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_Left{Left: leaveNofication}}
}

func GraftNotification(topic string) proto_defs.Notification {
	graftNotification := &proto_defs.Graft{Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_Grafted{Grafted: graftNotification}}
}

func PruneNotification(topic string) proto_defs.Notification {
	pruneNotification := &proto_defs.Prune{Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_Pruned{Pruned: pruneNotification}}
}

func ValidateMessageNotification(topic string) proto_defs.Notification {
	validateMessageNotification := &proto_defs.ValidateMessageGossip{Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_ValidateMessage{ValidateMessage: validateMessageNotification}}
}

func DeliverMessageNotification(topic string) proto_defs.Notification {
	deliverMessageNotification := &proto_defs.DeliverMessage{Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_DeliverMessage{DeliverMessage: deliverMessageNotification}}
}

func UndeliverableMessageNotification(topic string) proto_defs.Notification {
	unDeliverableMessageNotification := &proto_defs.UnDeliverableMessage{Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_UnDeliverableMessage{UnDeliverableMessage: unDeliverableMessageNotification}}
}

func RejectMessageNotification(topic string) proto_defs.Notification {
	rejectMessageNotification := &proto_defs.RejectMessage{Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_RejectMessage{RejectMessage: rejectMessageNotification}}
}

func DuplicateMessageNotification(topic string) proto_defs.Notification {
	duplicateMessageNotification := &proto_defs.DuplicateMessage{Topic: topic}
	return proto_defs.Notification{N: &proto_defs.Notification_DuplicateMessage{DuplicateMessage: duplicateMessageNotification}}
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
