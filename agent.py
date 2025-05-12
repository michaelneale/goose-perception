#!/usr/bin/env python3
"""
agent.py - Process transcribed conversations and take actions based on them

This is a simple agent that can be invoked by listen.py when a conversation is complete.
It receives the transcript and audio file paths as arguments and can take actions based on the content.
"""

import argparse
import sys
import json
import os
from datetime import datetime

def process_conversation(transcript_path, audio_path):
    """
    Process a conversation transcript and take appropriate actions
    
    Args:
        transcript_path (str): Path to the transcript file
        audio_path (str): Path to the audio file
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
    
    # Here you would add your agent logic to:
    # 1. Parse the transcript for intent
    # 2. Extract relevant information
    # 3. Take appropriate actions
    
    # For now, we'll just do a simple keyword analysis
    keywords = {
        "weather": "I detected a question about weather. I would check a weather API.",
        "time": "I detected a question about time. Current time is " + datetime.now().strftime("%H:%M:%S"),
        "reminder": "I detected a request to set a reminder. I would create a reminder.",
        "search": "I detected a search request. I would perform a web search.",
        "play": "I detected a request to play media. I would start playing requested content.",
    }
    
    detected_intents = []
    for keyword, response in keywords.items():
        if keyword in transcript.lower():
            detected_intents.append(response)
    
    if detected_intents:
        print("DETECTED INTENTS:")
        for intent in detected_intents:
            print(f"• {intent}")
    else:
        print("No specific intents detected. I would ask for clarification.")
    
    # Create a response object that could be used by other systems
    response = {
        "timestamp": timestamp,
        "transcript": transcript,
        "transcript_path": transcript_path,
        "audio_path": audio_path,
        "detected_intents": detected_intents,
    }
    
    # You could save this to a file, send it to another service, etc.
    # For now, just print it as JSON
    print("-"*80)
    print("AGENT RESPONSE OBJECT:")
    print(json.dumps(response, indent=2))
    print("="*80)
    
    return response

def main():
    parser = argparse.ArgumentParser(description="Process transcribed conversations")
    parser.add_argument("transcript", help="Path to the transcript file")
    parser.add_argument("audio", help="Path to the audio file")
    parser.add_argument("--json", action="store_true", help="Output only JSON response")
    args = parser.parse_args()
    
    response = process_conversation(args.transcript, args.audio)
    
    if args.json and response:
        # If JSON output is requested, print only the JSON response
        print(json.dumps(response))

if __name__ == "__main__":
    main()