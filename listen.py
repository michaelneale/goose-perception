#!/usr/bin/env python3
"""
listen.py - Continuously listen to audio, detect wake word, and capture full conversations
"""

# Set environment variables before importing libraries
import os
os.environ["TOKENIZERS_PARALLELISM"] = "false"

import subprocess
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
from fuzzywuzzy import fuzz

# Import our agent module
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import agent

# Add the wake-classifier directory to the path
sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'wake-classifier'))

# Import the wake classifier
from classifier import GooseWakeClassifier

# Initialize the Whisper models
def load_models():
    print(f"Loading Whisper models...")
    # Suppress the FP16 warning
    import warnings
    warnings.filterwarnings("ignore", message="FP16 is not supported on CPU; using FP32 instead")
    
    # MPS (Metal) support is still limited for some operations in Whisper
    # For now, we'll use CPU for better compatibility
    
    # Load the main model for full transcription
    print(f"Loading main transcription model ...")
    main_model = whisper.load_model("small")
    
    print(f"Loading lightweight model for wake word detection...")
    wake_word_model = whisper.load_model("base")
    
    print("Using CPU for Whisper models (MPS has compatibility issues with sparse tensors)")
    return main_model, wake_word_model

# Audio parameters - technical settings that rarely need changing
SAMPLE_RATE = 16000  # Whisper expects 16kHz audio
CHANNELS = 1  # Mono audio
DTYPE = 'float32'
BUFFER_DURATION = 2  # Duration in seconds for each audio chunk
LONG_BUFFER_DURATION = 60  # Duration in seconds for the longer context (1 minute)

# Audio threshold settings
SILENCE_THRESHOLD = 0.01  # Base threshold for silence detection
NOISE_FLOOR_THRESHOLD = 0.005  # Threshold for background noise floor
SPEECH_ACTIVITY_THRESHOLD = 0.02  # Threshold for detecting actual speech
MAX_NOISE_RATIO = 0.7  # Maximum ratio of noise to signal for accepting audio

# Default configuration - these can be overridden by command line arguments
# and should match the defaults in run.sh
DEFAULT_CONTEXT_DURATION = 30  # Duration in seconds to keep before wake word
DEFAULT_SILENCE_DURATION = 3   # Duration of silence to end active listening
DEFAULT_FUZZY_THRESHOLD = 80   # Fuzzy matching threshold (0-100)
DEFAULT_CLASSIFIER_THRESHOLD = 0.6  # Confidence threshold for classifier (0-1)

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

def quick_transcribe(model, audio_file, language=None):
    """
    Perform a quick transcription for wake word detection.
    This is a blocking call but uses the lightweight model.
    """
    try:
        options = {}
        if language:
            options["language"] = language
        
        result = model.transcribe(audio_file, **options)
        return result["text"].strip()
    except Exception as e:
        print(f"Quick transcription error: {e}")
        return ""

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

def contains_wake_word(text, classifier=None, fuzzy_threshold=80, classifier_threshold=0.6, recordings_dir="recordings"):
    """
    Check if the text contains the wake word 'goose' and is addressed to Goose
    
    Args:
        text (str): The text to check for wake word
        classifier (GooseWakeClassifier): The classifier to use
        fuzzy_threshold (int): Minimum fuzzy match score (0-100) for wake word detection
        classifier_threshold (float): Minimum confidence threshold (0-1) for classifier
        recordings_dir (str): Directory to save activation logs
        
    Returns:
        bool: True if wake word detected and addressed to Goose, False otherwise
    """
    text_lower = text.lower()
    wake_word_detected = False
    is_addressed = False
    confidence = 0.0
    
    # First check: exact match for "goose"
    if "goose" in text_lower:
        wake_word_detected = True
        print(f"Detected exact wake word 'goose'... checking classifier now..")
        if classifier:
            details = classifier.classify_with_details(text)
            is_addressed = details["addressed_to_goose"]
            confidence = details["confidence"]
            
            # Check if confidence meets threshold
            if is_addressed and confidence >= classifier_threshold:
                print(f"✅ Classifier confidence: {confidence:.2f} (threshold: {classifier_threshold})")
                # Log the successful activation
                log_activation_transcript(text, True, confidence, recordings_dir)
                return True
            elif is_addressed:
                print(f"👎 Classifier confidence too low: {confidence:.2f} < {classifier_threshold}")
            else:
                print(f"👎 Not addressed to Goose. Score: {confidence:.2f}")
            
            # Log the bypassed activation
            log_activation_transcript(text, False, confidence, recordings_dir)
            return False
    
    # Second check: fuzzy match for "goose" (only if exact match failed)
    # Split text into words and check each one
    if not wake_word_detected:
        words = text_lower.split()
        for word in words:
            # Calculate fuzzy match score
            score = fuzz.ratio("goose", word)
            if score >= fuzzy_threshold:
                wake_word_detected = True
                print(f"Detected fuzzy wake word match: '{word}' with score {score}... checking classifier now..")
                if classifier:
                    details = classifier.classify_with_details(text)
                    is_addressed = details["addressed_to_goose"]
                    confidence = details["confidence"]
                    
                    # Check if confidence meets threshold
                    if is_addressed and confidence >= classifier_threshold:
                        print(f"✅ Classifier confidence: {confidence:.2f} (threshold: {classifier_threshold})")
                        # Log the successful activation
                        log_activation_transcript(text, True, confidence, recordings_dir)
                        return True
                    elif is_addressed:
                        print(f"👎 Classifier confidence too low: {confidence:.2f} < {classifier_threshold}")
                    else:
                        print(f"👎 Not addressed to Goose. Score: {confidence:.2f}")
                    
                    # Log the bypassed activation
                    log_activation_transcript(text, False, confidence, recordings_dir)
                break
    
    return False

