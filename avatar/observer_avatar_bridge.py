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
import json
import re

try:
    from . import avatar_display
except ImportError:
    avatar_display = None

class ObserverAvatarBridge:
    def __init__(self, goose_model=None):
        self.perception_dir = Path("~/.local/share/goose-perception").expanduser()
        self.last_check_times = {}
        self.last_file_contents = {}
        self.is_running = False
        # Track last suggestion to reduce repeats
        self.last_suggestion_text = ""
        # Unified content generation timer (loaded from settings or default 1 minute)
        self.last_content_generation = datetime.min
        self.settings_path = Path.home() / ".local/share/goose-perception/AVATAR_SETTINGS.json"
        self.content_generation_interval = timedelta(minutes=self._load_suggestion_interval())
        self._settings_mtime = self.settings_path.stat().st_mtime if self.settings_path.exists() else 0
        
        # Recipe selection probabilities (which recipe to run when timer fires)
        self.suggestions_chance = 0.5     # 50% chance for helpful suggestions (higher)
        self.chatter_chance = 0.3         # 30% chance for casual chatter (lower)
        self.actionable_chance = 0.2      # 20% chance for actionable items
        # Total = 100% - one of these will always be selected
        
        # Model configuration for goose recipes
        self.goose_model = goose_model
        
        # Ensure perception directory exists
        self.perception_dir.mkdir(parents=True, exist_ok=True)
        
        # Files to monitor
        self.monitored_files = {
            'WORK.md': 'work',
            'LATEST_WORK.md': 'work',
            'INTERACTIONS.md': 'interaction',
            'CONTRIBUTIONS.md': 'productivity',
            'ACTIVITY-LOG.md': 'general',
            'AVATAR_MESSAGE.json': 'message'
        }
        
        # Unified message file path
        self.message_file = self.perception_dir / "AVATAR_MESSAGE.json"
    
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
                # Check every 15 seconds for more responsive avatar
                time.sleep(15)
            except Exception as e:
                print(f"Error in observer bridge: {e}")
                time.sleep(60)  # Wait longer on error
    
    def _check_files(self):
        """Check monitored files for changes"""
        current_time = datetime.now()
        
        # Check mute status
        if self._is_muted():
            return  # skip processing while muted
        
        # Hot-reload settings if file changed
        try:
            if self.settings_path.exists():
                mtime = self.settings_path.stat().st_mtime
                if mtime != self._settings_mtime:
                    self._settings_mtime = mtime
                    new_interval = self._load_suggestion_interval()
                    self.content_generation_interval = timedelta(minutes=new_interval)
                    print(f"🔄 Reloaded avatar settings: suggestion interval now {new_interval} min")
        except Exception as e:
            print(f"⚠️ Could not reload avatar settings: {e}")
        
        # Check if it's time to generate new content
        if current_time - self.last_content_generation > self.content_generation_interval:
            self._generate_content()
            self.last_content_generation = current_time
        
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
    
    def _get_goose_env(self):
        """Get environment variables for goose subprocess, including model configuration"""
        env = os.environ.copy()
        
        if self.goose_model:
            env["GOOSE_MODEL"] = self.goose_model
            print(f"🤖 Using model: {self.goose_model}")
        
        return env
    
    def _get_recipe_parameters(self):
        """Get all parameters for recipes, including personality, time, and timezone"""
        # Get personality parameters
        params = self.get_personality_parameters()
        
        # Get time and timezone
        now = datetime.now()
        params['current_time'] = now.strftime("%Y-%m-%d %H:%M:%S")
        params['timezone'] = time.strftime("%Z")
        
        # Attach contents of key perception files so recipes have data
        file_map = {
            'latest_work_content': 'LATEST_WORK.md',
            'interactions_content': 'INTERACTIONS.md',
            'contributions_content': 'CONTRIBUTIONS.md',
            'work_content': 'WORK.md',
            'activity_log_content': 'ACTIVITY-LOG.md',
        }
        for key, filename in file_map.items():
            try:
                file_path = self.perception_dir / filename
                if file_path.exists():
                    raw = file_path.read_text(errors='ignore')
                    recent = self._slice_recent_minutes(raw, minutes=15)
                    if not recent:
                        # fallback to last 4000 chars if no recent slice found
                        recent = raw[-4000:]
                    params[key] = recent.replace("\n", "\\n")
                else:
                    params[key] = ""
            except Exception:
                params[key] = ""
        
        # Include last suggestion so recipe can avoid immediate repeats
        if hasattr(self, 'last_suggestion_text') and self.last_suggestion_text:
            params['last_suggestion'] = self.last_suggestion_text.replace("\n", " ")[:400]
        else:
            params['last_suggestion'] = ""
        
        return params

    def _generate_content(self):
        """Generate content by probabilistically selecting which recipe to run"""
        rand = random.random()
        
        if rand < self.chatter_chance:
            # Run chatter recipe
            self._run_chatter_recipe()
            print(f"🎲 Selected chatter recipe ({self.chatter_chance*100:.0f}% chance)")
            
        elif rand < self.chatter_chance + self.suggestions_chance:
            # Run suggestions recipe
            self._run_avatar_suggestions()
            print(f"🎲 Selected suggestions recipe ({self.suggestions_chance*100:.0f}% chance)")
            
        else:
            # Run actionable suggestions recipe
            self._run_actionable_suggestions()
            print(f"🎲 Selected actionable recipe ({self.actionable_chance*100:.0f}% chance)")
    
    def _run_avatar_suggestions(self):
        """Run the avatar suggestions observer recipe and immediately display the result"""
        try:
            print("🔍 Running avatar suggestions observer recipe...")
            recipe_params = self._get_recipe_parameters()
            param_args = []
            for key, value in recipe_params.items():
                param_args.extend(['--params', f'{key}={value}'])
            cmd = ["goose", "run", "--no-session", "--recipe", "observers/recipe-avatar-suggestions.yaml"] + param_args
            print(f"🎭 Running with personality: {recipe_params.get('personality_name', 'default')}")
            env = self._get_goose_env()
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=120, env=env)
            if result.returncode == 0:
                print("✅ Avatar suggestions recipe completed successfully (inline)")
                data = self._extract_json_from_output(result.stdout)
                suggestion_text = data.get("suggestion") if data else None
                if suggestion_text:
                    suggestion = {'type': 'general', 'message': suggestion_text}
                    self._show_suggestion(suggestion)
                    print(f"💡 Displayed suggestion directly: {suggestion_text}")
                else:
                    # Fallback to reading file written by recipe
                    self._process_new_suggestions()
            else:
                print(f"❌ Avatar suggestions recipe failed: {result.stderr}")
        except subprocess.TimeoutExpired:
            print("⏰ Avatar suggestions recipe timed out")
        except Exception as e:
            print(f"Error running avatar suggestions: {e}")
    
    def _run_actionable_suggestions(self):
        """Run the actionable suggestions recipe and display the result immediately"""
        try:
            print("🎯 Running actionable suggestions observer recipe...")
            recipe_params = self._get_recipe_parameters()
            param_args = []
            for key, value in recipe_params.items():
                param_args.extend(['--params', f'{key}={value}'])
            cmd = ["goose", "run", "--no-session", "--recipe", "observers/recipe-actionable-suggestions.yaml"] + param_args
            print(f"🎭 Running actionable suggestions with personality: {recipe_params.get('personality_name', 'default')}")
            env = self._get_goose_env()
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=120, env=env)
            if result.returncode == 0:
                print("✅ Actionable suggestions recipe completed successfully (inline)")
                data = self._extract_json_from_output(result.stdout)
                suggestion = data.get("actionable_suggestion") if data else None
                if suggestion:
                    self._show_actionable_suggestion(suggestion)
                    print(f"🎯 Displayed actionable suggestion: {suggestion.get('message', '')[:60]}...")
                else:
                    # Fallback to reading file written by recipe
                    self._process_actionable_suggestions()
            else:
                print(f"❌ Actionable suggestions recipe failed: {result.stderr}")
        except subprocess.TimeoutExpired:
            print("⏰ Actionable suggestions recipe timed out")
        except Exception as e:
            print(f"Error running actionable suggestions: {e}")
    
    def _run_chatter_recipe(self):
        """Run the chit-chat recipe and display the result immediately"""
        try:
            print("💬 Running avatar chit-chat recipe...")
            recipe_params = self._get_recipe_parameters()
            param_args = []
            for key, value in recipe_params.items():
                param_args.extend(['--params', f'{key}={value}'])
            cmd = ["goose", "run", "--no-session", "--recipe", "observers/recipe-avatar-chatter.yaml"] + param_args
            print(f"🎭 Running chatter with personality: {recipe_params.get('personality_name', 'default')}")
            env = self._get_goose_env()
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60, env=env)
            if result.returncode == 0:
                print("✅ Avatar chit-chat recipe completed successfully (inline)")
                # Prefer file-based parsing to avoid picking up recipe metadata lines
                self._process_new_chatter()
            else:
                print(f"❌ Avatar chit-chat recipe failed: {result.stderr}")
        except subprocess.TimeoutExpired:
            print("⏰ Avatar chit-chat recipe timed out")
        except Exception as e:
            print(f"Error running avatar chit-chat: {e}")
    
    def _parse_suggestions_file(self):
        """Parse the AVATAR_MESSAGE.json file and return single suggestion"""
        suggestions_file = self.message_file
        
        if not suggestions_file.exists():
            return None
            
        try:
            with open(suggestions_file, 'r') as f:
                data = json.load(f)
                suggestion_text = data.get("suggestion", "")
                
                if suggestion_text:
                    return {
                        'type': 'general',  # Default type for non-actionable suggestions
                        'message': suggestion_text
                    }
            
            return None
        except Exception as e:
            print(f"Error parsing suggestions file: {e}")
            return None
    
    def _parse_chatter_file(self):
        """Parse the AVATAR_MESSAGE.json file and return single casual message"""
        chatter_file = self.message_file
        
        if not chatter_file.exists():
            return None
            
        try:
            import json
            data = json.loads(chatter_file.read_text())
            return data.get("chatter")
        except Exception as e:
            print(f"Error parsing chatter file: {e}")
            return None
    
    def _parse_actionable_suggestions_file(self):
        """Parse the AVATAR_MESSAGE.json file and return single actionable suggestion"""
        actionable_file = self.message_file
        
        if not actionable_file.exists():
            return None
            
        try:
            with open(actionable_file, 'r') as f:
                data = json.load(f)
                suggestion = data.get("actionable_suggestion", {})
            
            if not suggestion:
                return None
            
            # Validate that action command exists
            from pathlib import Path
            actions_dir = Path("actions")
            available_actions = set()
            if actions_dir.exists():
                available_actions = {f.stem for f in actions_dir.glob("*.yaml")}
            
            action_command = suggestion.get('action_command', '')
            if action_command in available_actions:
                return suggestion
            else:
                print(f"⚠️ Skipping actionable suggestion with missing action: {action_command}")
                return None
            
        except Exception as e:
            print(f"Error parsing actionable suggestions file: {e}")
            return None
    
    def _process_actionable_suggestions(self):
        """Process newly generated actionable suggestion"""
        suggestion = self._parse_actionable_suggestions_file()
        
        if suggestion:
            # Show immediately - actionable suggestions are high priority!
            self._show_actionable_suggestion(suggestion)
            print(f"🎯 Immediately showing actionable suggestion: {suggestion['message']}")
    
    def _show_actionable_suggestion(self, suggestion):
        """Show an actionable suggestion with action buttons"""
        try:
            # Create action data for the suggestion
            action_data = {
                'action_type': suggestion['action_type'],
                'action_command': suggestion['action_command'],
                'observation_type': suggestion['observation_type']
            }
            
            # Use the thread-safe function instead of direct avatar_instance call
            from . import avatar_display
            avatar_display.show_actionable_message(
                suggestion['message'], 
                action_data,
                avatar_state='pointing'
            )
            
            # Track last suggestion text as well (for diversity)
            try:
                self.last_suggestion_text = suggestion.get('message', '')
            except Exception:
                pass
            
        except Exception as e:
            print(f"Error showing actionable suggestion: {e}")
    
    def _process_new_suggestions(self):
        """Process newly generated suggestion and show immediately"""
        suggestion = self._parse_suggestions_file()
        
        if not suggestion:
            return
            
        # Show new suggestion immediately - it's fresh and relevant!
        self._show_suggestion(suggestion)
        print(f"💡 Immediately showing new suggestion: {suggestion['message']}")
    
    def _process_new_chatter(self):
        """Process newly generated chatter and show immediately"""
        chatter_message = self._parse_chatter_file()
        
        if not chatter_message:
            return
            
        # Show new chatter immediately - it's fresh and contextual!
        from . import avatar_display
        avatar_display.show_message(chatter_message, 4000)
        print(f"💬 Immediately showing new chatter: {chatter_message[:50]}...")
    
    def _show_suggestion(self, suggestion):
        """Helper method to show a suggestion with proper avatar state"""
        # Map suggestion types to avatar states
        suggestion_types = {
            'productivity': 'work',
            'collaboration': 'meetings', 
            'focus': 'focus',
            'attention': 'attention',
            'optimization': 'optimization',
            'break': 'break',
            'system': 'optimization'
        }
        
        suggestion_type = suggestion_types.get(suggestion['type'], 'work')
        message = suggestion['message']
        
        # Use the thread-safe function instead of direct call
        from . import avatar_display
        avatar_display.show_suggestion(suggestion_type, message)
        
        # Save last suggestion text for repetition avoidance
        try:
            self.last_suggestion_text = suggestion.get('message', '')
        except Exception:
            pass
    
    def _process_file_change(self, filename, new_content, old_content, category):
        """Process a file change and potentially trigger avatar message"""
        try:
            # Handle avatar suggestions file updates
            if filename == 'AVATAR_MESSAGE.json':
                self._process_new_suggestions()
                return
            
            # Do nothing on file change – we no longer want hard-coded fallback chatter
            return
            
        except Exception as e:
            print(f"Error processing {filename} change: {e}")
    
    def get_personality_parameters(self):
        """Get personality parameters for recipes - thread-safe version"""
        try:
            # Don't access avatar_instance from background threads - use fallback approach
            # This prevents Qt threading violations while still providing personality context
            
            # Try to load personality from saved settings file (thread-safe)
            settings_path = Path.home() / ".local/share/goose-perception/PERSONALITY_SETTINGS.json"
            if settings_path.exists():
                try:
                    with open(settings_path, 'r') as f:
                        settings = json.load(f)
                    saved_personality = settings.get("current_personality", "comedian")
                    
                    # Load personality data from file (thread-safe)
                    personalities_path = Path(__file__).parent / "personalities.json"
                    if personalities_path.exists():
                        with open(personalities_path, 'r') as f:
                            personalities_data = json.load(f)
                            personality_data = personalities_data.get("personalities", {}).get(saved_personality, {})
                            
                            if personality_data:
                                return {
                                    'personality_name': personality_data.get('name', saved_personality.title()),
                                    'personality_style': personality_data.get('suggestion_style', ''),
                                    'personality_tone': personality_data.get('tone', ''),
                                    'personality_priorities': ', '.join(personality_data.get('priorities', [])),
                                    'personality_phrases': ', '.join(personality_data.get('example_phrases', []))
                                }
                except Exception as e:
                    print(f"Error reading personality settings: {e}")
            
            # Fallback to comedian personality (thread-safe default)
            return {
                'personality_name': 'Comedian',
                'personality_style': 'Everything is an opportunity for humor. Makes jokes about coding, work situations, and daily activities. Keeps things light and funny.',
                'personality_tone': 'humorous, witty, entertaining, lighthearted',
                'personality_priorities': 'humor, entertainment, making people laugh, finding the funny side',
                'personality_phrases': 'Why did the developer, Speaking of comedy, Here\'s a joke for you, Plot twist comedy, Funny thing about'
            }
        except Exception as e:
            print(f"Error getting personality parameters: {e}")
            # Return safe default parameters
            return {
                'personality_name': 'Comedian',
                'personality_style': 'Everything is an opportunity for humor. Makes jokes about coding, work situations, and daily activities.',
                'personality_tone': 'humorous, witty, entertaining',
                'personality_priorities': 'humor, entertainment, making people laugh',
                'personality_phrases': 'Why did the developer, Speaking of comedy, Here\'s a joke for you'
            }

    def trigger_contextual_message(self):
        """Trigger a contextual message from recipes"""
        if avatar_display is None:
            return
        
        # Try to show a chit-chat message from recipe-generated content
        chatter_message = self._parse_chatter_file()
        if chatter_message:
            avatar_display.show_message(chatter_message, 4000)
        else:
            # Fallback to simple interaction if no chatter available
            avatar_display.show_message("👋 How's it going?", 3000)

    def clear_old_suggestions(self):
        """Clear old suggestion files to ensure only personality-appropriate content remains"""
        try:
            suggestion_files = [
                self.message_file
            ]
            
            for file_path in suggestion_files:
                if file_path.exists():
                    file_path.unlink()
                    print(f"🗑️ Cleared old suggestions from {file_path.name}")
                    
        except Exception as e:
            print(f"⚠️ Error clearing old suggestions: {e}")

    @staticmethod
    def _extract_json_from_output(output: str):
        """Return JSON object parsed from the last curly-brace block in output."""
        # Collect all json-ish blocks
        blocks = re.findall(r"\{.*?\}", output, re.S)
        # Reverse to prioritise last blocks (most likely the payload)
        for blk in reversed(blocks):
            try:
                data = json.loads(blk)
                # Ensure it contains at least one known key
                if any(k in data for k in ("suggestion", "actionable_suggestion", "chatter")):
                    return data
            except Exception:
                continue
        return None

    @staticmethod
    def _slice_recent_minutes(text: str, minutes: int = 15) -> str:
        """Return section of text whose timestamp is within last N minutes."""
        import re, datetime
        cutoff = datetime.datetime.now() - datetime.timedelta(minutes=minutes)
        ts_re = re.compile(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})")
        keep_lines = []
        append_mode = False
        for line in text.splitlines():
            m = ts_re.search(line)
            if m:
                try:
                    ts = datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
                    append_mode = ts >= cutoff
                except ValueError:
                    append_mode = False
            if append_mode:
                keep_lines.append(line)
        return "\n".join(keep_lines)

    # ------------------------------------------------------------------
    # Settings loader
    # ------------------------------------------------------------------
    def _load_suggestion_interval(self) -> int:
        """Load suggestion interval (minutes) from AVATAR_SETTINGS.json or return default (1)."""
        try:
            settings_path = Path.home() / ".local/share/goose-perception/AVATAR_SETTINGS.json"
            if settings_path.exists():
                import json
                with open(settings_path, 'r') as f:
                    data = json.load(f)
                value = int(data.get("suggestion_interval_minutes", 1))
                return max(1, value)
        except Exception as e:
            print(f"⚠️ Could not load avatar settings: {e}")
        return 1  # default to 1 minute

    def _is_muted(self) -> bool:
        """Return True if current time is before mute_until timestamp in settings."""
        try:
            if self.settings_path.exists():
                import json, datetime
                data = json.load(self.settings_path.open())
                mute_until = data.get("mute_until")
                if mute_until:
                    ts = datetime.datetime.fromisoformat(mute_until)
                    return datetime.datetime.now() < ts
        except Exception:
            pass
        return False

