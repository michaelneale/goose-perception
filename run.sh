#!/bin/bash

# Trap to handle script termination
trap 'echo "Stopping script..."; kill -TERM $PID 2>/dev/null; exit' INT TERM

# Activate virtual environment
source .venv/bin/activate

# Create recordings directory if it doesn't exist
RECORDINGS_DIR="recordings"
mkdir -p "$RECORDINGS_DIR"

# Run the listen.py script with the MacBook Pro microphone
python listen.py --model base --device 2 --wake-word "goose" --recordings-dir "$RECORDINGS_DIR" "$@" &
PID=$!

# Wait for the process to complete
wait $PID