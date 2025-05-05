#!/bin/bash

# Activate virtual environment
source .venv/bin/activate

# Run the listen.py script with the MacBook Pro microphone
python listen.py --model base --device 2 "$@"