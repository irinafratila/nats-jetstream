FROM nats:alpine

# Installing NATS CLI to be used in setup-jetstream.sh
COPY --from=natsio/nats-box:latest /usr/local/bin/nats /usr/local/bin/nats

# Puts NATS into Lame Duck Mode, where it evicts clients gradually.
# https://docs.nats.io/running-a-nats-service/nats_admin/signals
STOPSIGNAL SIGUSR2

COPY --chmod=0755 setup-jetstream.sh /usr/local/bin

COPY nats-server.conf /etc/nats/nats-server.conf

ENTRYPOINT ["setup-jetstream.sh"]
