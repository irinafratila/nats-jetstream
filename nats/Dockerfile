FROM nats:alpine

# Install nats CLI - needed by the wrapper.
RUN apk add --no-cache curl && \
    curl -L https://github.com/nats-io/natscli/releases/download/v0.3.1/nats-0.3.1-linux-amd64.zip -o nats.zip && \
    unzip nats.zip && \
    mv nats-0.3.1-linux-amd64/nats /usr/local/bin/nats && \
    chmod +x /usr/local/bin/nats && \
    rm -rf nats.zip nats-0.3.1-linux-amd64

STOPSIGNAL SIGUSR2

COPY --chmod=0755 setup-jetstream.sh /usr/local/bin

ENV JS_STREAM_NAME="event_stream"
ENV JS_STREAM_REPLICAS="1"

ENTRYPOINT ["setup-jetstream.sh", "docker-entrypoint.sh"]
