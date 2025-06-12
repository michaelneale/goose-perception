#!/usr/bin/env python3
"""
agent.py - Process transcribed conversations and invoke Goose with the transcript

This agent is invoked by listen.py when a conversation is complete.
It reads the transcript and passes it to the Goose CLI with appropriate instructions.
The Goose process runs in the background to avoid blocking the main process.
"""

import argparse
import sys
import os
import subprocess
import threading
import tempfile
from datetime import datetime
from pathlib import Path
from jinja2 import Template

# Import avatar display system
try:
    import avatar_display
except ImportError:
    avatar_display = None

notify_cmd = "osascript -e 'display notification \"Goose is working on it...\" with title \"Work in Progress\" subtitle \"Please wait\" sound name \"Submarine\"'"

def safe_read_file(file_path):
    """
    Safely read a file if it exists
    
    Args:
        file_path (str): Path to the file
        
    Returns:
        str: File content or empty string if file doesn't exist
    """
    path = Path(file_path).expanduser()
    if path.exists():
        try:
            return path.read_text()
        except Exception as e:
            print(f"Warning: Could not read {file_path}: {e}")
    return ""

def render_recipe_template(transcript, is_screen_capture=False):
    """
    Render the recipe template with dynamic content
    
    Args:
        transcript (str): The transcript text
        is_screen_capture (bool): Whether this is a screen capture request
        
    Returns:
        str: Path to the rendered template file
    """
    # Define paths - choose the appropriate template
    if is_screen_capture:
        template_path = Path("activation/agent-screen-activation.yaml")
        prefix = 'agent-screen-activation-'
    else:
        template_path = Path("activation/agent-voice-recipe.yaml")
        prefix = 'agent-voice-recipe-'
    
    perception_dir = Path("~/.local/share/goose-perception").expanduser()
    
    # Read template
    with open(template_path, 'r') as f:
        template_content = f.read()
    
    # Read additional content files
    latest_work = safe_read_file(perception_dir / "LATEST_WORK.md")
    interactions = safe_read_file(perception_dir / "INTERACTIONS.md")
    contributions = safe_read_file(perception_dir / "CONTRIBUTIONS.md")
    
    # Create Jinja template and render
    template = Template(template_content)
    rendered_content = template.render(
        latest_work=latest_work,
        interactions=interactions,
        contributions=contributions,
        transcription=transcript
    )
    
    # Create a temporary file for the rendered template
    with tempfile.NamedTemporaryFile(suffix='.yaml', prefix=prefix, delete=False) as tmp_file:
        tmp_file.write(rendered_content.encode('utf-8'))
        temp_path = tmp_file.name
    
    template_type = "screen capture" if is_screen_capture else "voice"
    print(f"Created rendered {template_type} recipe at {temp_path}")
    return temp_path

def log_activity(message):
    """
    Append a message to the ACTIVITY-LOG.md file with timestamp
    
    Args:
        message (str): Message to append to the log
    """
    try:
        data_dir = Path("~/.local/share/goose-perception").expanduser()
        data_dir.mkdir(parents=True, exist_ok=True)
        log_file = data_dir / "ACTIVITY-LOG.md"
        
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        with open(log_file, "a") as f:
            f.write(f"**{timestamp}**: {message}\n\n")
    except Exception as e:
        print(f"Error logging activity: {e}")

def run_goose_in_background(transcript):
    """
    Run the Goose command in a background thread
    
    Args:
        transcript (str): The transcript text
    """
    try:
        # Detect if this is a screen capture request
        is_screen_capture = "SCREEN CAPTURE REQUEST" in transcript
        
        # Notify user that Goose is running
        subprocess.call(notify_cmd, shell=True)
        
        if is_screen_capture:
            log_activity("Starting to process screen capture request")
            if avatar_display:
                avatar_display.show_message("🖥️ I'm analyzing your screen... Let me think about this.")
        else:
            log_activity("Starting to process voice request")
            if avatar_display:
                avatar_display.show_message("🎙️ I heard you! Working on your request now...")
        
        # Copy the transcript to /tmp/current_transcription.txt
        with open('/tmp/current_transcription.txt', 'w') as f:
            f.write(transcript)
            print("Saved transcript to /tmp/current_transcription.txt")
        
        # Render the appropriate recipe template
        temp_recipe_path = render_recipe_template(transcript, is_screen_capture=is_screen_capture)
        
        # Execute the command with the rendered template
        cmd = f"goose run --no-session --recipe {temp_recipe_path}"
        print(f"Executing: {cmd}")
        subprocess.call(cmd, shell=True)
        
        # Log completion
        if is_screen_capture:
            log_activity("Completed processing screen capture request")
            if avatar_display:
                avatar_display.show_message("✅ Done analyzing your screen! Check the results.")
        else:
            log_activity("Completed processing voice request")
            if avatar_display:
                avatar_display.show_message("✅ Finished processing your voice command!")
                
        
    except Exception as e:
        print(f"Error in Goose thread: {e}")

def process_conversation(transcript_path):
    """
    Process a conversation transcript and invoke Goose in a non-blocking way
    
    Args:
        transcript_path (str): Path to the transcript file
        
    Returns:
        dict: Information about the processed conversation
    """
    # Read the transcript
    try:
        with open(transcript_path, 'r') as f:
            transcript = f.read().strip()
    except Exception as e:
        print(f"Error reading transcript: {e}")
        return
    
    # Basic information about the conversation
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    transcript_filename = os.path.basename(transcript_path)
    
    print("\n" + "="*80)
    print(f"🤖 AGENT PROCESSING CONVERSATION AT {timestamp}")
    print(f"📝 Transcript: {transcript_filename}")
    print("-"*80)
    
    # Print the transcript
    print("TRANSCRIPT CONTENT:")
    print(transcript)
    print("-"*80)
    
    # Invoke Goose with the transcript in a background thread
    print(f"Invoking Goose in background...")
    
    # Create and start the thread
    goose_thread = threading.Thread(
        target=run_goose_in_background,
        args=(transcript,),  # Make it a tuple with one element
        daemon=True  # Make it a daemon thread so it doesn't block program exit
    )
    goose_thread.start()
    
    print("Goose process started in background. Continuing...")
    print("="*80)
    
    # Return immediately, allowing the main process to continue
    return {
        "timestamp": timestamp,
        "transcript": transcript,
        "transcript_path": transcript_path,
        "background_process_started": True
    }

def main():
    parser = argparse.ArgumentParser(description="Process transcribed conversations and invoke Goose")
    parser.add_argument("transcript", help="Path to the transcript file", nargs='?')
    parser.add_argument("--test", action="store_true", help="Run a test with a sample message")
    args = parser.parse_args()
    
    if args.test:
        # Create a temporary transcript file with a test message
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as temp_file:
            temp_file.write("Can you write hello.txt with a joke in it please")
            temp_transcript = temp_file.name
        
        print(f"Created test transcript file: {temp_transcript}")
        
        # Process the test conversation
        process_conversation(temp_transcript)
        
        # Wait a bit to see some output
        print("Test mode: Waiting for a few seconds to see output...")
        import time
        for i in range(10):
            time.sleep(1)
            print(f"Waiting... ({i+1}/10 seconds)")
        
        # Clean up the temporary file
        try:
            os.unlink(temp_transcript)
            print(f"Cleaned up test transcript file")
        except:
            pass
    
    elif args.transcript:
        # Normal operation with provided file
        process_conversation(args.transcript)
    
    else:
        parser.print_help()
        print("\nTip: Run with --test to try a test message")

if __name__ == "__main__":
    main()