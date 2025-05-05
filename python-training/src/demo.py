"""
Demo script for real-time wakeword detection.
"""
import os
import argparse
import time
import queue
import threading
import numpy as np
import pyaudio
from datetime import datetime

from src.audio.processor import AudioProcessor
from src.models.wakeword import WakewordDetector

def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Demo wakeword detection")
    
    parser.add_argument("--model_path", type=str, required=True,
                       help="Path to the trained wakeword model")
    parser.add_argument("--threshold", type=float, default=0.5,
                       help="Confidence threshold for detection")
    parser.add_argument("--sample_rate", type=int, default=16000,
                       help="Audio sample rate")
    parser.add_argument("--frame_duration", type=float, default=1.0,
                       help="Duration of audio frame to process (seconds)")
    parser.add_argument("--hop_duration", type=float, default=0.5,
                       help="Hop duration between frames (seconds)")
    parser.add_argument("--device", type=str, default=None,
                       help="Device to run inference on (cuda or cpu, default: auto-detect)")
    parser.add_argument("--save_detections", action="store_true",
                       help="Save audio when wakeword is detected")
    parser.add_argument("--save_dir", type=str, default="detections",
                       help="Directory to save detected audio clips")
    
    return parser.parse_args()

def main():
    """Main function for wakeword detection demo."""
    args = parse_args()
    
    # Set device
    if args.device is None:
        import torch
        device = "cuda" if torch.cuda.is_available() else "cpu"
    else:
        device = args.device
    
    print(f"Using device: {device}")
    
    # Create save directory if needed
    if args.save_detections:
        os.makedirs(args.save_dir, exist_ok=True)
    
    # Initialize audio processor
    audio_processor = AudioProcessor(sample_rate=args.sample_rate)
    
    # Load model
    print(f"Loading model from {args.model_path}...")
    detector = WakewordDetector.load_model(args.model_path, device=device)
    print("Model loaded successfully")
    
    # Calculate parameters
    frame_size = int(args.frame_duration * args.sample_rate)
    hop_size = int(args.hop_duration * args.sample_rate)
    
    # Initialize PyAudio
    p = pyaudio.PyAudio()
    
    # Create audio queue and buffer
    audio_queue = queue.Queue()
    audio_buffer = np.zeros(frame_size, dtype=np.float32)
    
    # Flag for controlling the detection loop
    running = True
    
    # Callback for PyAudio to capture audio data
    def audio_callback(in_data, frame_count, time_info, status):
        if running:
            audio_queue.put(in_data)
        return (in_data, pyaudio.paContinue)
    
    # Start audio stream
    stream = p.open(
        format=pyaudio.paFloat32,
        channels=1,
        rate=args.sample_rate,
        input=True,
        frames_per_buffer=hop_size,
        stream_callback=audio_callback
    )
    
    print("\n=== Wakeword Detection Demo ===")
    print(f"Listening for wakeword with threshold {args.threshold}")
    print("Press Ctrl+C to stop")
    
    # Start stream
    stream.start_stream()
    
    try:
        detection_count = 0
        last_detection_time = 0
        cooldown_period = 2.0  # seconds between detections
        
        while running:
            try:
                # Get audio data from queue
                data = audio_queue.get(timeout=1.0)
                
                # Convert bytes to numpy array
                chunk = np.frombuffer(data, dtype=np.float32)
                
                # Update buffer (shift and add new data)
                audio_buffer = np.roll(audio_buffer, -len(chunk))
                audio_buffer[-len(chunk):] = chunk
                
                # Extract features
                mfcc = audio_processor.extract_mfcc(audio_buffer)
                
                # Make prediction
                predicted_class, confidence = detector.predict(mfcc)
                
                # Check if wakeword detected
                current_time = time.time()
                if (predicted_class == 1 and confidence >= args.threshold and 
                    current_time - last_detection_time > cooldown_period):
                    
                    detection_count += 1
                    last_detection_time = current_time
                    
                    # Print detection info
                    timestamp = datetime.now().strftime("%H:%M:%S")
                    print(f"[{timestamp}] Wakeword detected! (Confidence: {confidence:.4f})")
                    
                    # Save audio if requested
                    if args.save_detections:
                        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                        filename = f"detection_{timestamp}.wav"
                        filepath = os.path.join(args.save_dir, filename)
                        
                        import soundfile as sf
                        sf.write(filepath, audio_buffer, args.sample_rate)
                        print(f"Saved detection to {filepath}")
            
            except queue.Empty:
                continue
            
            except KeyboardInterrupt:
                running = False
                break
    
    finally:
        # Clean up
        print("\nStopping...")
        running = False
        stream.stop_stream()
        stream.close()
        p.terminate()
        
        print(f"Demo finished with {detection_count} detections")

if __name__ == "__main__":
    main()