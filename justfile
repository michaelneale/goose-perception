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
    echo "🔧 Setting up directories..."
    python3 setup_directories.py
    echo "🔄 Syncing GooseSchedule schedules..."
    python3 startup.py

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
            python3 startup.py > /dev/null
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
    
    # Sync GooseSchedule schedules
    echo "🔄 Syncing GooseSchedule schedules..."
    python3 startup.py
    
    echo "Starting screenshot capture..."
    python3 observers/screenshot_capture.py

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
    
    # Sync GooseSchedule schedules
    echo "🔄 Syncing GooseSchedule schedules..."
    python3 startup.py
    
    echo "Starting screenshot capture in background..."
    nohup python3 observers/screenshot_capture.py > /tmp/goose-perception-observer.log 2>&1 &
    OBSERVER_PID=$!
    cd ..
    
    # Store the PID for cleanup
    echo $OBSERVER_PID > /tmp/goose-perception-observer-pid
    echo "Observer started with PID: $OBSERVER_PID (use 'just logs' to view)"
    
    # Simple cleanup that always runs
    trap 'echo "Cleaning up..."; just kill' EXIT INT TERM
    
    echo "Starting Goose Voice..."
    ./.use-hermit ./run.sh

kill:
    #!/usr/bin/env bash
    echo "🚦 KILLING ALL GOOSE PERCEPTION PROCESSES..."
    
    # Pause all schedules by stopping Temporal services
    echo "⏸️  Pausing all GooseSchedule jobs..."
    if command -v goose &> /dev/null; then
        goose schedule services-stop 2>/dev/null || true
        echo "✅ All schedules paused"
    else
        echo "ℹ️  GooseSchedule not available, skipping schedule pause"
    fi
    
    # Create halt file
    touch /tmp/goose-perception-halt 2>/dev/null || true
    
    # Kill specific observer PID if we have it
    if [ -f "/tmp/goose-perception-observer-pid" ]; then
        OBSERVER_PID=$(cat /tmp/goose-perception-observer-pid 2>/dev/null || echo "")
        if [ -n "$OBSERVER_PID" ]; then
            echo "Killing observer PID: $OBSERVER_PID"
            kill -KILL $OBSERVER_PID 2>/dev/null || true
        fi
    fi
    
    # Nuclear option - kill everything related
    echo "Killing all related processes..."
    pkill -KILL -f "screenshot_capture.py" 2>/dev/null || true
    pkill -KILL -f "goose run" 2>/dev/null || true
    pkill -KILL -f "recipe-" 2>/dev/null || true
    
    # Clean up temp files
    rm -f /tmp/goose-perception-* 2>/dev/null || true
    
    echo "✅ All processes killed and schedules paused."

# View observer logs
logs:
    #!/usr/bin/env bash
    echo "=== Observer Logs ==="
    if [ -f "/tmp/goose-perception-observer.log" ]; then
        tail -f /tmp/goose-perception-observer.log
    else
        echo "No log file found at /tmp/goose-perception-observer.log"
    fi

# View recent observer logs
logs-recent:
    #!/usr/bin/env bash
    echo "=== Recent Observer Logs ==="
    if [ -f "/tmp/goose-perception-observer.log" ]; then
        tail -50 /tmp/goose-perception-observer.log
    else
        echo "No log file found"
    fi

# Check status of running processes
status:
    #!/usr/bin/env bash
    echo "=== Goose Perception Status ==="
    echo
    
    # Check for halt file
    if [ -f "/tmp/goose-perception-halt" ]; then
        echo "🛑 Halt file exists - system should be stopping"
    fi
    echo
    
    # Check GooseSchedule status
    if command -v goose &> /dev/null; then
        echo "=== Schedule Status ==="
        if goose schedule services-status &> /dev/null; then
            echo "✅ Temporal services running - schedules active"
            SCHEDULE_COUNT=$(goose schedule list 2>/dev/null | grep -c "ID:" || echo "0")
            echo "📋 Active schedules: $SCHEDULE_COUNT"
        else
            echo "⏸️  Temporal services stopped - schedules paused"
        fi
        echo
    else
        echo "❌ GooseSchedule not available"
        echo
    fi
    
    # Check for observer PID file
    if [ -f "/tmp/goose-perception-observer-pid" ]; then
        OBSERVER_PID=$(cat /tmp/goose-perception-observer-pid)
        if kill -0 $OBSERVER_PID 2>/dev/null; then
            echo "✅ Observer process running (PID: $OBSERVER_PID)"
        else
            echo "❌ Observer PID file exists but process not running (stale PID: $OBSERVER_PID)"
        fi
    else
        echo "❌ No observer PID file found"
    fi
    echo
    
    # Check for running processes
    echo "Running goose processes:"
    ps aux | grep -E "(goose|recipe-)" | grep -v grep | grep -v "just status" || echo "  None found"
    echo
    
    echo "Running observation scripts:"
    ps aux | grep "screenshot_capture.py" | grep -v grep || echo "  None found"
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
