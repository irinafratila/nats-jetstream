package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	var (
		natsAddress    = "nats://nats-dynamic:4222,nats://nats-static-1:4222"
		streamName     = "event_stream"
		namespace      = os.Getenv("HOSTNAME")
		consumerNumStr = os.Getenv("CONSUMER_NUM")
	)

	// create nats connection
	nc, err := nats.Connect(natsAddress, nats.ConnectHandler(func(c *nats.Conn) {
		slog.Info(
			"NATS client connected",
			"cluster", c.ConnectedClusterName(),
			"connected server", c.ConnectedServerId(),
			"visible cluster servers", strings.Join(c.Servers(), ","),
			"discovered cluster servers", strings.Join(c.DiscoveredServers(), ","),
		)

		// create jetstream client
		js, err := jetstream.New(c)
		if err != nil {
			panic(fmt.Errorf("error creating NATS JetStream client: %w", err))
		}

		err = waitForStream(ctx, js, streamName, 10*time.Second)
		if err != nil {
			panic(fmt.Errorf("error getting stream: %w", err))
		}

		consumerNumber, err := strconv.Atoi(consumerNumStr)
		if err != nil {
			panic(fmt.Errorf("Error converting consumer num env var to int: %w", err))
		}

		err = startConsumers(ctx, js, streamName, namespace, consumerNumber)
		if err != nil {
			panic(fmt.Errorf("creating consumers: %w", err))
		}
	}))
	if err != nil {
		panic(fmt.Errorf("connecting to NATS: %w", err))
	}

	<-ctx.Done()
	slog.Info("Shutting down")

	nc.Close()
}

func startConsumers(ctx context.Context, js jetstream.JetStream, streamName, namespace string, consumers int) error {
	for i := range consumers {
		consumerName := namespace + "-consumer-" + strconv.Itoa(i)
		subjects := []string{"event." + strconv.Itoa(i) + ".>"}

		// slog.Info("Creating consumer", "name", consumerName, "subjects", subjects)

		// create a bunch of consumers
		cons, err := js.CreateOrUpdateConsumer(ctx, streamName, jetstream.ConsumerConfig{
			Durable:           consumerName,
			FilterSubjects:    subjects,
			DeliverPolicy:     jetstream.DeliverNewPolicy,
			AckPolicy:         jetstream.AckExplicitPolicy,
			AckWait:           5 * time.Second,
			InactiveThreshold: 14 * 24 * time.Hour, // 2 weeks
			MaxAckPending:     100,
			MaxDeliver:        100,
			Replicas:          0, // Inherit from the stream
		})
		if err != nil {
			panic(fmt.Errorf(time.Now().String(), "creating jetstream consumer for %s - %s: %w", subjects, consumerName, err))
		}

		_, err = cons.Consume(func(msg jetstream.Msg) {
			defer func() {
				if err := msg.Ack(); err != nil {
					panic(fmt.Errorf("acknowledging message: %w", err))
				}
			}()

			// slog.Info("Received message", "subject", msg.Subject(), "data", string(msg.Data()))
		})
		if err != nil {
			return fmt.Errorf("creating consumer %v: %w", i, err)
		}
	}

	return nil
}

func waitForStream(
	ctx context.Context,
	js jetstream.JetStream,
	streamName string,
	timeout time.Duration,
) error {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	for {
		stream, err := js.Stream(ctx, streamName)
		if err != nil {
			slog.Error("Error fetching stream", "err", err.Error())
		} else {
			slog.Info("stream is ready", "stream", stream.CachedInfo().Config.Name)

			return nil
		}

		select {
		case <-ctx.Done():
			return fmt.Errorf("timeout waiting for stream %s", streamName)
		case <-ticker.C:
		}
	}
}
