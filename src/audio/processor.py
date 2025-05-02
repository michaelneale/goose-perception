"""
Audio processing utilities for wakeword detection.
"""
import numpy as np
import librosa
import soundfile as sf
from typing import Tuple, List, Optional

class AudioProcessor:
    """Class for processing audio files and extracting features."""
    
    def __init__(self, sample_rate: int = 16000, n_mfcc: int = 40, 
                 n_fft: int = 400, hop_length: int = 160):
        """
        Initialize the audio processor.
        
        Args:
            sample_rate: Target sample rate for audio processing
            n_mfcc: Number of MFCC features to extract
            n_fft: FFT window size
            hop_length: Hop length for feature extraction
        """
        self.sample_rate = sample_rate
        self.n_mfcc = n_mfcc
        self.n_fft = n_fft
        self.hop_length = hop_length
    
    def load_audio(self, file_path: str) -> Tuple[np.ndarray, int]:
        """
        Load an audio file and resample if necessary.
        
        Args:
            file_path: Path to the audio file
            
        Returns:
            Tuple of (audio_data, sample_rate)
        """
        audio, sr = librosa.load(file_path, sr=self.sample_rate, mono=True)
        return audio, sr
    
    def extract_mfcc(self, audio: np.ndarray) -> np.ndarray:
        """
        Extract MFCC features from audio data.
        
        Args:
            audio: Audio data as numpy array
            
        Returns:
            MFCC features
        """
        mfccs = librosa.feature.mfcc(
            y=audio, 
            sr=self.sample_rate, 
            n_mfcc=self.n_mfcc,
            n_fft=self.n_fft,
            hop_length=self.hop_length
        )
        # Normalize features
        mfccs = (mfccs - np.mean(mfccs)) / (np.std(mfccs) + 1e-8)
        return mfccs
    
    def frame_audio(self, audio: np.ndarray, frame_length: float = 1.0, 
                   frame_shift: float = 0.5) -> List[np.ndarray]:
        """
        Split audio into overlapping frames.
        
        Args:
            audio: Audio data
            frame_length: Frame length in seconds
            frame_shift: Frame shift in seconds
            
        Returns:
            List of audio frames
        """
        frame_len_samples = int(frame_length * self.sample_rate)
        frame_shift_samples = int(frame_shift * self.sample_rate)
        
        frames = []
        for start in range(0, len(audio) - frame_len_samples + 1, frame_shift_samples):
            frames.append(audio[start:start + frame_len_samples])
            
        return frames
    
    def augment_audio(self, audio: np.ndarray, 
                     noise_factor: Optional[float] = None,
                     pitch_shift: Optional[int] = None,
                     speed_factor: Optional[float] = None) -> np.ndarray:
        """
        Apply data augmentation to audio.
        
        Args:
            audio: Audio data
            noise_factor: Factor for adding Gaussian noise (None to skip)
            pitch_shift: Number of semitones for pitch shifting (None to skip)
            speed_factor: Factor for time stretching (None to skip)
            
        Returns:
            Augmented audio
        """
        augmented = audio.copy()
        
        # Add noise if specified
        if noise_factor is not None:
            noise = np.random.normal(0, audio.std(), audio.size)
            augmented = augmented + noise_factor * noise
        
        # Pitch shift if specified
        if pitch_shift is not None:
            augmented = librosa.effects.pitch_shift(
                augmented, sr=self.sample_rate, n_steps=pitch_shift
            )
        
        # Time stretch if specified
        if speed_factor is not None:
            augmented = librosa.effects.time_stretch(augmented, rate=speed_factor)
            # Ensure same length as original
            if len(augmented) > len(audio):
                augmented = augmented[:len(audio)]
            elif len(augmented) < len(audio):
                augmented = np.pad(augmented, (0, len(audio) - len(augmented)))
        
        return augmented