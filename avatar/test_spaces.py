#!/usr/bin/env python3

import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Try both relative and absolute imports for flexibility
try:
    from .avatar_display import start_avatar_system
except ImportError:
    # Fallback for direct execution
    sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from avatar.avatar_display import start_avatar_system

def test_spaces_avatar():
    """Test avatar with macOS Spaces support"""
    print("🚀 Testing avatar with macOS Spaces support...")
    print("The avatar should now appear on ALL Spaces!")
    print("Try switching between Spaces - the avatar should be visible on all of them.")
    print("Press Ctrl+C to stop the test.")
    
    # Start the avatar system (now returns both app and avatar)
    app, avatar = start_avatar_system()
    
    # Show a welcome message
    avatar.show_message("I should appear on all your Spaces now! 🌟", 8000)
    
    # Let it run
    try:
        sys.exit(app.exec())
    except KeyboardInterrupt:
        print("\n👋 Test ended by user")
        sys.exit(0)

if __name__ == "__main__":
    test_spaces_avatar() 