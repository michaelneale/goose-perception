# Goose Voice Justfile
# Run commands with 'just <command>'

# Set default shell to bash with error handling
set shell := ["bash", "-c"]


# Default recipe (runs when you just type 'just')
default:
    @just run

# Check if repo is out of date with upstream and show banner if needed
check-upstream:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Get current branch
    CURRENT_BRANCH=$(git branch --show-current)
    
    # Skip if not on main branch
    if [[ "$CURRENT_BRANCH" != "main" ]]; then
        exit 0
    fi
    
    # Skip if repo is dirty
    if ! git diff-index --quiet HEAD --; then
        exit 0
    fi
    
    # Fetch latest from origin to get current remote state
    if ! git fetch origin main --quiet 2>/dev/null; then
        exit 0
    fi
    
    # Check if local main is behind origin/main
    LOCAL_COMMIT=$(git rev-parse HEAD)
    REMOTE_COMMIT=$(git rev-parse origin/main)
    
    if [[ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]]; then
        # Check if we're behind (not ahead or diverged)
        if git merge-base --is-ancestor HEAD origin/main; then
            echo ""
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║                    ⚠️  REPOSITORY OUT OF DATE ⚠️                ║"
            echo "╠══════════════════════════════════════════════════════════════╣"
            echo "║                                                              ║"
            echo "║  Your local repository is behind the remote main branch.    ║"
            echo "║                                                              ║"
            echo "║  To get the latest updates, please run:                     ║"
            echo "║                                                              ║"
            echo "║      git pull origin main                                    ║"
            echo "║                                                              ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            echo ""
        fi
    fi

# Check for ffmpeg on macOS and install if needed
check-ffmpeg:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Only check on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "🔍 Checking for ffmpeg on macOS..."
        
        # Check if ffmpeg is available
        if ! command -v ffmpeg &> /dev/null; then
            echo "⚠️  ffmpeg not found. Installing via Homebrew..."
            
            # Check if brew is available
            if ! command -v brew &> /dev/null; then
                echo "❌ Homebrew not found. Please install Homebrew first:"
                echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                exit 1
            fi
            
            # Install ffmpeg
            echo "📦 Installing ffmpeg..."
            if brew install ffmpeg; then
                echo "✅ ffmpeg installed successfully!"
            else
                echo "❌ Failed to install ffmpeg. Please install manually:"
                echo "   brew install ffmpeg"
                exit 1
            fi
        else
            echo "✅ ffmpeg is already installed"
        fi
    else
        echo "ℹ️  Not on macOS, skipping ffmpeg check"
    fi

# Check for Temporal CLI on macOS and install if needed
check-temporal:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Only check on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "🔍 Checking for Temporal CLI on macOS..."
        
        # Check if temporal is available
        if ! command -v temporal &> /dev/null; then
            echo "⚠️  Temporal CLI not found. Installing via Homebrew..."
            
            # Check if brew is available
            if ! command -v brew &> /dev/null; then
                echo "❌ Homebrew not found. Please install Homebrew first:"
                echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                exit 1
            fi
            
            # Install temporal
            echo "📦 Installing Temporal CLI..."
            if brew install temporal; then
                echo "✅ Temporal CLI installed successfully!"
                echo "🔄 This enables advanced GooseSchedule features with complex cron expressions"
            else
                echo "❌ Failed to install Temporal CLI. Please install manually:"
                echo "   brew install temporal"
                echo "ℹ️  Without Temporal, GooseSchedule will use legacy mode (basic schedules only)"
                # Don't exit - legacy mode still works
            fi
        else
            echo "✅ Temporal CLI is already installed"
            
            # Check if Temporal services are running for GooseSchedule
            echo "🔍 Checking Temporal services status..."
            if goose schedule services-status &> /dev/null; then
                echo "✅ Temporal services are running for GooseSchedule"
            else
                echo "ℹ️  Temporal CLI installed but services may need to start (will auto-start when needed)"
            fi
        fi
    else
        echo "ℹ️  Not on macOS, skipping Temporal check"
        echo "ℹ️  For Linux/Windows, install Temporal from: https://github.com/temporalio/cli/releases"
    fi

