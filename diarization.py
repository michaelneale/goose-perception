#!/usr/bin/env python3
"""
diarization.py - Speaker diarization using speechbrain to identify the speaker who said the wake word
"""

import torch
from speechbrain.pretrained import EncoderClassifier
import soundfile as sf
import numpy as np
from scipy.cluster.hierarchy import fcluster, linkage

# Cache the embedding model
_model = None

def get_model():
    """Get or initialize the speaker embedding model"""
    global _model
    if _model is None:
        _model = EncoderClassifier.from_hparams(
            source="speechbrain/spkrec-ecapa-voxceleb",
            run_opts={"device": "cuda" if torch.cuda.is_available() else "cpu"}
        )
    return _model

def get_speaker_audio(audio_file, wake_segments):
    """
    Extract audio for the speaker who said the wake word.
    
    Args:
        audio_file: Path to the conversation audio file
        wake_segments: List of segments containing wake word with timing info
    
    Returns:
        tuple: (speaker_audio, sample_rate) or (None, None) if speaker not found
    """
    # Load the audio
    waveform, sample_rate = sf.read(audio_file)
    waveform = torch.tensor(waveform).unsqueeze(0)
    
    # Split audio into segments
    segment_duration = 3.0  # seconds
    hop_duration = 1.5     # seconds
    segments = []
    embeddings = []
    model = get_model()
    
    # Extract embeddings for each segment
    for start in np.arange(0, waveform.shape[1]/sample_rate - segment_duration, hop_duration):
        end = start + segment_duration
        start_sample = int(start * sample_rate)
        end_sample = int(end * sample_rate)
        
        segment = waveform[:, start_sample:end_sample]
        embedding = model.encode_batch(segment)
        
        segments.append((start, end))
        embeddings.append(embedding.squeeze().cpu().numpy())
    
    embeddings = np.stack(embeddings)
    
    # Cluster embeddings to identify speakers
    linkage_matrix = linkage(embeddings, method='ward')
    labels = fcluster(linkage_matrix, t=0.7, criterion='distance') - 1
    
    # Find which speaker was talking during the wake word
    speaker_scores = {}
    
    for wake_segment in wake_segments:
        wake_start = wake_segment["start"]
        wake_end = wake_segment["end"]
        
        # Check each segment for overlap with wake word
        for (start, end), label in zip(segments, labels):
            if max(start, wake_start) < min(end, wake_end):
                speaker_scores[label] = speaker_scores.get(label, 0) + 1
    
    if not speaker_scores:
        return None, None
    
    # Get the most likely wake word speaker
    wake_speaker = max(speaker_scores.items(), key=lambda x: x[1])[0]
    
    # Extract all segments for this speaker
    speaker_segments = []
    current_start = None
    current_end = None
    
    for (start, end), label in zip(segments, labels):
        if label == wake_speaker:
            if current_start is None:
                current_start = start
                current_end = end
            elif start - current_end <= hop_duration:
                current_end = end
            else:
                speaker_segments.append((current_start, current_end))
                current_start = start
                current_end = end
    
    if current_start is not None:
        speaker_segments.append((current_start, current_end))
    
    # Extract and concatenate the speaker's audio
    speaker_chunks = []
    for start, end in speaker_segments:
        start_sample = int(start * sample_rate)
        end_sample = int(end * sample_rate)
        if end_sample <= len(waveform[0]):
            chunk = waveform[0, start_sample:end_sample]
            speaker_chunks.append(chunk)
    
    if not speaker_chunks:
        return None, None
    
    speaker_audio = torch.cat(speaker_chunks).numpy()
    return speaker_audio, sample_rate