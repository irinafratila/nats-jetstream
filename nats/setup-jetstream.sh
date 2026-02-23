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
    echo "Waiting for NATS to be ready..."
    
    # Wait for NATS port to be accepting connections (simple TCP check)
    max_attempts=15
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        echo "Checking NATS port (attempt $((attempt + 1))/$max_attempts)..."

        if nc -z localhost 4222 2>/dev/null; then
            echo "NATS port 4222 is open!"
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
    echo "Checking for existing streams..."
    streams=$(nats stream ls -n 2>/dev/null || echo "")
    
    if [ -z "$streams" ]; then
        echo "No streams found, creating event_stream..."

        # Set a flag to indicate whether the command was successful
        success=false

        # Loop until the command is successful or the maximum number of attempts is reached
        while [ $success = false ]; do
            nats stream add ${JS_STREAM_NAME} \
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
                --limit-consumer-max-pending 100

            # Check the exit code of the command
            if [ $? -eq 0 ]; then
                # The command was successful
                success=true
            else
                sleep 5
            fi
        done
    
        echo "Stream event_stream created successfully!"
    else
        echo "Streams already exist, skipping creation"
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
