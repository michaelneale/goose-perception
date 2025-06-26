#!/usr/bin/env python3
"""
emotion_detector_v2.py - Lightweight Modern Emotion Detection
A much faster, smaller, and more accurate emotion detection system
"""

import os
import json
import time
import threading
from datetime import datetime
from pathlib import Path
import logging
import numpy as np

# Set up logging to suppress verbose output
logging.getLogger('deepface').setLevel(logging.ERROR)
logging.getLogger('tensorflow').setLevel(logging.ERROR)

try:
    # Try lightweight emotion detection library first
    from deepface import DeepFace
    DEEPFACE_AVAILABLE = True
except ImportError:
    DEEPFACE_AVAILABLE = False
    print("⚠️ DeepFace not available. Installing...")

try:
    import cv2
    CV2_AVAILABLE = True
except ImportError:
    CV2_AVAILABLE = False
    print("⚠️ OpenCV not available. Using PIL for camera access...")

try:
    from PIL import Image, ImageDraw
    import io
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

class LightweightEmotionDetector:
    """
    Lightweight emotion detection system using modern efficient models
    """
    
    def __init__(self):
        self.is_initialized = False
        self.camera = None
        self.last_detection_time = 0
        self.detection_interval = 60  # 1 minute
        self.data_dir = Path.home() / ".local" / "share" / "goose-perception"
        
        # Lightweight emotion model configuration
        self.emotion_model = 'emotion'  # DeepFace's smallest model
        self.detector_backend = 'opencv'  # Fastest detector
        
        # Ensure data directory exists
        self.data_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize the system
        self._initialize()
    
    def _initialize(self):
        """Initialize the lightweight emotion detection system"""
        try:
            print("🎭 Initializing lightweight emotion detection...")
            
            if not DEEPFACE_AVAILABLE:
                self._install_deepface()
            
            # Test the emotion detection capability
            if self._test_emotion_model():
                print("✅ Emotion model verified")
            else:
                print("⚠️ Falling back to rule-based detection")
            
            # Initialize camera with fallback options
            self._initialize_camera()
            
            self.is_initialized = True
            print("✅ Lightweight emotion detection initialized successfully")
            
        except Exception as e:
            print(f"❌ Failed to initialize emotion detection: {e}")
            self.is_initialized = False
    
    def _install_deepface(self):
        """Install DeepFace if not available"""
        try:
            import subprocess
            import sys
            print("📦 Installing DeepFace...")
            subprocess.check_call([sys.executable, "-m", "pip", "install", "deepface"])
            global DEEPFACE_AVAILABLE
            from deepface import DeepFace
            DEEPFACE_AVAILABLE = True
            print("✅ DeepFace installed successfully")
        except Exception as e:
            print(f"❌ Failed to install DeepFace: {e}")
    
    def _test_emotion_model(self):
        """Test if the emotion model works"""
        try:
            if not DEEPFACE_AVAILABLE:
                return False
            
            # Create a simple test image
            test_img = np.ones((224, 224, 3), dtype=np.uint8) * 128
            
            # Test emotion detection
            result = DeepFace.analyze(
                img_path=test_img,
                actions=['emotion'],
                detector_backend=self.detector_backend,
                enforce_detection=False,
                silent=True
            )
            
            return True
        except Exception as e:
            print(f"⚠️ Emotion model test failed: {e}")
            return False
    
    def _initialize_camera(self):
        """Initialize camera with multiple fallback options"""
        if CV2_AVAILABLE:
            self._init_opencv_camera()
        else:
            print("⚠️ No camera support available")
            self.camera = None
    
    def _init_opencv_camera(self):
        """Initialize OpenCV camera"""
        try:
            for camera_id in range(3):
                test_camera = cv2.VideoCapture(camera_id)
                if test_camera.isOpened():
                    ret, frame = test_camera.read()
                    if ret and frame is not None:
                        print(f"📷 Using camera {camera_id}")
                        self.camera = test_camera
                        
                        # Optimize camera settings
                        self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
                        self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
                        self.camera.set(cv2.CAP_PROP_FPS, 15)
                        return
                    
                test_camera.release()
            
            print("⚠️ No working camera found")
            self.camera = None
            
        except Exception as e:
            print(f"❌ Camera initialization failed: {e}")
            self.camera = None
    
    def detect_emotion(self):
        """
        Detect emotion using lightweight modern models
        """
        # Check for manual override
        override_file = self.data_dir / "emotion_override.txt"
        if override_file.exists():
            try:
                override_emotion = override_file.read_text().strip()
                if override_emotion:
                    print(f"🎭 Using manual emotion override: {override_emotion}")
                    return {
                        "timestamp": datetime.now().isoformat(),
                        "emotion": override_emotion,
                        "confidence": 1.0,
                        "method": "override"
                    }
            except Exception as e:
                print(f"Error reading override: {e}")
        
        if not self.is_initialized or not self.camera:
            return None
        
        try:
            # Capture frame
            ret, frame = self.camera.read()
            if not ret or frame is None:
                print("⚠️ Failed to capture camera frame")
                return None
            
            # Use modern emotion detection
            if DEEPFACE_AVAILABLE:
                return self._detect_with_deepface(frame)
            else:
                return self._detect_fallback(frame)
                
        except Exception as e:
            print(f"❌ Error during emotion detection: {e}")
            return {
                "timestamp": datetime.now().isoformat(),
                "emotion": "error",
                "confidence": 0.0,
                "method": "error",
                "error": str(e)
            }
    
    def _detect_with_deepface(self, frame):
        """Detect emotion using DeepFace (lightweight and accurate)"""
        try:
            # Convert BGR to RGB
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            
            # Analyze emotion using DeepFace
            result = DeepFace.analyze(
                img_path=rgb_frame,
                actions=['emotion'],
                detector_backend=self.detector_backend,
                enforce_detection=False,
                silent=True
            )
            
            # Extract emotion data
            if isinstance(result, list):
                result = result[0]
            
            emotions = result.get('emotion', {})
            dominant_emotion = result.get('dominant_emotion', 'neutral')
            
            # Get confidence score for the dominant emotion
            confidence = emotions.get(dominant_emotion, 0.0) / 100.0
            
            return {
                "timestamp": datetime.now().isoformat(),
                "emotion": dominant_emotion.lower(),
                "confidence": confidence,
                "method": "deepface",
                "all_emotions": emotions,
                "face_region": result.get('region', {})
            }
            
        except Exception as e:
            print(f"⚠️ DeepFace detection failed, using fallback: {e}")
            return self._detect_fallback(frame)
    
    def _detect_fallback(self, frame):
        """Simple fallback emotion detection"""
        try:
            # Simple brightness-based mood detection (very basic fallback)
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            brightness = np.mean(gray)
            
            # Detect if there's a face region
            face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
            faces = face_cascade.detectMultiScale(gray, 1.1, 4)
            
            if len(faces) == 0:
                return {
                    "timestamp": datetime.now().isoformat(),
                    "emotion": "no_face_detected",
                    "confidence": 0.0,
                    "method": "fallback"
                }
            
            # Use brightness and simple heuristics for emotion
            if brightness > 120:
                emotion = "neutral"
                confidence = 0.6
            elif brightness > 100:
                emotion = "content" 
                confidence = 0.5
            else:
                emotion = "serious"
                confidence = 0.4
            
            return {
                "timestamp": datetime.now().isoformat(),
                "emotion": emotion,
                "confidence": confidence,
                "method": "fallback",
                "brightness": brightness,
                "faces_detected": len(faces)
            }
            
        except Exception as e:
            return {
                "timestamp": datetime.now().isoformat(),
                "emotion": "unknown",
                "confidence": 0.0,
                "method": "fallback_error",
                "error": str(e)
            }
    
    def log_emotion(self, emotion_data):
        """Log emotion data to file"""
        if not emotion_data:
            return
        
        try:
            log_file = self.data_dir / "emotions_v2.log"
            
            timestamp = emotion_data.get('timestamp', datetime.now().isoformat())
            emotion = emotion_data.get('emotion', 'unknown')
            confidence = emotion_data.get('confidence', 0.0)
            method = emotion_data.get('method', 'unknown')
            
            # Create detailed log line
            log_line = f"{timestamp},{emotion},{confidence:.3f},{method}\n"
            
            with open(log_file, 'a') as f:
                f.write(log_line)
            
            # Keep only last 1000 lines
            if log_file.exists():
                with open(log_file, 'r') as f:
                    lines = f.readlines()
                
                if len(lines) > 1000:
                    with open(log_file, 'w') as f:
                        f.writelines(lines[-1000:])
            
            print(f"🎭 Emotion: {emotion} ({confidence:.2f} confidence, {method})")
            
        except Exception as e:
            print(f"❌ Error logging emotion: {e}")
    
    def should_detect_now(self):
        """Check if it's time for next detection"""
        current_time = time.time()
        return (current_time - self.last_detection_time) >= self.detection_interval
    
    def run_detection_cycle(self):
        """Run emotion detection cycle"""
        current_time = time.time()
        time_since_last = current_time - self.last_detection_time
        
        if not self.should_detect_now():
            return
        
        self.last_detection_time = current_time
        
        print(f"🎭 Running emotion detection...")
        emotion_data = self.detect_emotion()
        
        if emotion_data:
            self.log_emotion(emotion_data)
            
            # Log to activity log if available
            try:
                from perception import log_activity
                emotion_summary = f"Emotion: {emotion_data['emotion']}"
                if emotion_data.get('confidence', 0) > 0:
                    emotion_summary += f" ({emotion_data['confidence']:.0%} confidence)"
                log_activity(emotion_summary)
            except ImportError:
                pass
    
    def get_recent_emotions(self, minutes=10):
        """Get recent emotion history"""
        try:
            log_file = self.data_dir / "emotions_v2.log"
            if not log_file.exists():
                return []
            
            cutoff_time = datetime.now().timestamp() - (minutes * 60)
            recent_emotions = []
            
            with open(log_file, 'r') as f:
                for line in f:
                    parts = line.strip().split(',')
                    if len(parts) >= 4:
                        timestamp_str, emotion, confidence, method = parts[:4]
                        try:
                            timestamp = datetime.fromisoformat(timestamp_str).timestamp()
                            if timestamp >= cutoff_time:
                                recent_emotions.append({
                                    'timestamp': timestamp_str,
                                    'emotion': emotion,
                                    'confidence': float(confidence),
                                    'method': method
                                })
                        except:
                            continue
            
            return recent_emotions
            
        except Exception as e:
            print(f"Error reading emotion history: {e}")
            return []
    
    def get_emotion_summary(self):
        """Get emotion detection summary"""
        recent = self.get_recent_emotions(60)  # Last hour
        
        if not recent:
            return {"status": "no_data", "message": "No recent emotion data"}
        
        emotions = [e['emotion'] for e in recent if e['emotion'] not in ['no_face_detected', 'error', 'unknown']]
        
        if not emotions:
            return {"status": "no_faces", "message": "No face detected recently"}
        
        # Calculate emotion distribution
        from collections import Counter
        emotion_counts = Counter(emotions)
        most_common = emotion_counts.most_common(1)[0] if emotion_counts else ('neutral', 0)
        
        avg_confidence = np.mean([e['confidence'] for e in recent if e['confidence'] > 0])
        
        return {
            "status": "active",
            "dominant_emotion": most_common[0],
            "emotion_distribution": dict(emotion_counts),
            "avg_confidence": float(avg_confidence),
            "detection_count": len(recent),
            "recent_emotions": emotions[-5:]  # Last 5 emotions
        }
    
    def cleanup(self):
        """Clean up resources"""
        if self.camera:
            self.camera.release()
            self.camera = None
        print("🎭 Emotion detection cleanup complete")

