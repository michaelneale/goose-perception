#!/bin/bash

# Script to check Apple Notes for items requiring goose attention
# This script is called periodically from run-observations.sh

# Get script directory for finding helper scripts
SCRIPT_DIR="$(dirname "$0")"

# Find the project root directory (one level up from observers)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use the virtual environment's Python interpreter
PYTHON_PATH="$PROJECT_ROOT/.venv/bin/python3"

# Fall back to system python3 if venv doesn't exist
if [ ! -f "$PYTHON_PATH" ]; then
    PYTHON_PATH="python3"
fi

# Create goose-perception directory if it doesn't exist
PERCEPTION_DIR="$HOME/.local/share/goose-perception"
mkdir -p "$PERCEPTION_DIR"

# Function to log activity to ACTIVITY-LOG.md
log_activity() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "**${timestamp}**: ${message}" >> "$PERCEPTION_DIR/ACTIVITY-LOG.md"
    echo "$(date): $message"
}

# Check if notes.py exists
if [ ! -f "$SCRIPT_DIR/notes.py" ]; then
    echo "$(date): Error: notes.py not found in $SCRIPT_DIR"
    exit 1
fi

# Run notes.py to check for notes requiring attention
echo "$(date): Checking Apple Notes for items requiring attention..."

# Execute notes.py with the appropriate Python interpreter
OUTPUT=$("$PYTHON_PATH" "$SCRIPT_DIR/notes.py" 2>&1)
EXIT_CODE=$?

# Check if the command was successful
if [ $EXIT_CODE -eq 0 ]; then
    echo "$OUTPUT"
    
    # Parse the output to determine if notes were found
    if echo "$OUTPUT" | grep -q "Found [1-9][0-9]* note(s) requiring attention"; then
        # Extract the number of notes found
        NOTE_COUNT=$(echo "$OUTPUT" | grep -oE "Found [0-9]+ note\(s\)" | grep -oE "[0-9]+")
        log_activity "Checked Apple Notes - found $NOTE_COUNT note(s) requiring attention"
        echo "$(date): Notes check completed - $NOTE_COUNT note(s) need processing"
    else
        log_activity "Checked Apple Notes - no notes requiring attention"
        echo "$(date): Notes check completed - no notes requiring attention"
    fi
else
    echo "$(date): Error running notes.py:"
    echo "$OUTPUT"
    log_activity "Failed to check Apple Notes - error code $EXIT_CODE"
    exit $EXIT_CODE
fi

# Output the location of the notes-todo file for reference
echo "$(date): Notes status written to: $PERCEPTION_DIR/notes-todo.txt"
