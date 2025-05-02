"""
Audio recording utilities for collecting wakeword samples.
"""
import os
import time
import wave
import numpy as np
import pyaudio
from datetime import datetime

class AudioRecorder:
    """Class for recording audio samples for wakeword training."""
    
    def __init__(self, output_dir: str = "data/raw", 
                 sample_rate: int = 16000, channels: int = 1,
                 chunk_size: int = 1024, format_type=pyaudio.paInt16):
        """
        Initialize the audio recorder.
        
        Args:
            output_dir: Directory to save recorded audio
            sample_rate: Recording sample rate
            channels: Number of audio channels (1 for mono)
            chunk_size: Size of audio chunks to process
            format_type: PyAudio format type
        """
        self.output_dir = output_dir
        self.sample_rate = sample_rate
        self.channels = channels
        self.chunk_size = chunk_size
        self.format_type = format_type
        self.audio = pyaudio.PyAudio()
        
        # Create output directory if it doesn't exist
        os.makedirs(output_dir, exist_ok=True)
    
    def record_sample(self, duration: float = 2.0, label: str = "wakeword", 
                     countdown: bool = True) -> str:
        """
        Record an audio sample.
        
        Args:
            duration: Recording duration in seconds
            label: Label for the recorded sample (e.g., "wakeword" or "not_wakeword")
            countdown: Whether to show a countdown before recording
            
        Returns:
            Path to the saved audio file
        """
        # Create label directory if needed
        label_dir = os.path.join(self.output_dir, label)
        os.makedirs(label_dir, exist_ok=True)
        
        # Generate filename with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{label}_{timestamp}.wav"
        filepath = os.path.join(label_dir, filename)
        
        if countdown:
            print("Recording in:")
            for i in range(3, 0, -1):
                print(f"{i}...")
                time.sleep(1)
            print("Recording now!")
        
        # Start recording
        stream = self.audio.open(
            format=self.format_type,
            channels=self.channels,
            rate=self.sample_rate,
            input=True,
            frames_per_buffer=self.chunk_size
        )
        
        frames = []
        for _ in range(0, int(self.sample_rate / self.chunk_size * duration)):
            data = stream.read(self.chunk_size)
            frames.append(data)
        
        # Stop recording
        stream.stop_stream()
        stream.close()
        
        # Save to WAV file
        with wave.open(filepath, 'wb') as wf:
            wf.setnchannels(self.channels)
            wf.setsampwidth(self.audio.get_sample_size(self.format_type))
            wf.setframerate(self.sample_rate)
            wf.writeframes(b''.join(frames))
        
        print(f"Saved recording to {filepath}")
        return filepath
    
    def record_multiple(self, count: int = 5, duration: float = 2.0, 
                       label: str = "wakeword", pause: float = 1.0) -> list:
        """
        Record multiple audio samples with pauses between them.
        
        Args:
            count: Number of samples to record
            duration: Duration of each recording in seconds
            label: Label for the recordings
            pause: Pause between recordings in seconds
            
        Returns:
            List of paths to saved audio files
        """
        filepaths = []
        
        for i in range(count):
            print(f"\nRecording sample {i+1}/{count}")
            filepath = self.record_sample(duration=duration, label=label)
            filepaths.append(filepath)
            
            if i < count - 1:  # Don't pause after the last recording
                print(f"Pausing for {pause} seconds before next recording...")
                time.sleep(pause)
        
        return filepaths
    
    def close(self):
        """Close the PyAudio instance."""
        self.audio.terminate()
        
    def __del__(self):
        """Ensure PyAudio is terminated when the object is deleted."""
        try:
            self.audio.terminate()
        except:
            pass