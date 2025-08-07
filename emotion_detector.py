#!/usr/bin/env python3
"""
emotion_detector.py - Facial emotion detection using camera and InsightFace
Detects emotional state from webcam feed and logs it similar to other perception activities
"""

import cv2
import numpy as np
import os
import json
import threading
import time
from datetime import datetime
from pathlib import Path
import logging

# Set up logging to suppress insightface warnings
logging.getLogger('insightface').setLevel(logging.ERROR)

try:
    import insightface
    from insightface.app import FaceAnalysis
    INSIGHTFACE_AVAILABLE = True
except ImportError:
    INSIGHTFACE_AVAILABLE = False
    print("⚠️ InsightFace not available. Emotion detection will be disabled.")

# Import configuration manager
from config_manager import get_config_manager

class EmotionDetector:
    """
    Handles facial emotion detection using camera feed
    """
    
    def __init__(self):
        self.app = None
        self.camera = None
        self.is_initialized = False
        self.last_detection_time = 0
        # Load detection interval from config
        self.config = get_config_manager()
        self.detection_interval = self.config.get_emotion_interval()  # Already in seconds
        self.data_dir = Path.home() / ".local" / "share" / "goose-perception"
        
        # Ensure data directory exists
        self.data_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize if dependencies are available
        if INSIGHTFACE_AVAILABLE:
            self._initialize()
    
    def _initialize(self):
        """Initialize the face analysis model and camera"""
        try:
            print("🎭 Initializing emotion detection system...")
            
            # Initialize InsightFace with all available models including emotion
            self.app = FaceAnalysis(providers=['CPUExecutionProvider'])
            self.app.prepare(ctx_id=0, det_size=(640, 640))
            
            # Check what models are loaded
            print("📋 Available InsightFace models:")
            for model_name, model in self.app.models.items():
                print(f"   - {model_name}: {type(model).__name__}")
            
            # Try to initialize camera - prefer built-in camera over external ones
            self.camera = None
            
            # Try cameras in order of preference (built-in first)
            for camera_id in range(5):  # Check first 5 camera indices
                test_camera = cv2.VideoCapture(camera_id)
                if test_camera.isOpened():
                    # Get camera name/info if possible
                    width = test_camera.get(cv2.CAP_PROP_FRAME_WIDTH)
                    height = test_camera.get(cv2.CAP_PROP_FRAME_HEIGHT)
                    
                    # Test capture to see if it works
                    ret, frame = test_camera.read()
                    if ret and frame is not None:
                        print(f"📷 Found camera {camera_id}: {width}x{height}")
                        
                        # Prefer camera 0 (usually built-in) unless it doesn't work
                        if camera_id == 0 or self.camera is None:
                            if self.camera:
                                self.camera.release()
                            self.camera = test_camera
                            print(f"✅ Using camera {camera_id}")
                            break
                    
                test_camera.release()
            
            if not self.camera or not self.camera.isOpened():
                print("⚠️ Could not open any camera for emotion detection")
                self.camera = None
                return
            
            # Set camera properties for better performance
            self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
            self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
            self.camera.set(cv2.CAP_PROP_FPS, 15)
            
            # Store face embeddings for recognition
            self.known_faces = []  # List of face embeddings we've seen
            self.face_count = 0    # Counter for face IDs
            
            self.is_initialized = True
            print("✅ Emotion detection system initialized successfully")
            print(f"🎭 Emotion detection will run every {self.detection_interval//60} minutes")
            
        except Exception as e:
            print(f"❌ Failed to initialize emotion detection: {e}")
            self.is_initialized = False
    
    def _get_face_identity(self, face_embedding):
        """
        Get or assign an identity to a face based on embedding similarity
        Returns face_id (int) for the recognized or new face
        """
        if not hasattr(face_embedding, 'shape') or len(self.known_faces) == 0:
            # First face or invalid embedding
            self.known_faces.append(face_embedding)
            self.face_count += 1
            return self.face_count
        
        # Compare with known faces using cosine similarity
        similarities = []
        for known_embedding in self.known_faces:
            # Calculate cosine similarity
            similarity = np.dot(face_embedding, known_embedding) / (
                np.linalg.norm(face_embedding) * np.linalg.norm(known_embedding)
            )
            similarities.append(similarity)
        
        # Find best match
        best_match_idx = np.argmax(similarities)
        best_similarity = similarities[best_match_idx]
        
        # Threshold for considering it the same person (0.6 is typical)
        if best_similarity > 0.6:
            return best_match_idx + 1  # Face IDs start from 1
        else:
            # New face
            self.known_faces.append(face_embedding)
            self.face_count += 1
            return self.face_count

    def _analyze_face_comprehensive(self, face):
        """
        Comprehensive face analysis using InsightFace capabilities
        """
        try:
            # Check what attributes this face object actually has
            print(f"🔍 Face attributes: {[attr for attr in dir(face) if not attr.startswith('_')]}")
            
            # Get basic attributes
            age = getattr(face, 'age', 0)
            gender = getattr(face, 'gender', 0)  # 0 = female, 1 = male
            
            # Check for emotion attribute (some InsightFace models have this)
            emotion = getattr(face, 'emotion', None)
            
            # Also check for 'emotions' or 'expression' attributes
            if emotion is None:
                emotion = getattr(face, 'emotions', None)
            if emotion is None:
                emotion = getattr(face, 'expression', None)
            
            if emotion is not None:
                print(f"🎭 InsightFace emotion detected: {emotion}")
                # Use InsightFace's emotion detection if available
                if hasattr(emotion, 'argmax'):
                    # Emotion is likely a probability array
                    emotion_labels = ['angry', 'disgust', 'fear', 'happy', 'sad', 'surprise', 'neutral']
                    emotion_idx = emotion.argmax()
                    detected_emotion = emotion_labels[emotion_idx] if emotion_idx < len(emotion_labels) else 'unknown'
                    confidence = float(emotion[emotion_idx])
                else:
                    detected_emotion = str(emotion)
                    confidence = 0.8
            else:
                # Fall back to geometric analysis
                print("📐 Using geometric emotion analysis (InsightFace emotion model not available)")
                detected_emotion, confidence = self._geometric_emotion_analysis(face)
            
            # Get face embedding for recognition
            embedding = getattr(face, 'embedding', None)
            face_id = self._get_face_identity(embedding) if embedding is not None else None
            
            return {
                "emotion": detected_emotion,
                "confidence": confidence,
                "face_id": face_id,
                "details": {
                    "age": int(age) if age and age > 0 else None,
                    "gender": "male" if gender > 0.5 else "female" if gender is not None else None,
                    "is_known_face": bool(face_id is not None and face_id <= len(self.known_faces)),
                    "detection_method": "insightface" if emotion is not None else "geometric"
                }
            }
                
        except Exception as e:
            print(f"Error analyzing face: {e}")
            return {
                "emotion": "unknown",
                "confidence": 0.0,
                "face_id": None,
                "details": {"error": str(e)}
            }
    
    def _geometric_emotion_analysis(self, face):
        """Enhanced geometric emotion analysis using facial landmarks"""
        try:
            if hasattr(face, 'landmark_2d_106'):
                landmarks = face.landmark_2d_106
                
                # Get key facial regions with proper landmark indices for 106-point model
                # Mouth region (points 84-95 in 106-point model)
                mouth_points = landmarks[84:96]
                
                # Eye regions (approximate - adjust based on actual 106-point layout)
                left_eye = landmarks[60:68]   # Left eye region
                right_eye = landmarks[68:76]  # Right eye region
                
                # Eyebrow regions (approximate)
                left_eyebrow = landmarks[33:38]   
                right_eyebrow = landmarks[38:43]
                
                # Analyze mouth geometry
                mouth_corners = [mouth_points[0], mouth_points[6]]  # Left and right corners
                mouth_center_top = mouth_points[3]
                mouth_center_bottom = mouth_points[9]
                
                # Calculate mouth curvature (smile/frown indicator)
                mouth_width = np.linalg.norm(mouth_corners[1] - mouth_corners[0])
                mouth_height = np.linalg.norm(mouth_center_bottom - mouth_center_top)
                
                # More sophisticated mouth analysis
                # Check if corners are raised (smile) or lowered (frown)
                corner_height_avg = (mouth_corners[0][1] + mouth_corners[1][1]) / 2
                center_height = mouth_center_top[1]
                mouth_curvature = center_height - corner_height_avg  # Positive = smile, negative = frown
                
                # Normalize mouth metrics
                mouth_aspect_ratio = mouth_width / (mouth_height + 1e-6)
                
                # Analyze eye openness
                def eye_aspect_ratio(eye_points):
                    # Calculate eye aspect ratio (EAR)
                    # Vertical distances
                    A = np.linalg.norm(eye_points[1] - eye_points[5])
                    B = np.linalg.norm(eye_points[2] - eye_points[4])
                    # Horizontal distance  
                    C = np.linalg.norm(eye_points[0] - eye_points[3])
                    return (A + B) / (2.0 * C + 1e-6)
                
                left_ear = eye_aspect_ratio(left_eye)
                right_ear = eye_aspect_ratio(right_eye)
                avg_ear = (left_ear + right_ear) / 2
                
                # Analyze eyebrow position (raised = surprise, lowered = anger/concentration)
                def eyebrow_height(eyebrow_points, eye_points):
                    eyebrow_center = np.mean(eyebrow_points, axis=0)
                    eye_center = np.mean(eye_points, axis=0)
                    return eyebrow_center[1] - eye_center[1]  # Negative = raised eyebrows
                
                left_brow_height = eyebrow_height(left_eyebrow, left_eye)
                right_brow_height = eyebrow_height(right_eyebrow, right_eye)
                avg_brow_height = (left_brow_height + right_brow_height) / 2
                
                # Debug logging with more detailed metrics
                print(f"🔍 Detailed emotion metrics:")
                print(f"   Mouth: aspect_ratio={mouth_aspect_ratio:.2f}, curvature={mouth_curvature:.2f}")
                print(f"   Eyes: ear={avg_ear:.3f}")
                print(f"   Eyebrows: height={avg_brow_height:.2f}")
                
                # Enhanced emotion classification using multiple features
                # Happy: raised mouth corners, normal/wide eyes, normal/raised eyebrows
                if mouth_curvature < -2 and mouth_aspect_ratio > 3.5 and avg_ear > 0.25:
                    confidence = min(0.9, abs(mouth_curvature) / 5.0)
                    return "happy", confidence
                
                # Content/slight smile: slight mouth curvature, normal eyes
                elif mouth_curvature < -0.5 and mouth_aspect_ratio > 3.0 and avg_ear > 0.2:
                    return "content", 0.7
                
                # Sad: lowered mouth corners, normal/droopy eyes
                elif mouth_curvature > 1 or (mouth_aspect_ratio < 2.5 and avg_ear < 0.2):
                    confidence = min(0.8, mouth_curvature / 3.0)
                    return "sad", confidence
                
                # Surprised: wide eyes, raised eyebrows, open mouth
                elif avg_ear > 0.35 and avg_brow_height < -3 and mouth_aspect_ratio > 4.0:
                    return "surprised", 0.8
                
                # Angry: lowered eyebrows, tight mouth, normal/narrow eyes
                elif avg_brow_height > 2 and mouth_aspect_ratio < 3.0 and avg_ear < 0.25:
                    return "angry", 0.7
                
                # Tired: droopy eyes, neutral mouth
                elif avg_ear < 0.15:
                    return "tired", 0.8
                
                # Serious/concentrated: slightly lowered brows, neutral mouth
                elif avg_brow_height > 0.5 and abs(mouth_curvature) < 1:
                    return "serious", 0.6
                
                # Neutral: everything in normal ranges
                else:
                    return "neutral", 0.5
                    
            else:
                print("⚠️ No 106-point landmarks available for emotion analysis")
                return "neutral", 0.3
                
        except Exception as e:
            print(f"❌ Error in geometric emotion analysis: {e}")
            return "unknown", 0.0
    
    def detect_emotion(self):
        """
        Capture a frame from camera and detect emotional state
        Returns emotion data or None if detection fails
        """
        # Check for manual emotion override (for testing)
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
                        "face_id": 1,
                        "details": {"override": True}
                    }
            except Exception as e:
                print(f"Error reading override: {e}")
        
        # Check for calibration mode
        calibration_file = self.data_dir / "emotion_calibration.txt"
        if calibration_file.exists():
            try:
                calibration_mode = calibration_file.read_text().strip()
                if calibration_mode:
                    print(f"🎯 Calibration mode: {calibration_mode}")
                    # Capture baseline measurements for this emotion
                    emotion_data = self._capture_calibration_data(calibration_mode)
                    return emotion_data
            except Exception as e:
                print(f"Error in calibration mode: {e}")
        
        if not self.is_initialized or not self.camera:
            return None
        
        try:
            # Capture frame
            ret, frame = self.camera.read()
            if not ret:
                print("⚠️ Failed to capture camera frame")
                return None
            
            # Analyze faces in the frame
            faces = self.app.get(frame)
            
            if not faces:
                return {
                    "timestamp": datetime.now().isoformat(),
                    "emotion": "no_face_detected",
                    "confidence": 0.0,
                    "details": {"faces_detected": 0}
                }
            
            # Use the largest face (presumably the user)
            largest_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
            
            # Comprehensive face analysis
            emotion_data = self._analyze_face_comprehensive(largest_face)
            
            # Add metadata
            emotion_data.update({
                "timestamp": datetime.now().isoformat(),
                "faces_detected": len(faces),
                "face_bbox": largest_face.bbox.tolist() if hasattr(largest_face, 'bbox') else None
            })
            
            return emotion_data
            
        except Exception as e:
            print(f"❌ Error during emotion detection: {e}")
            return {
                "timestamp": datetime.now().isoformat(),
                "emotion": "error",
                "confidence": 0.0,
                "details": {"error": str(e)}
            }
    
    def log_emotion(self, emotion_data):
        """
        Log emotion data to a simple text file
        Format: timestamp,emotion,face_id
        """
        if not emotion_data:
            return
        
        try:
            # Simple log file
            log_file = self.data_dir / "emotions.log"
            
            # Extract only the requested data
            timestamp = emotion_data.get('timestamp', datetime.now().isoformat())
            emotion = emotion_data.get('emotion', 'unknown')
            face_id = emotion_data.get('face_id', 'unknown')
            
            # Create log line with only timestamp, emotion, and face_id
            log_line = f"{timestamp},{emotion},{face_id}\n"
            
            # Append to log file
            with open(log_file, 'a') as f:
                f.write(log_line)
            
            # Keep only last 500 lines
            if log_file.exists():
                with open(log_file, 'r') as f:
                    lines = f.readlines()
                
                if len(lines) > 500:
                    with open(log_file, 'w') as f:
                        f.writelines(lines[-500:])
            
            print(f"🎭 Emotion logged: {emotion} - Face ID: {face_id}")
            
        except Exception as e:
            print(f"❌ Error logging emotion: {e}")
    
    def should_detect_now(self):
        """Check if it's time for the next emotion detection"""
        current_time = time.time()
        return (current_time - self.last_detection_time) >= self.detection_interval
    
    def run_detection_cycle(self):
        """Run a single emotion detection cycle"""
        current_time = time.time()
        time_since_last = current_time - self.last_detection_time
        
        if not self.should_detect_now():
            # Show a periodic status update (every 30 seconds)
            if int(time_since_last) % 30 == 0 and int(time_since_last) > 0:
                remaining = self.detection_interval - time_since_last
                print(f"🎭 Next emotion detection in {remaining:.0f} seconds")
            return
        
        self.last_detection_time = current_time
        
        print(f"🎭 Running emotion detection cycle (every {self.detection_interval//60} minutes)...")
        emotion_data = self.detect_emotion()
        
        if emotion_data:
            self.log_emotion(emotion_data)
            
            # Also log to activity log if available
            try:
                from perception import log_activity
                emotion_summary = f"Emotion detected: {emotion_data['emotion']}"
                if emotion_data.get('confidence', 0) > 0:
                    emotion_summary += f" (confidence: {emotion_data['confidence']:.2f})"
                log_activity(emotion_summary)
            except ImportError:
                pass  # log_activity not available
    
    def _capture_calibration_data(self, emotion_label):
        """Capture calibration data for a specific emotion"""
        try:
            # Capture frame
            ret, frame = self.camera.read()
            if not ret:
                print("⚠️ Failed to capture calibration frame")
                return None
            
            # Analyze faces in the frame
            faces = self.app.get(frame)
            
            if not faces:
                print("⚠️ No face detected for calibration")
                return None
            
            # Use the largest face
            largest_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
            
            # Get detailed metrics for calibration
            if hasattr(largest_face, 'landmark_2d_106'):
                landmarks = largest_face.landmark_2d_106
                mouth_points = landmarks[84:96]
                left_eye = landmarks[60:68]
                right_eye = landmarks[68:76]
                left_eyebrow = landmarks[33:38]
                right_eyebrow = landmarks[38:43]
                
                # Calculate all the metrics
                mouth_corners = [mouth_points[0], mouth_points[6]]
                mouth_center_top = mouth_points[3]
                mouth_center_bottom = mouth_points[9]
                
                mouth_width = np.linalg.norm(mouth_corners[1] - mouth_corners[0])
                mouth_height = np.linalg.norm(mouth_center_bottom - mouth_center_top)
                
                corner_height_avg = (mouth_corners[0][1] + mouth_corners[1][1]) / 2
                center_height = mouth_center_top[1]
                mouth_curvature = center_height - corner_height_avg
                mouth_aspect_ratio = mouth_width / (mouth_height + 1e-6)
                
                # Save calibration data
                calibration_data = {
                    "emotion": emotion_label,
                    "mouth_curvature": float(mouth_curvature),
                    "mouth_aspect_ratio": float(mouth_aspect_ratio),
                    "timestamp": datetime.now().isoformat()
                }
                
                calibration_log = self.data_dir / "emotion_calibration.json"
                if calibration_log.exists():
                    with open(calibration_log, 'r') as f:
                        data = json.load(f)
                else:
                    data = {"calibrations": []}
                
                data["calibrations"].append(calibration_data)
                
                with open(calibration_log, 'w') as f:
                    json.dump(data, f, indent=2)
                
                print(f"🎯 Calibrated {emotion_label}: curvature={mouth_curvature:.2f}, ratio={mouth_aspect_ratio:.2f}")
                
                return {
                    "timestamp": datetime.now().isoformat(),
                    "emotion": f"calibrating_{emotion_label}",
                    "confidence": 1.0,
                    "face_id": 1,
                    "details": {"calibration": calibration_data}
                }
            
        except Exception as e:
            print(f"❌ Error in calibration: {e}")
            return None

    def cleanup(self):
        """Clean up camera resources"""
        if self.camera:
            self.camera.release()
            self.camera = None
        print("🎭 Emotion detection cleanup complete")

# Global instance
_emotion_detector = None

def get_emotion_detector():
    """Get the global emotion detector instance"""
    global _emotion_detector
    if _emotion_detector is None:
        _emotion_detector = EmotionDetector()
    return _emotion_detector

def run_emotion_detection_cycle():
    """Run a single emotion detection cycle (for use by perception.py)"""
    detector = get_emotion_detector()
    if detector.is_initialized:
        detector.run_detection_cycle()

def cleanup_emotion_detector():
    """Cleanup emotion detector resources"""
    global _emotion_detector
    if _emotion_detector:
        _emotion_detector.cleanup()
        _emotion_detector = None

if __name__ == "__main__":
    # Test the emotion detector
    print("🎭 Testing emotion detection...")
    detector = EmotionDetector()
    
    if detector.is_initialized:
        print("Running test detection...")
        emotion_data = detector.detect_emotion()
        if emotion_data:
            print(f"Detected emotion: {json.dumps(emotion_data, indent=2)}")
            detector.log_emotion(emotion_data)
        else:
            print("No emotion data detected")
    else:
        print("Emotion detector not initialized")
    
    detector.cleanup()