# Setup required dependencies and data
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔧 Setting up Goose Perception dependencies..."
    
    # Check for ffmpeg on macOS
    just check-ffmpeg
    
    # Check for Temporal CLI on macOS
    just check-temporal
    
    echo "✅ Setup complete! (NLTK data will be downloaded automatically when needed)"

# Sync GooseSchedule schedules
sync-schedules:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔄 Syncing GooseSchedule schedules..."
    ./.use-hermit python3 sync_schedules.py

# Resume GooseSchedule schedules (auto-starts services)
resume-schedules:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "▶️  Resuming GooseSchedule schedules..."
    if command -v goose &> /dev/null; then
        # Services auto-start when we check status or sync
        if goose schedule services-status &> /dev/null; then
            echo "✅ Temporal services are running"
        else
            echo "🔄 Starting Temporal services..."
            # Trigger service start by running a simple sync
            ./.use-hermit python3 sync_schedules.py > /dev/null
        fi
        echo "✅ All schedules resumed"
    else
        echo "❌ GooseSchedule not available"
        exit 1
    fi

# Train the wake word classifier
train-classifier:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Training wake word classifier..."
    ./.use-hermit ./wake-classifier/train.sh

# Run just the observers/recipes in the background
run-simple:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Check if repo is up to date with upstream
    just check-upstream
    
    # Ensure setup is done
    just setup
    
    # Kill any existing processes first
    just kill
    
    # Sync GooseSchedule schedules (includes system setup)
    echo "🔄 Syncing GooseSchedule schedules..."
    ./.use-hermit python3 sync_schedules.py
    
    echo "✅ Observers are now running via GooseSchedule"
    echo "   Use 'just status' to check status"
    echo "   Use 'just schedule-status' for detailed schedule info"

# Run the full voice recognition system (observers + voice)
run: 
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Check if repo is up to date with upstream
    just check-upstream
    
    # Ensure setup is done
    just setup
    
    if [ ! -d "wake-classifier/model/final" ]; then
        just train-classifier
    fi
    
    # Kill any existing processes first
    just kill
    
    # Sync GooseSchedule schedules (includes system setup)
    echo "🔄 Syncing GooseSchedule schedules..."
    ./.use-hermit python3 sync_schedules.py
    
    echo "✅ Observers are now running via GooseSchedule"
    
    # Simple cleanup that always runs
    trap 'echo "Cleaning up..."; just kill' EXIT INT TERM
    
    echo "Starting Goose Voice..."
    ./.use-hermit ./run.sh

kill:
    #!/usr/bin/env bash
    echo "🚦 STOPPING ALL GOOSE PERCEPTION PROCESSES..."
    
    # Pause all schedules by stopping Temporal services
    echo "⏸️  Pausing all GooseSchedule jobs..."
    if command -v goose &> /dev/null; then
        goose schedule services-stop 2>/dev/null || true
        echo "✅ All schedules paused"
    else
        echo "ℹ️  GooseSchedule not available, skipping schedule pause"
    fi
    
    # Kill any running goose processes
    echo "Killing all related processes..."
    pkill -KILL -f "goose run" 2>/dev/null || true
    pkill -KILL -f "recipe-" 2>/dev/null || true
    
    # Clean up temp files
    rm -f /tmp/goose-perception-* 2>/dev/null || true
    
    echo "✅ All processes stopped and schedules paused."

# View observer logs (now from GooseSchedule)
logs:
    #!/usr/bin/env bash
    echo "=== GooseSchedule Logs ==="
    if command -v goose &> /dev/null; then
        echo "Recent schedule activity:"
        goose schedule list 2>/dev/null || echo "No schedules found"
        echo ""
        echo "To view logs for a specific recipe run:"
        echo "  goose run --recipe observers/recipe-name.yaml"
    else
        echo "GooseSchedule not available"
    fi

# View recent observer logs
logs-recent:
    #!/usr/bin/env bash
    echo "=== Recent Schedule Activity ==="
    if command -v goose &> /dev/null; then
        goose schedule list 2>/dev/null || echo "No schedules found"
    else
        echo "GooseSchedule not available"
    fi

