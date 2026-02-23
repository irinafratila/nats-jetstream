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
		natsAddress     = "nats://nats-dynamic:4222,nats://nats-static-1:4222"
		streamName      = "event_stream"
		namespace       = os.Getenv("HOSTNAME")
		publisherNumStr = os.Getenv("PUBLISHER_NUM")
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

		slog.Info("Initiating Connect sequence..")

		// create jetstream client
		js, err := jetstream.New(c)
		if err != nil {
			panic(fmt.Errorf("error creating NATS JetStream client: %w", err))
		}

		err = waitForStream(ctx, js, streamName, 10*time.Second)
		if err != nil {
			panic(fmt.Errorf("error getting stream: %w", err))
		}

		publsiherNum, err := strconv.Atoi(publisherNumStr)
		if err != nil {
			panic(fmt.Errorf("Error convering pub number env var to int: %w", err))
		}

		err = startPublishers(ctx, js, namespace, publsiherNum)
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

func startPublishers(ctx context.Context, js jetstream.JetStream, namespace string, publishers int) error {
	for i := range publishers {
		go func() {
			count := 0

			ticker := time.NewTicker(500 * time.Millisecond)
			defer ticker.Stop()

			for {
				_, err := js.Publish(ctx, fmt.Sprintf("event.%v.%v", i, count), []byte(namespace))
				if err != nil {
					panic(fmt.Errorf("publishing message: %w", err))
				}

				count++

				select {
				case <-ctx.Done():
					slog.Info("stopping publisher", "idx", i)

					return
				case <-ticker.C:
				}
			}
		}()
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
