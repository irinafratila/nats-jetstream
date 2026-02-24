#!/bin/sh

# Function to forward signals to the child process (NATS).
forward_signal() {
    echo "Forwarding signal $1 to PID $nats_pid"
    kill -s $1 "$nats_pid"
}

# Function to setup signal traps where the handling function will receive the
# signal type as an arg.
trap_with_arg() {
    func="$1" ; shift
    for sig ; do
        trap "$func $sig" "$sig"
    done
}

retry_cmd() {
    max_attempts="$1"
    delay_seconds="$2"
    shift 2

    attempt=1
    while [ "$attempt" -le "$max_attempts" ]; do
        if "$@"; then
            return 0
        fi

        echo "Command failed (attempt ${attempt}/${max_attempts}): $*" >> /tmp/log
        if [ "$attempt" -eq "$max_attempts" ]; then
            return 1
        fi

        sleep "$delay_seconds"
        attempt=$((attempt + 1))
    done
}

# Function to wait for NATS to be ready and create stream
setup_jetstream() {   
    ## Get the container ID from Docker Socket
    container_id="$(cat /etc/hostname 2>/dev/null || true)"
    if [ -z "$container_id" ] || [ ! -S /var/run/docker.sock ]; then
        return 1
    fi

    ## Get the container name so we can identify the 1st one to run
    container_json="$(curl -s --unix-socket /var/run/docker.sock "http://localhost/containers/${container_id}/json" 2>/dev/null || true)"
    container_name="$(printf '%s\n' "$container_json" | sed -n 's/.*"Name":"\/\([^"]*\)".*/\1/p' | head -n 1)"

        echo "Cont_name: $container_name" > /tmp/log 2>&1
        echo "Cont_json: $container_json" >> /tmp/log 2>&1
        echo "Cont_id: $container_id" >> /tmp/log 2>&1

    ## Ensure only the first container run actually interacts with NATS
    if [ "$container_name" = "nats-jetstream-nats-dynamic-1" ]; then
            echo "Running inside the 1st nats container. Setting up JetStream Stream." >> /tmp/log 2>&1
    ## I hate the retry logic
            if retry_cmd 10 2 nats stream add ${JS_STREAM_NAME} \
                --defaults \
                --subjects "event.>" \
                --description "All event messages" \
                --storage "memory" \
                --replicas ${JS_STREAM_REPLICAS} \
                --ack \
                --retention "interest" \
                --discard "old" \
                --max-age "8760h" \
                --allow-direct \
                --limit-consumer-max-pending 100 >> /tmp/log 2>&1; then
            echo "Finished setting up JetStream Stream." >> /tmp/log 2>&1
        else
            echo "Failed to set up JetStream Stream after retries." >> /tmp/log 2>&1
        fi
    ## Sleep 60 to let consumers get setup
    sleep 60

    ## Loop through all orphaned consumers and request leader step down if there are unprocessed messages
    nats consumer ls -j -n event_stream 2>> /tmp/log \
        | jq -r '.[] | if type == "object" then (.name // .consumer // empty) else . end' 2>> /tmp/log \
        | while IFS= read -r consumer; do
                [ -z "$consumer" ] && continue
                info=$(nats consumer info "event_stream" "$consumer" -j 2>> /tmp/log || true)
                [ -z "$info" ] && continue
                unprocessed=$(echo "$info" | jq -r '.num_pending // 0')
                leader=$(echo "$info" | jq -r '.cluster.leader // "unknown"')

                if [ "$unprocessed" -gt 0 ]; then
                    echo "$consumer Unprocessed Messages: $unprocessed Leader: $leader" >> /tmp/log 2>&1
                    nats consumer cluster step-down "${JS_STREAM_NAME}" "$consumer" >> /tmp/log 2>&1
                fi
            done

        else
            echo "Not primary NATS container (${container_name}); skipping JetStream setup and leader cleanup." >> /tmp/log 2>&1
        fi

}


# Start the executable in the background
"$@" &

# Store the NATS process PID
nats_pid=$!

# Trap all signals relevant to NATS and forward them
trap_with_arg 'forward_signal' SIGKILL SIGQUIT SIGINT SIGUSR1 SIGHUP SIGUSR2 SIGTERM

# Setup JetStream in the background
setup_jetstream &

# Wait for all child process to finish
wait