# Check status of running processes
status:
    #!/usr/bin/env bash
    echo "=== Goose Perception Status ==="
    echo
    
    # Check GooseSchedule status
    if command -v goose &> /dev/null; then
        echo "=== Schedule Status ==="
        if goose schedule services-status &> /dev/null; then
            echo "✅ Temporal services running - schedules active"
            SCHEDULE_COUNT=$(goose schedule list 2>/dev/null | grep -c "ID:" || echo "0")
            echo "📋 Active schedules: $SCHEDULE_COUNT"
            echo ""
            echo "Recent schedule activity:"
            ./.use-hermit python3 schedule_manager.py status
        else
            echo "⏸️  Temporal services stopped - schedules paused"
            echo "   Run 'just resume-schedules' to restart"
        fi
        echo
    else
        echo "❌ GooseSchedule not available"
        echo
    fi
    
    echo "Running goose processes:"
    ps aux | grep -E "(goose|recipe-)" | grep -v grep | grep -v "just status" || echo "  None found"
    echo

# Run tests
test:
    #!/usr/bin/env bash
    echo "🧪 Running Goose Perception Tests..."
    echo
    
    # Test wake word classifier
    echo "1. Testing wake word classifier..."
    ./.use-hermit python wake-classifier/classifier.py "how are you"
    echo
    
    # Test emotion detection
    echo "2. Testing emotion detection..."
    ./.use-hermit python -c "
    try:
        from emotion_detector import run_emotion_detection_cycle
        print('✅ Emotion detection module imports successfully')
        run_emotion_detection_cycle()
        print('✅ Emotion detection cycle completed')
    except Exception as e:
        print(f'❌ Emotion detection test failed: {e}')
    "
    echo
    
    # Test menu notifications
    echo "3. Testing menu notifications..."
    ./.use-hermit python test_menu_notifications.py
    echo
    
    # Test avatar system (non-interactive)
    echo "4. Testing avatar system (import test)..."
    ./.use-hermit python -c "
    try:
        from avatar import avatar_display
        print('✅ Avatar system imports successfully')
    except Exception as e:
        print(f'❌ Avatar system test failed: {e}')
    "
    echo
    
    echo "✅ All tests completed!"

# Run interactive avatar test
test-avatar:
    #!/usr/bin/env bash
    echo "🎭 Running interactive avatar test..."
    echo "This will open a GUI window - close it when done."
    ./.use-hermit python avatar/test_avatar.py

update: 
    git checkout main
    git pull origin main    

# Schedule management commands
schedule-list:
    #!/usr/bin/env bash
    echo "📋 Discovered Schedules:"
    ./.use-hermit python3 schedule_manager.py list

schedule-status:
    #!/usr/bin/env bash
    echo "📊 Schedule Status:"
    ./.use-hermit python3 schedule_manager.py status

schedule-sync:
    #!/usr/bin/env bash
    echo "🔄 Syncing Schedules:"
    ./.use-hermit python3 sync_schedules.py

schedule-dry-run:
    #!/usr/bin/env bash
    echo "🔍 Schedule Dry Run (no changes):"
    ./.use-hermit python3 schedule_manager.py dry-run

schedule-help:
    #!/usr/bin/env bash
    echo "📖 Schedule Management Commands:"
    echo "  just schedule-list      - List all configured schedules"
    echo "  just schedule-status    - Show schedule status"
    echo "  just schedule-sync      - Sync schedules with GooseSchedule"
    echo "  just schedule-sync-safe - Sync without removing extra schedules"
    echo "  just schedule-dry-run   - Show what would change (no changes)"
    echo "  just schedule-clean     - Clean up old/extra schedules (interactive)"
    echo "  just sync-schedules     - Full sync with directory setup"
    echo ""
    echo "📝 To add schedule to a recipe:"
    echo "  ./.use-hermit python3 schedule_manager.py add-schedule --recipe observers/recipe-example.yaml --frequency hourly"
    echo ""
    echo "📖 See SCHEDULE_CONFIGURATION.md for detailed documentation"

schedule-sync-safe:
    #!/usr/bin/env bash
    echo "🔄 Syncing Schedules (safe mode - no removal):"
    ./.use-hermit python3 schedule_manager.py sync --no-remove

schedule-clean:
    #!/usr/bin/env bash
    echo "🧹 Cleaning up extra schedules:"
    ./.use-hermit python3 schedule_manager.py clean    
