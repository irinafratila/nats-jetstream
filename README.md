# Jetstream Issue Repro

We enabled JetStream across our NATS cluster running in ECS and observed that consumers were not being consistently replicated to newly added nodes. We have been able to reproduce the issue locally: when scaling down from a 4-node cluster to 3, some consumers stop receiving message deliveries entirely, they show unprocessed messages and messages on the stream pile up.

## Stream creation wrapper

To make sure that a stream always exists to create consumers against, we're using a bash wrapper script in the NATS container. The script starts NATS, waits for NATS to be available, then repeatedly tries to create a stream until successful. The wrapper also forwards any singals sent to the container to the NATS process.
On NATS process exit, the wrapper puts the server into Lame Duck Mode and removes it from the RAFT group via ```nats server cluster peer-remove```.

## Repro

With Docker and the NATS CLI installed, run the following:

```sh
docker compose up -d --build  --scale nats-dynamic=3
```
Scale the cluster to 4 nodes:

```sh
docker compose up -d --no-recreate --scale nats-dynamic=4
```
All is well so far, node 4 joins the RAFT group as expected. 
```sh
╭──────────────────────────────────────────────────────────────────────────────────────────────────────╮
│                                           JetStream Summary                                          │
├───────────────┬─────────┬─────────┬───────────┬──────────┬───────┬────────┬──────┬─────────┬─────────┤
│ Server        │ Cluster │ Streams │ Consumers │ Messages │ Bytes │ Memory │ File │ API Req │ Pending │
├───────────────┼─────────┼─────────┼───────────┼──────────┼───────┼────────┼──────┼─────────┼─────────┤
│ 44a16aab2811  │ backend │ 0       │ 0         │ 0        │ 0 B   │ 0 B    │ 0 B  │ 0       │       0 │
│ 6cde0f378d67* │ backend │ 1       │ 10        │ 0        │ 0 B   │ 0 B    │ 0 B  │ 19      │       0 │
│ 7c385b9b1109  │ backend │ 1       │ 10        │ 0        │ 0 B   │ 0 B    │ 0 B  │ 1,171   │       0 │
│ 80f5280f2f8f  │ backend │ 1       │ 10        │ 0        │ 0 B   │ 0 B    │ 0 B  │ 5       │       0 │
├───────────────┼─────────┼─────────┼───────────┼──────────┼───────┼────────┼──────┼─────────┼─────────┤
│               │         │ 3       │ 30        │ 0        │ 0 B   │ 0 B    │ 0 B  │ 1,195   │       0 │
╰───────────────┴─────────┴─────────┴───────────┴──────────┴───────┴────────┴──────┴─────────┴─────────╯

╭───────────────────────────────────────────────────────────────────────╮
│          RAFT Meta Group Information - Lead cluster: backend          │
├─────────────────┬──────────┬────────┬─────────┬────────┬────────┬─────┤
│ Connection Name │ ID       │ Leader │ Current │ Online │ Active │ Lag │
├─────────────────┼──────────┼────────┼─────────┼────────┼────────┼─────┤
│ 44a16aab2811    │ rL2G5TjJ │        │ true    │ true   │ 465ms  │ 0   │
│ 6cde0f378d67    │ HL5BadrF │ yes    │ true    │ true   │ 0s     │ 0   │
│ 7c385b9b1109    │ L56AtEfh │        │ true    │ true   │ 465ms  │ 0   │
│ 80f5280f2f8f    │ SWw1ylKk │        │ true    │ true   │ 465ms  │ 0   │
╰─────────────────┴──────────┴────────┴─────────┴────────┴────────┴─────╯
```

Next, remove node 1:

```sh
docker stop nats-jetstream-nats-dynamic-1
docker rm nats-jetstream-nats-dynamic-1
```

The issue presents itself as consumers with "unprocessed" messages.

```sh
╭─────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│                                                Consumers                                                │
├─────────────────────────┬─────────────┬─────────────────────┬─────────────┬─────────────┬───────────────┤
│ Name                    │ Description │ Created             │ Ack Pending │ Unprocessed │ Last Delivery │
├─────────────────────────┼─────────────┼─────────────────────┼─────────────┼─────────────┼───────────────┤
│ ff515921143d-consumer-0 │             │ 2026-03-27 15:35:22 │           0 │           0 │ 399ms         │
│ ff515921143d-consumer-1 │             │ 2026-03-27 15:35:22 │           0 │           0 │ 399ms         │
│ ff515921143d-consumer-2 │             │ 2026-03-27 15:35:22 │           0 │           0 │ 398ms         │
│ ff515921143d-consumer-3 │             │ 2026-03-27 15:35:22 │           0 │           0 │ 399ms         │
│ ff515921143d-consumer-4 │             │ 2026-03-27 15:35:22 │           0 │           0 │ 399ms         │
│ ff515921143d-consumer-5 │             │ 2026-03-27 15:35:22 │           0 │          69 │ 41.64s        │
│ ff515921143d-consumer-9 │             │ 2026-03-27 15:35:23 │           0 │           0 │ 398ms         │
╰─────────────────────────┴─────────────┴─────────────────────┴─────────────┴─────────────┴───────────────╯
```
Once finished with the test, bring the cluster down:

```sh
docker compose down
```

### Repeatability

The issue happens 100% of the time. 
