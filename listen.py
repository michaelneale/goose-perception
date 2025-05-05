#!/usr/bin/env python3
"""
listen.py - Continuously listen to audio and transcribe using Whisper
"""

import os
import tempfile
import queue
import threading
import time
import numpy as np
import sounddevice as sd
import whisper
import argparse
from datetime import datetime

# Initialize the Whisper model
def load_model(model_name):
    print(f"Loading Whisper model: {model_name}...")
    return whisper.load_model(model_name)

# Audio parameters
SAMPLE_RATE = 16000  # Whisper expects 16kHz audio
CHANNELS = 1  # Mono audio
DTYPE = 'float32'
BUFFER_DURATION = 5  # Duration in seconds for each audio chunk

# Queue for audio chunks
audio_queue = queue.Queue()

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

def main():
    parser = argparse.ArgumentParser(description="Listen to audio and transcribe using Whisper")
    parser.add_argument("--model", type=str, default="base", help="Whisper model size (tiny, base, small, medium, large)")
    parser.add_argument("--language", type=str, default=None, help="Language code (optional, e.g., 'en', 'es', 'fr')")
    parser.add_argument("--device", type=int, default=None, help="Audio input device index")
    parser.add_argument("--list-devices", action="store_true", help="List available audio devices and exit")
    args = parser.parse_args()

    if args.list_devices:
        print("Available audio devices:")
        print(sd.query_devices())
        return

    # Load the Whisper model
    model = load_model(args.model)
    print(f"Model loaded. Using {'default' if args.device is None else f'device {args.device}'} for audio input.")
    
    # Create a temporary directory for audio chunks
    temp_dir = tempfile.mkdtemp()
    print(f"Temporary files will be stored in: {temp_dir}")

    try:
        # Start the audio stream
        with sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype=DTYPE,
            callback=audio_callback,
            device=args.device
        ):
            print("\nListening... Press Ctrl+C to stop.\n")
            
            # Process audio chunks
            while True:
                # Collect audio for BUFFER_DURATION seconds
                audio_data = []
                collection_start = time.time()
                
                while time.time() - collection_start < BUFFER_DURATION:
                    try:
                        chunk = audio_queue.get(timeout=0.1)
                        audio_data.append(chunk)
                    except queue.Empty:
                        pass
                
                if not audio_data:
                    continue
                
                # Concatenate audio chunks
                audio_data = np.concatenate(audio_data)
                
                # Save to temporary file
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                temp_file = os.path.join(temp_dir, f"audio_chunk_{timestamp}.wav")
                save_audio_chunk(audio_data, temp_file)
                
                # Transcribe
                print("\nTranscribing...")
                transcript = transcribe_audio(model, temp_file, args.language)
                
                if transcript:
                    print(f"Transcript: {transcript}")
                else:
                    print("No speech detected or transcription failed.")
                
                # Clean up the temporary file
                try:
                    os.remove(temp_file)
                except:
                    pass

    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
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

if __name__ == "__main__":
    main()