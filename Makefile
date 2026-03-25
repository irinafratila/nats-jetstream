start:
	docker compose up -d --build  --scale nats-dynamic=3

add_one:
	docker compose up -d --no-recreate --scale nats-dynamic=4

consumer-ls:
	NATS_URL=$(docker compose port nats-dynamic 4222) nats consumer ls event_stream

down:
	docker compose down

remove:
	docker stop nats-jetstream-nats-dynamic-1
	docker rm nats-jetstream-nats-dynamic-1 -f