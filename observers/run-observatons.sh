#!/bin/bash

# Script to continuously take screenshots and periodically summarize them
# Takes screenshots every 20 seconds
# Runs summarization every 20 minutes

# Create screenshots directory if it doesn't exist
SCREENSHOT_DIR="/tmp/screenshots"
mkdir -p "$SCREENSHOT_DIR"

# Create goose-perception directory if it doesn't exist
PERCEPTION_DIR="$HOME/.local/share/goose-perception"
mkdir -p "$PERCEPTION_DIR"

# initialize with data
#goose run --recipe recipe-contributions.yaml --no-session
#goose run --recipe recipe-interactions.yaml --no-session
#goose run --recipe recipe-projects.yaml --no-session

# Function to capture screenshots of all displays
capture_screenshots() {
  # Get current timestamp for unique filenames
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

  # Get the number of displays
  NUM_DISPLAYS=$(system_profiler SPDisplaysDataType | grep "Resolution" | wc -l | xargs)

  echo "$(date): Capturing $NUM_DISPLAYS display(s)..."

  if [ "$NUM_DISPLAYS" -eq 0 ]; then
    echo "No displays detected. Skipping capture."
    return 1
  fi

  # Take screenshots of each display individually
  for (( i=1; i<=$NUM_DISPLAYS; i++ ))
  do
    screencapture -x -D $i "$SCREENSHOT_DIR/screen_${TIMESTAMP}_display$i.png"
  done

  echo "$(date): Screenshots saved to $SCREENSHOT_DIR"
}

# Function to run the summarization logic
run_summarize() {
  echo "$(date): Running summarization..."
  
  # Run the summarize script logic
  goose run --no-session --recipe recipe-work.yaml
  
  # Run recent_docs_apps.py to collect file and app data
  echo "$(date): Collecting recent files and running applications data..."
  "$(dirname "$0")/recent_docs_apps.py" 2 30
  
  # Clean up screenshots after summarization
  rm /tmp/screenshots/*
  
  echo "$(date): Summarization complete and screenshots cleaned up."
}

echo "Starting continuous screenshot and summarization process..."
echo "- Taking screenshots every 20 seconds"
echo "- Running summarization every 20 minutes"
echo "Press Ctrl+C to stop"

# Counter to track when to run summarization
COUNTER=0
MAX_COUNT=60  # 60 * 20 seconds = 20 minutes

# Main loop
while true; do
  # Capture screenshots
  capture_screenshots
  
  # Increment counter
  COUNTER=$((COUNTER + 1))
  
  # Check if it's time to run summarization
  if [ $COUNTER -ge $MAX_COUNT ]; then
    run_summarize
    COUNTER=0
  fi
  
  # Wait 20 seconds before next capture
  sleep 20
done