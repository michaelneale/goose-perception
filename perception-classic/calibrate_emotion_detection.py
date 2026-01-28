#!/usr/bin/env python3
"""
calibrate_emotion_detection.py - Calibration tool for emotion detection
"""

import sys
import time
import json
from emotion_detector_v2 import LightweightEmotionDetector

def show_menu():
    """Show the calibration menu"""
    print("\n🎯 EMOTION DETECTION CALIBRATION MENU")
    print("=" * 45)
    print("1. Check current calibration status")
    print("2. Calibrate confidence threshold")
    print("3. Calibrate personal baseline (neutral)")
    print("4. Calibrate personal baseline (happy)")
    print("5. Calibrate personal baseline (sad)")
    print("6. Add manual feedback correction")
    print("7. Test detection with calibration")
    print("8. Test detection without calibration")
    print("9. Adjust calibration strength (responsiveness)")
    print("10. Reset all calibration data")
    print("0. Exit")
    print("=" * 45)

def check_calibration_status(detector):
    """Show current calibration status"""
    print("\n📊 CURRENT CALIBRATION STATUS")
    print("-" * 30)
    
    status = detector.get_calibration_status()
    
    print(f"Confidence threshold: {status['confidence_threshold']:.2f}")
    print(f"Personal baselines: {status['personal_baselines']} emotions calibrated")
    print(f"Feedback corrections: {status['feedback_corrections']} recorded")
    print(f"Temporal smoothing: {'Enabled' if status['temporal_smoothing'] else 'Disabled'}")
    print(f"Calibration strength: {status['calibration_strength']:.1f} (0.0=off, 1.0=max)")
    
    # Show what the calibration strength means
    strength = status['calibration_strength']
    if strength == 0.0:
        print("   📌 Raw AI detection only")
    elif strength <= 0.3:
        print("   📌 Gentle calibration - responsive with light smoothing")
    elif strength <= 0.7:
        print("   📌 Moderate calibration - balanced accuracy and stability")
    else:
        print("   📌 Strong calibration - maximum stability, slower response")
    
    if status['recommendations']:
        print("\n💡 RECOMMENDATIONS:")
        for i, rec in enumerate(status['recommendations'], 1):
            print(f"   {i}. {rec}")
    else:
        print("\n✅ Calibration looks good!")

def calibrate_confidence_threshold(detector):
    """Run confidence threshold calibration"""
    print("\n🎯 CONFIDENCE THRESHOLD CALIBRATION")
    print("-" * 35)
    print("This will take 10 detections while you make various expressions.")
    print("Try to show different emotions: neutral, happy, sad, surprised, etc.")
    
    input("Press Enter to start calibration...")
    detector.calibrate_confidence_threshold()

def calibrate_personal_baseline(detector, emotion):
    """Run personal baseline calibration for specific emotion"""
    print(f"\n🎯 PERSONAL BASELINE CALIBRATION: {emotion.upper()}")
    print("-" * 40)
    print(f"Please maintain a clear {emotion} expression for 30 seconds.")
    print("This helps the system learn what YOUR {emotion} looks like.")
    
    if emotion == 'neutral':
        print("For neutral: relax your face, look at the camera normally")
    elif emotion == 'happy':
        print("For happy: smile naturally, show genuine happiness")
    elif emotion == 'sad':
        print("For sad: frown, droop mouth corners, look downward slightly")
    
    input("Press Enter when you're ready to start...")
    detector.calibrate_personal_baseline(emotion, duration=30)

def add_manual_feedback(detector):
    """Add manual feedback correction"""
    print("\n🔧 MANUAL FEEDBACK CORRECTION")
    print("-" * 30)
    print("First, let's detect your current emotion...")
    
    result = detector.detect_emotion(apply_calibration=False)
    if not result:
        print("❌ Could not detect emotion. Please try again.")
        return
    
    detected_emotion = result['emotion']
    detected_confidence = result['confidence']
    
    print(f"Detected: {detected_emotion} (confidence: {detected_confidence:.2f})")
    print("\nWhat was the ACTUAL emotion you were expressing?")
    print("Options: neutral, happy, sad, angry, surprised, fear, disgust")
    
    actual_emotion = input("Actual emotion: ").strip().lower()
    
    if actual_emotion in ['neutral', 'happy', 'sad', 'angry', 'surprised', 'fear', 'disgust']:
        detector.add_feedback_correction(detected_emotion, detected_confidence, actual_emotion)
    else:
        print("❌ Invalid emotion. Please use one of the listed options.")

