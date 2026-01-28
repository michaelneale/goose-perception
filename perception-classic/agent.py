#!/usr/bin/env python3
"""
agent.py - Process transcribed conversations and invoke Goose with the transcript

This agent is invoked by perception.py when a conversation is complete.
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
from jinja2 import Environment, BaseLoader
import yaml
import json

# Import avatar display system
from avatar.avatar_display import (show_message, show_suggestion, show_actionable_message, 
                                 set_avatar_state, show_error_message, force_dismiss_stuck_message,
                                 emergency_avatar_reset)

# Get the absolute path of the script's directory
SCRIPT_DIR = Path(__file__).parent.resolve()
RECIPES_DIR = SCRIPT_DIR / "actions"
OBSERVERS_DIR = SCRIPT_DIR / "observers"
TEMPLATES_DIR = SCRIPT_DIR / "templates"

# Create a simple Jinja2 environment
jinja_env = Environment(loader=BaseLoader())

# Custom filter to format content for JSON
def to_json_string(value):
    """Converts a Python object to a JSON string, escaping necessary characters."""
    if not isinstance(value, str):
        value = str(value)
    return json.dumps(value)

jinja_env.filters['to_json_string'] = to_json_string

notify_cmd = "osascript -e 'display notification \"Goose is working on it...\" with title \"Work in Progress\" subtitle \"Please wait\" sound name \"Submarine\"'"

# Define the persistent path for user preferences
PREFS_DIR = Path("~/.local/share/goose-perception").expanduser()
PREFS_PATH = PREFS_DIR / "user_prefs.yaml"

# Load user preferences
user_prefs = {}
if PREFS_PATH.exists():
    with open(PREFS_PATH, "r") as f:
        user_prefs = yaml.safe_load(f)

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
        template_path = Path("actions/agent-screen-activation.yaml")
        prefix = 'agent-screen-activation-'
    else:
        template_path = Path("actions/agent-voice-recipe.yaml")
        prefix = 'agent-voice-recipe-'
    
    perception_dir = Path("~/.local/share/goose-perception").expanduser()
    
    # Read template
    with open(template_path, 'r') as f:
        template_content = f.read()
    
    # Read additional content files
    latest_work = safe_read_file(perception_dir / "LATEST_WORK.md")
    interactions = safe_read_file(perception_dir / "INTERACTIONS.md")
    contributions = safe_read_file(perception_dir / "CONTRIBUTIONS.md")
    
    # Create Jinja environment with autoescape enabled for security
    env = Environment(
        loader=BaseLoader(),
        autoescape=True  # Enable autoescaping to prevent XSS/injection attacks
    )
    
    # Create Jinja template and render
    template = env.from_string(template_content)
    rendered_content = template.render(
        latest_work=latest_work,
        interactions=interactions,
        contributions=contributions,
        transcription=transcript,
        user_prefs=user_prefs  # Pass user preferences to the template
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
            try:
                show_message("🖥️ I'm analyzing your screen... Let me think about this.")
            except Exception as e:
                print(f"Error showing avatar message: {e}")
        else:
            log_activity("Starting to process voice request")
            try:
                show_message("🎙️ I heard you! Working on your request now...")
            except Exception as e:
                print(f"Error showing avatar message: {e}")
        
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
            try:
                show_message("✅ Done analyzing your screen! Check the results.")
            except Exception as e:
                print(f"Error showing avatar message: {e}")
        else:
            log_activity("Completed processing voice request")
            try:
                show_message("✅ Finished processing your voice command!")
            except Exception as e:
                print(f"Error showing avatar message: {e}")
                
        
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

def get_user_prefs():
    """Load user preferences from the YAML file."""
    if not PREFS_PATH.exists():
        return {}
    try:
        with open(PREFS_PATH, "r") as f:
            return yaml.safe_load(f) or {}
    except (yaml.YAMLError, IOError) as e:
        print(f"Error loading user preferences: {e}", file=sys.stderr)
        return {}

def run_action(action_name: str, params: dict = None):
    """
    Run a specific action recipe, checking for required preferences first.
    """
    try:
        if params is None:
            params = {}

        recipe_path = RECIPES_DIR / f"{action_name}.yaml"
        if not recipe_path.exists():
            print(f"Error: Action recipe not found at {recipe_path}", file=sys.stderr)
            sys.exit(1)

        with open(recipe_path, "r") as f:
            recipe_data = yaml.safe_load(f)

        # Check for required parameters defined in the recipe
        required_params = [
            p['name'] for p in recipe_data.get('parameters', []) 
            if p.get('requirement') == 'required'
        ]
        
        missing_params = [p for p in required_params if p not in params]
        
        if missing_params:
            print(f"Error: Missing required parameters for action '{action_name}': {', '.join(missing_params)}", file=sys.stderr)
            sys.exit(1)

        # Check for required preferences
        user_prefs = get_user_prefs()
        required_prefs = recipe_data.get("required_prefs", [])
        
        for pref_key in required_prefs:
            if pref_key not in user_prefs or not user_prefs[pref_key]:
                # Signal to the UI that a preference is needed.
                # Since the new format only has a key, we'll generate a generic question.
                pref_details = {
                    "key": pref_key,
                    "question": f"I need a value for '{pref_key.replace('_', ' ')}'. What should it be?",
                    "type": "text"
                }
                print(f"NEEDS_PREF:{json.dumps(pref_details)}")
                sys.exit(0)  # Exit cleanly, UI will handle it

        # Add user preferences to the parameters for the recipe to use
        params['user_prefs'] = json.dumps(user_prefs)

        # If all prefs are present, run the recipe
        print(f"Running action: {action_name}")
        
        # Prepare for running the recipe with `goose run`
        full_recipe_path = recipe_path.resolve()
        
        command = [
            "goose", "run", "--no-session",
            "--recipe", str(full_recipe_path)
        ]
        # Goose requires KEY=VALUE for its --params argument, which can be repeated.
        if params:
            for key, value in params.items():
                # Format as KEY="VALUE" to handle spaces and special characters safely
                command.extend(["--params", f'{key}="{value}"'])
        
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        
        print("--- Action Standard Output ---")
        print(result.stdout)
        print("--- End Action Standard Output ---")
        
        if result.stderr:
            print("--- Action Standard Error ---", file=sys.stderr)
            print(result.stderr, file=sys.stderr)
            print("--- End Action Standard Error ---", file=sys.stderr)

    except subprocess.CalledProcessError as e:
        print(f"Action '{action_name}' failed.", file=sys.stderr)
        print(f"STDOUT: {e.stdout}", file=sys.stderr)
        print(f"STDERR: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred in run_action: {e}", file=sys.stderr)
        sys.exit(1)


def run_observer(observer_name: str, last_run_seconds: int):
    """
    Run an observer recipe and process its output to generate suggestions.
    """
    try:
        recipe_path = OBSERVERS_DIR / f"{observer_name}.yaml"
        if not recipe_path.exists():
            print(f"Error: Observer recipe not found at {recipe_path}", file=sys.stderr)
            sys.exit(1)
            
        print(f"Running observer: {observer_name}")

        # Placeholder for running the observer recipe and getting its output
        # In a real scenario, this would involve `goose run` and capturing stdout
        # Let's simulate some output for demonstration
        simulated_output = "This is a simulated observation."
        
        # The real implementation would be something like:
        # result = subprocess.run(['goose', 'run', '--recipe', str(recipe_path)], capture_output=True, text=True)
        # if result.returncode == 0:
        #     process_and_display_observation(result.stdout, observer_name)
        
        process_and_display_observation(simulated_output, observer_name)

    except Exception as e:
        print(f"An error occurred in run_observer: {e}", file=sys.stderr)
        sys.exit(1)


def process_and_display_observation(observation_text, observer_name):
    """
    Processes the raw output from an observer, formats it into an
    actionable suggestion, and displays it via the avatar.
    """
    if not observation_text or observation_text.strip() == "Nothing to report.":
        print(f"Observer '{observer_name}' had nothing to report.")
        return

    # This is a simplified example. A real implementation would involve
    # more sophisticated logic to decide the action_command and message.
    action_data = {
        'action_type': 'task',
        'action_command': 'update_project_status', # Example action
        'observation_type': observer_name
    }
    
    message = f"I noticed: {observation_text[:100]}... Want me to help with that?"
    
    show_actionable_message(message, action_data)


def main():
    parser = argparse.ArgumentParser(description="Goose Perception Agent")
    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # run-action command
    action_parser = subparsers.add_parser('run-action', help='Run a specific action')
    action_parser.add_argument('action_name', help='Name of the action to run')
    action_parser.add_argument('--params', type=json.loads, help='JSON string of parameters', default={})

    # run-observer command
    observer_parser = subparsers.add_parser('run-observer', help='Run an observer')
    observer_parser.add_argument('observer_name', help='Name of the observer to run')
    observer_parser.add_argument('--last_run_seconds', type=int, default=0, help='Seconds since last run')

    args = parser.parse_args()

    try:
        if args.command == 'run-action':
            run_action(args.action_name, args.params)
        elif args.command == 'run-observer':
            run_observer(args.observer_name, args.last_run_seconds)
        else:
            parser.print_help()
            sys.exit(1)

    except Exception as e:
        print(f"An error occurred: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
