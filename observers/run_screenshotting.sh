#!/bin/bash

# Sleep for 5 seconds
sleep 5

# Enumerate open windows and their titles
echo "=== Open Windows ==="
osascript -e '
tell application "System Events"
    set windowList to {}
    repeat with proc in application processes
        try
            if (count of windows of proc) > 0 and visible of proc is true then
                set appName to name of proc
                repeat with win in windows of proc
                    try
                        set winTitle to name of win
                        set end of windowList to (appName & ": " & winTitle)
                    end try
                end repeat
            end if
        end try
    end repeat
    return windowList
end tell
' 2>/dev/null

echo "===================="

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