def test_detection(detector, with_calibration=True):
    """Test emotion detection"""
    calibration_text = "WITH" if with_calibration else "WITHOUT"
    print(f"\n🧪 TESTING DETECTION {calibration_text} CALIBRATION")
    print("-" * 40)
    print("Make different expressions. Press Ctrl+C to stop.")
    
    try:
        while True:
            result = detector.detect_emotion(apply_calibration=with_calibration)
            if result:
                emotion = result['emotion']
                confidence = result['confidence']
                method = result.get('method', 'unknown')
                
                print(f"🎭 {emotion} ({confidence:.2f} confidence, {method})")
                
                # Show calibration details if available
                if with_calibration and 'raw_emotion' in result:
                    raw_emotion = result['raw_emotion']
                    raw_confidence = result['raw_confidence']
                    if raw_emotion != emotion or abs(raw_confidence - confidence) > 0.05:
                        print(f"   └─ Raw: {raw_emotion} ({raw_confidence:.2f}) → Calibrated: {emotion} ({confidence:.2f})")
                
                if 'calibration_note' in result:
                    print(f"   └─ Note: {result['calibration_note']}")
                
                if 'temporal_smoothing' in result:
                    print(f"   └─ Smoothed from: {result.get('smoothing_history', [])}")
            
            time.sleep(3)
            
    except KeyboardInterrupt:
        print("\n✅ Testing stopped.")

def adjust_calibration_strength(detector):
    """Adjust calibration strength (responsiveness)"""
    print("\n🎛️ ADJUST CALIBRATION STRENGTH")
    print("-" * 30)
    current = detector.calibration_strength
    print(f"Current strength: {current:.1f}")
    print("\nCalibration strength levels:")
    print("0.0 = Raw AI only (most responsive, may be noisy)")
    print("0.3 = Gentle (responsive with light smoothing) [recommended]")
    print("0.5 = Moderate (balanced accuracy and stability)")
    print("0.7 = Strong (stable but slower to respond)")
    print("1.0 = Maximum (very stable, very slow response)")
    
    try:
        strength_input = input(f"\nEnter new strength (0.0-1.0) or press Enter to keep {current:.1f}: ").strip()
        
        if not strength_input:
            print("❌ No change made.")
            return
        
        strength = float(strength_input)
        detector.set_calibration_strength(strength)
        
    except ValueError:
        print("❌ Invalid input. Please enter a number between 0.0 and 1.0.")

def reset_calibration_data(detector):
    """Reset all calibration data"""
    print("\n⚠️ RESET CALIBRATION DATA")
    print("-" * 25)
    print("This will delete ALL calibration data including:")
    print("- Confidence threshold settings")
    print("- Personal baselines")
    print("- Manual feedback corrections")
    
    confirm = input("Are you sure? Type 'yes' to confirm: ").lower()
    
    if confirm == 'yes':
        detector.confidence_threshold = 0.4
        detector.personal_baselines = {}
        detector.feedback_corrections = {}
        detector.environmental_factors = {}
        detector.calibration_strength = 0.3
        detector._save_calibration()
        print("✅ Calibration data reset to defaults.")
    else:
        print("❌ Reset cancelled.")

def main():
    """Main calibration interface"""
    print("🎭 Emotion Detection Calibration Tool")
    print("Loading emotion detector...")
    
    detector = LightweightEmotionDetector()
    
    if not detector.is_initialized:
        print("❌ Emotion detector failed to initialize.")
        return
    
    print("✅ Emotion detector ready!")
    
    while True:
        show_menu()
        try:
            choice = input("\nEnter your choice (0-10): ").strip()
            
            if choice == '0':
                print("👋 Goodbye!")
                break
            elif choice == '1':
                check_calibration_status(detector)
            elif choice == '2':
                calibrate_confidence_threshold(detector)
            elif choice == '3':
                calibrate_personal_baseline(detector, 'neutral')
            elif choice == '4':
                calibrate_personal_baseline(detector, 'happy')
            elif choice == '5':
                calibrate_personal_baseline(detector, 'sad')
            elif choice == '6':
                add_manual_feedback(detector)
            elif choice == '7':
                test_detection(detector, with_calibration=True)
            elif choice == '8':
                test_detection(detector, with_calibration=False)
            elif choice == '9':
                adjust_calibration_strength(detector)
            elif choice == '10':
                reset_calibration_data(detector)
            else:
                print("❌ Invalid choice. Please enter 0-10.")
                
        except KeyboardInterrupt:
            print("\n👋 Goodbye!")
            break
        except Exception as e:
            print(f"❌ Error: {e}")
    
    detector.cleanup()

if __name__ == "__main__":
    main() 