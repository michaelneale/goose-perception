#!/bin/bash

# Local observers script - simplified version with ollama image descriptions
# Takes screenshots every 20 seconds
# Every 20 minutes: describes images with ollama, then runs work analysis
# Runs other simple recipes on schedule

# Create directories
SCREENSHOT_DIR="/tmp/screenshots"
DESCRIPTION_DIR="/tmp/screenshot-descriptions"
mkdir -p "$SCREENSHOT_DIR"
mkdir -p "$DESCRIPTION_DIR"

# Create goose-perception directory if it doesn't exist
PERCEPTION_DIR="$HOME/.local/share/goose-perception"
mkdir -p "$PERCEPTION_DIR"

rm -f /tmp/goose-perception-halt

# Function to log activity
log_activity() {
  local message="$1"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "**${timestamp}**: ${message}" >> "$PERCEPTION_DIR/ACTIVITY-LOG.md"
  echo "$(date): $message"
}

# Function to capture screenshots
capture_screenshots() {
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  NUM_DISPLAYS=$(system_profiler SPDisplaysDataType | grep "Resolution" | wc -l | xargs)

  echo "$(date): Capturing $NUM_DISPLAYS display(s)..."

  if [ "$NUM_DISPLAYS" -eq 0 ]; then
    echo "No displays detected. Skipping capture."
    return 1
  fi

  # Take screenshots of each display
  for (( i=1; i<=$NUM_DISPLAYS; i++ ))
  do
    screencapture -x -D $i "$SCREENSHOT_DIR/screen_${TIMESTAMP}_display$i.png"
  done

  echo "$(date): Screenshots saved to $SCREENSHOT_DIR"
}

# Function to describe screenshots with ollama and clean up
describe_and_cleanup_screenshots() {
  echo "$(date): Describing screenshots with ollama..."
  log_activity "Starting screenshot description with ollama"
  
  # Check if ollama is available
  if ! command -v ollama &> /dev/null; then
    echo "$(date): ollama not found, skipping description"
    log_activity "ollama not available, skipping description"
    return 1
  fi

  local description_count=0
  
  # Process each screenshot
  for screenshot in "$SCREENSHOT_DIR"/*.png; do
    if [ -f "$screenshot" ]; then
      local basename=$(basename "$screenshot" .png)
      local description_file="$DESCRIPTION_DIR/${basename}.txt"
      local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
      
      echo "$(date): Describing $screenshot..."
      
      # Use ollama to describe the image
      if ollama run llava "Describe this screenshot in detail, focusing on what work or activities are visible: $screenshot" > "$description_file" 2>/dev/null; then
        # Add timestamp to the description
        echo "" >> "$description_file"
        echo "Screenshot taken at: $timestamp" >> "$description_file"
        echo "Original file: $screenshot" >> "$description_file"
        description_count=$((description_count + 1))
      else
        echo "$(date): Failed to describe $screenshot"
        rm -f "$description_file"
      fi
      
      # Remove the screenshot after processing
      rm -f "$screenshot"
    fi
  done
  
  echo "$(date): Described $description_count screenshots"
  log_activity "Described $description_count screenshots with ollama"
}

# Function to run a recipe if needed
run_recipe_if_needed() {
  local recipe="$1"
  local frequency="$2"
  local output_file="$3"
  local marker_file="$PERCEPTION_DIR/.recipe-last-run-$(basename "$recipe" .yaml)"
  local full_output_path="$PERCEPTION_DIR/$output_file"
  
  # Handle time-based frequencies
  local find_time=""
  case "$frequency" in
    "20m")
      find_time="-mmin +20"
      ;;
    "hourly")
      find_time="-mmin +60"
      ;;
    "daily")
      find_time="-mtime +1"
      ;;
    "weekly")
      find_time="-mtime +7"
      ;;
    *)
      echo "Unknown frequency format: $frequency"
      return 1
      ;;
  esac
  
  # Check if marker file doesn't exist or is older than frequency
  if [ ! -f "$marker_file" ] || [ $(find "$marker_file" $find_time -print | wc -l) -gt 0 ]; then
    echo "$(date): Running $recipe recipe ($frequency)..."
    log_activity "Starting $recipe ($frequency)"
    
    # Run recipe and update marker on success
    if GOOSE_CONTEXT_STRATEGY="truncate" goose run --no-session --recipe "local-observers/$recipe"; then
      touch "$marker_file"
      [ -n "$output_file" ] && touch "$full_output_path"
      log_activity "Completed $recipe"
    else
      log_activity "Failed $recipe"
    fi
  else
    echo "$(date): Skipping $recipe, ran recently (frequency: $frequency)."
  fi
}

# Function to run work analysis (called every 20 minutes)
run_work_analysis() {
  echo "$(date): Running work analysis..."
  
  # First describe screenshots with ollama
  describe_and_cleanup_screenshots
  
  # Then run the work analysis recipe
  run_recipe_if_needed "recipe-work-simple.yaml" "20m" "WORK.md"
}

# Function to check and run other scheduled recipes
run_scheduled_recipes() {
  echo "$(date): Checking other scheduled recipes..."
  
  # Run other simple recipes
  run_recipe_if_needed "recipe-focus-simple.yaml" "hourly" "FOCUS.md"
  run_recipe_if_needed "recipe-contributions-simple.yaml" "daily" "CONTRIBUTIONS.md"
  run_recipe_if_needed "recipe-interactions-simple.yaml" "daily" "INTERACTIONS.md"
  
  echo "$(date): Scheduled recipe check complete."
}

echo "Starting local observers process..."
echo "- Taking screenshots every 20 seconds"
echo "- Describing screenshots with ollama and running work analysis every 20 minutes"
echo "- Running other recipes: focus (hourly), contributions (daily), interactions (daily)"
echo "Press Ctrl+C to stop"

# Log startup
log_activity "Starting local observers system"

# Counters
SCREENSHOT_COUNTER=0
RECIPE_COUNTER=0
WORK_ANALYSIS_COUNTER=0

# 20 seconds = 1 screenshot cycle
# 5 minutes = 15 screenshot cycles (for other recipes check)
# 20 minutes = 60 screenshot cycles (for work analysis)
MAX_RECIPE_COUNT=15    # Check other recipes every 5 minutes
MAX_WORK_COUNT=60      # Work analysis every 20 minutes

# Run scheduled recipes once at startup
echo "$(date): Running scheduled recipes at startup..."
run_scheduled_recipes

# Main loop
while true; do
  # Check if halt file exists
  if [ -f "/tmp/goose-perception-halt" ]; then
    echo "$(date): Halting local observers as requested."
    log_activity "Local observers system stopping"
    rm -f /tmp/goose-perception-halt
    exit 0
  fi
  
  # Capture screenshots
  capture_screenshots
  
  # Increment counters
  SCREENSHOT_COUNTER=$((SCREENSHOT_COUNTER + 1))
  RECIPE_COUNTER=$((RECIPE_COUNTER + 1))
  WORK_ANALYSIS_COUNTER=$((WORK_ANALYSIS_COUNTER + 1))
  
  # Run work analysis every 20 minutes
  if [ $WORK_ANALYSIS_COUNTER -ge $MAX_WORK_COUNT ]; then
    run_work_analysis
    WORK_ANALYSIS_COUNTER=0
  fi
  
  # Check other recipes every 5 minutes
  if [ $RECIPE_COUNTER -ge $MAX_RECIPE_COUNT ]; then
    run_scheduled_recipes
    RECIPE_COUNTER=0
  fi
  
  # Wait 20 seconds before next capture
  sleep 20
done