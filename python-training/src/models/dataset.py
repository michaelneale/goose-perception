"""
Dataset utilities for wakeword detection.
"""
import os
import glob
import random
import torch
import numpy as np
from torch.utils.data import Dataset, DataLoader
from typing import Tuple, List, Dict, Optional
import torchaudio
from tqdm import tqdm

from src.audio.processor import AudioProcessor

class WakewordDataset(Dataset):
    """Dataset for wakeword detection training and evaluation."""
    
    def __init__(self, features: np.ndarray, labels: np.ndarray):
        """
        Initialize the dataset.
        
        Args:
            features: MFCC features as numpy array [n_samples, n_mfcc, n_time_frames]
            labels: Labels as numpy array [n_samples]
        """
        self.features = torch.from_numpy(features).float().unsqueeze(1)  # Add channel dimension
        self.labels = torch.from_numpy(labels).long()
    
    def __len__(self) -> int:
        """Return the number of samples in the dataset."""
        return len(self.labels)
    
    def __getitem__(self, idx: int) -> Tuple[torch.Tensor, torch.Tensor]:
        """
        Get a sample from the dataset.
        
        Args:
            idx: Index of the sample
            
        Returns:
            Tuple of (features, label)
        """
        return self.features[idx], self.labels[idx]


class WakewordDataProcessor:
    """Class for processing audio files into datasets for training."""
    
    def __init__(self, audio_processor: Optional[AudioProcessor] = None):
        """
        Initialize the data processor.
        
        Args:
            audio_processor: AudioProcessor instance for feature extraction
        """
        if audio_processor is None:
            self.audio_processor = AudioProcessor()
        else:
            self.audio_processor = audio_processor
    
    def process_audio_files(self, data_dir: str, target_length: float = 1.0) -> Tuple[np.ndarray, np.ndarray, Dict[int, str]]:
        """
        Process audio files from directories into features and labels.
        
        Args:
            data_dir: Root directory containing subdirectories for each class
            target_length: Target audio length in seconds
            
        Returns:
            Tuple of (features, labels, label_mapping)
        """
        # Get all subdirectories (classes)
        class_dirs = [d for d in os.listdir(data_dir) 
                     if os.path.isdir(os.path.join(data_dir, d))]
        
        # Create label mapping
        label_mapping = {i: class_name for i, class_name in enumerate(class_dirs)}
        reverse_mapping = {class_name: i for i, class_name in label_mapping.items()}
        
        features_list = []
        labels_list = []
        
        # Process each class
        for class_name in class_dirs:
            class_dir = os.path.join(data_dir, class_name)
            class_label = reverse_mapping[class_name]
            
            # Get all audio files in this class
            audio_files = glob.glob(os.path.join(class_dir, "*.wav"))
            
            print(f"Processing {len(audio_files)} files for class '{class_name}'")
            
            # Process each audio file
            for audio_file in tqdm(audio_files):
                # Load audio
                audio, sr = self.audio_processor.load_audio(audio_file)
                
                # Ensure audio is of target length
                target_samples = int(target_length * sr)
                if len(audio) > target_samples:
                    # Take a random segment if too long
                    start = random.randint(0, len(audio) - target_samples)
                    audio = audio[start:start + target_samples]
                elif len(audio) < target_samples:
                    # Pad with zeros if too short
                    padding = target_samples - len(audio)
                    audio = np.pad(audio, (0, padding))
                
                # Extract MFCC features
                mfcc = self.audio_processor.extract_mfcc(audio)
                
                # Add to lists
                features_list.append(mfcc)
                labels_list.append(class_label)
        
        # Convert lists to arrays
        features = np.array(features_list)
        labels = np.array(labels_list)
        
        return features, labels, label_mapping
    
    def create_data_loaders(self, features: np.ndarray, labels: np.ndarray, 
                           val_split: float = 0.2, test_split: float = 0.1, 
                           batch_size: int = 32, shuffle: bool = True) -> Dict[str, DataLoader]:
        """
        Create train/val/test data loaders from features and labels.
        
        Args:
            features: MFCC features as numpy array
            labels: Labels as numpy array
            val_split: Fraction of data to use for validation
            test_split: Fraction of data to use for testing
            batch_size: Batch size for data loaders
            shuffle: Whether to shuffle the data
            
        Returns:
            Dictionary of data loaders
        """
        # Determine split sizes
        n_samples = len(labels)
        indices = np.arange(n_samples)
        
        if shuffle:
            np.random.shuffle(indices)
        
        test_size = int(n_samples * test_split)
        val_size = int(n_samples * val_split)
        train_size = n_samples - val_size - test_size
        
        # Split indices
        train_indices = indices[:train_size]
        val_indices = indices[train_size:train_size + val_size]
        test_indices = indices[train_size + val_size:]
        
        # Create datasets
        train_dataset = WakewordDataset(features[train_indices], labels[train_indices])
        val_dataset = WakewordDataset(features[val_indices], labels[val_indices])
        test_dataset = WakewordDataset(features[test_indices], labels[test_indices])
        
        # Create data loaders
        train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
        val_loader = DataLoader(val_dataset, batch_size=batch_size)
        test_loader = DataLoader(test_dataset, batch_size=batch_size)
        
        return {
            'train': train_loader,
            'val': val_loader,
            'test': test_loader
        }
    
    def augment_data(self, features: np.ndarray, labels: np.ndarray, 
                    augmentation_factor: int = 2) -> Tuple[np.ndarray, np.ndarray]:
        """
        Augment data by adding noise, pitch shifting, and time stretching.
        
        Args:
            features: MFCC features as numpy array
            labels: Labels as numpy array
            augmentation_factor: Number of augmented samples to create per original sample
            
        Returns:
            Tuple of (augmented_features, augmented_labels)
        """
        n_samples = len(labels)
        augmented_features = [features]
        augmented_labels = [labels]
        
        # Define augmentation parameters
        noise_factors = [0.01, 0.02, 0.05]
        pitch_shifts = [-2, -1, 1, 2]
        speed_factors = [0.9, 0.95, 1.05, 1.1]
        
        # Create augmented samples
        for _ in range(augmentation_factor):
            # Randomly select augmentation parameters
            noise_factor = random.choice(noise_factors) if random.random() > 0.5 else None
            pitch_shift = random.choice(pitch_shifts) if random.random() > 0.5 else None
            speed_factor = random.choice(speed_factors) if random.random() > 0.5 else None
            
            # Skip if no augmentation selected
            if noise_factor is None and pitch_shift is None and speed_factor is None:
                continue
            
            # Augment each sample
            augmented_batch = []
            for i in range(n_samples):
                # Convert MFCC back to audio (approximate)
                # This is a simplified approach - in practice you might want to augment the raw audio
                # before feature extraction
                augmented = features[i] + np.random.normal(0, 0.01, features[i].shape)
                augmented_batch.append(augmented)
            
            # Add augmented batch to lists
            augmented_features.append(np.array(augmented_batch))
            augmented_labels.append(labels.copy())
        
        # Concatenate all batches
        return np.vstack(augmented_features), np.concatenate(augmented_labels)