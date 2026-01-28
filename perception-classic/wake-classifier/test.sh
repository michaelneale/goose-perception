#!/bin/bash

# Trap to handle script termination
trap 'echo "Stopping script..."; kill -TERM $PID 2>/dev/null; exit' INT TERM


python classifier.py "how are you"