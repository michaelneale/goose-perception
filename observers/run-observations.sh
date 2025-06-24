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

# Create automated-actions and adapted-observers directories
mkdir -p "$PERCEPTION_DIR/automated-actions/daily"
mkdir -p "$PERCEPTION_DIR/automated-actions/weekly"
mkdir -p "$PERCEPTION_DIR/adapted-observers"

# Copy .goosehints file to each directory
GOOSEHINTS_FILE="./observers/.goosehints"
cp "$GOOSEHINTS_FILE" "$PERCEPTION_DIR/automated-actions/daily/.goosehints"
cp "$GOOSEHINTS_FILE" "$PERCEPTION_DIR/automated-actions/weekly/.goosehints"
cp "$GOOSEHINTS_FILE" "$PERCEPTION_DIR/adapted-observers/.goosehints"

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
  local weekday_only="${4:-false}"  # Optional 4th parameter, defaults to false
  local marker_file="$PERCEPTION_DIR/.recipe-last-run-$(basename "$recipe" .yaml)"
  local full_output_path="$PERCEPTION_DIR/$output_file"
  
  # Check for adapted recipe first
  local adapted_recipe_path="$PERCEPTION_DIR/adapted-observers/$(basename "$recipe")"
  local recipe_to_run="$recipe"
  
  if [ -f "$adapted_recipe_path" ]; then
    echo "$(date): Found adapted recipe: $adapted_recipe_path"
    recipe_to_run="$adapted_recipe_path"
  fi
  
  # Check if weekday_only is enabled and today is weekend
  if [ "$weekday_only" = "weekday-only" ]; then
    local day_of_week=$(date +%u)  # 1=Monday, 7=Sunday
    if [ $day_of_week -gt 5 ]; then  # 6=Saturday, 7=Sunday
      echo "$(date): Skipping $recipe, weekday-only enabled and today is weekend."
      return 0
    fi
  fi
  
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
    
    # Run the recipe
    echo "$(date): Running $recipe_to_run recipe ($frequency)..."
    log_activity "Starting $recipe_to_run ($frequency)"
    GOOSE_CONTEXT_STRATEGY="truncate" goose run --no-session --recipe "$recipe_to_run" && {
      touch "$marker_file"
      [ -n "$output_file" ] && touch "$full_output_path"
      log_activity "Completed $recipe_to_run"
    } || log_activity "Failed $recipe_to_run"
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
    echo "$(date): Running $recipe_to_run recipe ($frequency)..."
    log_activity "Starting $recipe_to_run ($frequency)"
    # Run recipe and wait for completion
    local current_hour=$(date +%H)
    local session_name="${recipe_to_run}-${current_hour}"
    goose run --no-session --recipe "$recipe_to_run" && {
      # Update marker file on success
      touch "$marker_file"
      # Touch the output file to update its timestamp even if the recipe didn't modify it
      [ -n "$output_file" ] && touch "$full_output_path"
      log_activity "Completed $recipe_to_run"
    } || log_activity "Failed $recipe_to_run"
  else
    echo "$(date): Skipping $recipe, ran recently (frequency: $frequency)."
  fi
}

# Function to run screenshot capture loop asynchronously
run_screenshot_loop() {
  echo "$(date): Starting screenshot capture loop (PID: $$)..."
  while true; do
    # Check for halt file
    if [ -f "/tmp/goose-perception-halt" ]; then
      echo "$(date): Screenshot loop halting as requested."
      break
    fi
    
    # Capture screenshots
    capture_screenshots
    
    # Wait 20 seconds before next capture
    sleep 20
  done
  echo "$(date): Screenshot loop stopped."
}

