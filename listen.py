#!/usr/bin/env python3
"""
listen.py - Continuously listen to audio, detect wake word, and capture full conversations
"""

# Set environment variables before importing libraries
import os
os.environ["TOKENIZERS_PARALLELISM"] = "false"

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
import sys

# Add the wake-classifier directory to the path
sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'wake-classifier'))

# Import the wake classifier
from classifier import GooseWakeClassifier

# Initialize the Whisper model
def load_model(model_name):
    print(f"Loading Whisper model: {model_name}...")
    # Suppress the FP16 warning
    import warnings
    warnings.filterwarnings("ignore", message="FP16 is not supported on CPU; using FP32 instead")
    
    # MPS (Metal) support is still limited for some operations in Whisper
    # For now, we'll use CPU for better compatibility
    model = whisper.load_model(model_name)
    print("Using CPU for Whisper model (MPS has compatibility issues with sparse tensors)")
    return model

# Audio parameters
SAMPLE_RATE = 16000  # Whisper expects 16kHz audio
CHANNELS = 1  # Mono audio
DTYPE = 'float32'
BUFFER_DURATION = 5  # Duration in seconds for each audio chunk
LONG_BUFFER_DURATION = 60  # Duration in seconds for the longer context (1 minute)
CONTEXT_DURATION = 30  # Duration in seconds to keep before wake word
SILENCE_THRESHOLD = 0.01  # Threshold for silence detection
SILENCE_DURATION = 3  # Duration of silence to end active listening

# Queue for audio chunks
audio_queue = queue.Queue()

# Flag to control the main loop
running = True

# Transcription thread control
transcription_thread = None
transcription_event = threading.Event()
transcription_result = None
transcription_lock = threading.Lock()

def signal_handler(sig, frame):
    """Handle interrupt signals for clean shutdown"""
    global running
    print("\nReceived interrupt signal. Shutting down...")
    running = False
    if transcription_thread and transcription_thread.is_alive():
        transcription_event.set()  # Signal the transcription thread to exit

def cleanup_resources():
    """Clean up any resources that might be in use"""
    try:
        # Try to reset the audio system
        sd._terminate()
        sd._initialize()
        print("Audio system reset.")
    except Exception as e:
        print(f"Error during audio system reset: {e}")
        
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

def transcribe_audio_thread(model, audio_file, language=None):
    """Transcribe audio file using Whisper in a separate thread."""
    global transcription_result
    
    try:
        options = {}
        if language:
            options["language"] = language
        
        result = model.transcribe(audio_file, **options)
        transcript = result["text"].strip()
        
        # Store the result
        with transcription_lock:
            transcription_result = transcript
        
    except Exception as e:
        print(f"Transcription error: {e}")
        with transcription_lock:
            transcription_result = ""
    
    # Signal that transcription is complete
    transcription_event.set()

def start_transcription(model, audio_file, language=None):
    """Start a transcription in a background thread."""
    global transcription_thread, transcription_result, transcription_event
    
    # Reset the event and result
    transcription_event.clear()
    with transcription_lock:
        transcription_result = None
    
    # Start the transcription thread
    transcription_thread = threading.Thread(
        target=transcribe_audio_thread,
        args=(model, audio_file, language)
    )
    transcription_thread.daemon = True
    transcription_thread.start()

def get_transcription_result(timeout=None):
    """Get the result of the transcription, waiting if necessary."""
    # Wait for the transcription to complete
    if timeout is not None:
        transcription_event.wait(timeout)
    else:
        transcription_event.wait()
    
    # Get the result
    with transcription_lock:
        result = transcription_result
    
    return result

def contains_wake_word(text, classifier=None):
    """Check if the text contains the wake word 'goose' and is addressed to Goose"""
    # Use the classifier to determine if the text is addressed to Goose
    if "goose" in text.lower():
        print(f"Detected wake word 'goose'.... checking classifier now..")
        if classifier:
            return classifier.classify(text)
    return False

def is_silence(audio_data, threshold=SILENCE_THRESHOLD):
    """Check if audio chunk is silence based on amplitude threshold"""
    return np.mean(np.abs(audio_data)) < threshold

