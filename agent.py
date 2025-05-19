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
import json
from datetime import datetime

notify_cmd = "osascript -e 'display notification \"Task is currently running...\" with title \"Work in Progress\" subtitle \"Please wait\" sound name \"Submarine\"'"


def update_history(transcript, voice_dir, max_history=20):
    """
    Update the history.json file with the latest transcript, keeping only the last max_history entries
    
    Args:
        transcript (str): The transcript to add to history
        voice_dir (str): The directory where history.json is stored
        max_history (int): Maximum number of transcripts to keep in history
        
    Returns:
        list: The updated history list
    """
    history_path = os.path.join(voice_dir, "history.json")
    history = []
    
    # Load existing history if it exists
    if os.path.exists(history_path):
        try:
            with open(history_path, 'r') as f:
                history = json.load(f)
        except json.JSONDecodeError:
            print("Error reading history.json, starting with empty history")
            history = []
    
    # Add new transcript with timestamp
    history.append({
        "timestamp": datetime.now().isoformat(),
        "transcript": transcript
    })
    
    # Keep only the last max_history entries
    if len(history) > max_history:
        history = history[-max_history:]
    
    # Save the updated history
    try:
        with open(history_path, 'w') as f:
            json.dump(history, f, indent=2)
    except Exception as e:
        print(f"Error saving history.json: {e}")
    
    return history

def run_goose_in_background(full_input, voice_dir):
    """
    Run the Goose command in a background thread
    
    Args:
        full_input (str): The complete input to pass to Goose
        voice_dir (str): The directory to run Goose from
    """
    try:
        # Save current directory
        current_dir = os.getcwd()
        
        # Change to voice directory
        os.chdir(voice_dir)
        
        # Notify user that Goose is running
        subprocess.call(notify_cmd, shell=True)

        # Execute the command
        cmd = f"goose run -t \"{full_input}\""
        print(f"Executing: {cmd}")
        subprocess.call(cmd, shell=True)
        
        # Change back to original directory
        os.chdir(current_dir)
        
    except Exception as e:
        print(f"Error in Goose thread: {e}")

def process_conversation(transcript_path, audio_path):
    """
    Process a conversation transcript and invoke Goose in a non-blocking way
    
    Args:
        transcript_path (str): Path to the transcript file
        audio_path (str): Path to the audio file
        
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
    audio_filename = os.path.basename(audio_path)
    
    print("\n" + "="*80)
    print(f"🤖 AGENT PROCESSING CONVERSATION AT {timestamp}")
    print(f"📝 Transcript: {transcript_filename}")
    print(f"🔊 Audio: {audio_filename}")
    print("-"*80)
    
    # Print the transcript
    print("TRANSCRIPT CONTENT:")
    print(transcript)
    print("-"*80)
    
    # Change to the voice directory
    voice_dir = os.path.expanduser("~/Documents/voice")
    
    # Ensure the directory exists
    if not os.path.exists(voice_dir):
        print(f"Creating directory: {voice_dir}")
        os.makedirs(voice_dir)
    
    # Update history with the new transcript
    history = update_history(transcript, voice_dir)
    print(f"Updated history.json with the latest transcript (keeping last 20)")
    
    # Prepare the instruction to prefix the transcript
    prompt = f"""
    You are a helpful assistant responding to spoken commands/discussion.  
    You can look in the history.json file if you need past conversation history if required from the transcript of the command below.
    Please try to act on the request witout expecting further input from the user.
    You can use a command like {notify_cmd} to notify the user if you wish to get their attention.
    You can also use the `say` command to speak the response back to the user if needed.

    Command:
    {transcript}
    """
    
    
    # Invoke Goose with the transcript in a background thread
    print(f"Invoking Goose from {voice_dir} in background...")
    
    # Create and start the thread
    goose_thread = threading.Thread(
        target=run_goose_in_background,
        args=(prompt, voice_dir),
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
        "audio_path": audio_path,
        "background_process_started": True
    }

def main():
    parser = argparse.ArgumentParser(description="Process transcribed conversations and invoke Goose")
    parser.add_argument("transcript", help="Path to the transcript file", nargs='?')
    parser.add_argument("audio", help="Path to the audio file", nargs='?')
    parser.add_argument("--test", action="store_true", help="Run a test with a sample message")
    args = parser.parse_args()
    
    if args.test:
        # Create a temporary transcript file with a test message
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as temp_file:
            temp_file.write("Can you write hello.txt with a joke in it please")
            temp_transcript = temp_file.name
        
        print(f"Created test transcript file: {temp_transcript}")
        
        # Use a dummy audio path
        temp_audio = "test_audio.wav"
        
        # Process the test conversation
        process_conversation(temp_transcript, temp_audio)
        
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
    
    elif args.transcript and args.audio:
        # Normal operation with provided files
        process_conversation(args.transcript, args.audio)
    
    else:
        parser.print_help()
        print("\nTip: Run with --test to try a test message")

if __name__ == "__main__":
    main()