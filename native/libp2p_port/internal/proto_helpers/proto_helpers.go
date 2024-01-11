package proto_helpers

import (
	proto_defs "libp2p_port/internal/proto"
)

type Config struct {
	ListenAddr      []string
	EnableDiscovery bool
	DiscoveryAddr   string
	Bootnodes       []string
	ForkDigest      []byte
}

func ConfigFromInitArgs(initArgs *proto_defs.InitArgs) Config {
	return Config{
		ListenAddr:      initArgs.ListenAddr,
		EnableDiscovery: initArgs.EnableDiscovery,
		DiscoveryAddr:   initArgs.DiscoveryAddr,
		Bootnodes:       initArgs.Bootnodes,
		ForkDigest:      initArgs.ForkDigest,
	}
}

func AddPeerNotification() proto_defs.Notification {
	addPeerNotification := &proto_defs.AddPeerGossip{}
	tracer := &proto_defs.Tracer{T: &proto_defs.Tracer_AddPeer{AddPeer: addPeerNotification}}
	return proto_defs.Notification{N: &proto_defs.Notification_Tracer{Tracer: tracer}}
}

func RemovePeerNotification() proto_defs.Notification {
	removePeerNotification := &proto_defs.RemovePeerGossip{}
	tracer := &proto_defs.Tracer{T: &proto_defs.Tracer_RemovePeer{RemovePeer: removePeerNotification}}
	return proto_defs.Notification{N: &proto_defs.Notification_Tracer{Tracer: tracer}}
}

func JoinNotification(topic string) proto_defs.Notification {
	joinNotification := &proto_defs.Join{Topic: topic}
	tracer := &proto_defs.Tracer{T: &proto_defs.Tracer_Joined{Joined: joinNotification}}
	return proto_defs.Notification{N: &proto_defs.Notification_Tracer{Tracer: tracer}}
}

func LeaveNofication(topic string) proto_defs.Notification {
	leaveNofication := &proto_defs.Leave{Topic: topic}
	tracer := &proto_defs.Tracer{T: &proto_defs.Tracer_Left{Left: leaveNofication}}
	return proto_defs.Notification{N: &proto_defs.Notification_Tracer{Tracer: tracer}}
}

func GraftNotification(topic string) proto_defs.Notification {
	graftNotification := &proto_defs.Graft{Topic: topic}
	tracer := &proto_defs.Tracer{T: &proto_defs.Tracer_Grafted{Grafted: graftNotification}}
	return proto_defs.Notification{N: &proto_defs.Notification_Tracer{Tracer: tracer}}
}

func PruneNotification(topic string) proto_defs.Notification {
	pruneNotification := &proto_defs.Prune{Topic: topic}
	tracer := &proto_defs.Tracer{T: &proto_defs.Tracer_Pruned{Pruned: pruneNotification}}
	return proto_defs.Notification{N: &proto_defs.Notification_Tracer{Tracer: tracer}}
}

func ValidateMessageNotification(topic string) proto_defs.Notification {
	validateMessageNotification := &proto_defs.ValidateMessageGossip{Topic: topic}
	tracer := &proto_defs.Tracer{T: &proto_defs.Tracer_ValidateMessage{ValidateMessage: validateMessageNotification}}
	return proto_defs.Notification{N: &proto_defs.Notification_Tracer{Tracer: tracer}}
}

func DeliverMessageNotification(topic string) proto_defs.Notification {
	deliverMessageNotification := &proto_defs.DeliverMessage{Topic: topic}
	tracer := &proto_defs.Tracer{T: &proto_defs.Tracer_DeliverMessage{DeliverMessage: deliverMessageNotification}}
	return proto_defs.Notification{N: &proto_defs.Notification_Tracer{Tracer: tracer}}
}

func UndeliverableMessageNotification(topic string) proto_defs.Notification {
	unDeliverableMessageNotification := &proto_defs.UnDeliverableMessage{Topic: topic}
	tracer := &proto_defs.Tracer{T: &proto_defs.Tracer_UnDeliverableMessage{UnDeliverableMessage: unDeliverableMessageNotification}}
	return proto_defs.Notification{N: &proto_defs.Notification_Tracer{Tracer: tracer}}
}

func RejectMessageNotification(topic string) proto_defs.Notification {
	rejectMessageNotification := &proto_defs.RejectMessage{Topic: topic}
	tracer := &proto_defs.Tracer{T: &proto_defs.Tracer_RejectMessage{RejectMessage: rejectMessageNotification}}
	return proto_defs.Notification{N: &proto_defs.Notification_Tracer{Tracer: tracer}}
}

func DuplicateMessageNotification(topic string) proto_defs.Notification {
	duplicateMessageNotification := &proto_defs.DuplicateMessage{Topic: topic}
	tracer := &proto_defs.Tracer{T: &proto_defs.Tracer_DuplicateMessage{DuplicateMessage: duplicateMessageNotification}}
	return proto_defs.Notification{N: &proto_defs.Notification_Tracer{Tracer: tracer}}
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
