#!/usr/bin/env python3
"""
listen.py - Continuously listen to audio and transcribe using Whisper
"""

import os
import tempfile
import queue
import threading
import time
import signal
import numpy as np
import sounddevice as sd
import whisper
import argparse
from datetime import datetime
from collections import deque

# Initialize the Whisper model
def load_model(model_name):
    print(f"Loading Whisper model: {model_name}...")
    return whisper.load_model(model_name)

# Audio parameters
SAMPLE_RATE = 16000  # Whisper expects 16kHz audio
CHANNELS = 1  # Mono audio
DTYPE = 'float32'
BUFFER_DURATION = 5  # Duration in seconds for each audio chunk
LONG_BUFFER_DURATION = 60  # Duration in seconds for the longer context (1 minute)

# Queue for audio chunks
audio_queue = queue.Queue()

# Flag to control the main loop
running = True

def signal_handler(sig, frame):
    """Handle interrupt signals for clean shutdown"""
    global running
    print("\nReceived interrupt signal. Shutting down...")
    running = False

def audio_callback(indata, frames, time_info, status):
    """This is called for each audio block."""
    if status:
        print(f"Audio callback status: {status}")
    # Add the audio data to the queue
    audio_queue.put(indata.copy())

def save_audio_chunk(audio_data, filename):
    """Save audio data to a WAV file."""
    import soundfile as sf
    sf.write(filename, audio_data, SAMPLE_RATE)

def transcribe_audio(model, audio_file, language=None):
    """Transcribe audio file using Whisper."""
    try:
        options = {}
        if language:
            options["language"] = language
        
        result = model.transcribe(audio_file, **options)
        return result["text"].strip()
    except Exception as e:
        print(f"Transcription error: {e}")
        return ""

def contains_wake_word(text, wake_word="goose"):
    """Check if the text contains the wake word (case insensitive)"""
    return wake_word.lower() in text.lower()

def main():
    parser = argparse.ArgumentParser(description="Listen to audio and transcribe using Whisper")
    parser.add_argument("--model", type=str, default="base", help="Whisper model size (tiny, base, small, medium, large)")
    parser.add_argument("--language", type=str, default=None, help="Language code (optional, e.g., 'en', 'es', 'fr')")
    parser.add_argument("--device", type=int, default=None, help="Audio input device index")
    parser.add_argument("--list-devices", action="store_true", help="List available audio devices and exit")
    parser.add_argument("--wake-word", type=str, default="goose", help="Wake word to listen for (default: goose)")
    parser.add_argument("--recordings-dir", type=str, default="recordings", help="Directory to save long transcriptions")
    args = parser.parse_args()

    if args.list_devices:
        print("Available audio devices:")
        print(sd.query_devices())
        return

    # Set up signal handlers for clean termination
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Load the Whisper model
    model = load_model(args.model)
    print(f"Model loaded. Using {'default' if args.device is None else f'device {args.device}'} for audio input.")
    print(f"Listening for wake word: '{args.wake_word}'")
    
    # Create a temporary directory for audio chunks
    temp_dir = tempfile.mkdtemp()
    print(f"Temporary files will be stored in: {temp_dir}")
    
    # Create recordings directory if it doesn't exist
    os.makedirs(args.recordings_dir, exist_ok=True)
    print(f"Long transcriptions will be saved in: {args.recordings_dir}")

    # Audio stream object
    stream = None
    
    # Initialize a deque to store the last minute of audio chunks
    # Each chunk is BUFFER_DURATION seconds, so we need (LONG_BUFFER_DURATION / BUFFER_DURATION) chunks
    long_buffer_chunks = int(LONG_BUFFER_DURATION / BUFFER_DURATION)
    long_buffer = deque(maxlen=long_buffer_chunks)
    
    # Initialize a counter for the long transcriptions
    long_transcription_counter = 0
    
    # Timer for long transcription
    last_long_transcription_time = time.time()

    try:
        # Start the audio stream
        stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype=DTYPE,
            callback=audio_callback,
            device=args.device
        )
        stream.start()
        
        print("\nListening... Press Ctrl+C to stop.\n")
        
        # Process audio chunks
        while running:
            # Collect audio for BUFFER_DURATION seconds
            audio_data = []
            collection_start = time.time()
            
            while running and (time.time() - collection_start < BUFFER_DURATION):
                try:
                    chunk = audio_queue.get(timeout=0.1)
                    audio_data.append(chunk)
                except queue.Empty:
                    pass
            
            if not audio_data or not running:
                continue
            
            # Concatenate audio chunks
            audio_data = np.concatenate(audio_data)
            
            # Save to temporary file
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            temp_file = os.path.join(temp_dir, f"audio_chunk_{timestamp}.wav")
            save_audio_chunk(audio_data, temp_file)
            
            # Add the current chunk to the long buffer
            long_buffer.append((audio_data, temp_file))
            
            # Transcribe the current chunk
            transcript = transcribe_audio(model, temp_file, args.language)
            
            # Only print if wake word is detected
            if transcript and contains_wake_word(transcript, args.wake_word):
                print(f"\nWake word detected! Transcript: {transcript}")
            
            # Check if it's time for a long transcription (every minute)
            current_time = time.time()
            if current_time - last_long_transcription_time >= LONG_BUFFER_DURATION:
                # Process the long buffer
                if long_buffer:
                    # Concatenate all audio chunks in the long buffer
                    long_audio = np.concatenate([chunk[0] for chunk in long_buffer])
                    
                    # Save the long audio to a file in the recordings directory
                    long_timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    long_file = os.path.join(args.recordings_dir, f"long_recording_{long_timestamp}.wav")
                    save_audio_chunk(long_audio, long_file)
                    
                    # Transcribe the long audio
                    print("\nTranscribing the last minute of audio...")
                    long_transcript = transcribe_audio(model, long_file, args.language)
                    
                    # Save the transcription to a text file
                    transcript_file = os.path.join(args.recordings_dir, f"transcript_{long_timestamp}.txt")
                    with open(transcript_file, "w") as f:
                        f.write(long_transcript)
                    
                    print(f"Long transcription saved to {transcript_file}")
                    long_transcription_counter += 1
                
                # Reset the timer
                last_long_transcription_time = current_time
            
            # Clean up the temporary file (we keep the files in the long buffer)
            if temp_file not in [chunk[1] for chunk in long_buffer]:
                try:
                    os.remove(temp_file)
                except:
                    pass

    except Exception as e:
        print(f"\nError: {e}")
    finally:
        # Clean up resources
        if stream is not None and stream.active:
            stream.stop()
            stream.close()
        
        # Clean up temporary files in the long buffer
        for _, temp_file in long_buffer:
            try:
                os.remove(temp_file)
            except:
                pass
        
        # Clean up temporary directory
        for file in os.listdir(temp_dir):
            try:
                os.remove(os.path.join(temp_dir, file))
            except:
                pass
        try:
            os.rmdir(temp_dir)
        except:
            pass
        print("Cleanup complete.")
        print(f"Created {long_transcription_counter} long transcriptions in {args.recordings_dir}")

if __name__ == "__main__":
    main()