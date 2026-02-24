static:
	docker compose --profile static up -d --build

dynamic:
	docker compose --profile dynamic up -d --build

consumer-ls:
	NATS_URL=$(docker compose port nats-dynamic 4222) nats consumer ls event_stream

stop:
	docker compose --profile dynamic down

monitor-primary-container:
	docker exec -it nats-jetstream-nats-dynamic-1 sh -lc 'tail -f /tmp/log'
