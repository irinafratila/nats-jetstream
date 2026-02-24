export NATS_URL=$(docker compose port nats-dynamic 4222)

STREAM=event_stream

nats consumer ls -j -n "$STREAM" \
	| jq -r '.[] | if type == "object" then (.name // .consumer // empty) else . end' \
	| while IFS= read -r consumer; do
			[ -z "$consumer" ] && continue
			info=$(nats consumer info "$STREAM" "$consumer" -j)
			unprocessed=$(echo "$info" | jq -r '.num_pending // 0')
			leader=$(echo "$info" | jq -r '.cluster.leader // "unknown"')

			if [ "$unprocessed" -gt 0 ]; then
				echo "$consumer Unprocessed Messages: $unprocessed Leader: $leader"
			##	nats consumer cluster step-down "$STREAM" "$consumer" ## Commented out to prevent cleaning up the consumers
			fi
			
		done
