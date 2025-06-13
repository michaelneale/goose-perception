#!/usr/bin/env python3

import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from PyQt6.QtCore import QTimer

# Try both relative and absolute imports for flexibility
try:
    from .avatar_display import start_avatar_system
except ImportError:
    # Fallback for direct execution
    sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from avatar.avatar_display import start_avatar_system

def test_actionable_avatar():
    """Test avatar with actionable suggestions"""
    print("🎯 Testing actionable avatar system...")
    print("The avatar will show suggestions with action buttons!")
    print("Try clicking 'Do It' to execute actions or 'Not Now' to dismiss.")
    print("Press Ctrl+C to stop the test.")
    
    # Start the avatar system
    app, avatar = start_avatar_system()
    
    # Show welcome message first
    avatar.show_message("Ready to help with actionable suggestions! 🚀", 3000)
    
    # Use QTimer for safe UI updates instead of threading
    def show_first_action():
        action_data = {
            'action_type': 'email',
            'action_command': 'compose_team_update',
            'observation_type': 'communication'
        }
        print("Showing first actionable suggestion...")
        avatar.show_message(
            "You haven't sent a team update in 3 days. Send status update?",
            duration=20000,  # 20 seconds to test
            avatar_state='pointing',
            action_data=action_data
        )
        
        # Schedule second action
        QTimer.singleShot(25000, show_second_action)
    
    def show_second_action():
        action_data = {
            'action_type': 'meeting',
            'action_command': 'create_follow_up_meeting',
            'observation_type': 'follow_up'
        }
        print("Showing second actionable suggestion...")
        avatar.show_message(
            "Yesterday's design meeting needs follow-up. Schedule planning session?",
            duration=20000,
            avatar_state='pointing',
            action_data=action_data
        )
        
        # Schedule third action
        QTimer.singleShot(25000, show_third_action)
    
    def show_third_action():
        action_data = {
            'action_type': 'status',
            'action_command': 'update_project_status',
            'observation_type': 'update'
        }
        print("Showing third actionable suggestion...")
        avatar.show_message(
            "Project status hasn't been updated in 5 days. Update stakeholders?",
            duration=20000,
            avatar_state='pointing',
            action_data=action_data
        )
    
    # Start the demo sequence with QTimer
    QTimer.singleShot(4000, show_first_action)  # Start after 4 seconds
    
    # Let it run
    try:
        sys.exit(app.exec())
    except KeyboardInterrupt:
        print("\n👋 Test ended by user")
        sys.exit(0)

if __name__ == "__main__":
    test_actionable_avatar() 