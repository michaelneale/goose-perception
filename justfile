# Goose Voice Justfile
# Run commands with 'just <command>'

# Set default shell to bash with error handling
set shell := ["bash", "-c"]

# Default recipe (runs when you just type 'just')
default:
    @just --list

# Setup virtual environment and install dependencies
setup-venv:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d ".venv" ]; then
        echo "Creating virtual environment..."
        uv venv
    fi
    echo "Activating virtual environment and installing dependencies..."
    source .venv/bin/activate
    uv pip install -r requirements.txt
    echo "Virtual environment setup complete!"

# Train the wake word classifier
train-classifier: setup-venv
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Training wake word classifier..."
    source .venv/bin/activate
    uv pip install accelerate
    cd wake-classifier && python train_classifier.py


# Test the classifier with a sample text
test-classifier TEXT="Hey Goose, what's the weather like today?": setup-venv
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Testing classifier with text: '{{TEXT}}'"
    source .venv/bin/activate
    cd wake-classifier && python classifier.py "{{TEXT}}"

# Run the voice recognition system
run: setup-venv
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Starting Goose Voice..."
    source .venv/bin/activate
    ./run.sh

# Clean up generated files and caches
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Cleaning up..."
    find . -type d -name "__pycache__" -exec rm -rf {} +
    find . -type d -name "*.egg-info" -exec rm -rf {} +
    find . -type f -name "*.pyc" -delete
    echo "Cleanup complete!"

