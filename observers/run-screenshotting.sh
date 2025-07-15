#!/bin/bash

# Create screenshots directory
mkdir -p /tmp/screenshots

# Generate timestamp for the output file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="/tmp/screenshots/screens_${TIMESTAMP}.txt"

# Sleep for 5 seconds
sleep 5

# Enumerate open windows and their titles
echo "=== Open Windows ==="
WINDOW_LIST=$(osascript -e '
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
' 2>/dev/null)

echo "$WINDOW_LIST"
echo "===================="

# Take screenshots of all displays (silent)
screencapture -x -D 1 /tmp/screenshots/screen1.png 2>/dev/null || true
screencapture -x -D 2 /tmp/screenshots/screen2.png 2>/dev/null || true
screencapture -x -D 3 /tmp/screenshots/screen3.png 2>/dev/null || true

# Start screens.txt with window listing
echo "=== Open Windows ===" > "$OUTPUT_FILE"
echo "$WINDOW_LIST" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Function to get image dimensions
get_image_size() {
    sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null | grep -E 'pixelWidth|pixelHeight' | awk '{print $2}' | tr '\n' ' '
}

# Function to check if ollama and llava model are available
check_ollama_llava() {
    if ! command -v ollama >/dev/null 2>&1; then
        return 1
    fi
    
    if ! ollama list | grep -q "llava"; then
        return 1
    fi
    
    return 0
}

# Function to get AI description of image
get_ai_description() {
    local img_path="$1"
    local description_type="$2"  # "screen" or "quarter"
    
    if check_ollama_llava; then
        echo "Getting AI description for $img_path..."
        local description=$(ollama run llava:13b "Describe what the user is doing in this screenshot. Focus on applications, activities, and visible content." "$img_path" 2>/dev/null)
        if [ -n "$description" ]; then
            echo "AI Description ($description_type): $description"
            return 0
        else
            echo "AI Description ($description_type): Failed to get description"
            return 1
        fi
    else
        return 1
    fi
}

# Function to filter OCR garbage and keep readable text
filter_ocr_text() {
    local input_text="$1"
    
    # Filter out lines that are mostly garbage
    echo "$input_text" | while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue
        
        # Skip lines that are mostly symbols/numbers/single characters
        if echo "$line" | grep -qE '^[^a-zA-Z]*$'; then
            continue
        fi
        
        # Skip lines with too many underscores, random symbols
        if echo "$line" | grep -qE '_{5,}|[_]{3,}[^a-zA-Z ]{3,}'; then
            continue
        fi
        
        # Skip lines that are mostly fragmented (lots of single chars with spaces)
        if echo "$line" | grep -qE '^([a-zA-Z]_? ){5,}$'; then
            continue
        fi
        
        # Keep lines that have reasonable word patterns
        # At least 3 characters in a row that form word-like patterns
        if echo "$line" | grep -qE '[a-zA-Z]{3,}'; then
            # Clean up the line - remove excessive underscores and weird chars
            cleaned_line=$(echo "$line" | sed 's/_/ /g' | sed 's/[^a-zA-Z0-9 .,!?:;()-]//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
            
            # Only output if it still has meaningful content after cleaning
            if echo "$cleaned_line" | grep -qE '[a-zA-Z]{2,}.*[a-zA-Z]{2,}|[a-zA-Z]{4,}'; then
                echo "$cleaned_line"
            fi
        fi
    done
}

# Function to split large image into quarters and OCR each
ocr_image() {
    local img_path="$1"
    local screen_num="$2"
    
    # Get image dimensions
    local dimensions=$(get_image_size "$img_path")
    local width=$(echo $dimensions | cut -d' ' -f1)
    local height=$(echo $dimensions | cut -d' ' -f2)
    
    echo "Image $img_path: ${width}x${height}"
    
    # If image is large (over 2000px in either dimension), split into quarters
    if [ "$width" -gt 2000 ] || [ "$height" -gt 2000 ]; then
        echo "Large image detected, splitting into quarters..."
        
        local half_width=$((width / 2))
        local half_height=$((height / 2))
        
        # Create quarters
        sips --cropToHeightWidth $half_height $half_width --cropOffset 0 0 "$img_path" --out "/tmp/screenshots/screen${screen_num}_q1.png" >/dev/null 2>&1
        sips --cropToHeightWidth $half_height $half_width --cropOffset 0 $half_width "$img_path" --out "/tmp/screenshots/screen${screen_num}_q2.png" >/dev/null 2>&1
        sips --cropToHeightWidth $half_height $half_width --cropOffset $half_height 0 "$img_path" --out "/tmp/screenshots/screen${screen_num}_q3.png" >/dev/null 2>&1
        sips --cropToHeightWidth $half_height $half_width --cropOffset $half_height $half_width "$img_path" --out "/tmp/screenshots/screen${screen_num}_q4.png" >/dev/null 2>&1
        
        # Get AI description of full screen first
        echo "--- Screen $screen_num ---" >> "$OUTPUT_FILE"
        ai_desc=$(get_ai_description "$img_path" "full screen")
        if [ $? -eq 0 ]; then
            echo "$ai_desc" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
        
        # OCR each quarter
        for q in 1 2 3 4; do
            if [ -f "/tmp/screenshots/screen${screen_num}_q${q}.png" ]; then
                echo "--- Screen $screen_num Quarter $q ---" >> "$OUTPUT_FILE"
                
                # Get AI description for quarter
                ai_desc=$(get_ai_description "/tmp/screenshots/screen${screen_num}_q${q}.png" "quarter")
                if [ $? -eq 0 ]; then
                    echo "$ai_desc" >> "$OUTPUT_FILE"
                    echo "" >> "$OUTPUT_FILE"
                fi
                
                # OCR the quarter
                raw_ocr=$(gocr "/tmp/screenshots/screen${screen_num}_q${q}.png" 2>/dev/null || echo "OCR failed for screen${screen_num}_q${q}.png")
                filtered_ocr=$(filter_ocr_text "$raw_ocr")
                if [ -n "$filtered_ocr" ]; then
                    echo "OCR Text:" >> "$OUTPUT_FILE"
                    echo "$filtered_ocr" >> "$OUTPUT_FILE"
                fi
                echo "" >> "$OUTPUT_FILE"
            fi
        done
    else
        # Regular OCR for smaller images
        echo "=== Screen $screen_num ===" >> "$OUTPUT_FILE"
        
        # Get AI description
        ai_desc=$(get_ai_description "$img_path" "screen")
        if [ $? -eq 0 ]; then
            echo "$ai_desc" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
        
        # OCR the image
        raw_ocr=$(gocr "$img_path" 2>/dev/null || echo "OCR failed for screen$screen_num.png")
        filtered_ocr=$(filter_ocr_text "$raw_ocr")
        if [ -n "$filtered_ocr" ]; then
            echo "OCR Text:" >> "$OUTPUT_FILE"
            echo "$filtered_ocr" >> "$OUTPUT_FILE"
        fi
        echo "" >> "$OUTPUT_FILE"
    fi
}

# Run OCR on each screenshot that exists
for i in 1 2 3; do
    if [ -f "/tmp/screenshots/screen$i.png" ]; then
        echo "Running OCR on screen$i.png..."
        ocr_image "/tmp/screenshots/screen$i.png" "$i"
    fi
done

# Print completion message with output file location
echo "Screenshot processing complete!"
echo "Output saved to: $OUTPUT_FILE"

# Clean up screenshot images after processing
echo "Cleaning up screenshot images..."
rm -f /tmp/screenshots/screen*.png
echo "Screenshot images cleaned up."
