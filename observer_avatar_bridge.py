#!/usr/bin/env python3
"""
observer_avatar_bridge.py - Bridge between observer system and avatar display
Monitors observer outputs and triggers appropriate avatar messages
"""

import os
import time
import random
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
import threading

try:
    import avatar_display
except ImportError:
    avatar_display = None

class ObserverAvatarBridge:
    def __init__(self):
        self.perception_dir = Path("~/.local/share/goose-perception").expanduser()
        self.last_check_times = {}
        self.last_file_contents = {}
        self.is_running = False
        self.last_suggestions_run = datetime.min
        self.suggestions_interval = timedelta(minutes=30)  # Run avatar suggestions every 30 minutes
        
        # Ensure perception directory exists
        self.perception_dir.mkdir(parents=True, exist_ok=True)
        
        # Files to monitor
        self.monitored_files = {
            'WORK.md': 'work',
            'LATEST_WORK.md': 'work',
            'INTERACTIONS.md': 'interaction',
            'CONTRIBUTIONS.md': 'productivity',
            'ACTIVITY-LOG.md': 'general',
            'AVATAR_SUGGESTIONS.md': 'suggestions'
        }
    
    def start_monitoring(self):
        """Start monitoring observer files"""
        if avatar_display is None:
            print("Avatar display not available, bridge disabled")
            return
            
        self.is_running = True
        monitor_thread = threading.Thread(target=self._monitor_loop, daemon=True)
        monitor_thread.start()
        print("🔗 Observer-Avatar bridge started...")
    
    def stop_monitoring(self):
        """Stop monitoring"""
        self.is_running = False
    
    def _monitor_loop(self):
        """Main monitoring loop"""
        while self.is_running:
            try:
                self._check_files()
                # Check every 30 seconds
                time.sleep(30)
            except Exception as e:
                print(f"Error in observer bridge: {e}")
                time.sleep(60)  # Wait longer on error
    
    def _check_files(self):
        """Check monitored files for changes"""
        current_time = datetime.now()
        
        # Check if it's time to run avatar suggestions
        if current_time - self.last_suggestions_run > self.suggestions_interval:
            self._run_avatar_suggestions()
            self.last_suggestions_run = current_time
        
        for filename, category in self.monitored_files.items():
            file_path = self.perception_dir / filename
            
            if not file_path.exists():
                continue
                
            try:
                # Get file modification time
                mod_time = datetime.fromtimestamp(file_path.stat().st_mtime)
                last_check = self.last_check_times.get(filename, datetime.min)
                
                # If file was modified since last check
                if mod_time > last_check:
                    self.last_check_times[filename] = current_time
                    
                    # Read new content
                    new_content = file_path.read_text()
                    old_content = self.last_file_contents.get(filename, "")
                    
                    # Check if content actually changed
                    if new_content != old_content:
                        self.last_file_contents[filename] = new_content
                        self._process_file_change(filename, new_content, old_content, category)
                        
            except Exception as e:
                print(f"Error checking {filename}: {e}")
    
    def _run_avatar_suggestions(self):
        """Run the avatar suggestions observer recipe"""
        try:
            print("🔍 Running avatar suggestions observer recipe...")
            
            # Run the goose recipe
            result = subprocess.run([
                "goose", "run", "--no-session", 
                "--recipe", "observers/recipe-avatar-suggestions.yaml"
            ], capture_output=True, text=True, timeout=120)
            
            if result.returncode == 0:
                print("✅ Avatar suggestions recipe completed successfully")
                self._process_new_suggestions()
            else:
                print(f"❌ Avatar suggestions recipe failed: {result.stderr}")
                
        except subprocess.TimeoutExpired:
            print("⏰ Avatar suggestions recipe timed out")
        except Exception as e:
            print(f"Error running avatar suggestions: {e}")
    
    def _parse_suggestions_file(self):
        """Parse the AVATAR_SUGGESTIONS.md file and return suggestions"""
        suggestions_file = self.perception_dir / "AVATAR_SUGGESTIONS.md"
        suggestions = []
        
        if not suggestions_file.exists():
            return suggestions
            
        try:
            content = suggestions_file.read_text()
            lines = content.strip().split('\n')
            
            for line in lines:
                if ':' in line and not line.startswith('#'):
                    suggestion_type, message = line.split(':', 1)
                    suggestions.append({
                        'type': suggestion_type.strip(),
                        'message': message.strip().strip('"')
                    })
            
            return suggestions
        except Exception as e:
            print(f"Error parsing suggestions file: {e}")
            return []
    
    def _process_new_suggestions(self):
        """Process newly generated suggestions and potentially show one"""
        suggestions = self._parse_suggestions_file()
        
        if not suggestions:
            return
            
        # Show a random suggestion with some probability
        if random.random() < 0.6:  # 60% chance to show a suggestion
            suggestion = random.choice(suggestions)
            
            # Map suggestion types to avatar states
            suggestion_types = {
                'productivity': 'work',
                'collaboration': 'meetings', 
                'focus': 'focus',
                'attention': 'attention',
                'optimization': 'optimization',
                'break': 'break'
            }
            
            suggestion_type = suggestion_types.get(suggestion['type'], 'work')
            message = suggestion['message']
            
            if avatar_display:
                avatar_display.show_suggestion(suggestion_type, message)
    
    def _process_file_change(self, filename, new_content, old_content, category):
        """Process a file change and potentially trigger avatar message"""
        try:
            # Handle avatar suggestions file updates
            if filename == 'AVATAR_SUGGESTIONS.md':
                self._process_new_suggestions()
                return
            
            # For other files, occasionally show a contextual message
            if random.random() > 0.3:  # 30% chance to show message
                return
                
            # Simple fallback messages for file changes
            if filename == 'LATEST_WORK.md':
                if avatar_display:
                    avatar_display.show_message("📝 I see you're updating your current work focus...")
            elif filename == 'INTERACTIONS.md':
                if avatar_display:
                    avatar_display.show_message("🤝 New interaction data updated...")
            elif filename == 'CONTRIBUTIONS.md':
                if avatar_display:
                    avatar_display.show_message("📈 Your contribution patterns have been updated...")
                
        except Exception as e:
            print(f"Error processing {filename} change: {e}")
    

    
    def trigger_random_creepy_message(self):
        """Trigger a random creepy/helpful message"""
        if avatar_display is None:
            return
            
        creepy_messages = [
            "👁️ I've been watching your patterns... Want to optimize something?",
            "🔍 I notice you haven't checked your email in 23 minutes. Shall I summarize?",
            "⏰ Your most productive time is approaching. Should I prepare your workspace?",
            "🤖 I could automate that task you do every day at this time...",
            "📈 Your efficiency dropped 8% in the last hour. Need help focusing?",
            "🧠 I've learned your preferences. Want me to anticipate your next move?",
            "🔮 Based on your patterns, you'll want to work on Project X next.",
            "⚡ I spotted a better way to do what you're working on...",
            "📝 That document could be 47% shorter with better organization.",
            "🎯 I can predict what you need before you realize it yourself."
        ]
        
        message = random.choice(creepy_messages)
        avatar_display.show_message(message)

# Global bridge instance
bridge_instance = None

def start_observer_bridge():
    """Start the observer-avatar bridge"""
    global bridge_instance
    
    if bridge_instance is None:
        bridge_instance = ObserverAvatarBridge()
        bridge_instance.start_monitoring()
    
    return bridge_instance

def trigger_random_message():
    """Trigger a random message (can be called from other modules)"""
    global bridge_instance
    if bridge_instance:
        bridge_instance.trigger_random_creepy_message()

if __name__ == "__main__":
    # Test the bridge
    import avatar_display
    
    # Start avatar system
    avatar_display.start_avatar_system()
    time.sleep(2)
    
    # Start bridge
    bridge = start_observer_bridge()
    
    print("🔗 Observer-Avatar bridge test running...")
    print("This will monitor observer files and trigger avatar messages.")
    print("Press Ctrl+C to stop.")
    
    try:
        while True:
            # Occasionally trigger random messages for testing
            if random.random() < 0.1:  # 10% chance every loop
                bridge.trigger_random_creepy_message()
            time.sleep(10)
    except KeyboardInterrupt:
        print("\n👋 Bridge test ended.")
        bridge.stop_monitoring() 