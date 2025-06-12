#!/usr/bin/env python3
"""
test_avatar.py - Test the Goose Avatar Display System
"""

import sys
import time
from PyQt6.QtWidgets import QApplication
from PyQt6.QtCore import QTimer
import avatar_display

def test_avatar():
    """Test the avatar system with various creepy suggestions"""
    
    print("🤖 Starting Avatar Test...")
    
    # Create QApplication
    app = QApplication(sys.argv)
    
    # Create avatar instance
    avatar = avatar_display.GooseAvatar()
    avatar.app = app
    avatar.show_avatar()
    
    # Schedule tests to run after avatar is shown
    QTimer.singleShot(2000, lambda: run_tests(avatar))
    
    print("📊 Starting tests...")
    
    # Start the Qt application event loop
    sys.exit(app.exec())

def run_tests(avatar):
    """Run the actual tests"""
    # Test different types of messages
    test_messages = [
        ("👁️ Goose is now watching...", 3),
        ("🔍 I've been observing your workflow patterns...", 4),
        ("⚡ I noticed you've been doing that task manually again. Want me to automate it?", 5),
        ("📈 Your productivity seems to have dipped 15 minutes ago. Time for a break?", 5),
        ("🤖 I could help you optimize that code you were just working on...", 4),
        ("👀 I see you checking email frequently. Should I summarize your messages?", 5),
        ("⏰ Based on your patterns, you'll need more coffee in about 20 minutes...", 4),
        ("🎯 I can help you focus on what matters most right now...", 4),
        ("💡 Want me to create a reminder about that meeting you mentioned?", 4),
        ("🔮 I predict you'll want to work on that project next. Should I prepare some files?", 5)
    ]
    
    print("📊 Testing different message types...")
    
    def show_next_message(index=0):
        if index < len(test_messages):
            message, duration = test_messages[index]
            print(f"Test {index+1}: {message[:50]}...")
            avatar.show_message(message)
            # Schedule next message
            QTimer.singleShot((duration + 2) * 1000, lambda: show_next_message(index + 1))
        else:
            # Start observer tests
            QTimer.singleShot(2000, lambda: run_observer_tests(avatar))
    
    show_next_message()

def run_observer_tests(avatar):
    """Run observer suggestion tests"""
    print("\n🎭 Testing different observation types...")
    
    # Test observer suggestions
    observation_tests = [
        ("work", "You've been coding for 2 hours straight. Consider taking a 5-minute break."),
        ("meetings", "Your next meeting starts in 10 minutes. Should I prepare the agenda?"),
        ("focus", "I notice you're switching between tasks frequently. Want help prioritizing?"),
        ("productivity", "Your most productive hours seem to be 9-11 AM. Plan important tasks then."),
        ("optimization", "That script you ran could be 3x faster with some tweaks."),
    ]
    
    def show_next_observation(index=0):
        if index < len(observation_tests):
            obs_type, message = observation_tests[index]
            print(f"Observer test ({obs_type}): {message[:50]}...")
            avatar.show_observer_suggestion(obs_type, message)
            # Schedule next observation
            QTimer.singleShot(6000, lambda: show_next_observation(index + 1))
        else:
            # Start queue tests
            QTimer.singleShot(2000, lambda: run_queue_tests(avatar))
    
    show_next_observation()

def run_queue_tests(avatar):
    """Run message queue tests"""
    print("\n🎬 Testing message queue...")
    
    # Test message queueing
    queue_messages = [
        "First message in queue",
        "Second message - this should queue up",
        "Third message - this should also queue",
        "Final message in the queue test"
    ]
    
    for msg in queue_messages:
        avatar.queue_message(msg)
    
    print("\n✅ Avatar test complete! The avatar should continue running.")
    print("Click on the avatar to interact with it or close the window to exit.")

if __name__ == "__main__":
    test_avatar() 