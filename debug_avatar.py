#!/usr/bin/env python3
"""
Debug script for the avatar system - force dismiss stuck messages
Usage: python debug_avatar.py [command]
Commands:
  dismiss - Force dismiss any stuck message
  reset   - Emergency reset of avatar UI
  status  - Show avatar status
"""

import sys
import os
from pathlib import Path

# Add the current directory to Python path
sys.path.insert(0, str(Path(__file__).parent))

try:
    import avatar_display
except ImportError as e:
    print(f"❌ Could not import avatar_display: {e}")
    sys.exit(1)

def show_status():
    """Show current avatar status"""
    if avatar_display.avatar_instance:
        instance = avatar_display.avatar_instance
        print(f"🤖 Avatar Status:")
        print(f"  • Visible: {instance.is_visible}")
        print(f"  • Showing message: {instance.is_showing_message}")
        print(f"  • Current state: {instance.current_state}")
        print(f"  • Message queue length: {len(instance.message_queue)}")
        
        # Check timer states
        timers = {
            'hide_timer': getattr(instance, 'hide_timer', None),
            'auto_dismiss_timer': getattr(instance, 'auto_dismiss_timer', None),
            'emergency_timer': getattr(instance, 'emergency_timer', None)
        }
        
        print(f"  • Active timers:")
        for name, timer in timers.items():
            if timer and hasattr(timer, 'isActive'):
                is_active = timer.isActive()
                remaining = timer.remainingTime() if is_active else 0
                print(f"    - {name}: {'Active' if is_active else 'Inactive'} ({remaining}ms remaining)")
            else:
                print(f"    - {name}: Not available")
                
        return True
    else:
        print("❌ Avatar instance not found - system may not be running")
        return False

def force_dismiss():
    """Force dismiss any stuck message"""
    print("🆘 Attempting to force dismiss stuck message...")
    success = avatar_display.force_dismiss_stuck_message()
    if success:
        print("✅ Force dismiss completed")
    return success

def emergency_reset():
    """Emergency reset of avatar system"""
    print("🆘 Attempting emergency reset...")
    success = avatar_display.emergency_avatar_reset()
    if success:
        print("✅ Emergency reset completed")
    return success

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        print("\n🤖 Available commands:")
        print("  status  - Show current avatar status")
        print("  dismiss - Force dismiss any stuck message")
        print("  reset   - Emergency reset of avatar UI")
        sys.exit(1)
    
    command = sys.argv[1].lower()
    
    if command == "status":
        show_status()
    elif command == "dismiss":
        if not show_status():
            sys.exit(1)
        force_dismiss()
    elif command == "reset":
        if not show_status():
            sys.exit(1)
        emergency_reset()
    else:
        print(f"❌ Unknown command: {command}")
        print("Available commands: status, dismiss, reset")
        sys.exit(1)

if __name__ == "__main__":
    main() 