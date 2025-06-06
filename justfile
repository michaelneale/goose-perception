# Goose Voice Justfile
# Run commands with 'just <command>'

# Set default shell to bash with error handling
set shell := ["bash", "-c"]

# Default recipe (runs when you just type 'just')
default:
    @just --list


# Train the wake word classifier
train-classifier:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Training wake word classifier..."
    ./.use-hermit ./wake-classifier/train.sh

# Run the voice recognition system
run: 
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d "wake-classifier/model/final" ]; then
        just train-classifier
    fi
    
    echo "Starting observers in background..."
    cd observers 
    ./run-observations.sh &
    OBSERVER_PID=$!
    cd ..
    
    # Set up trap to kill the background process when this script exits
    trap 'echo "Shutting down observation script (PID: $OBSERVER_PID)..."; kill $OBSERVER_PID 2>/dev/null; touch /tmp/goose-perception-halt || true' EXIT
    
    echo "Starting Goose Voice..."
    ./.use-hermit ./run.sh

kill:
    echo "Stopping Goose Voice..."
    # Send a signal to the observers script to stop
    touch /tmp/goose-perception-halt || true
    # "Stopping any recipes running in the background..."
    ps aux | grep "recipe-" | grep -v grep | awk '{print $2}' | xargs -r kill -9

# Launch the console web interface
console:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Starting console on http://localhost:9922"
    # Start Chrome in app mode after a short delay to allow the server to start
    (sleep 2 && "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --app="http://localhost:9922" &>/dev/null || true) &
    # Run the console server (blocking)
    python3 console.py
