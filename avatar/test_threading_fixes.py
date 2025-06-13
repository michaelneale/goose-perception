#!/usr/bin/env python3
"""
Test script to verify threading fixes for avatar system
"""

import sys
import time
import threading
from pathlib import Path

# Add the avatar module to the path
sys.path.insert(0, str(Path(__file__).parent))

from avatar_display import start_avatar_system, show_message, show_actionable_message, process_qt_events

def test_background_thread_messages():
    """Test that messages from background threads work correctly"""
    print("🧪 Testing background thread message sending...")
    
    def background_message_sender():
        time.sleep(2)
        print("📤 Sending message from background thread...")
        show_message("🧪 Test message from background thread!", 5000)
        
        time.sleep(3)
        print("📤 Sending actionable message from background thread...")
        action_data = {
            'action_type': 'test',
            'action_command': 'test-action',
            'observation_type': 'test'
        }
        show_actionable_message("🎯 Test actionable message from background thread!", action_data, 8000)
    
    # Start background thread
    thread = threading.Thread(target=background_message_sender, daemon=True)
    thread.start()
    
    print("✅ Background thread started - should not cause Qt threading errors")

def main():
    """Main test function"""
    print("🧪 Starting avatar threading test...")
    
    # Start the avatar system
    app, avatar = start_avatar_system()
    
    # Test background thread messages
    test_background_thread_messages()
    
    # Process Qt events for 15 seconds to see if any errors occur
    print("⏰ Running for 15 seconds to check for threading errors...")
    for i in range(150):  # 15 seconds
        process_qt_events()
        time.sleep(0.1)
    
    print("✅ Test completed - check console for any Qt threading errors")
    print("❌ If you see 'QObject::setParent' or 'QObject::startTimer' errors, threading issues remain")
    print("✅ If no Qt errors appear, threading fixes are working!")
    
    # Clean exit
    sys.exit(0)

if __name__ == "__main__":
    main() 