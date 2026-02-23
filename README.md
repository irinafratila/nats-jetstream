# Jetstream Issue Repro

In the migration of our services platform from regular NATS publishers and subscribers, to Jetstream publishers and consumers, we noticed an issue. **Some consumers would be successfully created but would never process any messages.** The Jetstream client SDK does not seem to report any errors, and the consumers seem to be setup and active. This repo is an attempt to isolate and reproduce the problem.

## Dynamic vs Static clustering

Our platform uses a service discovery feature to populate a DNS record with all the IP addresses of our NATS nodes. This means we can set the same routes address for every node and let the nodes discover each other via DNS. This has worked reliably for forming a cluster in AWS ECS for many years. We have reproduced this "dynamic" setup here using docker compose and a single service scaled to three container instances.

During our research we noticed the more typical way of configuring a cluster is to run three static nodes with unique addresses and routes values, i.e. statically configuring each node to be aware of the other two. So for testing we have also reproduced this "static" setup.

Distinguishing these two cluster setups is important as we're only able to reproduce our issue with the "dynamic" setup.

## Stream creation wrapper

To make sure that a stream always exists to create consumers against, we're using a bash wrapper script in the NATS container. The script starts NATS, waits for NATS to be available, then repeatedly tries to create a stream until successful. The wrapper also forwards any singals sent to the container to the NATS process.

## Repro

With Docker and the NATS CLI installed, run the following:

```sh
# Start the dynamic NATS cluster along with a number of consumers and publisher
# apps.
docker compose --profile dynamic up -d --build
# List the consumers for our event stream
NATS_URL=$(docker compose port nats-dynamic 4222) nats consumer ls event_stream
```

The issue presents itself as consumers with "unprocessed" messages and "last delivery" times of "never" (full table has been trimmed).

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│                                                 Consumers                                                │
├──────────────────────────┬─────────────┬─────────────────────┬─────────────┬─────────────┬───────────────┤
│ Name                     │ Description │ Created             │ Ack Pending │ Unprocessed │ Last Delivery │
├──────────────────────────┼─────────────┼─────────────────────┼─────────────┼─────────────┼───────────────┤
│ ad4882ce6cc9-consumer-0  │             │ 2026-02-23 09:53:53 │           0 │           0 │ 207ms         │
│ ad4882ce6cc9-consumer-1  │             │ 2026-02-23 09:53:53 │           0 │           0 │ 208ms         │
│ ad4882ce6cc9-consumer-10 │             │ 2026-02-23 09:53:54 │           0 │          88 │ never         │
│ ad4882ce6cc9-consumer-11 │             │ 2026-02-23 09:53:54 │           0 │          88 │ never         │
│ ad4882ce6cc9-consumer-12 │             │ 2026-02-23 09:53:54 │           0 │           0 │ 207ms         │
│ ad4882ce6cc9-consumer-13 │             │ 2026-02-23 09:53:54 │           0 │          87 │ never         │
│ ad4882ce6cc9-consumer-14 │             │ 2026-02-23 09:53:55 │           0 │           0 │ 207ms         │
╰──────────────────────────┴─────────────┴─────────────────────┴─────────────┴─────────────┴───────────────╯
```
Once finished with the test, bring the cluster down:

```sh
docker compose --profile dynamic down
```

### Repeatability

The issue does not happen 100% of the time, but seems more likely with more consumers and publishers running - adjust these values in the docker-compose.yaml file.

### Repro fails with static cluster

The same test can be performed with the statically configured cluster and does not present the same issue:

```sh
# Start the static NATS cluster along with a number of consumers and publisher
# apps.
docker compose --profile static up -d --build
# List the consumers for our event stream
nats consumer ls event_stream

# Stop all services
docker compose --profile static down
```
