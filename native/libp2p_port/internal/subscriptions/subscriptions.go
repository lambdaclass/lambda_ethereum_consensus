package gossipsub

import (
	"context"
	"errors"
	"math"
	"time"

	"libp2p_port/internal/port"
	"libp2p_port/internal/proto_helpers"
	"libp2p_port/internal/utils"

	pubsub "github.com/libp2p/go-libp2p-pubsub"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
)

type subscription struct {
	Topic *pubsub.Topic
	CloseChannel chan struct{}
}

type Subscriber struct {
	subscriptions map[string]subscription
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

	gsub, err := pubsub.NewGossipSub(context.Background(), h, options...)
	utils.PanicIfError(err)

	return Subscriber{
		subscriptions: make(map[string]subscription),
		gsub:          gsub,
		port:          p,
	}
}

func (s *Subscriber) Subscribe(topicName string, handler []byte) error {
	_, isSubscribed := s.subscriptions[topicName]
	if isSubscribed {
		return errors.New("already subscribed")
	}
	topic, err := s.gsub.Join(topicName)
	utils.PanicIfError(err)
	ch := make(chan struct{}, 1)
	s.subscriptions[topicName] = subscription{
		Topic: topic,
		CloseChannel: ch,
	}
	sub, err := topic.Subscribe()
	utils.PanicIfError(err)
	go subscribeToTopic(sub, ch, handler, s.port)
	return nil
}

func subscribeToTopic(sub *pubsub.Subscription, stop chan struct{}, handler []byte, p *port.Port) {
	topic := sub.Topic()
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		<-stop
		cancel()
	}()
	for {
		msg, err := sub.Next(ctx)
		if err == context.Canceled {
			return
		}
		utils.PanicIfError(err)
		notification := proto_helpers.GossipNotification(topic, handler, msg.Data)
		p.SendNotification(&notification)
	}
}

func (s *Subscriber) Unsubscribe(topicName string) {
	sub, isSubscribed := s.subscriptions[topicName]
	if !isSubscribed {
		return
	}
	delete(s.subscriptions, topicName)
	sub.CloseChannel <- struct{}{}
	sub.Topic.Close()
}

func (s *Subscriber) Publish(topicName string, message []byte) {
	sub, isSubscribed := s.subscriptions[topicName]
	if !isSubscribed {
		panic("not subscribed to topic")
	}
	err := sub.Topic.Publish(context.Background(), message)
	utils.PanicIfError(err)
}
