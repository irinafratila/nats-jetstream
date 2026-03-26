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

# Function to wait for NATS to be ready and create stream
setup_jetstream() {
    nats context unselect 
    
    # Wait for NATS port to be accepting connections (simple TCP check)
    max_attempts=15
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if nc -z localhost 4222 2>/dev/null; then
            break
        fi

        attempt=$((attempt + 1))
        sleep 1
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "Warning: NATS port did not open within the timeout period"
        return 1
    fi
    
    # Check if stream already exists
    streams=$(nats stream ls -n 2>/dev/null || echo "")
    
    if [ -z "$streams" ]; then
        # Set a flag to indicate whether the command was successful
        success=false

        # Loop until the command is successful or the maximum number of attempts is reached
        while [ $success = false ]; do
            nats stream add ${STREAM_NAME} \
                --defaults \
                --subjects ${STREAM_SUBJECT} \
                --description "All event messages" \
                --storage "memory" \
                --replicas ${STREAM_REPLICAS} \
                --ack \
                --retention "interest" \
                --discard "old" \
                --max-age "8760h" \
                --allow-direct \
                --limit-consumer-max-pending 100

            # Check the exit code of the command
            if [ $? -eq 0 ]; then
                # The command was successful
                success=true
            else
                sleep 5
            fi
        done
    else
        echo "Streams already exist, skipping creation"
    fi

    nats context select sys-context
}

evict_peer() {
    echo "evicting peer ${HOSTNAME} from cluster.. "
    max_attempts=6
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        nats server cluster peer-remove ${HOSTNAME} --server nats://nats-dynamic:4222 --user admin --password pass --force --trace
        if [ $? -eq 0 ]; then
            echo "Peer evicted successfully"
            return 0
        fi
        echo "evict attempt $attempt failed, retrying..."
        attempt=$((attempt + 1))
        sleep 2
    done
    echo "Failed to evict peer after $max_attempts attempts"
    return 1
} 
# Start the executable in the background
"$@" &

# Store the NATS process PID
nats_pid=$!

nats context save sys-context \
  --server nats://localhost:4222 \
  --user admin \
  --password pass >/dev/null

nats context select sys-context

# Trap all signals relevant to NATS and forward them
trap_with_arg 'forward_signal' SIGKILL SIGQUIT SIGINT SIGUSR1 SIGHUP SIGUSR2 SIGTERM

setup_jetstream &

# Wait for all child process to finish
wait "$nats_pid"

evict_peer &
EVICT_PID=$!

wait $EVICT_PID
