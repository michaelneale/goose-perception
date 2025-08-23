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

ensure_observer_config() {
  local cfg="$PERCEPTION_DIR/observer-config.json"
  mkdir -p "$PERCEPTION_DIR"
  if [ -f "$cfg" ]; then
    return 0
  fi
  cat > "$cfg" <<'JSON'
{
  "globals": {
    "goose_provider": "ollama",
    "goose_model": "qwen3:14b",
    "goose_context_strategy": "truncate",

    "notes_check_interval_sec": 300,          // run-observations.sh cadence
    "screenshot_loop_interval_sec": 60,       // run-observations.sh cadence (comment said 20s, was 60s in code)
    "local_screenshot_loop_interval_sec": 20, // local-observations.sh cadence
    "local_work_analysis_interval_sec": 1200, // 20 minutes (local)
    "local_other_recipes_interval_sec": 300   // 5 minutes (local)
  },

  "paths": {
    "screenshot_dir": "/tmp/screenshots",
    "screenshot_descriptions_dir": "/tmp/screenshot-descriptions",
    "perception_dir": "~/.local/share/goose-perception",
    "adapted_observers_dir": "~/.local/share/goose-perception/adapted-observers",
    "automated_actions_daily_dir": "~/.local/share/goose-perception/automated-actions/daily",
    "automated_actions_weekly_dir": "~/.local/share/goose-perception/automated-actions/weekly"
  },

  "observers": [
    { "id": "recipe-work-daily",                 "freq": "morning",  "weekday_only": true,  "output": "WORK.md" },
    { "id": "recipe-work-daily",                 "freq": "afternoon","weekday_only": true,  "output": "WORK.md" },

    { "id": "recipe-contributions",              "freq": "weekly",   "weekday_only": true,  "output": "CONTRIBUTIONS.md" },
    { "id": "recipe-focus",                      "freq": "weekly",   "weekday_only": true,  "output": ".focus" },
    { "id": "recipe-hypedoc",                    "freq": "weekly",   "weekday_only": false, "output": ".hypedoc" },

    { "id": "recipe-important-attention-message","freq": "120m",     "weekday_only": true,  "output": ".important-messages" },

    { "id": "recipe-background-tasks",           "freq": "180m",     "weekday_only": true,  "output": ".background-tasks" },
    { "id": "recipe-background-technical",       "freq": "180m",     "weekday_only": true,  "output": ".background-technical" },

    { "id": "recipe-garbage-collect",            "freq": "weekly",   "weekday_only": true,  "output": ".garbage-collect" },
    { "id": "recipe-projects",                   "freq": "weekly",   "weekday_only": true,  "output": "PROJECTS.md" },
    { "id": "recipe-work-personal",              "freq": "weekly",   "weekday_only": false, "output": ".work-personal" },

    { "id": "recipe-interactions",               "freq": "daily",    "weekday_only": false, "output": "INTERACTIONS.md" },
    { "id": "recipe-chrome-history",             "freq": "weekly",   "weekday_only": true,  "output": "CHROME_HISTORY.md" },

    { "id": "recipe-interests",                  "freq": "daily",    "weekday_only": false, "output": "INTERESTS.md" },
    { "id": "recipe-morning-attention",          "freq": "morning",  "weekday_only": true,  "output": ".morning-attention" },
    { "id": "recipe-upcoming",                   "freq": "afternoon","weekday_only": true,  "output": ".upcoming" },
    { "id": "recipe-what-working-on",            "freq": "evening",  "weekday_only": true,  "output": ".working-on" },

    { "id": "recipe-optimize",                   "freq": "weekly",   "weekday_only": false, "output": ".optimize" },
    { "id": "recipe-meetings-actions",           "freq": "morning",  "weekday_only": true,  "output": ".meetings-afternoon" },
    { "id": "recipe-apps-preferences",           "freq": "daily",    "weekday_only": true,  "output": ".apps-preferences" },
    { "id": "recipe-meetings-actions",           "freq": "evening",  "weekday_only": true,  "output": ".meetings-evening" },

    { "id": "recipe-start-fixing",               "freq": "evening",  "weekday_only": false, "output": ".fixing" },
    { "id": "recipe-follow-up-content",          "freq": "morning",  "weekday_only": true,  "output": ".follow-up-content" },

    { "id": "recipe-take-time-back",             "freq": "weekly",   "weekday_only": true,  "output": ".give-time-back" },

    { "id": "../adapt-recipes",                  "freq": "weekly",   "weekday_only": false, "output": ".adapting" }
  ]

}
JSON
  echo "$(date): Created default observer-config.json at $cfg"
}

