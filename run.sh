#!/bin/bash

# Trap to handle script termination
trap 'echo "Stopping script..."; kill -TERM $PID 2>/dev/null; exit' INT TERM


# Create recordings directory if it doesn't exist
RECORDINGS_DIR="recordings"
mkdir -p "$RECORDINGS_DIR"

# Configuration - these should match the defaults in listen.py
CONTEXT_SECONDS=30     # Seconds of context to keep before wake word
SILENCE_SECONDS=3      # Seconds of silence to end active listening
FUZZY_THRESHOLD=80     # Fuzzy matching threshold (0-100)
CLASSIFIER_THRESHOLD=0.6  # Confidence threshold for classifier (0-1)

# Set environment variables to suppress warnings
export TOKENIZERS_PARALLELISM=false

# Run the listen.py script with default device detection
# The script already has device detection capabilities
python listen.py \
  --recordings-dir "$RECORDINGS_DIR" \
  --context-seconds $CONTEXT_SECONDS \
  --silence-seconds $SILENCE_SECONDS \
  --use-lightweight-model \
  --fuzzy-threshold $FUZZY_THRESHOLD \
  --classifier-threshold $CLASSIFIER_THRESHOLD \
  "$@" &
PID=$!

# Wait for the process to complete
wait $PID