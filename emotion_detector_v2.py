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
from collections import deque

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
        
        # Calibration settings
        self.calibration_data = self._load_calibration()
        self.confidence_threshold = self.calibration_data.get('confidence_threshold', 0.4)  # Lower default
        self.personal_baselines = self.calibration_data.get('personal_baselines', {})
        self.environmental_factors = self.calibration_data.get('environmental_factors', {})
        
        # Calibration aggressiveness (0.0 = no calibration, 1.0 = full calibration)
        self.calibration_strength = self.calibration_data.get('calibration_strength', 0.3)  # Gentle by default
        
        # Temporal smoothing
        self.emotion_history = deque(maxlen=5)  # Last 5 detections for smoothing
        self.enable_temporal_smoothing = self.calibration_data.get('temporal_smoothing', True)
        
        # Manual feedback system
        self.feedback_corrections = self.calibration_data.get('feedback_corrections', {})
        
        # Ensure data directory exists
        self.data_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize the system
        self._initialize()
    
    def _load_calibration(self):
        """Load calibration data from file"""
        try:
            calibration_file = Path.home() / ".local" / "share" / "goose-perception" / "calibration.json"
            if calibration_file.exists():
                with open(calibration_file, 'r') as f:
                    return json.load(f)
        except Exception as e:
            print(f"Note: Creating new calibration file ({e})")
        
        # Default calibration settings (gentle)
        return {
            'confidence_threshold': 0.4,  # Lower threshold for more responsiveness
            'personal_baselines': {},
            'environmental_factors': {},
            'temporal_smoothing': True,
            'feedback_corrections': {},
            'calibration_strength': 0.3  # Gentle calibration by default
        }
    
    def _save_calibration(self):
        """Save calibration data to file"""
        try:
            calibration_file = self.data_dir / "calibration.json"
            
            # Convert numpy types to Python types for JSON serialization
            def convert_numpy_types(obj):
                if hasattr(obj, 'item'):  # numpy scalars
                    return obj.item()
                elif isinstance(obj, np.ndarray):
                    return obj.tolist()
                elif isinstance(obj, dict):
                    return {k: convert_numpy_types(v) for k, v in obj.items()}
                elif isinstance(obj, list):
                    return [convert_numpy_types(v) for v in obj]
                else:
                    return obj
            
            calibration_data = {
                'confidence_threshold': float(self.confidence_threshold),
                'personal_baselines': convert_numpy_types(self.personal_baselines),
                'environmental_factors': convert_numpy_types(self.environmental_factors),
                'temporal_smoothing': self.enable_temporal_smoothing,
                'feedback_corrections': convert_numpy_types(self.feedback_corrections),
                'calibration_strength': float(self.calibration_strength),
                'last_updated': datetime.now().isoformat()
            }
            
            with open(calibration_file, 'w') as f:
                json.dump(calibration_data, f, indent=2)
            
            print(f"✅ Calibration saved to {calibration_file}")
            
        except Exception as e:
            print(f"❌ Error saving calibration: {e}")
    
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
    
    def detect_emotion(self, apply_calibration=True):
        """
        Detect emotion using lightweight modern models with optional calibration
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
                raw_result = self._detect_with_deepface(frame)
            else:
                raw_result = self._detect_fallback(frame)
            
            if raw_result and apply_calibration:
                return self._apply_calibration(raw_result, frame)
            
            return raw_result
                
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
    
    def _apply_calibration(self, raw_result, frame):
        """Apply calibration adjustments to raw emotion detection"""
        if not raw_result:
            return raw_result
        
        calibrated_result = raw_result.copy()
        calibrated_result['raw_emotion'] = raw_result['emotion']
        calibrated_result['raw_confidence'] = raw_result['confidence']
        
        # 1. Apply confidence threshold filtering
        if raw_result['confidence'] < self.confidence_threshold:
            calibrated_result['emotion'] = 'uncertain'
            calibrated_result['confidence'] = raw_result['confidence']
            calibrated_result['calibration_note'] = f"Below confidence threshold ({self.confidence_threshold})"
            return calibrated_result
        
        # 2. Apply personal baseline correction (gentler)
        emotion = raw_result['emotion']
        confidence = raw_result['confidence']
        
        if emotion in self.personal_baselines:
            baseline = self.personal_baselines[emotion]
            # Adjustable correction based on calibration strength
            baseline_confidence = baseline.get('avg_confidence', 0.5)
            confidence_adjustment = (confidence - baseline_confidence) * 0.2 * self.calibration_strength
            calibrated_result['confidence'] = max(0.1, min(1.0, confidence + confidence_adjustment))
            calibrated_result['baseline_adjustment'] = confidence_adjustment
        
        # 3. Apply environmental calibration
        frame_brightness = np.mean(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
        env_key = f"brightness_{int(frame_brightness/20)*20}"  # Group by 20-unit ranges
        
        if env_key in self.environmental_factors:
            env_factor = self.environmental_factors[env_key]
            emotion_adjustments = env_factor.get('emotion_adjustments', {})
            if emotion in emotion_adjustments:
                adjustment = emotion_adjustments[emotion]
                calibrated_result['confidence'] *= (1 + adjustment)
                calibrated_result['confidence'] = max(0.1, min(1.0, calibrated_result['confidence']))
                calibrated_result['environmental_adjustment'] = adjustment
        
        # 4. Apply feedback corrections
        feedback_key = f"{emotion}_{int(confidence*10)/10}"  # Round confidence to 0.1
        if feedback_key in self.feedback_corrections:
            correction = self.feedback_corrections[feedback_key]
            corrected_emotion = correction.get('corrected_emotion', emotion)
            correction_weight = correction.get('weight', 1.0)
            
            if correction_weight > 2:  # Strong correction based on multiple feedbacks
                calibrated_result['emotion'] = corrected_emotion
                calibrated_result['feedback_correction'] = True
        
        # 5. Apply temporal smoothing
        if self.enable_temporal_smoothing:
            self.emotion_history.append({
                'emotion': calibrated_result['emotion'],
                'confidence': calibrated_result['confidence']
            })
            
            if len(self.emotion_history) >= 3:
                smoothed = self._temporal_smooth()
                calibrated_result.update(smoothed)
        
        calibrated_result['method'] = calibrated_result.get('method', '') + '_calibrated'
        return calibrated_result
    
    def _temporal_smooth(self):
        """Apply gentle temporal smoothing to reduce detection noise"""
        if len(self.emotion_history) < 3:
            return {}
        
        current_detection = self.emotion_history[-1]
        recent_emotions = [h['emotion'] for h in self.emotion_history]
        
        # Only smooth if current detection has low confidence AND there's a pattern
        if current_detection['confidence'] > 0.7:
            return {}  # High confidence - don't smooth
        
        # Count emotion frequencies in recent history
        from collections import Counter
        emotion_counts = Counter(recent_emotions[:-1])  # Exclude current detection
        
        if len(emotion_counts) == 0:
            return {}
        
        most_common_emotion = emotion_counts.most_common(1)[0][0]
        
        # Only smooth if there's a strong pattern (3+ occurrences) and current is uncertain
        if emotion_counts[most_common_emotion] >= 3 and current_detection['confidence'] < 0.6:
            avg_confidence = np.mean([h['confidence'] for h in self.emotion_history[:-1] 
                                    if h['emotion'] == most_common_emotion])
            
            return {
                'emotion': most_common_emotion,
                'confidence': min(avg_confidence, 0.8),  # Cap smoothed confidence
                'temporal_smoothing': True,
                'smoothing_history': recent_emotions,
                'smoothing_reason': f"Low confidence {current_detection['confidence']:.2f}, pattern: {most_common_emotion}"
            }
        
        return {}
    
    def calibrate_confidence_threshold(self, test_detections=10):
        """Calibrate confidence threshold by analyzing detection quality"""
        print(f"🎯 Calibrating confidence threshold with {test_detections} detections...")
        print("Make various facial expressions during this calibration.")
        
        detections = []
        for i in range(test_detections):
            print(f"Detection {i+1}/{test_detections}...")
            result = self.detect_emotion(apply_calibration=False)  # Get raw results
            if result and result.get('confidence', 0) > 0:
                detections.append(result['confidence'])
            time.sleep(2)
        
        if detections:
            # Set threshold at 15th percentile to be less aggressive
            new_threshold = np.percentile(detections, 15)
            old_threshold = self.confidence_threshold
            self.confidence_threshold = max(0.3, min(0.6, new_threshold))  # Clamp between 0.3-0.6 (less strict)
            
            print(f"✅ Confidence threshold calibrated: {old_threshold:.2f} → {self.confidence_threshold:.2f}")
            self._save_calibration()
        else:
            print("❌ No valid detections for calibration")
    
    def calibrate_personal_baseline(self, emotion='neutral', duration=30):
        """Calibrate personal baseline for a specific emotion"""
        print(f"🎯 Calibrating personal baseline for '{emotion}'")
        print(f"Please maintain a {emotion} expression for {duration} seconds...")
        
        start_time = time.time()
        detections = []
        
        while time.time() - start_time < duration:
            result = self.detect_emotion(apply_calibration=False)
            if result and result.get('confidence', 0) > 0.3:  # Basic confidence filter
                detections.append({
                    'emotion': result['emotion'],
                    'confidence': result['confidence'],
                    'timestamp': time.time()
                })
            time.sleep(1)
        
        if detections:
            # Analyze the detections
            target_detections = [d for d in detections if d['emotion'] == emotion]
            avg_confidence = np.mean([d['confidence'] for d in detections])
            
            self.personal_baselines[emotion] = {
                'avg_confidence': avg_confidence,
                'sample_count': len(detections),
                'target_accuracy': len(target_detections) / len(detections) if detections else 0,
                'calibrated_at': datetime.now().isoformat()
            }
            
            print(f"✅ Baseline calibrated for '{emotion}': {len(detections)} samples, {avg_confidence:.2f} avg confidence")
            self._save_calibration()
        else:
            print(f"❌ No valid detections for {emotion} baseline")
    
    def add_feedback_correction(self, detected_emotion, detected_confidence, actual_emotion):
        """Add manual feedback to improve future detections"""
        feedback_key = f"{detected_emotion}_{int(detected_confidence*10)/10}"
        
        if feedback_key not in self.feedback_corrections:
            self.feedback_corrections[feedback_key] = {
                'corrected_emotion': actual_emotion,
                'weight': 1.0,
                'examples': []
            }
        else:
            # Increase weight for repeated corrections
            self.feedback_corrections[feedback_key]['weight'] += 0.5
            if self.feedback_corrections[feedback_key]['corrected_emotion'] != actual_emotion:
                # Conflicting feedback, reduce weight
                self.feedback_corrections[feedback_key]['weight'] *= 0.8
        
        self.feedback_corrections[feedback_key]['examples'].append({
            'timestamp': datetime.now().isoformat(),
            'detected': detected_emotion,
            'actual': actual_emotion,
            'confidence': detected_confidence
        })
        
        # Keep only last 10 examples
        self.feedback_corrections[feedback_key]['examples'] = \
            self.feedback_corrections[feedback_key]['examples'][-10:]
        
        print(f"✅ Feedback recorded: {detected_emotion}→{actual_emotion} (weight: {self.feedback_corrections[feedback_key]['weight']:.1f})")
        self._save_calibration()
    
    def get_calibration_status(self):
        """Get current calibration status and recommendations"""
        status = {
            'confidence_threshold': self.confidence_threshold,
            'personal_baselines': len(self.personal_baselines),
            'feedback_corrections': len(self.feedback_corrections),
            'temporal_smoothing': self.enable_temporal_smoothing,
            'calibration_strength': self.calibration_strength,
            'recommendations': []
        }
        
        # Generate recommendations
        if len(self.personal_baselines) == 0:
            status['recommendations'].append("Run calibrate_personal_baseline('neutral') to improve accuracy")
        
        if len(self.feedback_corrections) < 5:
            status['recommendations'].append("Use add_feedback_correction() when you notice wrong detections")
        
        if self.confidence_threshold == 0.5:  # Default value
            status['recommendations'].append("Run calibrate_confidence_threshold() to optimize detection quality")
        
        return status
    
    def set_calibration_strength(self, strength):
        """Set calibration aggressiveness (0.0 = no calibration, 1.0 = full calibration)"""
        if 0.0 <= strength <= 1.0:
            old_strength = self.calibration_strength
            self.calibration_strength = strength
            self._save_calibration()
            print(f"✅ Calibration strength: {old_strength:.1f} → {strength:.1f}")
            
            if strength == 0.0:
                print("   📌 Calibration disabled - raw AI detection only")
            elif strength <= 0.3:
                print("   📌 Gentle calibration - responsive with light smoothing")
            elif strength <= 0.7:
                print("   📌 Moderate calibration - balanced accuracy and stability")
            else:
                print("   📌 Strong calibration - maximum stability, slower response")
        else:
            print("❌ Strength must be between 0.0 and 1.0")
    
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