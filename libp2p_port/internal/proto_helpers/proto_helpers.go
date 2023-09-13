package proto_helpers

import libp2p "libp2p_port/internal/proto"

func GossipNotification(topic string, message string) libp2p.Notification {
	gossip_sub_notification := &libp2p.GossipSub{Topic: topic, Message: message}
	return libp2p.Notification{N: &libp2p.Notification_Gossip{Gossip: gossip_sub_notification}}
}

func ResponseNotification(success bool, message string) libp2p.Notification {
	response_notification := &libp2p.Response{Success: success, Message: message}
	return libp2p.Notification{N: &libp2p.Notification_Response{Response: response_notification}}
}
