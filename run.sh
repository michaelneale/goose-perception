#!/bin/bash

# Trap to handle script termination
trap 'echo "Stopping script..."; kill -TERM $PID 2>/dev/null; exit' INT TERM

# Activate virtual environment
source .venv/bin/activate

# Create recordings directory if it doesn't exist
RECORDINGS_DIR="recordings"
mkdir -p "$RECORDINGS_DIR"

# Configuration
CONTEXT_SECONDS=30  # Seconds of context to keep before wake word
SILENCE_SECONDS=3   # Seconds of silence to end active listening

# Set environment variables to suppress warnings
export TOKENIZERS_PARALLELISM=false

# Run the listen.py script with default device detection
# The script already has device detection capabilities
python listen.py \
  --model base \
  --recordings-dir "$RECORDINGS_DIR" \
  --context-seconds $CONTEXT_SECONDS \
  --silence-seconds $SILENCE_SECONDS \
  "$@" &
PID=$!

# Wait for the process to complete
wait $PID