cfg() { jq -r "$1" "$PERCEPTION_DIR/observer-config.json"; }
cfg_int() { jq -r "$1" "$PERCEPTION_DIR/observer-config.json" | awk '{print int($0)}'; }

ensure_observer_config

# Export model/provider/context from config (available to all goose runs)
export GOOSE_MODEL="$(cfg '.globals.goose_model')"
export GOOSE_PROVIDER="$(cfg '.globals.goose_provider')"
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

  run_recipe_if_needed "recipe-work-daily.yaml" "morning" "WORK.md" "weekday-only"  
  run_recipe_if_needed "recipe-work-daily.yaml" "afternoon" "WORK.md" "weekday-only"  

  run_recipe_if_needed "recipe-contributions.yaml" "weekly" "CONTRIBUTIONS.md" "weekday-only"
  run_recipe_if_needed "recipe-focus.yaml" "weekly" ".focus" "weekday-only"
  run_recipe_if_needed "recipe-hypedoc.yaml" "weekly" ".hypedoc"

  run_recipe_if_needed "recipe-important-attention-message.yaml" "120m" ".important-messages" "weekday-only"

  run_recipe_if_needed "recipe-background-tasks.yaml" "180m" ".background-tasks"  "weekday-only"
  run_recipe_if_needed "recipe-background-technical.yaml" "180m" ".background-technical"  "weekday-only"

  run_recipe_if_needed "recipe-garbage-collect.yaml" "weekly" ".garbage-collect" "weekday-only"
  run_recipe_if_needed "recipe-projects.yaml" "weekly" "PROJECTS.md" "weekday-only"
  run_recipe_if_needed "recipe-work-personal.yaml" "weekly" ".work-personal"
  run_recipe_if_needed "recipe-interactions.yaml" "daily" "INTERACTIONS.md"
  run_recipe_if_needed "recipe-chrome-history.yaml" "weekly" "CHROME_HISTORY.md" "weekday-only"

  run_recipe_if_needed "recipe-interests.yaml" "daily" "INTERESTS.md"
  run_recipe_if_needed "recipe-morning-attention.yaml" "morning" ".morning-attention" "weekday-only"
  run_recipe_if_needed "recipe-upcoming.yaml" "afternoon" ".upcoming" "weekday-only"
  run_recipe_if_needed "recipe-what-working-on.yaml" "evening" ".working-on" "weekday-only"
  run_recipe_if_needed "recipe-optimize.yaml" "weekly" ".optimize"
  run_recipe_if_needed "recipe-meetings-actions.yaml" "morning" ".meetings-afternoon" "weekday-only"
  run_recipe_if_needed "recipe-apps-preferences.yaml" "daily" ".apps-preferences" "weekday-only"
  run_recipe_if_needed "recipe-meetings-actions.yaml" "evening" ".meetings-evening" "weekday-only"
  run_recipe_if_needed "recipe-start-fixing.yaml" "evening" ".fixing"
  run_recipe_if_needed "recipe-follow-up-content.yaml" "morning" ".follow-up-content" "weekday-only"
  run_recipe_if_needed "recipe-take-time-back.yaml" "weekly" ".give-time-back" "weekday-only"
  run_recipe_if_needed "../adapt-recipes.yaml" "weekly" ".adapting"

  echo "$(date): Scheduled recipe check complete."
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
run_scheduled_recipes

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
  run_scheduled_recipes

  # Wait 1 minute before next recipe check
  sleep 60  # 1 minute
done
