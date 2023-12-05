package gossipsub

import (
	"context"
	"errors"
	"math"
	"sync"
	"time"

	"libp2p_port/internal/port"
	"libp2p_port/internal/proto_helpers"
	"libp2p_port/internal/utils"

	pubsub "github.com/libp2p/go-libp2p-pubsub"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
)

type subscription struct {
	Topic  *pubsub.Topic
	Cancel context.CancelFunc
}

type Subscriber struct {
	subscriptions   map[string]subscription
	pendingMessages sync.Map
	gsub            *pubsub.PubSub
	port            *port.Port
}

type GossipTracer struct {
	port *port.Port
}

func (g GossipTracer) AddPeer(p peer.ID, proto protocol.ID) {
	notification := proto_helpers.AddPeerNotification()
	g.port.SendNotification(&notification)
}

func (g GossipTracer) RemovePeer(p peer.ID) {
	notification := proto_helpers.RemovePeerNotification()
	g.port.SendNotification(&notification)
}

func (g GossipTracer) Join(topic string) {
	notification := proto_helpers.JoinNotification(topic)
	g.port.SendNotification(&notification)
}

func (g GossipTracer) Leave(topic string) {
	notification := proto_helpers.LeaveNofication(topic)
	g.port.SendNotification(&notification)
}

func (g GossipTracer) Graft(p peer.ID, topic string) {
	notification := proto_helpers.GraftNotification(topic)
	g.port.SendNotification(&notification)
}

func (g GossipTracer) Prune(p peer.ID, topic string) {
	notification := proto_helpers.PruneNotification(topic)
	g.port.SendNotification(&notification)
}

func (g GossipTracer) ValidateMessage(msg *pubsub.Message) {
	notification := proto_helpers.ValidateMessageNotification(*msg.Topic)
	g.port.SendNotification(&notification)
}

func (g GossipTracer) DeliverMessage(msg *pubsub.Message) {
	notification := proto_helpers.DeliverMessageNotification(*msg.Topic)
	g.port.SendNotification(&notification)
}

func (g GossipTracer) UndeliverableMessage(msg *pubsub.Message) {
	notification := proto_helpers.UndeliverableMessageNotification(*msg.Topic)
	g.port.SendNotification(&notification)
}

func (g GossipTracer) RejectMessage(msg *pubsub.Message, reason string) {
	notification := proto_helpers.RejectMessageNotification(*msg.Topic)
	g.port.SendNotification(&notification)
}

func (g GossipTracer) DuplicateMessage(msg *pubsub.Message) {
	notification := proto_helpers.DuplicateMessageNotification(*msg.Topic)
	g.port.SendNotification(&notification)
}

func (g GossipTracer) ThrottlePeer(p peer.ID) {
	// no-op
}

func (g GossipTracer) RecvRPC(rpc *pubsub.RPC) {
	// no-op
}

func (g GossipTracer) SendRPC(rpc *pubsub.RPC, p peer.ID) {
	// no-op
}

func (g GossipTracer) DropRPC(rpc *pubsub.RPC, p peer.ID) {
	// no-op
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
		pubsub.WithPeerOutboundQueueSize(600),
		pubsub.WithValidateQueueSize(600),
		pubsub.WithMaxMessageSize(10 * (1 << 20)), // 10 MB
		pubsub.WithRawTracer(GossipTracer{port: p}),
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
	sub := s.getSubscription(topicName)
	if sub.Cancel != nil {
		return errors.New("already subscribed")
	}
	port := s.port
	validator := func(ctx context.Context, p peer.ID, msg *pubsub.Message) pubsub.ValidationResult {
		id := []byte(msg.ID)
		notification := proto_helpers.GossipNotification(topicName, handler, id, msg.Data)
		port.SendNotification(&notification)
		ch := make(chan pubsub.ValidationResult)
		// NOTE: we use strings because []byte is mutable
		s.pendingMessages.Store(string(id), ch)
		return <-ch
	}
	s.gsub.RegisterTopicValidator(topicName, validator)
	ctx, cancel := context.WithCancel(context.Background())
	sub.Cancel = cancel
	topicSub, err := sub.Topic.Subscribe()
	utils.PanicIfError(err)
	go subscribeToTopic(topicSub, ctx, s.gsub)
	s.subscriptions[topicName] = sub
	return nil
}

func (s *Subscriber) Unsubscribe(topicName string) {
	sub, isSubscribed := s.subscriptions[topicName]
	if !isSubscribed {
		return
	}
	delete(s.subscriptions, topicName)
	sub.Cancel()
	sub.Topic.Close()
}

func (s *Subscriber) Validate(msgId []byte, intResult int) {
	result := pubsub.ValidationResult(intResult)
	// NOTE: we use strings because []byte is mutable
	ch, loaded := s.pendingMessages.LoadAndDelete(string(msgId))
	if !loaded {
		return
	}
	if result != pubsub.ValidationAccept && result != pubsub.ValidationReject && result != pubsub.ValidationIgnore {
		panic("invalid validation result")
	}
	ch.(chan pubsub.ValidationResult) <- result
}

func (s *Subscriber) Publish(topicName string, message []byte) {
	sub := s.getSubscription(topicName)
	err := sub.Topic.Publish(context.Background(), message)
	utils.PanicIfError(err)
}

// NOTE: we send the message to the port in the validator.
// Here we just flush received messages and handle unsubscription.
func subscribeToTopic(sub *pubsub.Subscription, ctx context.Context, gsub *pubsub.PubSub) {
	topic := sub.Topic()
	for {
		_, err := sub.Next(ctx)
		if err == context.Canceled {
			break
		}
	}
	gsub.UnregisterTopicValidator(topic)
}

func (s *Subscriber) getSubscription(topicName string) subscription {
	sub, isSubscribed := s.subscriptions[topicName]
	if !isSubscribed {
		topic, err := s.gsub.Join(topicName)
		utils.PanicIfError(err)
		sub = subscription{
			Topic: topic,
		}
		s.subscriptions[topicName] = sub
	}
	return sub
}
