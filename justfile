# Goose Voice Justfile
# Run commands with 'just <command>'

# Set default shell to bash with error handling
set shell := ["bash", "-c"]

# Default recipe (runs when you just type 'just')
default:
    @just --list


# Train the wake word classifier
train-classifier:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Training wake word classifier..."
    ./.run-hermit ./wake-classifier/train.sh

# Run the voice recognition system
run: 
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d "wake-classifier/model/final" ]; then
        just train-classifier
    fi
    echo "Starting Goose Voice..."
    ./.run-hermit ./run.sh
