package gossipsub

import (
	"fmt"
	"libp2p_port/internal/port"
	"libp2p_port/internal/proto_helpers"
	"time"
)

type Subscriber struct {
	subscriptions map[string]chan struct{}
	port          *port.Port
}

func NewSubscriber(p *port.Port) Subscriber {
	return Subscriber{subscriptions: make(map[string]chan struct{}), port: p}
}

func (s *Subscriber) Subscribe(topic_name string) {
	_, is_subscribed := s.subscriptions[topic_name]
	if !is_subscribed {
		s.subscriptions[topic_name] = make(chan struct{})
		go SubscribeToTopic(topic_name, s.subscriptions[topic_name], s.port)
	}
}

func (s *Subscriber) Unsubscribe(topic_name string) {
	s.subscriptions[topic_name] <- struct{}{}
	delete(s.subscriptions, topic_name)
}

func SubscribeToTopic(name string, stop chan struct{}, p *port.Port) {
	// This is mocked for the PoC. An actual subscription should call libp2p.
	i := 0
	for {
		select {
		case <-stop:
			return
		default:
			notification := proto_helpers.GossipNotification(name, fmt.Sprintf("Mock notification %d", i))
			p.SendNotification(&notification)
			i += 1
			time.Sleep(1 * time.Second)
		}
	}
}
