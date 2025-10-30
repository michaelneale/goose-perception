#!/bin/bash

# Script to continuously take screenshots and periodically run observation recipes
# Takes screenshots every 20 seconds
# Runs work summarization every 20 minutes
# Runs other recipes once per day if their output files don't exist or are out of date

# Force public PyPI usage (override any corporate/internal registry settings)
export UV_INDEX_URL="https://pypi.org/simple"
export PIP_INDEX_URL="https://pypi.org/simple"

# Create screenshots directory if it doesn't exist
SCREENSHOT_DIR="/tmp/screenshots"
mkdir -p "$SCREENSHOT_DIR"

# Create goose-perception directory if it doesn't exist
PERCEPTION_DIR="$HOME/.local/share/goose-perception"
mkdir -p "$PERCEPTION_DIR"

ensure_observer_config() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local cfg="$PERCEPTION_DIR/observer-config.json"
  if [ ! -f "$cfg" ]; then
    cp "$SCRIPT_DIR/observer-config.default.json" "$cfg"
    
    # Check for system Goose config and use those values if available
    local goose_config="$HOME/.config/goose/config.yaml"
    if [ -f "$goose_config" ]; then
      # Extract GOOSE_MODEL and GOOSE_PROVIDER from system config
      local system_model=$(grep "^GOOSE_MODEL:" "$goose_config" 2>/dev/null | cut -d: -f2- | xargs)
      local system_provider=$(grep "^GOOSE_PROVIDER:" "$goose_config" 2>/dev/null | cut -d: -f2- | xargs)
      
      # Add model/provider fields to config if system values exist
      if [ -n "$system_model" ]; then
        jq ".globals.goose_model = \"$system_model\"" "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
        echo "$(date): Using system GOOSE_MODEL: $system_model"
      fi
      
      if [ -n "$system_provider" ]; then
        jq ".globals.goose_provider = \"$system_provider\"" "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
        echo "$(date): Using system GOOSE_PROVIDER: $system_provider"
      fi
    else
      echo "$(date): WARNING: No system Goose config found at $goose_config"
      echo "$(date): Model and provider will need to be configured in observer-config.json or via environment variables"
    fi
    
    echo "$(date): Created $cfg from default"
  fi
}


cfg() { jq -r "$1" "$PERCEPTION_DIR/observer-config.json"; }
cfg_int() { jq -r "$1" "$PERCEPTION_DIR/observer-config.json" | awk '{print int($0)}'; }

ensure_observer_config

# Export model/provider/context from config (available to all goose runs)
# Only export if values exist in config, otherwise goose will use system defaults
model_value="$(cfg '.globals.goose_model')"
provider_value="$(cfg '.globals.goose_provider')"

if [ "$model_value" != "null" ] && [ -n "$model_value" ]; then
  export GOOSE_MODEL="$model_value"
  echo "$(date): Using GOOSE_MODEL from config: $model_value"
fi

if [ "$provider_value" != "null" ] && [ -n "$provider_value" ]; then
  export GOOSE_PROVIDER="$provider_value"
  echo "$(date): Using GOOSE_PROVIDER from config: $provider_value"
fi

# Always export context strategy as it has a default
export GOOSE_CONTEXT_STRATEGY_DEFAULT="$(cfg '.globals.goose_context_strategy')"

# Loop tunables from config
NOTES_CHECK_INTERVAL_SEC=$(cfg_int '.globals.notes_check_interval_sec')
SCREENSHOT_LOOP_INTERVAL_SEC=$(cfg_int '.globals.screenshot_loop_interval_sec')

# Create automated-actions and adapted-observers directories
mkdir -p "$PERCEPTION_DIR/automated-actions/daily"
mkdir -p "$PERCEPTION_DIR/automated-actions/weekly"
mkdir -p "$PERCEPTION_DIR/adapted-observers"

# Copy .goosehints file to each directory
GOOSEHINTS_FILE="./observers/.goosehints"
cp "$GOOSEHINTS_FILE" "$PERCEPTION_DIR/automated-actions/daily/.goosehints" 2>/dev/null || true
cp "$GOOSEHINTS_FILE" "$PERCEPTION_DIR/automated-actions/weekly/.goosehints" 2>/dev/null || true
cp "$GOOSEHINTS_FILE" "$PERCEPTION_DIR/adapted-observers/.goosehints" 2>/dev/null || true

rm -f /tmp/goose-perception-halt

# Function to log activity to ACTIVITY-LOG.md
log_activity() {
  local message="$1"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "**${timestamp}**: ${message}" >> "$PERCEPTION_DIR/ACTIVITY-LOG.md"
  echo "$(date): $message"
}

# Function to run the comprehensive screenshotting script
capture_screenshots() {
  echo "$(date): Running screenshot processing..."

  # Get the directory where this script is located
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Run the screenshotting script
  "$SCRIPT_DIR/run-screenshotting.sh"

  echo "$(date): Screenshot processing completed"
}

