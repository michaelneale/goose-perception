#!/usr/bin/env python3
"""
test_emotion_detection.py - Test and compare emotion detection systems
"""

import time
import json
from datetime import datetime
import sys

def test_old_system():
    """Test the old emotion detection system"""
    print("🔍 Testing OLD emotion detection system...")
    try:
        from emotion_detector import EmotionDetector
        detector = EmotionDetector()
        
        if detector.is_initialized:
            print("✅ Old system initialized")
            emotion_data = detector.detect_emotion()
            detector.cleanup()
            return emotion_data
        else:
            print("❌ Old system failed to initialize")
            return None
    except Exception as e:
        print(f"❌ Old system error: {e}")
        return None

def test_new_system():
    """Test the new emotion detection system"""
    print("🔍 Testing NEW emotion detection system...")
    try:
        from emotion_detector_v2 import LightweightEmotionDetector
        detector = LightweightEmotionDetector()
        
        if detector.is_initialized:
            print("✅ New system initialized")
            emotion_data = detector.detect_emotion()
            
            # Also test the summary feature
            summary = detector.get_emotion_summary()
            detector.cleanup()
            
            return emotion_data, summary
        else:
            print("❌ New system failed to initialize")
            return None, None
    except Exception as e:
        print(f"❌ New system error: {e}")
        return None, None

def compare_systems():
    """Compare both emotion detection systems"""
    print("🎭 EMOTION DETECTION SYSTEM COMPARISON")
    print("=" * 50)
    
    # Test old system
    old_result = test_old_system()
    print()
    
    # Test new system
    new_result, new_summary = test_new_system()
    print()
    
    # Show results
    print("📊 COMPARISON RESULTS:")
    print("-" * 30)
    
    if old_result:
        print("OLD SYSTEM OUTPUT:")
        print(json.dumps(old_result, indent=2, default=str))
    else:
        print("OLD SYSTEM: Failed to run")
    
    print()
    
    if new_result:
        print("NEW SYSTEM OUTPUT:")
        print(json.dumps(new_result, indent=2, default=str))
        print()
        if new_summary:
            print("NEW SYSTEM SUMMARY:")
            print(json.dumps(new_summary, indent=2, default=str))
    else:
        print("NEW SYSTEM: Failed to run")
    
    print()
    print("🔍 ANALYSIS:")
    
    if old_result and new_result:
        old_emotion = old_result.get('emotion', 'unknown')
        new_emotion = new_result.get('emotion', 'unknown')
        old_confidence = old_result.get('confidence', 0)
        new_confidence = new_result.get('confidence', 0)
        
        print(f"Emotion detected:")
        print(f"  - Old system: {old_emotion} (confidence: {old_confidence})")
        print(f"  - New system: {new_emotion} (confidence: {new_confidence})")
        
        if old_emotion == new_emotion:
            print("✅ Both systems detected the same emotion!")
        else:
            print("⚠️ Systems detected different emotions")
            
        print(f"Method used by new system: {new_result.get('method', 'unknown')}")
        
    elif new_result and not old_result:
        print("✅ New system works while old system failed!")
        print(f"New system detected: {new_result.get('emotion')} (confidence: {new_result.get('confidence')})")
        
    elif old_result and not new_result:
        print("⚠️ Old system works but new system failed")
        
    else:
        print("❌ Both systems failed to run")

def run_live_test():
    """Run a live test of the new emotion detection system"""
    print("🎭 LIVE EMOTION DETECTION TEST")
    print("=" * 40)
    print("This will run 5 emotion detections with 3-second intervals")
    print("Make different facial expressions to test the system!")
    print()
    
    try:
        from emotion_detector_v2 import LightweightEmotionDetector
        detector = LightweightEmotionDetector()
        
        if not detector.is_initialized:
            print("❌ Emotion detector not initialized")
            return
        
        emotions_detected = []
        
        for i in range(5):
            print(f"🎯 Detection {i+1}/5...")
            emotion_data = detector.detect_emotion()
            
            if emotion_data:
                emotion = emotion_data.get('emotion', 'unknown')
                confidence = emotion_data.get('confidence', 0)
                method = emotion_data.get('method', 'unknown')
                
                print(f"   Result: {emotion} ({confidence:.2f} confidence, {method})")
                emotions_detected.append(emotion)
                
                # Log the emotion
                detector.log_emotion(emotion_data)
            else:
                print("   Result: No emotion detected")
                emotions_detected.append('none')
            
            if i < 4:  # Don't wait after the last detection
                print("   Waiting 3 seconds...")
                time.sleep(3)
        
        print()
        print("📊 LIVE TEST SUMMARY:")
        print(f"Emotions detected: {emotions_detected}")
        
        # Show system summary
        summary = detector.get_emotion_summary()
        print("System summary:")
        print(json.dumps(summary, indent=2, default=str))
        
        detector.cleanup()
        
    except Exception as e:
        print(f"❌ Live test error: {e}")

def main():
    """Main test function"""
    if len(sys.argv) > 1 and sys.argv[1] == "--live":
        run_live_test()
    else:
        compare_systems()
        print()
        print("💡 TIP: Run with --live flag for a live emotion detection test:")
        print("   python test_emotion_detection.py --live")

if __name__ == "__main__":
    main() 