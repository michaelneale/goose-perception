#!/bin/bash

# Sleep for 5 seconds
sleep 5

# Take screenshots of all displays (silent)
screencapture -x -D 1 ./screen1.png 2>/dev/null || true
screencapture -x -D 2 ./screen2.png 2>/dev/null || true
screencapture -x -D 3 ./screen3.png 2>/dev/null || true

# Run OCR on each screenshot that exists
for i in 1 2 3; do
    if [ -f "./screen$i.png" ]; then
        echo "Running OCR on screen$i.png..."
        gocr "./screen$i.png" > "./screen$i.txt" 2>/dev/null || echo "OCR failed for screen$i.png" > "./screen$i.txt"
    fi
done
