static:
	docker compose --profile static up -d --build

pub-msg:
	docker exec -it js-app /bin/sh -c "nats --server nats://nats1:4222 publish --jetstream --count 10 event.1.a '{}'"

stop:
	docker compose --profile dynamic down

dynamic:
	docker compose --profile dynamic up -d --build

consumer-ls:
	NATS_URL=$(docker compose port nats-dynamic 4222) nats consumer ls event_stream