#!/usr/bin/env python3
"""
Test script to verify that long actionable messages are displayed correctly
"""

import sys
import time
from pathlib import Path

# Add the avatar module to the path
sys.path.insert(0, str(Path(__file__).parent))

from avatar_display import start_avatar_system, show_actionable_message, process_qt_events

def test_long_actionable_messages():
    """Test that long actionable messages display correctly"""
    print("🧪 Testing long actionable message display...")
    
    # Test short message first
    short_message = "Quick reminder: Check your notifications!"
    action_data_short = {
        'action_type': 'notifications',
        'action_command': 'check-notifications',
        'observation_type': 'productivity'
    }
    
    print(f"📏 Short message length: {len(short_message)} characters")
    print(f"📝 Short message: '{short_message}'")
    print("🎯 Sending short actionable message...")
    
    show_actionable_message(short_message, action_data_short, 8000)
    
    # Wait before showing next message
    time.sleep(4)
    
    # Create a long message like the ones from your logs
    long_message = (
        "Kvadratni's been waiting on your temporal scheduler review since yesterday. "
        "Oh sure, because making your collaborators wait while you perfect avatar bridging "
        "is totally not passive-aggressive. Shocking concept: maybe prioritize the humans "
        "who are actually trying to work with you instead of endlessly tweaking UI elements?"
    )
    
    action_data = {
        'action_type': 'slack',
        'action_command': 'check-slack-messages',
        'observation_type': 'collaboration'
    }
    
    print(f"📏 Long message length: {len(long_message)} characters")
    print(f"📝 Long message: '{long_message}'")
    print("🎯 Sending long actionable message...")
    
    show_actionable_message(long_message, action_data, 10000)
    
    # Test medium message
    time.sleep(4)
    
    medium_message = (
        "Let me guess - you'll spend another 3 hours debugging recipe parameters "
        "while your actual project deadlines slip further into the abyss."
    )
    
    action_data2 = {
        'action_type': 'focus',
        'action_command': 'review-priorities',
        'observation_type': 'productivity'
    }
    
    print(f"📏 Medium message length: {len(medium_message)} characters")
    print(f"📝 Medium message: '{medium_message}'")
    print("🎯 Sending medium actionable message...")
    
    show_actionable_message(medium_message, action_data2, 10000)

def main():
    """Main test function"""
    print("🧪 Starting long message display test...")
    
    # Start the avatar system
    app, avatar = start_avatar_system()
    
    # Test long actionable messages
    test_long_actionable_messages()
    
    # Process Qt events for 30 seconds to see the messages
    print("⏰ Running for 30 seconds to observe message display...")
    for i in range(300):  # 30 seconds
        process_qt_events()
        time.sleep(0.1)
    
    print("✅ Test completed - check if long messages displayed fully")
    
    # Clean exit
    sys.exit(0)

if __name__ == "__main__":
    main() 