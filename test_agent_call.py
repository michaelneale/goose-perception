#!/usr/bin/env python3
"""
test_agent_call.py - Test calling agent.py as if from listen.py
"""

import subprocess
import time

def main():
    print("Simulating listen.py calling agent.py...")
    
    # Create a test transcript file
    with open("test_transcript.txt", "w") as f:
        f.write("What's the weather like today?")
    
    # Call agent.py with the transcript file
    print("Calling agent.py...")
    subprocess.Popen(["./agent.py", "test_transcript.txt", "dummy_audio.wav"])
    
    # Simulate listen.py continuing to do other work
    print("listen.py continues running...")
    for i in range(5):
        print(f"listen.py doing work... ({i+1}/5)")
        time.sleep(1)
    
    print("listen.py finished its work.")
    print("In a real scenario, listen.py would continue listening for new commands.")

if __name__ == "__main__":
    main()