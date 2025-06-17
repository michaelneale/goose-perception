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

# Setup required dependencies and data
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔧 Setting up Goose Perception dependencies..."
    
    # Check for ffmpeg on macOS
    just check-ffmpeg
    
    echo "✅ Setup complete! (NLTK data will be downloaded automatically when needed)"

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
    
    echo "Starting observers..."
    cd observers 
    ./run-observations.sh

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
    
    echo "Starting observers in background..."
    cd observers 
    nohup ./run-observations.sh > /tmp/goose-perception-observer.log 2>&1 &
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
    pkill -KILL -f "run-observations.sh" 2>/dev/null || true
    pkill -KILL -f "goose run" 2>/dev/null || true
    pkill -KILL -f "recipe-" 2>/dev/null || true
    
    # Clean up temp files
    rm -f /tmp/goose-perception-* 2>/dev/null || true
    
    echo "✅ All processes killed."

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
    ps aux | grep "run-observations.sh" | grep -v grep || echo "  None found"
    echo

update: 
    git checkout main
    git pull origin main    
