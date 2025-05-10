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

# Find the first available input device and its channel count
echo "Detecting available audio input devices..."
DEVICE_INFO=$(python -c "
import sounddevice as sd
import json

devices = sd.query_devices()
input_devices = [(i, d) for i, d in enumerate(devices) if d['max_input_channels'] > 0]

if input_devices:
    idx, device = input_devices[0]
    print(json.dumps({'device': idx, 'channels': device['max_input_channels']}))
else:
    print(json.dumps({'device': 'None', 'channels': 0}))
")

# Parse the JSON output
DEVICE=$(echo $DEVICE_INFO | python -c "import sys, json; print(json.load(sys.stdin)['device'])")
CHANNELS=$(echo $DEVICE_INFO | python -c "import sys, json; print(json.load(sys.stdin)['channels'])")

if [ "$DEVICE" == "None" ]; then
    echo "Error: No audio input device found. Please check your microphone connection."
    exit 1
fi

echo "Using audio input device: $DEVICE with $CHANNELS channel(s)"

# Run the listen.py script with the detected microphone
python listen.py \
  --model base \
  --device $DEVICE \
  --channels $CHANNELS \
  --recordings-dir "$RECORDINGS_DIR" \
  --context-seconds $CONTEXT_SECONDS \
  --silence-seconds $SILENCE_SECONDS \
  "$@" &
PID=$!

# Wait for the process to complete
wait $PID