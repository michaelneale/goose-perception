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
import concurrent.futures
from typing import Optional, Tuple, Dict, Any

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

# Priority levels for transcription tasks
class Priority:
    HIGH = 1  # For short chunks used in wake word detection
    LOW = 2   # For long transcriptions and conversation saving

# Transcription task class
class TranscriptionTask:
    def __init__(self, audio_file: str, language: Optional[str], priority: int, task_id: str):
        self.audio_file = audio_file
        self.language = language
        self.priority = priority
        self.task_id = task_id
        self.timestamp = time.time()
    
    def __lt__(self, other):
        # Compare based on priority first, then timestamp
        if self.priority != other.priority:
            return self.priority < other.priority
        return self.timestamp < other.timestamp

# Transcription service class
class TranscriptionService:
    def __init__(self, model, max_workers=2):
        self.model = model
        self.executor = concurrent.futures.ThreadPoolExecutor(max_workers=max_workers)
        self.task_queue = queue.PriorityQueue()
        self.futures = {}
        self.results = {}
        self.running = True
        self.worker_thread = threading.Thread(target=self._worker_loop)
        self.worker_thread.daemon = True
        self.worker_thread.start()
    
    def _worker_loop(self):
        """Worker loop that processes transcription tasks"""
        while self.running:
            try:
                # Get the next task from the queue
                task = self.task_queue.get(timeout=0.5)
                
                # Submit the task to the thread pool
                future = self.executor.submit(
                    self._transcribe_task, 
                    task.audio_file, 
                    task.language
                )
                
                # Store the future for later retrieval
                self.futures[task.task_id] = future
                
                # Mark the task as done in the queue
                self.task_queue.task_done()
            except queue.Empty:
                # No tasks in the queue, continue the loop
                continue
            except Exception as e:
                print(f"Error in transcription worker: {e}")
    
    def _transcribe_task(self, audio_file, language):
        """Perform the actual transcription"""
        try:
            options = {}
            if language:
                options["language"] = language
            
            result = self.model.transcribe(audio_file, **options)
            return result["text"].strip()
        except Exception as e:
            print(f"Transcription error: {e}")
            return ""
    
    def submit_task(self, audio_file, language=None, priority=Priority.HIGH):
        """Submit a new transcription task"""
        task_id = f"{time.time()}_{id(audio_file)}"
        task = TranscriptionTask(audio_file, language, priority, task_id)
        self.task_queue.put(task)
        return task_id
    
    def get_result(self, task_id, timeout=None):
        """Get the result of a transcription task"""
        # Check if we already have the result
        if task_id in self.results:
            result = self.results.pop(task_id)
            return result
        
        # Check if the task is still running
        if task_id in self.futures:
            try:
                # Wait for the task to complete
                future = self.futures[task_id]
                result = future.result(timeout=timeout)
                
                # Clean up
                del self.futures[task_id]
                
                return result
            except concurrent.futures.TimeoutError:
                # Task is still running
                return None
            except Exception as e:
                print(f"Error getting transcription result: {e}")
                # Clean up
                if task_id in self.futures:
                    del self.futures[task_id]
                return ""
        
        # Task not found
        return None
    
    def shutdown(self):
        """Shutdown the transcription service"""
        self.running = False
        if self.worker_thread.is_alive():
            self.worker_thread.join(timeout=1.0)
        self.executor.shutdown(wait=False)

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

def signal_handler(sig, frame):
    """Handle interrupt signals for clean shutdown"""
    global running
    print("\nReceived interrupt signal. Shutting down...")
    running = False

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

def transcribe_audio(transcription_service, audio_file, language=None, priority=Priority.HIGH, timeout=None):
    """Submit audio file for transcription and optionally wait for the result."""
    try:
        # Submit the transcription task
        task_id = transcription_service.submit_task(audio_file, language, priority)
        
        # If timeout is provided, wait for the result
        if timeout is not None:
            return transcription_service.get_result(task_id, timeout)
        
        # Otherwise, return the task ID for later retrieval
        return task_id
    except Exception as e:
        print(f"Error submitting transcription: {e}")
        return "" if timeout is not None else None

