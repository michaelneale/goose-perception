#!/usr/bin/env python3
"""
Test script for menu bar notifications using osascript
"""
import sys
import time
from pathlib import Path

# Add the avatar module to the path
sys.path.insert(0, str(Path(__file__).parent / "avatar"))

try:
    from menu_bar_avatar import test_menu_bar_notification, show_menu_bar_notification
    
    def test_notifications():
        print("🧪 Testing menu bar notifications with osascript...")
        
        # Test regular notification
        print("\n1. Testing regular notification...")
        show_menu_bar_notification("Goose Test", "This is a regular notification with native macOS sound!", "Glass")
        time.sleep(3)
        
        # Test success notification  
        print("\n2. Testing success notification...")
        show_menu_bar_notification("Goose", "Task completed successfully! ✅", "Glass")
        time.sleep(3)
        
        # Test error notification
        print("\n3. Testing error notification...")
        show_menu_bar_notification("Goose", "Something failed! ❌", "Basso")
        time.sleep(3)
        
        # Test attention-grabbing notification
        print("\n4. Testing attention notification...")
        show_menu_bar_notification("Goose", "Important update requires your attention! 🚨", "Submarine")
        time.sleep(3)
        
        # Test actionable notification
        print("\n5. Testing actionable notification...")
        test_menu_bar_notification("Ready for an action! Click the menu bar icon to interact.", actionable=True)
        
        print("\n✅ All notifications sent! Check your menu bar and notification center.")
        print("💡 The actionable notification should show with interaction instructions.")
        print("💡 Click the Goose menu bar icon to interact with actionable messages.")

    def test_direct_osascript():
        """Test osascript directly to make sure it works"""
        import subprocess
        
        print("\n🔧 Testing direct osascript notification...")
        
        script = '''
        display notification "Direct osascript test - Hello from Goose! 🪿" with title "Direct Test" sound name "Glass"
        '''
        
        try:
            result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
            if result.returncode == 0:
                print("✅ Direct osascript test successful!")
            else:
                print(f"❌ Direct osascript test failed: {result.stderr}")
        except Exception as e:
            print(f"❌ Error running direct osascript: {e}")

    if __name__ == "__main__":
        print("🪿 Goose Menu Bar Notification Test")
        print("=" * 40)
        
        # Test direct osascript first
        test_direct_osascript()
        
        # Test via menu bar system
        try:
            test_notifications()
        except Exception as e:
            print(f"❌ Error testing notifications: {e}")
            print("💡 Make sure Goose is running in menu bar mode!")
            
except ImportError as e:
    print(f"❌ Could not import menu bar avatar: {e}")
    print("💡 Make sure you're in the goose-perception directory and menu bar avatar is available") 