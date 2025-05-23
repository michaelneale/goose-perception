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
    ./run-observatons.sh &
    OBSERVER_PID=$!
    cd ..
    
    # Set up trap to kill the background process when this script exits
    trap 'echo "Shutting down observation script (PID: $OBSERVER_PID)..."; kill $OBSERVER_PID 2>/dev/null; touch /tmp/goose-perception-halt || true' EXIT
    
    echo "Starting Goose Voice..."
    ./.use-hermit ./run.sh