def get_transcription_result(transcription_service, task_id, timeout=None):
    """Get the result of a previously submitted transcription task."""
    return transcription_service.get_result(task_id, timeout)

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
    parser.add_argument("--transcription-threads", type=int, default=2,
                        help="Number of threads to use for transcription (default: 2)")
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
    
    # Initialize the transcription service
    print(f"Initializing transcription service with {args.transcription_threads} threads...")
    transcription_service = TranscriptionService(model, max_workers=args.transcription_threads)
    print("Transcription service initialized.")
    
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
    
    # Dictionary to track pending transcription tasks
    pending_tasks = {}

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
            
            # Submit the current chunk for transcription with HIGH priority
            task_id = transcribe_audio(
                transcription_service, 
                temp_file, 
                args.language,
                priority=Priority.HIGH
            )
            
            # Store the task ID along with the chunk information
            chunk_info = (audio_data, temp_file, None)  # Transcript will be filled in later
            pending_tasks[task_id] = {
                'chunk_info': chunk_info,
                'timestamp': time.time(),
                'processed': False
            }
            
            # Process completed transcription tasks
            completed_tasks = []
            for task_id, task_info in pending_tasks.items():
                if not task_info['processed']:
                    # Try to get the result with a short timeout
                    transcript = get_transcription_result(transcription_service, task_id, timeout=0.01)
                    
                    if transcript is not None:  # Result is available
                        # Update the chunk info with the transcript
                        audio_data, temp_file, _ = task_info['chunk_info']
                        task_info['chunk_info'] = (audio_data, temp_file, transcript)
                        task_info['processed'] = True
                        completed_tasks.append(task_id)
                        
                        # Process the transcribed chunk
                        if is_active_listening:
                            # We're in active listening mode after wake word detection
                            
                            # Add this chunk to the active conversation
                            active_conversation_chunks.append(task_info['chunk_info'])
                            
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
                            context_buffer.append(task_info['chunk_info'])
                            
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
            
            # Clean up completed tasks
            for task_id in completed_tasks:
                if task_id in pending_tasks:
                    del pending_tasks[task_id]
            
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
                        
                        # Transcribe the long audio with LOW priority
                        print("\n" + "-"*80)
                        print(f"📝 PERIODIC TRANSCRIPTION [{datetime.now().strftime('%H:%M:%S')}]")
                        
                        # Submit for transcription but don't wait for the result
                        long_task_id = transcribe_audio(
                            transcription_service,
                            long_file,
                            args.language,
                            priority=Priority.LOW
                        )
                        
                        # We'll check for the result in the next iteration
                        pending_tasks[long_task_id] = {
                            'chunk_info': (None, long_file, None),
                            'timestamp': time.time(),
                            'processed': False,
                            'is_long': True,
                            'long_timestamp': long_timestamp
                        }
                
                # Reset the timer
                last_long_transcription_time = current_time
            
            # Process completed long transcription tasks
            for task_id, task_info in list(pending_tasks.items()):
                if task_info.get('is_long', False) and not task_info['processed']:
                    # Try to get the result with a short timeout
                    transcript = get_transcription_result(transcription_service, task_id, timeout=0.01)
                    
                    if transcript is not None:  # Result is available
                        task_info['processed'] = True
                        long_timestamp = task_info.get('long_timestamp')
                        long_file = task_info['chunk_info'][1]
                        
                        # Save the transcription to a text file
                        transcript_file = os.path.join(args.recordings_dir, f"periodic_{long_timestamp}.txt")
                        with open(transcript_file, "w") as f:
                            f.write(transcript)
                        
                        print(f"📜 LAST {args.context_seconds} SECONDS:\n{transcript}")
                        print("-"*80)
                        
                        # Clean up
                        completed_tasks.append(task_id)
            
            # Clean up the temporary file if it's not in use
            if temp_file not in [chunk[1] for chunk in context_buffer] and \
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
        
        # Shutdown the transcription service
        if 'transcription_service' in locals():
            print("Shutting down transcription service...")
            transcription_service.shutdown()
        
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