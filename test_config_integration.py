#!/usr/bin/env python3
"""
Test script to verify that all config values are being used correctly
"""

from config_manager import get_config_manager
import sys
import os

def test_config_integration():
    """Test that all config values are properly integrated"""
    
    config = get_config_manager()
    
    print("=" * 60)
    print("TESTING CONFIG INTEGRATION")
    print("=" * 60)
    
    # Test 1: Check config values are accessible
    print("\n1. Testing config value access:")
    print(f"   Voice enabled: {config.is_voice_enabled()}")
    print(f"   Avatar enabled: {config.is_avatar_enabled()}")
    print(f"   Emotions enabled: {config.is_emotion_enabled()}")
    print(f"   Notifications enabled: {config.is_notifications_enabled()}")
    print(f"   Hotkeys enabled: {config.is_hotkeys_enabled()}")
    print(f"   Wake word: {config.get_voice_wake_word()}")
    print(f"   Context seconds: {config.get_voice_context_seconds()}")
    print(f"   Silence seconds: {config.get_voice_silence_seconds()}")
    print(f"   Fuzzy threshold: {config.get_voice_fuzzy_threshold()}")
    print(f"   Confidence threshold: {config.get_voice_confidence_threshold()}")
    print(f"   Avatar personality: {config.get_avatar_personality()}")
    print(f"   Interface mode: {config.get_interface_mode()}")
    print(f"   Emotion interval: {config.get_emotion_interval()}")
    
    # Test 2: Check emotion_detector_v2 uses config
    print("\n2. Testing emotion_detector_v2 integration:")
    try:
        from emotion_detector_v2 import LightweightEmotionDetector
        detector = LightweightEmotionDetector()
        if detector.detection_interval == config.get_emotion_interval():
            print(f"   ✅ Emotion detector using config interval: {detector.detection_interval}s")
        else:
            print(f"   ❌ Emotion detector NOT using config! Has {detector.detection_interval}s, config has {config.get_emotion_interval()}s")
    except Exception as e:
        print(f"   ❌ Error testing emotion detector: {e}")
    
    # Test 3: Check perception.py uses config
    print("\n3. Testing perception.py integration:")
    try:
        # Import the constants from perception
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import perception
        
        if perception.DEFAULT_CONTEXT_DURATION == config.get_voice_context_seconds():
            print(f"   ✅ Perception using config context duration: {perception.DEFAULT_CONTEXT_DURATION}s")
        else:
            print(f"   ❌ Perception NOT using config context! Has {perception.DEFAULT_CONTEXT_DURATION}s")
            
        if perception.DEFAULT_SILENCE_DURATION == config.get_voice_silence_seconds():
            print(f"   ✅ Perception using config silence duration: {perception.DEFAULT_SILENCE_DURATION}s")
        else:
            print(f"   ❌ Perception NOT using config silence! Has {perception.DEFAULT_SILENCE_DURATION}s")
            
        if perception.DEFAULT_FUZZY_THRESHOLD == config.get_voice_fuzzy_threshold():
            print(f"   ✅ Perception using config fuzzy threshold: {perception.DEFAULT_FUZZY_THRESHOLD}")
        else:
            print(f"   ❌ Perception NOT using config fuzzy! Has {perception.DEFAULT_FUZZY_THRESHOLD}")
            
        if perception.DEFAULT_CLASSIFIER_THRESHOLD == config.get_voice_confidence_threshold():
            print(f"   ✅ Perception using config classifier threshold: {perception.DEFAULT_CLASSIFIER_THRESHOLD}")
        else:
            print(f"   ❌ Perception NOT using config classifier! Has {perception.DEFAULT_CLASSIFIER_THRESHOLD}")
            
    except Exception as e:
        print(f"   ❌ Error testing perception: {e}")
    
    # Test 4: Test config modification
    print("\n4. Testing config modification:")
    original_voice = config.is_voice_enabled()
    config.set_voice_enabled(not original_voice)
    new_voice = config.is_voice_enabled()
    if new_voice != original_voice:
        print(f"   ✅ Config modification works: voice changed from {original_voice} to {new_voice}")
        # Restore original
        config.set_voice_enabled(original_voice)
    else:
        print(f"   ❌ Config modification failed!")
    
    # Test 5: Test config save and reload
    print("\n5. Testing config persistence:")
    config.save_config()
    config.reload()
    if config.is_voice_enabled() == original_voice:
        print(f"   ✅ Config save/reload works")
    else:
        print(f"   ❌ Config save/reload failed!")
    
    print("\n" + "=" * 60)
    print("CONFIG INTEGRATION TEST COMPLETE")
    print("=" * 60)

if __name__ == "__main__":
    test_config_integration()
