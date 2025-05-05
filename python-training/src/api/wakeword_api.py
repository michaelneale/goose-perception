"""
Simple API for wakeword detection.
"""
import os
import time
import json
import queue
import threading
import numpy as np
from typing import Dict, Any, Optional, Callable
import pyaudio
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from src.audio.processor import AudioProcessor
from src.models.wakeword import WakewordDetector

# Create FastAPI app
app = FastAPI(title="Wakeword Detection API")

# Global variables
detector = None
audio_processor = None
is_listening = False
listen_thread = None
audio_queue = queue.Queue()


class WakewordConfig(BaseModel):
    """Configuration for wakeword detection."""
    model_path: str
    threshold: float = 0.5
    sample_rate: int = 16000
    frame_duration: float = 1.0
    hop_duration: float = 0.5
    device: str = "cpu"


@app.post("/load_model")
async def load_model(config: WakewordConfig) -> Dict[str, Any]:
    """
    Load a wakeword detection model.
    
    Args:
        config: Model configuration
        
    Returns:
        Status message
    """
    global detector, audio_processor
    
    try:
        # Initialize audio processor
        audio_processor = AudioProcessor(sample_rate=config.sample_rate)
        
        # Load model
        detector = WakewordDetector.load_model(config.model_path, device=config.device)
        
        return {
            "status": "success",
            "message": f"Model loaded from {config.model_path}",
            "config": config.dict()
        }
    except Exception as e:
        return {
            "status": "error",
            "message": f"Failed to load model: {str(e)}"
        }


@app.get("/status")
async def get_status() -> Dict[str, Any]:
    """
    Get the current status of the wakeword detector.
    
    Returns:
        Status information
    """
    global detector, is_listening
    
    return {
        "model_loaded": detector is not None,
        "is_listening": is_listening
    }


def audio_callback(in_data, frame_count, time_info, status):
    """Callback for PyAudio to capture audio data."""
    if is_listening:
        audio_queue.put(in_data)
    return (in_data, pyaudio.paContinue)


def listen_for_wakeword(callback: Callable[[Dict[str, Any]], None], 
                       threshold: float = 0.5,
                       frame_duration: float = 1.0,
                       hop_duration: float = 0.5):
    """
    Listen for wakeword in a separate thread.
    
    Args:
        callback: Function to call when wakeword is detected
        threshold: Confidence threshold for detection
        frame_duration: Duration of audio frame to process (seconds)
        hop_duration: Hop duration between frames (seconds)
    """
    global is_listening, detector, audio_processor
    
    if detector is None or audio_processor is None:
        callback({
            "status": "error",
            "message": "Model or audio processor not initialized"
        })
        return
    
    # Initialize PyAudio
    p = pyaudio.PyAudio()
    
    # Calculate parameters
    sample_rate = audio_processor.sample_rate
    frame_size = int(frame_duration * sample_rate)
    hop_size = int(hop_duration * sample_rate)
    
    # Start audio stream
    stream = p.open(
        format=pyaudio.paFloat32,
        channels=1,
        rate=sample_rate,
        input=True,
        frames_per_buffer=hop_size,
        stream_callback=audio_callback
    )
    
    # Buffer for audio data
    audio_buffer = np.zeros(frame_size, dtype=np.float32)
    
    try:
        # Start stream
        stream.start_stream()
        
        while is_listening:
            # Get audio data from queue
            try:
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
                if predicted_class == 1 and confidence >= threshold:
                    callback({
                        "status": "detected",
                        "confidence": float(confidence),
                        "timestamp": time.time()
                    })
                    
                    # Optional: pause briefly after detection
                    time.sleep(1.0)
            
            except queue.Empty:
                continue
    
    finally:
        # Clean up
        stream.stop_stream()
        stream.close()
        p.terminate()


@app.post("/start_listening")
async def start_listening(threshold: float = 0.5, 
                         frame_duration: float = 1.0,
                         hop_duration: float = 0.5) -> Dict[str, Any]:
    """
    Start listening for wakeword.
    
    Args:
        threshold: Confidence threshold for detection
        frame_duration: Duration of audio frame to process (seconds)
        hop_duration: Hop duration between frames (seconds)
        
    Returns:
        Status message
    """
    global is_listening, listen_thread, detector
    
    if detector is None:
        return {
            "status": "error",
            "message": "Model not loaded"
        }
    
    if is_listening:
        return {
            "status": "error",
            "message": "Already listening"
        }
    
    # Define callback for detections
    def detection_callback(result):
        print(f"Detection: {result}")
        # In a real application, you might want to store these results
        # or trigger some action
    
    # Start listening in a separate thread
    is_listening = True
    listen_thread = threading.Thread(
        target=listen_for_wakeword,
        args=(detection_callback, threshold, frame_duration, hop_duration)
    )
    listen_thread.daemon = True
    listen_thread.start()
    
    return {
        "status": "success",
        "message": "Started listening for wakeword",
        "config": {
            "threshold": threshold,
            "frame_duration": frame_duration,
            "hop_duration": hop_duration
        }
    }


@app.post("/stop_listening")
async def stop_listening() -> Dict[str, Any]:
    """
    Stop listening for wakeword.
    
    Returns:
        Status message
    """
    global is_listening, listen_thread
    
    if not is_listening:
        return {
            "status": "error",
            "message": "Not currently listening"
        }
    
    # Stop listening thread
    is_listening = False
    if listen_thread is not None:
        listen_thread.join(timeout=2.0)
        listen_thread = None
    
    return {
        "status": "success",
        "message": "Stopped listening for wakeword"
    }


# WebSocket endpoint for real-time wakeword detection
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """
    WebSocket endpoint for real-time wakeword detection.
    
    Args:
        websocket: WebSocket connection
    """
    await websocket.accept()
    
    try:
        # Wait for configuration
        config_data = await websocket.receive_json()
        threshold = config_data.get("threshold", 0.5)
        
        # Define callback for detections
        async def ws_detection_callback(result):
            await websocket.send_json(result)
        
        # Start listening
        global is_listening, listen_thread
        is_listening = True
        listen_thread = threading.Thread(
            target=listen_for_wakeword,
            args=(ws_detection_callback, threshold, 1.0, 0.5)
        )
        listen_thread.daemon = True
        listen_thread.start()
        
        # Keep connection alive
        while is_listening:
            try:
                # Check for messages (e.g., to stop listening)
                data = await websocket.receive_json()
                if data.get("action") == "stop":
                    is_listening = False
            except WebSocketDisconnect:
                is_listening = False
                break
    
    finally:
        # Clean up
        is_listening = False
        if listen_thread is not None:
            listen_thread.join(timeout=2.0)
            listen_thread = None