def trigger_personality_update():
    """Trigger personality-based suggestion regeneration (can be called from other modules)"""
    global bridge_instance
    if bridge_instance:
        print("🎭 Triggering personality-based suggestion regeneration...")
        # Clear old suggestions first
        bridge_instance.clear_old_suggestions()
        # Generate new personality-based suggestions
        bridge_instance._run_avatar_suggestions()
        bridge_instance._run_actionable_suggestions()
        bridge_instance._run_chatter_recipe()
        return True
    else:
        print("❌ Bridge instance not available for personality update")
        return False

# Global bridge instance
bridge_instance = None

def start_observer_bridge(goose_model=None):
    """Start the observer-avatar bridge"""
    global bridge_instance
    
    if bridge_instance is None:
        bridge_instance = ObserverAvatarBridge(goose_model=goose_model)
        bridge_instance.start_monitoring()
    
    return bridge_instance

def trigger_contextual_message():
    """Trigger a contextual message (can be called from other modules)"""
    global bridge_instance
    if bridge_instance:
        bridge_instance.trigger_contextual_message()

if __name__ == "__main__":
    # Test the bridge
    try:
        from . import avatar_display
    except ImportError:
        # Fallback for direct execution
        import os
        import sys
        sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        from avatar import avatar_display
    
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
            # Occasionally trigger contextual messages for testing
            if random.random() < 0.1:  # 10% chance every loop
                bridge.trigger_contextual_message()
            time.sleep(10)
    except KeyboardInterrupt:
        print("\n👋 Bridge test ended.")
        bridge.stop_monitoring() 