"""
Script for collecting wakeword audio samples.
"""
import os
import argparse
import time

from src.audio.recorder import AudioRecorder

def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Collect wakeword audio samples")
    
    parser.add_argument("--output_dir", type=str, default="data/raw",
                       help="Directory to save recorded audio")
    parser.add_argument("--wakeword", type=str, default="goose",
                       help="The wakeword to record")
    parser.add_argument("--num_samples", type=int, default=20,
                       help="Number of wakeword samples to record")
    parser.add_argument("--num_negative", type=int, default=20,
                       help="Number of negative samples to record")
    parser.add_argument("--duration", type=float, default=2.0,
                       help="Duration of each recording in seconds")
    parser.add_argument("--pause", type=float, default=1.0,
                       help="Pause between recordings in seconds")
    parser.add_argument("--sample_rate", type=int, default=16000,
                       help="Sample rate for recordings")
    
    return parser.parse_args()

def main():
    """Main function for collecting audio samples."""
    args = parse_args()
    
    # Initialize recorder
    recorder = AudioRecorder(
        output_dir=args.output_dir,
        sample_rate=args.sample_rate
    )
    
    try:
        print("\n=== Wakeword Sample Collection ===\n")
        print(f"Wakeword: '{args.wakeword}'")
        print(f"Recording {args.num_samples} wakeword samples and {args.num_negative} negative samples")
        print(f"Each recording will be {args.duration} seconds long\n")
        
        input("Press Enter to start recording wakeword samples...")
        
        # Record wakeword samples
        print(f"\nRecording {args.num_samples} samples of the wakeword '{args.wakeword}'")
        print("Please speak the wakeword clearly when prompted")
        
        wakeword_files = recorder.record_multiple(
            count=args.num_samples,
            duration=args.duration,
            label=args.wakeword,
            pause=args.pause
        )
        
        print(f"\nRecorded {len(wakeword_files)} wakeword samples")
        
        # Record negative samples
        print("\nNow we'll record some negative samples (other words or background noise)")
        print("These help the model learn what is NOT the wakeword")
        input("Press Enter when ready to record negative samples...")
        
        negative_files = recorder.record_multiple(
            count=args.num_negative,
            duration=args.duration,
            label="not_wakeword",
            pause=args.pause
        )
        
        print(f"\nRecorded {len(negative_files)} negative samples")
        
        # Summary
        print("\n=== Recording Summary ===")
        print(f"Wakeword samples: {len(wakeword_files)}")
        print(f"Negative samples: {len(negative_files)}")
        print(f"All samples saved to: {args.output_dir}")
        print("\nYou can now use these samples to train a wakeword detection model")
        print("Run the training script with:")
        print(f"python -m src.models.train --data_dir {args.output_dir}")
    
    finally:
        # Clean up
        recorder.close()

if __name__ == "__main__":
    main()