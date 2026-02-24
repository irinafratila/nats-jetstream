# #!/usr/bin/env bash
while true; do
    clear
	NATS_URL=$(docker compose port nats-dynamic 4222) nats consumer ls event_stream  2>/dev/null 
	sleep 1
done 