# Function to check and run all recipes based on their frequencies
run_scheduled_recipes() {
  echo "$(date): Checking scheduled recipes..."
  
  # Check for automated recipes in ~/.local/share/goose-perception/automated-actions/
  local automated_dir="$HOME/.local/share/goose-perception/automated-actions"
  
  # Check daily recipes
  if [ -d "$automated_dir/daily" ]; then
    echo "$(date): Checking daily automated recipes..."
    for recipe in "$automated_dir/daily"/*.yaml; do
      if [ -f "$recipe" ]; then
        local recipe_name=$(basename "$recipe")
        echo "$(date): Found daily recipe: $recipe_name"
        run_recipe_if_needed "$recipe" "daily" ""
      fi
    done
  fi
  
  # Check weekly recipes
  if [ -d "$automated_dir/weekly" ]; then
    echo "$(date): Checking weekly automated recipes..."
    for recipe in "$automated_dir/weekly"/*.yaml; do
      if [ -f "$recipe" ]; then
        local recipe_name=$(basename "$recipe")
        echo "$(date): Found weekly recipe: $recipe_name"
        run_recipe_if_needed "$recipe" "weekly" ""
      fi
    done
  fi
  
  # Work summary recipe (every 20 minutes, weekdays only)
  run_recipe_if_needed "recipe-work.yaml" "20m" "WORK.md" "weekday-only"  
  
  run_recipe_if_needed "recipe-contributions.yaml" "hourly" "CONTRIBUTIONS.md" "weekday-only"
  run_recipe_if_needed "recipe-focus.yaml" "55m" ".focus" "weekday-only"
  run_recipe_if_needed "recipe-hypedoc.yaml" "weekly" ".hypedoc"

  
  run_recipe_if_needed "recipe-garbage-collect.yaml" "weekly" ".garbage-collect" "weekday-only"
  run_recipe_if_needed "recipe-projects.yaml" "morning" "PROJECTS.md" "weekday-only"
  run_recipe_if_needed "recipe-work-personal.yaml" "evening" ".work-personal"
  run_recipe_if_needed "recipe-interactions.yaml" "hourly" "INTERACTIONS.md"
  run_recipe_if_needed "recipe-important-attention-message.yaml" "hourly" ".important-messages" "weekday-only"
  run_recipe_if_needed "recipe-interests.yaml" "daily" "INTERESTS.md"
  run_recipe_if_needed "recipe-morning-attention.yaml" "morning" ".morning-attention" "weekday-only"
  run_recipe_if_needed "recipe-upcoming.yaml" "afternoon" ".upcoming" "weekday-only"
  run_recipe_if_needed "recipe-what-working-on.yaml" "evening" ".working-on" "weekday-only"
  run_recipe_if_needed "recipe-optimize.yaml" "weekly" ".optimize"
  run_recipe_if_needed "recipe-meetings-actions.yaml" "morning" ".meetings-afternoon" "weekday-only"
  run_recipe_if_needed "recipe-apps-preferences.yaml" "daily" ".apps-preferences" "weekday-only"
  run_recipe_if_needed "recipe-meetings-actions.yaml" "evening" ".meetings-evening" "weekday-only"
  run_recipe_if_needed "recipe-start-fixing.yaml" "evening" ".fixing"
  run_recipe_if_needed "recipe-background-tasks.yaml" "15m" ".background-tasks"
  run_recipe_if_needed "recipe-background-technical.yaml" "15m" ".background-technical"
  run_recipe_if_needed "recipe-follow-up-content.yaml" "morning" ".follow-up-content" "weekday-only"
  run_recipe_if_needed "recipe-take-time-back.yaml" "weekly" ".give-time-back" "weekday-only"
  run_recipe_if_needed "../adapt-recipes.yaml" "weekly" ".adapting"

  
  
  
  echo "$(date): Scheduled recipe check complete."
}

echo "Starting continuous screenshot and observation process..."
echo "- Taking screenshots every 20 seconds (async)"
echo "- Checking and running recipes based on their frequencies every 1 minute"
echo "- Recipes can be: hourly, daily, weekly, or custom (e.g., 20m, 2h, 3d)"
echo "Press Ctrl+C to stop"

# Log startup
log_activity "Starting observation system"

# Start screenshot capture loop in background
run_screenshot_loop &
SCREENSHOT_PID=$!
echo "$(date): Screenshot loop started in background (PID: $SCREENSHOT_PID)"

# Function to cleanup on exit
cleanup() {
  echo "$(date): Observer cleanup starting..."
  log_activity "Observation system stopping"
  
  # Create halt file to stop screenshot loop
  touch /tmp/goose-perception-halt
  
  # Kill any running recipe processes
  echo "$(date): Stopping recipe processes..."
  pkill -KILL -f "goose run" 2>/dev/null || true
  pkill -KILL -f "python.*goose" 2>/dev/null || true
  
  # Kill screenshot loop if it's still running
  if kill -0 $SCREENSHOT_PID 2>/dev/null; then
    echo "$(date): Stopping screenshot loop (PID: $SCREENSHOT_PID)..."
    kill -KILL $SCREENSHOT_PID 2>/dev/null || true
  fi
  
  # Clean up files
  rm -f /tmp/goose-perception-halt
  
  echo "$(date): Observer cleanup complete."
  exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Run scheduled recipes once at startup
echo "$(date): Running scheduled recipes at startup..."
run_scheduled_recipes

# Main loop - focus on recipe management
while true; do
  # Check if /tmp/goose-perception-halt exists and exit if it does
  if [ -f "/tmp/goose-perception-halt" ]; then
    echo "$(date): Halting observation script as requested."
    cleanup
  fi
  
  # Run scheduled recipes (this can block when recipes need to be run)
  run_scheduled_recipes
  
  # Wait 1 minute before next recipe check
  sleep 60  # 1 minute
done