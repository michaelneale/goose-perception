#!/bin/bash

# Script to continuously take screenshots and periodically run observation recipes
# Takes screenshots every 20 seconds
# Runs work summarization every 20 minutes
# Runs other recipes once per day if their output files don't exist or are out of date

# Create screenshots directory if it doesn't exist
SCREENSHOT_DIR="/tmp/screenshots"
mkdir -p "$SCREENSHOT_DIR"

# Create goose-perception directory if it doesn't exist
PERCEPTION_DIR="$HOME/.local/share/goose-perception"
mkdir -p "$PERCEPTION_DIR"

rm -f /tmp/goose-perception-halt

# Function to log activity to ACTIVITY-LOG.md
log_activity() {
  local message="$1"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "**${timestamp}**: ${message}" >> "$PERCEPTION_DIR/ACTIVITY-LOG.md"
  echo "$(date): $message"
}

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

# Function to run the work summarization logic
run_work_summarize() {
  echo "$(date): Running work summarization..."
  log_activity "Starting work summarization"
  
  # Run the work summarize recipe
  goose run --no-session --recipe recipe-work.yaml || echo "Work summarization failed, continuing..."
  
  # Clean up screenshots after summarization
  rm -f /tmp/screenshots/*
  
  echo "$(date): Work summarization complete and screenshots cleaned up."
  log_activity "Completed work summarization"
}

# Function to run a recipe if its output file doesn't exist or is older than 24 hours
run_recipe_if_needed() {
  local recipe="$1"
  local output_file="$2"
  local full_output_path="$PERCEPTION_DIR/$output_file"
  
  # Check if file doesn't exist or is older than 24 hours
  if [ ! -f "$full_output_path" ] || [ $(find "$full_output_path" -mtime +1 -print | wc -l) -gt 0 ]; then
    echo "$(date): Running $recipe recipe in background..."
    log_activity "Starting $recipe"
    # Run recipe in background and continue regardless of success/failure
    (
      goose run --no-session --recipe "$recipe" && {
        # Touch the output file to update its timestamp even if the recipe didn't modify it
        touch "$full_output_path"
        log_activity "Completed $recipe"
      } || log_activity "Failed $recipe"
    ) &
  else
    echo "$(date): Skipping $recipe, output file is up to date."
  fi
}

# Function to check and run all other recipes once per day
run_daily_recipes() {
  echo "$(date): Checking if daily recipes need to be run..."
  
  run_recipe_if_needed "recipe-contributions.yaml" "CONTRIBUTIONS.md"
  run_recipe_if_needed "recipe-interactions.yaml" "INTERACTIONS.md"
  run_recipe_if_needed "recipe-projects.yaml" "PROJECTS.md"
  run_recipe_if_needed "recipe-important-email.yaml" ".important-email"
  run_recipe_if_needed "recipe-interests.yaml" "INTERESTS.md"
  run_recipe_if_needed "recipe-work-personal.yaml" ".work-personal"
  
  echo "$(date): Daily recipe check complete."
}

echo "Starting continuous screenshot and observation process..."
echo "- Taking screenshots every 20 seconds"
echo "- Running work summarization every 20 minutes"
echo "- Running other recipes once per day if needed"
echo "Press Ctrl+C to stop"

# Log startup
log_activity "Starting observation system"

# Counter to track when to run summarization
COUNTER=0
MAX_COUNT=60  # 60 * 20 seconds = 20 minutes

# Daily counter to check other recipes once per day
DAILY_COUNTER=0
DAILY_MAX_COUNT=4320  # 4320 * 20 seconds = 24 hours

# Run daily recipes once at startup
echo "$(date): Running daily recipes at startup..."
run_daily_recipes

# Main loop
while true; do

  # check if /tmp/goose-perception-halt exists and exit if it does
  if [ -f "/tmp/goose-perception-halt" ]; then
    echo "$(date): Halting observation script as requested."
    log_activity "Observation system stopping"
    rm -f /tmp/goose-perception-halt
    exit 0
  fi
  # Capture screenshots
  capture_screenshots
  
  # Increment counters
  COUNTER=$((COUNTER + 1))
  DAILY_COUNTER=$((DAILY_COUNTER + 1))
  
  # Check if it's time to run work summarization
  if [ $COUNTER -ge $MAX_COUNT ]; then
    run_work_summarize
    COUNTER=0
  fi
  
  # Check if it's time to run daily recipes
  if [ $DAILY_COUNTER -ge $DAILY_MAX_COUNT ]; then
    run_daily_recipes
    DAILY_COUNTER=0
  fi
  
  # Wait 20 seconds before next capture
  sleep 20
done