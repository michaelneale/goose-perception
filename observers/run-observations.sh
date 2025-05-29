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



# Function to run a recipe if needed based on frequency
run_recipe_if_needed() {
  local recipe="$1"
  local frequency="$2"
  local output_file="$3"
  local marker_file="$PERCEPTION_DIR/.recipe-last-run-$(basename "$recipe" .yaml)"
  local full_output_path="$PERCEPTION_DIR/$output_file"
  
  # Handle time-of-day frequencies (morning, afternoon, evening)
  if [[ "$frequency" =~ ^(morning|afternoon|evening)$ ]]; then
    local current_hour=$(date +%H)
    
    # Check if we've already run today
    if [ -f "$marker_file" ]; then
      local marker_date=$(date -r "$marker_file" +%Y-%m-%d)
      local today_date=$(date +%Y-%m-%d)
      if [ "$marker_date" = "$today_date" ]; then
        echo "$(date): Skipping $recipe, already ran today."
        return 0
      fi
    fi
    
    # Check if it's the right time to run
    case "$frequency" in
      "morning")
        # Morning: run anytime (first thing)
        ;;
      "afternoon")
        # Afternoon: only run after 12 PM
        if [ $current_hour -lt 12 ]; then
          return 0
        fi
        ;;
      "evening")
        # Evening: only run after 6 PM
        if [ $current_hour -lt 18 ]; then
          return 0
        fi
        ;;
    esac
    
    # Run the recipe with random offset based on frequency
    local offset_minutes=$((5 + RANDOM % 11))  # Random delay 5-15 minutes for time-based recipes
    local offset=$((offset_minutes * 60))
    echo "$(date): Running $recipe recipe ($frequency) in background (offset: ${offset_minutes}m)..."
    log_activity "Starting $recipe ($frequency)"
    (
      sleep $offset
      goose run --no-session --recipe "$recipe" && {
        touch "$marker_file"
        [ -n "$output_file" ] && touch "$full_output_path"
        log_activity "Completed $recipe"
      } || log_activity "Failed $recipe"
    ) &
    return 0
  fi
  
  # Handle regular frequencies (hourly, daily, weekly, custom)
  local find_time=""
  case "$frequency" in
    "hourly")
      find_time="-mmin +60"
      ;;
    "daily")
      find_time="-mtime +1"
      ;;
    "weekly")
      find_time="-mtime +7"
      ;;
    *"m")
      # Extract minutes (e.g., "20m" -> 20)
      local minutes="${frequency%m}"
      find_time="-mmin +$minutes"
      ;;
    *"h")
      # Extract hours (e.g., "2h" -> 120 minutes)
      local hours="${frequency%h}"
      local minutes=$((hours * 60))
      find_time="-mmin +$minutes"
      ;;
    *"d")
      # Extract days (e.g., "3d" -> 3)
      local days="${frequency%d}"
      find_time="-mtime +$days"
      ;;
    *)
      echo "Unknown frequency format: $frequency"
      return 1
      ;;
  esac
  
  # Check if marker file doesn't exist or is older than frequency
  if [ ! -f "$marker_file" ] || [ $(find "$marker_file" $find_time -print | wc -l) -gt 0 ]; then
    # Calculate offset based on frequency
    local offset_minutes
    local offset_label
    case "$frequency" in
      "hourly"|*"h")
        # For hourly+ frequencies: 5-15 minute offset
        offset_minutes=$((5 + RANDOM % 11))
        offset_label="${offset_minutes}m"
        ;;
      "daily"|*"d"|"weekly")
        # For daily+ frequencies: 5-15 minute offset  
        offset_minutes=$((5 + RANDOM % 11))
        offset_label="${offset_minutes}m"
        ;;
      *)
        # For shorter frequencies (minutes): 30 second - 2 minute offset
        local offset_seconds=$((30 + RANDOM % 91))  # 30-120 seconds
        offset_minutes=0
        local offset=$offset_seconds
        offset_label="${offset_seconds}s"
        ;;
    esac
    
    if [ $offset_minutes -gt 0 ]; then
      local offset=$((offset_minutes * 60))
    fi
    
    echo "$(date): Running $recipe recipe ($frequency) in background (offset: ${offset_label})..."
    log_activity "Starting $recipe ($frequency)"
    # Run recipe in background and continue regardless of success/failure
    (
      sleep $offset
      goose run --no-session --recipe "$recipe" && {
        # Update marker file on success
        touch "$marker_file"
        # Touch the output file to update its timestamp even if the recipe didn't modify it
        [ -n "$output_file" ] && touch "$full_output_path"
        log_activity "Completed $recipe"
      } || log_activity "Failed $recipe"
    ) &
  else
    echo "$(date): Skipping $recipe, ran recently (frequency: $frequency)."
  fi
}

# Function to check and run all recipes based on their frequencies
run_scheduled_recipes() {
  echo "$(date): Checking scheduled recipes..."
  
  # Work recipe (every 20 minutes)
  run_recipe_if_needed "recipe-work.yaml" "20m" "WORK.md"
  
  # Time-based recipes
  run_recipe_if_needed "recipe-contributions.yaml" "evening" "CONTRIBUTIONS.md"
  run_recipe_if_needed "recipe-focus.yaml" "55m" ".focus"
  run_recipe_if_needed "recipe-goose-sessions.yaml" "60m" ".goose-sessions"
  run_recipe_if_needed "recipe-hypedoc.yaml" "weekly" ".hypedoc"

  run_recipe_if_needed "recipe-projects.yaml" "morning" "PROJECTS.md"
  run_recipe_if_needed "recipe-work-personal.yaml" "evening" ".work-personal"
  run_recipe_if_needed "recipe-day-improvements.yaml" "evening" "DAY-IMPROVEMENTS.md"
  
  # Regular frequency recipes
  run_recipe_if_needed "recipe-interactions.yaml" "daily" "INTERACTIONS.md"
  run_recipe_if_needed "recipe-important-email.yaml" "hourly" ".important-email"
  run_recipe_if_needed "recipe-interests.yaml" "daily" "INTERESTS.md"
  run_recipe_if_needed "recipe-morning-attention.yaml" "morning" ".morning-attention"
  run_recipe_if_needed "recipe-upcoming.yaml" "afternoon" ".upcoming"
  run_recipe_if_needed "recipe-what-working-on.yaml" "evening" ".working-on"
  run_recipe_if_needed "recipe-optimize.yml" "weekly" ".optimize"
  
  
  echo "$(date): Scheduled recipe check complete."
}

echo "Starting continuous screenshot and observation process..."
echo "- Taking screenshots every 20 seconds"
echo "- Checking and running recipes based on their frequencies every 5 minutes"
echo "- Recipes can be: hourly, daily, weekly, or custom (e.g., 20m, 2h, 3d)"
echo "Press Ctrl+C to stop"

# Log startup
log_activity "Starting observation system"

# Counter to track when to check recipes (every 5 minutes)
COUNTER=0
MAX_COUNT=15  # 15 * 20 seconds = 5 minutes

# Run scheduled recipes once at startup
echo "$(date): Running scheduled recipes at startup..."
run_scheduled_recipes

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
  
  # Increment counter
  COUNTER=$((COUNTER + 1))
  
  # Check recipes every 5 minutes
  if [ $COUNTER -ge $MAX_COUNT ]; then
    run_scheduled_recipes
    COUNTER=0
  fi
  
  # Wait 20 seconds before next capture
  sleep 20
done