def main():
    parser = argparse.ArgumentParser(description="Listen to audio and transcribe using Whisper")
    parser.add_argument("--model", type=str, default="base", help="Whisper model size (tiny, base, small, medium, large)")
    parser.add_argument("--language", type=str, default=None, help="Language code (optional, e.g., 'en', 'es', 'fr')")
    parser.add_argument("--device", type=int, default=None, help="Audio input device index")
    parser.add_argument("--channels", type=int, default=CHANNELS, help="Number of audio channels (default: 1)")
    parser.add_argument("--list-devices", action="store_true", help="List available audio devices and exit")
    parser.add_argument("--recordings-dir", type=str, default="recordings", help="Directory to save long transcriptions")
    parser.add_argument("--context-seconds", type=int, default=CONTEXT_DURATION, 
                        help=f"Seconds of context to keep before wake word (default: {CONTEXT_DURATION})")
    parser.add_argument("--silence-seconds", type=int, default=SILENCE_DURATION,
                        help=f"Seconds of silence to end active listening (default: {SILENCE_DURATION})")
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
    print(f"Listening for wake word: 'goose'")
    
    # Initialize the wake word classifier
    print("Initializing wake word classifier...")
    classifier = GooseWakeClassifier.get_instance()
    print("Wake word classifier initialized.")
    
    # Create a temporary directory for audio chunks
    temp_dir = tempfile.mkdtemp()
    print(f"Temporary files will be stored in: {temp_dir}")
    
    # Create recordings directory if it doesn't exist
    os.makedirs(args.recordings_dir, exist_ok=True)
    print(f"Long transcriptions will be saved in: {args.recordings_dir}")

    # Audio stream object
    stream = None
    
    # Initialize a deque to store context before wake word
    # Each chunk is BUFFER_DURATION seconds, so we need (CONTEXT_DURATION / BUFFER_DURATION) chunks
    context_chunks = int(args.context_seconds / BUFFER_DURATION)
    context_buffer = deque(maxlen=context_chunks)
    
    # Initialize a counter for the long transcriptions
    conversation_counter = 0
    
    # Timer for long transcription
    last_long_transcription_time = time.time()
    
    # State tracking
    is_active_listening = False
    active_conversation_chunks = []
    silence_counter = 0
    
    # Current transcription state
    current_temp_file = None
    transcription_in_progress = False

    try:
        # Start the audio stream
        try:
            stream = sd.InputStream(
                samplerate=SAMPLE_RATE,
                channels=args.channels,
                dtype=DTYPE,
                callback=audio_callback,
                device=args.device
            )
            stream.start()
        except Exception as e:
            print(f"\nError opening audio input stream: {e}")
            print("\nAvailable audio devices:")
            print(sd.query_devices())
            print("\nTry specifying a different device with --device <number>")
            print("or a different number of channels with --channels <number>")
            return
        
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
            
            # Check for silence if in active listening mode
            current_is_silence = is_silence(audio_data)
            
            # If a transcription is in progress, check if it's complete
            if transcription_in_progress:
                if transcription_event.is_set():
                    # Get the result
                    transcript = get_transcription_result()
                    transcription_in_progress = False
                    
                    # Process the transcribed chunk
                    if is_active_listening:
                        # We're in active listening mode after wake word detection
                        
                        # Add the previous chunk to the active conversation
                        if current_temp_file:
                            active_conversation_chunks.append((audio_data, current_temp_file, transcript))
                        
                        # Print what we're hearing
                        print(f"🎙️ Active: {transcript}")
                        
                        # Check for silence to potentially end the active listening
                        if current_is_silence:
                            silence_counter += 1
                            print(f"Detected silence ({silence_counter}/{args.silence_seconds // BUFFER_DURATION})...")
                        else:
                            silence_counter = 0
                        
                        # If we've had enough consecutive silence chunks, end the active listening
                        if silence_counter >= (args.silence_seconds // BUFFER_DURATION):
                            print("\n" + "="*80)
                            print(f"📢 CONVERSATION COMPLETE - DETECTED {args.silence_seconds}s OF SILENCE")
                            
                            # Process the full conversation (context + active)
                            all_audio = []
                            all_transcripts = []
                            
                            # First add the context buffer
                            for context_audio, _, context_transcript in context_buffer:
                                all_audio.append(context_audio)
                                if context_transcript:
                                    all_transcripts.append(context_transcript)
                            
                            # Then add the active conversation
                            for conv_audio, _, conv_transcript in active_conversation_chunks:
                                all_audio.append(conv_audio)
                                if conv_transcript:
                                    all_transcripts.append(conv_transcript)
                            
                            # Concatenate all audio
                            if all_audio:
                                full_audio = np.concatenate(all_audio)
                                
                                # Save the full conversation
                                conversation_timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                                conversation_file = os.path.join(
                                    args.recordings_dir, 
                                    f"conversation_{conversation_timestamp}.wav"
                                )
                                save_audio_chunk(full_audio, conversation_file)
                                
                                # Create the full transcript
                                full_transcript = " ".join(all_transcripts)
                                
                                # Save the transcript
                                transcript_file = os.path.join(
                                    args.recordings_dir, 
                                    f"conversation_{conversation_timestamp}.txt"
                                )
                                with open(transcript_file, "w") as f:
                                    f.write(full_transcript)
                                
                                print(f"📝 FULL CONVERSATION TRANSCRIPT:")
                                print("-"*80)
                                print(full_transcript)
                                print("-"*80)
                                print(f"✅ Saved conversation to {conversation_file}")
                                print(f"✅ Saved transcript to {transcript_file}")
                                conversation_counter += 1
                            
                            # Reset for next conversation
                            is_active_listening = False
                            active_conversation_chunks = []
                            silence_counter = 0
                            print("="*80)
                            print("Returning to passive listening mode. Waiting for wake word...")
                    else:
                        # We're in passive listening mode, waiting for wake word
                        
                        # Add to context buffer
                        context_buffer.append((audio_data, current_temp_file, transcript))
                        
                        # Print a short status update occasionally
                        if transcript:
                            # Show a snippet of what was heard
                            snippet = transcript[:30] + "..." if len(transcript) > 30 else transcript
                            print(f"Heard: {snippet} [{datetime.now().strftime('%H:%M:%S')}]", end="\r")
                        
                        # Check for wake word using the classifier
                        if transcript and contains_wake_word(transcript, classifier):
                            timestamp = datetime.now().strftime('%H:%M:%S')
                            print(f"\n{'='*80}")
                            print(f"🔔 WAKE WORD DETECTED at {timestamp}!")
                            
                            # Get detailed classification information
                            details = classifier.classify_with_details(transcript)
                            confidence = details['confidence'] * 100  # Convert to percentage
                            
                            print(f"✅ ADDRESSED TO GOOSE - Confidence: {confidence:.1f}%")
                            
                            print(f"Switching to active listening mode...")
                            print(f"Context from the last {args.context_seconds} seconds:")
                            
                            # Print the context from before the wake word
                            context_transcripts = [chunk[2] for chunk in context_buffer if chunk[2]]
                            if context_transcripts:
                                context_text = " ".join(context_transcripts)
                                print(f"📜 CONTEXT: {context_text}")
                            else:
                                print("(No speech detected in context window)")
                            
                            print(f"Wake word detected in: {transcript}")
                            print("Now actively listening until silence is detected...")
                            print(f"{'='*80}")
                            
                            # Switch to active listening mode
                            is_active_listening = True
                            active_conversation_chunks = list(context_buffer)  # Start with the context
                            silence_counter = 0
            
            # Start a new transcription if none is in progress
            if not transcription_in_progress:
                # Start transcribing the current chunk
                start_transcription(model, temp_file, args.language)
                transcription_in_progress = True
                current_temp_file = temp_file
            
            # Check if it's time for a long transcription (every minute)
            current_time = time.time()
            if current_time - last_long_transcription_time >= LONG_BUFFER_DURATION:
                # Process the context buffer for a periodic long transcription
                if context_buffer and not is_active_listening:
                    # Concatenate all audio chunks in the buffer
                    buffer_audio = [chunk[0] for chunk in context_buffer]
                    if buffer_audio:
                        long_audio = np.concatenate(buffer_audio)
                        
                        # Save the long audio to a file in the recordings directory
                        long_timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                        long_file = os.path.join(args.recordings_dir, f"periodic_{long_timestamp}.wav")
                        save_audio_chunk(long_audio, long_file)
                        
                        # We'll transcribe this in the background when we have a chance
                        # For now, just save the audio file
                        print("\n" + "-"*80)
                        print(f"📝 PERIODIC AUDIO SAVED [{datetime.now().strftime('%H:%M:%S')}]")
                        print(f"📜 Saved to {long_file}")
                        print("-"*80)
                
                # Reset the timer
                last_long_transcription_time = current_time
            
            # Clean up the temporary file if it's not in use
            if temp_file != current_temp_file and \
               temp_file not in [chunk[1] for chunk in context_buffer] and \
               temp_file not in [chunk[1] for chunk in active_conversation_chunks]:
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
        
        # Reset audio system
        cleanup_resources()
        
        # Clean up temporary files
        all_temp_files = set()
        for _, temp_file, _ in context_buffer:
            all_temp_files.add(temp_file)
        for _, temp_file, _ in active_conversation_chunks:
            all_temp_files.add(temp_file)
        
        for temp_file in all_temp_files:
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
        print(f"Created {conversation_counter} conversation transcriptions in {args.recordings_dir}")

if __name__ == "__main__":
    main()