# Global instance
_emotion_detector_v2 = None

def get_emotion_detector():
    """Get the global lightweight emotion detector instance"""
    global _emotion_detector_v2
    if _emotion_detector_v2 is None:
        _emotion_detector_v2 = LightweightEmotionDetector()
    return _emotion_detector_v2

def run_emotion_detection_cycle():
    """Run emotion detection cycle (for integration with perception.py)"""
    detector = get_emotion_detector()
    if detector.is_initialized:
        detector.run_detection_cycle()

def cleanup_emotion_detector():
    """Cleanup resources"""
    global _emotion_detector_v2
    if _emotion_detector_v2:
        _emotion_detector_v2.cleanup()
        _emotion_detector_v2 = None

if __name__ == "__main__":
    # Test the lightweight emotion detector
    print("🎭 Testing lightweight emotion detection...")
    detector = LightweightEmotionDetector()
    
    if detector.is_initialized:
        print("✅ Running test detection...")
        emotion_data = detector.detect_emotion()
        if emotion_data:
            print(f"✅ Detected emotion: {json.dumps(emotion_data, indent=2)}")
            detector.log_emotion(emotion_data)
            
            # Show summary
            summary = detector.get_emotion_summary()
            print(f"📊 Summary: {json.dumps(summary, indent=2)}")
        else:
            print("⚠️ No emotion data detected")
    else:
        print("❌ Emotion detector not initialized")
    
    detector.cleanup() 