def log_activation_transcript(text, triggered, confidence, recordings_dir):
    """
    Log activation transcripts for analysis and retraining
    
    Args:
        text (str): The transcript text
        triggered (bool): Whether this activation triggered Goose
        confidence (float): The classifier confidence score
        recordings_dir (str): Directory to save logs
    """
    try:
        # Create a timestamped filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        prefix = "activation_triggered" if triggered else "activation_bypassed"
        filename = f"{prefix}_{timestamp}.txt"
        filepath = os.path.join(recordings_dir, filename)
        
        # Save the transcript with metadata
        with open(filepath, "w") as f:
            f.write(f"TIMESTAMP: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"CONFIDENCE: {confidence:.4f}\n")
            f.write(f"TRIGGERED: {triggered}\n")
            f.write("TRANSCRIPT:\n")
            f.write(text)
        
        print(f"Saved activation transcript to {filepath}")
    except Exception as e:
        print(f"Error saving activation transcript: {e}")

def is_silence(audio_data, threshold=SILENCE_THRESHOLD):
    """Check if audio chunk is silence based on amplitude threshold"""
    return np.mean(np.abs(audio_data)) < threshold

def notify_user(message):
    subprocess.call(f"""
                    osascript -e 'display notification "{message} " with title "Goose"'
                    """, shell=True)

def analyze_audio(audio_data):
    """
    Analyze audio data to determine if it contains speech or just noise.
    
    Returns:
        dict: Analysis results containing:
            - is_silence: Whether the audio is below silence threshold
            - is_speech: Whether the audio appears to contain speech
            - signal_level: The average signal level
            - noise_ratio: Estimated ratio of noise to signal
    """
    # Calculate basic metrics
    abs_data = np.abs(audio_data)
    mean_level = np.mean(abs_data)
    
    # Calculate more advanced metrics
    std_dev = np.std(abs_data)  # Standard deviation helps distinguish noise from speech
    peak_level = np.max(abs_data)  # Peak level
    
    # Zero-crossing rate can help distinguish speech from noise
    # Speech typically has lower zero-crossing rate than noise
    zero_crossings = np.sum(np.diff(np.signbit(audio_data).astype(int)) != 0)
    zero_crossing_rate = zero_crossings / len(audio_data)
    
    # Calculate noise ratio (lower is better)
    # For speech, std_dev is usually higher relative to mean
    noise_ratio = 0.0
    if peak_level > 0:
        noise_ratio = mean_level / (peak_level * std_dev + 1e-10)
    
    # Determine if this is silence
    is_silence = mean_level < SILENCE_THRESHOLD
    
    # Determine if this is likely speech vs noise
    # Speech typically has higher variance and lower zero-crossing rate than noise
    is_speech = (
        mean_level >= SPEECH_ACTIVITY_THRESHOLD and
        noise_ratio < MAX_NOISE_RATIO and
        zero_crossing_rate < 0.5  # Typical threshold for speech
    )
    
    return {
        "is_silence": is_silence,
        "is_speech": is_speech,
        "signal_level": mean_level,
        "noise_ratio": noise_ratio,
        "zero_crossing_rate": zero_crossing_rate
    }

def main():
    parser = argparse.ArgumentParser(description="Listen to audio and transcribe using Whisper")
    parser.add_argument("--language", type=str, default=None, help="Language code (optional, e.g., 'en', 'es', 'fr')")
    parser.add_argument("--device", type=int, default=None, help="Audio input device index")
    parser.add_argument("--channels", type=int, default=CHANNELS, help="Number of audio channels (default: 1)")
    parser.add_argument("--list-devices", action="store_true", help="List available audio devices and exit")
    parser.add_argument("--recordings-dir", type=str, default="recordings", help="Directory to save long transcriptions")
    parser.add_argument("--context-seconds", type=int, default=DEFAULT_CONTEXT_DURATION, 
                        help=f"Seconds of context to keep before wake word (default: {DEFAULT_CONTEXT_DURATION})")
    parser.add_argument("--silence-seconds", type=int, default=DEFAULT_SILENCE_DURATION,
                        help=f"Seconds of silence to end active listening (default: {DEFAULT_SILENCE_DURATION})")
    parser.add_argument("--use-lightweight-model", action="store_true", default=True,
                        help="Use lightweight model (tiny) for wake word detection (default: True)")
    parser.add_argument("--no-lightweight-model", action="store_false", dest="use_lightweight_model",
                        help="Don't use lightweight model for wake word detection")
    parser.add_argument("--fuzzy-threshold", type=int, default=DEFAULT_FUZZY_THRESHOLD,
                        help=f"Fuzzy matching threshold for wake word detection (0-100, default: {DEFAULT_FUZZY_THRESHOLD})")
    parser.add_argument("--classifier-threshold", type=float, default=DEFAULT_CLASSIFIER_THRESHOLD,
                        help=f"Confidence threshold for wake word classifier (0-1, default: {DEFAULT_CLASSIFIER_THRESHOLD})")
    parser.add_argument("--silence-threshold", type=float, default=SILENCE_THRESHOLD,
                        help=f"Threshold for silence detection (default: {SILENCE_THRESHOLD})")
    parser.add_argument("--speech-threshold", type=float, default=SPEECH_ACTIVITY_THRESHOLD,
                        help=f"Threshold for speech activity detection (default: {SPEECH_ACTIVITY_THRESHOLD})")
    parser.add_argument("--noise-ratio", type=float, default=MAX_NOISE_RATIO,
                        help=f"Maximum noise-to-signal ratio to accept audio (default: {MAX_NOISE_RATIO})")
    parser.add_argument("--noise-reduction", action="store_true", default=True,
                        help="Enable enhanced noise reduction (default: True)")
    parser.add_argument("--no-noise-reduction", action="store_false", dest="noise_reduction",
                        help="Disable enhanced noise reduction")
    args = parser.parse_args()

    if args.list_devices:
        print("Available audio devices:")
        print(sd.query_devices())
        return

    # Set up signal handlers for clean termination
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Load the Whisper model
    main_model, wake_word_model = load_models()
    print(f"Models loaded. Using {'default' if args.device is None else f'device {args.device}'} for audio input.")
    print(f"Listening for wake word: 'goose' (fuzzy threshold: {args.fuzzy_threshold}, classifier threshold: {args.classifier_threshold})")
    
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
            
            if is_active_listening:
                # In active listening mode, use the main model for high-quality transcription
                if not transcription_in_progress:
                    # Start transcribing with the main model
                    start_transcription(main_model, temp_file, args.language)
                    transcription_in_progress = True
                    current_temp_file = temp_file
                
                # If a transcription is in progress, check if it's complete
                if transcription_event.is_set():
                    # Get the result
                    transcript = get_transcription_result()
                    transcription_in_progress = False
                    
                    # Add the previous chunk to the active conversation
                    if current_temp_file:
                        active_conversation_chunks.append((audio_data, current_temp_file, transcript))
                    
                    # Print what we're hearing
                    print(f"🎙️ Active: {transcript}")
                    
                    # Check for wake word during active listening
                    # This allows for chained commands without waiting for silence
                    if contains_wake_word(transcript, classifier, args.fuzzy_threshold, args.classifier_threshold, args.recordings_dir):
                        print("\n🔔 ADDITIONAL WAKE WORD DETECTED DURING ACTIVE LISTENING!")
                        print("Continuing to listen...")
                        
                        # Reset the silence counter to keep listening
                        silence_counter = 0
                    
                    # Check for silence to potentially end the active listening
                    if current_is_silence:
                        silence_counter += 1
                        print(f"Detected silence ({silence_counter}/{args.silence_seconds // BUFFER_DURATION})...")
                        notify_user("got it")
                    else:
                        silence_counter = 0
                    
                    # If we've had enough consecutive silence chunks, end the active listening
                    if silence_counter >= (args.silence_seconds // BUFFER_DURATION):
                        print("\n" + "="*80)
                        print(f"📢 CONVERSATION COMPLETE - DETECTED {args.silence_seconds}s OF SILENCE")
                        
                        # Process the full conversation (context + active)
                        all_audio = []
                        
                        # First add the context buffer audio (ignore lightweight transcripts)
                        for context_audio, _, _ in context_buffer:
                            all_audio.append(context_audio)
                        
                        # Then add the active conversation audio
                        for conv_audio, _, _ in active_conversation_chunks:
                            all_audio.append(conv_audio)
                        
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
                            
                            # Re-transcribe the entire audio with the main model for high quality
                            print("Re-transcribing full conversation with main model...")
                            full_result = main_model.transcribe(conversation_file, language=args.language)
                            full_transcript = full_result["text"].strip()
                            
                            # Save the transcript
                            transcript_file = os.path.join(
                                args.recordings_dir, 
                                f"conversation_{conversation_timestamp}.txt"
                            )
                            with open(transcript_file, "w") as f:
                                f.write(full_transcript)
                            
                            print(f"📝 FULL CONVERSATION TRANSCRIPT (transcribed with main model):")
                            print("-"*80)
                            print(full_transcript)
                            print("-"*80)
                            print(f"✅ Saved conversation to {conversation_file}")
                            print(f"✅ Saved transcript to {transcript_file}")
                            conversation_counter += 1
                            
                            # If an agent is specified, invoke it with the transcript file only
                            try:
                                print(f"🤖 Invoking agent module directly")
                                # Call the agent's process_conversation function directly
                                agent_result = agent.process_conversation(transcript_file)
                                
                                if agent_result and agent_result.get("background_process_started"):
                                    print(f"✅ Agent started processing in background")
                                else:
                                    print(f"⚠️ Agent may not have started properly")
                            except Exception as e:
                                print(f"⚠️ Error invoking agent: {e}")
                        
                        # Reset for next conversation
                        is_active_listening = False
                        active_conversation_chunks = []
                        silence_counter = 0
                        print("="*80)
                        print("Returning to passive listening mode. Waiting for wake word...")
            else:
                # In passive listening mode, use the lightweight model for wake word detection
                # This is a quick, blocking call but with the tiny model it should be fast
                quick_transcript = quick_transcribe(wake_word_model, temp_file, args.language)
                
                # Add to context buffer with the quick transcript
                context_buffer.append((audio_data, temp_file, quick_transcript))
                
                # Print a short status update
                if quick_transcript:
                    # Show a snippet of what was heard
                    snippet = quick_transcript[:30] + "..." if len(quick_transcript) > 30 else quick_transcript
                    print(f"Heard: {snippet} [{datetime.now().strftime('%H:%M:%S')}]", end="\r")
                
                # Check for wake word using the classifier with our thresholds
                if quick_transcript and contains_wake_word(quick_transcript, classifier, 
                                                         args.fuzzy_threshold, args.classifier_threshold,
                                                         args.recordings_dir):
                    timestamp = datetime.now().strftime('%H:%M:%S')
                    print(f"\n{'='*80}")
                    print(f"🔔 WAKE WORD DETECTED at {timestamp}!")
                    
                    # Get detailed classification information
                    details = classifier.classify_with_details(quick_transcript)
                    confidence = details['confidence'] * 100  # Convert to percentage
                    
                    print(f"✅ ADDRESSED TO GOOSE - Confidence: {confidence:.1f}%")
                    notify_user("Goose is listening...")
                    
                    print(f"Switching to active listening mode...")
                    print(f"Context from the last {args.context_seconds} seconds:")
                    
                    # Print the context from before the wake word
                    context_transcripts = [chunk[2] for chunk in context_buffer if chunk[2]]
                    if context_transcripts:
                        context_text = " ".join(context_transcripts)
                        print(f"📜 CONTEXT: {context_text}")
                    else:
                        print("(No speech detected in context window)")
                    
                    print(f"Wake word detected in: {quick_transcript}")
                    print("Now actively listening until silence is detected...")
                    print(f"{'='*80}")
                    
                    # Switch to active listening mode
                    is_active_listening = True
                    active_conversation_chunks = list(context_buffer)  # Start with the context
                    silence_counter = 0
                    
                    # Start a high-quality transcription of the current chunk with the main model
                    start_transcription(main_model, temp_file, args.language)
                    transcription_in_progress = True
                    current_temp_file = temp_file
                
                # If we're not in active mode and not processing wake word, 
                # we don't need to start a background transcription
                
            
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