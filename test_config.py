#!/usr/bin/env python3
"""
Basic test script for goose-perception configuration system
"""

import os
import sys
from pathlib import Path

# Add parent directory to path to import our modules
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config_manager import ConfigManager

def test_config_basics():
    """Test basic configuration functionality"""
    print("🧪 Testing configuration basics...")
    
    # Create config manager instance
    config = ConfigManager()
    
    # Test default values
    assert config.is_voice_enabled() == True, "Voice should be enabled by default"
    assert config.is_avatar_enabled() == True, "Avatar should be enabled by default"
    assert config.get_voice_wake_word() == "goose", "Default wake word should be 'goose'"
    assert config.get_emotion_interval() == 60, "Default emotion interval should be 60"
    print("  ✅ Default values are correct")
    
    # Test feature toggling
    config.set_voice_enabled(False)
    assert config.is_voice_enabled() == False, "Voice should be disabled"
    config.set_voice_enabled(True)
    assert config.is_voice_enabled() == True, "Voice should be enabled"
    print("  ✅ Feature toggling works")
    
    # Test persistence
    config1 = ConfigManager()
    config1.set_avatar_enabled(False)
    
    config2 = ConfigManager()
    assert not config2.is_avatar_enabled(), "Setting should persist"
    
    # Reset for cleanup
    config2.set_avatar_enabled(True)
    print("  ✅ Settings persist across instances")
    
    return True

def main():
    """Run tests"""
    print("=" * 60)
    print("🧪 CONFIGURATION TEST")
    print("=" * 60)
    
    try:
        if test_config_basics():
            print("\n✅ All tests passed!")
            return 0
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