# Function to check Apple Notes for items requiring attention
check_notes() {
  echo "$(date): Checking Apple Notes..."

  # Get the directory where this script is located
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Run the notes checking script
  "$SCRIPT_DIR/run-notes.sh"

  echo "$(date): Notes check completed"
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
    # Validate the adapted recipe. If valid, use it.
    if goose recipe validate "$adapted_recipe_path" > /dev/null 2>&1; then
      recipe_to_run="$adapted_recipe_path"
    else
      echo "$(date): Adapted recipe $adapted_recipe_path is invalid. Sticking with original recipe"
    fi
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
    # Use default context strategy from config unless overridden in environment
    GOOSE_CONTEXT_STRATEGY="${GOOSE_CONTEXT_STRATEGY:-$GOOSE_CONTEXT_STRATEGY_DEFAULT}" goose run --no-session --recipe "$recipe_to_run" && {
      touch "$marker_file"
      [ -n "$output_file" ] && touch "$full_output_path"
      log_activity "Completed $recipe_to_run"

      # Clear /tmp/screenshots after recipe-work.yaml completes successfully
      if [[ "$(basename "$recipe_to_run")" == "recipe-work.yaml" ]]; then
        echo "$(date): Clearing /tmp/screenshots after recipe-work.yaml completion..."
        rm -f /tmp/screenshots/*        
      fi
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
    GOOSE_CONTEXT_STRATEGY="${GOOSE_CONTEXT_STRATEGY:-$GOOSE_CONTEXT_STRATEGY_DEFAULT}" goose run --no-session --recipe "$recipe_to_run" && {
      # Update marker file on success
      touch "$marker_file"
      # Touch the output file to update its timestamp even if the recipe didn't modify it
      [ -n "$output_file" ] && touch "$full_output_path"
      log_activity "Completed $recipe_to_run"

      # Clear /tmp/screenshots after recipe-work.yaml completes successfully
      if [[ "$(basename "$recipe_to_run")" == "recipe-work.yaml" ]]; then
        echo "$(date): Clearing /tmp/screenshots after recipe-work.yaml completion..."
        rm -f /tmp/screenshots/*
        log_activity "Cleared /tmp/screenshots after recipe-work.yaml"
      fi
    } || log_activity "Failed $recipe_to_run"
  else
    echo "$(date): Skipping $recipe, ran recently (frequency: $frequency)."
  fi
}
# Function to run all observers from config
run_all_config_observers() {
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
  
  # Each item: id, freq, output, weekday_only
  jq -c '.observers[] | [ .id, .freq, (.output // ""), (if .weekday_only then "weekday-only" else "" end) ]' \
     "$PERCEPTION_DIR/observer-config.json" |
  while IFS= read -r row; do
    id=$(echo "$row" | jq -r '.[0]')
    freq=$(echo "$row" | jq -r '.[1]')
    out=$(echo "$row" | jq -r '.[2]')
    wk=$(echo "$row" | jq -r '.[3]')
    run_recipe_if_needed "$id.yaml" "$freq" "$out" "$wk"
  done
  
  echo "$(date): Scheduled recipe check complete."
}


# Function to run screenshot capture loop asynchronously
run_screenshot_loop() {
  echo "$(date): Starting screenshot processing loop (PID: $$)..."
  while true; do
    # Check for halt file
    if [ -f "/tmp/goose-perception-halt" ]; then
      echo "$(date): Screenshot processing loop halting as requested."
      break
    fi

    # Run comprehensive screenshot processing
    capture_screenshots

    # Wait N seconds before next capture (from config)
    sleep "${SCREENSHOT_LOOP_INTERVAL_SEC:-60}"
  done
  echo "$(date): Screenshot processing loop stopped."
}

echo "Starting continuous screenshot and observation process..."
echo "- Running comprehensive screenshot processing (OCR + AI analysis) every ${SCREENSHOT_LOOP_INTERVAL_SEC:-60}s (async)"
echo "- Screenshot images are automatically cleaned up after processing"
echo "- Processed results saved to timestamped files in /tmp/screenshots/"
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

# Initialize notes check tracking (from config)
LAST_NOTES_CHECK=$(date +%s)

# Main loop - focus on recipe management
while true; do
  # Check if /tmp/goose-perception-halt exists and exit if it does
  if [ -f "/tmp/goose-perception-halt" ]; then
    echo "$(date): Halting observation script as requested."
    cleanup
  fi

  # Check Apple Notes per configured cadence (default 300s)
  CURRENT_TIME=$(date +%s)
  TIME_SINCE_NOTES_CHECK=$((CURRENT_TIME - LAST_NOTES_CHECK))
  if [ $TIME_SINCE_NOTES_CHECK -ge ${NOTES_CHECK_INTERVAL_SEC:-300} ]; then
    check_notes
    LAST_NOTES_CHECK=$CURRENT_TIME
  fi

  # Run scheduled recipes (this can block when recipes need to be run)
  run_all_config_observers

  # Wait 1 minute before next recipe check
  sleep 60  # 1 minute
done
