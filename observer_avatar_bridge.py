#!/usr/bin/env python3
"""
observer_avatar_bridge.py - Bridge between observer system and avatar display
Monitors observer outputs and triggers appropriate avatar messages
"""

import os
import time
import random
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
        
        # Ensure perception directory exists
        self.perception_dir.mkdir(parents=True, exist_ok=True)
        
        # Files to monitor
        self.monitored_files = {
            'WORK.md': 'work',
            'LATEST_WORK.md': 'work',
            'INTERACTIONS.md': 'interaction',
            'CONTRIBUTIONS.md': 'productivity',
            'ACTIVITY-LOG.md': 'general'
        }
        
        # Avatar message templates based on work patterns
        self.message_templates = {
            'productivity_suggestion': [
                "📈 I notice you've been productive with {}. Want me to help optimize further?",
                "⚡ You're making great progress on {}. Should I prepare related tasks?",
                "🎯 Your focus on {} is impressive. Need any resources or reminders?",
            ],
            'break_reminder': [
                "⏰ You've been working intensely for a while. Time for a quick break?",
                "🧘 I detect focused work for extended periods. A 5-minute break might help.",
                "☕ Based on your patterns, you might need some coffee or water soon.",
            ],
            'meeting_prep': [
                "📅 I see meeting activity. Should I help prepare follow-up actions?",
                "🤝 Looks like you had some important discussions. Want me to create reminders?",
                "📝 I noticed some collaboration. Should I summarize the key points?",
            ],
            'work_pattern': [
                "🔍 I'm tracking your work patterns. You seem most productive during {} hours.",
                "📊 Your workflow shows interesting patterns. Want insights on optimization?",
                "⚙️ I've learned your work style. Should I suggest some improvements?",
            ],
            'attention_needed': [
                "🚨 Something requires your attention based on recent activity.",
                "⚠️ I noticed some items that might need follow-up.",
                "🔔 There are some patterns worth discussing when you have time.",
            ]
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
    
    def _process_file_change(self, filename, new_content, old_content, category):
        """Process a file change and potentially trigger avatar message"""
        
        # Don't spam messages - only show occasionally
        if random.random() > 0.4:  # 40% chance to show message
            return
            
        try:
            # Analyze the content change
            if filename == 'LATEST_WORK.md':
                self._handle_work_update(new_content)
            elif filename == 'INTERACTIONS.md':
                self._handle_interaction_update(new_content)
            elif filename == 'CONTRIBUTIONS.md':
                self._handle_contribution_update(new_content)
            elif filename == 'ACTIVITY-LOG.md':
                self._handle_activity_update(new_content)
                
        except Exception as e:
            print(f"Error processing {filename} change: {e}")
    
    def _handle_work_update(self, content):
        """Handle work updates"""
        # Look for keywords to determine type of work
        content_lower = content.lower()
        
        if any(word in content_lower for word in ['meeting', 'call', 'discussion']):
            message = random.choice(self.message_templates['meeting_prep'])
            avatar_display.show_suggestion('meetings', message)
        elif any(word in content_lower for word in ['coding', 'programming', 'development']):
            message = "🔍 I see you're deep in code. Want me to watch for any patterns or issues?"
            avatar_display.show_suggestion('work', message)
        elif any(word in content_lower for word in ['writing', 'document', 'doc']):
            message = "📝 Looks like you're working on documentation. Need help organizing your thoughts?"
            avatar_display.show_suggestion('work', message)
        else:
            message = random.choice(self.message_templates['work_pattern'])
            avatar_display.show_suggestion('work', message.format("work"))
    
    def _handle_interaction_update(self, content):
        """Handle interaction updates"""
        if random.random() < 0.3:  # 30% chance
            message = random.choice(self.message_templates['meeting_prep'])
            avatar_display.show_suggestion('meetings', message)
    
    def _handle_contribution_update(self, content):
        """Handle contribution updates"""
        if random.random() < 0.3:  # 30% chance
            message = "📈 I'm tracking your contributions. Your productivity looks great today!"
            avatar_display.show_suggestion('productivity', message)
    
    def _handle_activity_update(self, content):
        """Handle activity log updates"""
        # Look for patterns in recent activity
        if 'voice request' in content.lower() or 'screen capture' in content.lower():
            return  # Skip these, we already handle them in agent.py
            
        if random.random() < 0.2:  # 20% chance for general activity
            message = random.choice([
                "👁️ I'm keeping track of everything... as always.",
                "📊 Your activity patterns are quite interesting today.",
                "🤔 I notice some changes in your workflow. Adapting accordingly.",
                "⚙️ Background processing complete. Everything is under control."
            ])
            avatar_display.show_message(message)
    
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