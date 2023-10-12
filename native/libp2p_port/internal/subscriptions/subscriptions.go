package gossipsub

import (
	"context"
	"fmt"
	"math"
	"time"

	"libp2p_port/internal/port"
	"libp2p_port/internal/proto_helpers"
	"libp2p_port/internal/utils"

	pubsub "github.com/libp2p/go-libp2p-pubsub"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
)

type Subscriber struct {
	subscriptions map[string]chan struct{}
	gsub          *pubsub.PubSub
	port          *port.Port
}

func NewSubscriber(p *port.Port, h host.Host) Subscriber {
	heartbeat := 700 * time.Millisecond
	gsubParams := pubsub.DefaultGossipSubParams()
	gsubParams.D = 8
	gsubParams.Dlo = 6
	gsubParams.HeartbeatInterval = heartbeat
	gsubParams.FanoutTTL = 60 * time.Second
	gsubParams.HistoryLength = 6
	gsubParams.HistoryGossip = 3

	thresholds := &pubsub.PeerScoreThresholds{
		GossipThreshold:             -4000,
		PublishThreshold:            -8000,
		GraylistThreshold:           -16000,
		AcceptPXThreshold:           100,
		OpportunisticGraftThreshold: 5,
	}
	scoreParams := &pubsub.PeerScoreParams{
		Topics:        make(map[string]*pubsub.TopicScoreParams),
		TopicScoreCap: 32.72,
		AppSpecificScore: func(p peer.ID) float64 {
			return 0
		},
		AppSpecificWeight:           1,
		IPColocationFactorWeight:    -35.11,
		IPColocationFactorThreshold: 10,
		IPColocationFactorWhitelist: nil,
		BehaviourPenaltyWeight:      -15.92,
		BehaviourPenaltyThreshold:   6,
		BehaviourPenaltyDecay:       math.Pow(0.01, 1/float64(10*32)),
		DecayInterval:               12 * time.Second,
		DecayToZero:                 0.01,
		RetainScore:                 100 * 32 * 12 * time.Second,
	}

	// TODO: add more options
	options := []pubsub.Option{
		pubsub.WithMessageSignaturePolicy(pubsub.StrictNoSign),
		pubsub.WithNoAuthor(),
		pubsub.WithMessageIdFn(utils.MsgID),
		pubsub.WithPeerScore(scoreParams, thresholds),
		pubsub.WithGossipSubParams(gsubParams),
		pubsub.WithSeenMessagesTTL(550 * heartbeat),
		pubsub.WithMaxMessageSize(10 * (1 << 20)), // 10 MB
	}

	gsub, err := pubsub.NewGossipSub(context.TODO(), h, options...)
	utils.PanicIfError(err)

	return Subscriber{subscriptions: make(map[string]chan struct{}), gsub: gsub, port: p}
}

func (s *Subscriber) Subscribe(topic_name string) {
	_, is_subscribed := s.subscriptions[topic_name]
	if !is_subscribed {
		s.subscriptions[topic_name] = make(chan struct{}, 1)
		go SubscribeToTopic(topic_name, s.subscriptions[topic_name], s.port)
	}
}

func (s *Subscriber) Unsubscribe(topic_name string) {
	_, is_subscribed := s.subscriptions[topic_name]
	if is_subscribed {
		s.subscriptions[topic_name] <- struct{}{}
		delete(s.subscriptions, topic_name)
	}
}

func SubscribeToTopic(name string, stop chan struct{}, p *port.Port) {
	// This is mocked for the PoC. An actual subscription should call libp2p.
	i := 0
	for {
		select {
		case <-stop:
			return
		default:
			notification := proto_helpers.GossipNotification(name, []byte(fmt.Sprintf("Mock notification %d", i)))
			p.SendNotification(&notification)
			i += 1
			time.Sleep(1 * time.Second)
		}
	}
}
