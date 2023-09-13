package gossipsub

import (
	"libp2p_port/internal/port"
	"libp2p_port/internal/proto_helpers"
	"time"
)

type Subscriber struct {
	subscriptions map[string]chan struct{}
}

func (s *Subscriber) Subscribe(topic_name string) {
	_, is_subscribed := s.subscriptions[topic_name]
	if !is_subscribed {
		s.subscriptions[topic_name] = make(chan struct{})
		go SubscribeToTopic(topic_name, s.subscriptions[topic_name])
	}
}

func (s *Subscriber) Unsubscribe(topic_name string) {
	s.subscriptions[topic_name] <- struct{}{}
	delete(s.subscriptions, topic_name)
}

func SubscribeToTopic(name string, stop chan struct{}) {
	// This is mocked for the PoC. An actual subscription should call libp2p.
	for {
		select {
		case <-stop:
			return
		default:
			notification := proto_helpers.GossipNotification(name, "Mock notification")
			port.SendNotification(&notification)
			time.Sleep(5 * time.Second)
		}
	}
}
