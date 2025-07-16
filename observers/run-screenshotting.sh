#!/bin/bash

# Create screenshots directory
mkdir -p /tmp/screenshots

# Generate timestamp for this session
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Sleep for 5 seconds
sleep 5

# Get script directory for finding helper scripts
SCRIPT_DIR="$(dirname "$0")"

# Find the project root directory (one level up from observers)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use the virtual environment's Python interpreter
PYTHON_PATH="$PROJECT_ROOT/.venv/bin/python3"

# Fall back to system python3 if venv doesn't exist
if [ ! -f "$PYTHON_PATH" ]; then
    PYTHON_PATH="python3"
fi

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
    
    if check_ollama_llava; then
        echo "Getting AI description for $img_path..."
        local description=$(ollama run llava:13b "Describe what the user is doing in this screenshot. Focus on applications, activities, and visible content." "$img_path" 2>/dev/null)
        if [ -n "$description" ]; then
            echo "AI Description: $description"
            return 0
        else
            echo "AI Description: Failed to get description"
            return 1
        fi
    else
        return 1
    fi
}

# Function to perform OCR using ocrmac (Apple Vision Framework)
perform_ocr() {
    local img_path="$1"
    
    # Use Python helper script for OCR
    "$PYTHON_PATH" "$SCRIPT_DIR/ocr_helper.py" "$img_path"
}

# Function to create safe filename from app and window name
create_safe_filename() {
    local app_name="$1"
    local window_name="$2"
    
    # Create a combined name
    local combined_name="${app_name} - ${window_name}"
    
    # Replace problematic characters with underscores
    local safe_name=$(echo "$combined_name" | sed 's/[^a-zA-Z0-9 ._-]/_/g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
    
    # Truncate if too long (keeping reasonable filename length)
    if [ ${#safe_name} -gt 100 ]; then
        safe_name="${safe_name:0:100}"
    fi
    
    echo "$safe_name"
}

# Function to process a single window screenshot
process_window_screenshot() {
    local img_path="$1"
    local app_name="$2"
    local window_name="$3"
    local window_id="$4"
    
    # Get image dimensions
    local dimensions=$(get_image_size "$img_path")
    local width=$(echo $dimensions | cut -d' ' -f1)
    local height=$(echo $dimensions | cut -d' ' -f2)
    
    echo "Processing window: $app_name - $window_name (${width}x${height})"
    
    # Create safe filename for this window
    local safe_name=$(create_safe_filename "$app_name" "$window_name")
    local output_file="/tmp/screenshots/${TIMESTAMP}_${safe_name}.txt"
    
    # Write window information to its own file
    echo "=== WINDOW SCREENSHOT ANALYSIS ===" > "$output_file"
    echo "Timestamp: $(date)" >> "$output_file"
    echo "Application: $app_name" >> "$output_file"
    echo "Window: $window_name" >> "$output_file"
    echo "Window ID: $window_id" >> "$output_file"
    echo "Dimensions: ${width}x${height}" >> "$output_file"
    echo "" >> "$output_file"
    
    # Get AI description if available
    ai_desc=$(get_ai_description "$img_path")
    if [ $? -eq 0 ]; then
        echo "$ai_desc" >> "$output_file"
        echo "" >> "$output_file"
    fi
    
    # OCR the window
    echo "Running OCR on window..."
    ocr_result=$(perform_ocr "$img_path")
    if [ -n "$ocr_result" ] && [ "$ocr_result" != "No text detected in image" ]; then
        echo "OCR Text:" >> "$output_file"
        echo "$ocr_result" >> "$output_file"
    else
        echo "No text detected in this window." >> "$output_file"
    fi
    
    echo "Window analysis saved to: $output_file"
}

# Get window information using Python script
echo "Getting window information..."
WINDOW_JSON=$("$PYTHON_PATH" "$SCRIPT_DIR/get_windows.py" --json)

# Create summary file
SUMMARY_FILE="/tmp/screenshots/${TIMESTAMP}_SUMMARY.txt"
echo "=== WINDOW SCREENSHOT SESSION SUMMARY ===" > "$SUMMARY_FILE"
echo "Timestamp: $(date)" >> "$SUMMARY_FILE"
echo "Total windows found: $(echo "$WINDOW_JSON" | jq length)" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

echo "=== WINDOWS PROCESSED ===" >> "$SUMMARY_FILE"
echo "$WINDOW_JSON" | jq -r '.[] | "- \(.app_name): \(.window_name)"' >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

echo "=== OUTPUT FILES ===" >> "$SUMMARY_FILE"

# Process each window
echo "Processing windows..."
echo "$WINDOW_JSON" | jq -c '.[]' | while read -r window; do
    window_id=$(echo "$window" | jq -r '.window_id')
    app_name=$(echo "$window" | jq -r '.app_name')
    window_name=$(echo "$window" | jq -r '.window_name')
    
    # Skip if window name is empty or null
    if [ "$window_name" = "null" ] || [ -z "$window_name" ]; then
        window_name="[Unnamed Window]"
    fi
    
    # Take screenshot of this window
    window_screenshot="/tmp/screenshots/window_${window_id}.png"
    
    echo "Capturing window: $app_name - $window_name (ID: $window_id)"
    
    # Capture window screenshot silently (with shadow by default, -o flag removes shadow)
    if screencapture -x -l "$window_id" "$window_screenshot" 2>/dev/null; then
        # Process the screenshot
        process_window_screenshot "$window_screenshot" "$app_name" "$window_name" "$window_id"
        
        # Add to summary
        safe_name=$(create_safe_filename "$app_name" "$window_name")
        echo "- ${TIMESTAMP}_${safe_name}.txt" >> "$SUMMARY_FILE"
        
        # Clean up the main window screenshot
        rm -f "$window_screenshot"
    else
        echo "Failed to capture window: $app_name - $window_name (ID: $window_id)"
        echo "⚠️  Failed to capture: $app_name - $window_name (ID: $window_id)" >> "$SUMMARY_FILE"
    fi
done

# Print completion message
echo ""
echo "Window screenshot processing complete!"
echo "Summary saved to: $SUMMARY_FILE"
echo "Individual window files saved to: /tmp/screenshots/${TIMESTAMP}_*.txt"
echo ""
echo "Files created:"
ls -la /tmp/screenshots/${TIMESTAMP}_*.txt

# Clean up any remaining screenshot images
echo ""
echo "Cleaning up any remaining screenshot images..."
rm -f /tmp/screenshots/window_*.png
rm -f /tmp/screenshots/screen*.png
echo "Screenshot images cleaned up."
