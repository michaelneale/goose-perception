#!/usr/bin/env python3
"""
Configuration manager for Goose Perception
Handles loading and managing all settings from user_prefs.yaml

This provides a centralized configuration system that:
- Uses a single user_prefs.yaml file for ALL configuration
- Provides sensible defaults so users only need to override what they want
- Automatically merges user settings with defaults
- Maintains backward compatibility with existing code

Users only need to add settings they want to change to user_prefs.yaml.
All technical defaults are handled here.
"""

import yaml
from pathlib import Path
from typing import Dict, Any, Optional

class ConfigManager:
    """Manages configuration for Goose Perception features using user_prefs.yaml"""
    
    DEFAULT_CONFIG = {
        # User preferences (existing)
        'interface_mode': 'floating',
        'team_channel': '',
        'announcement_channel': '',
        'send_email_updates': False,
        'email_recipients': '',
        'notification_urgency': '',
        'reminders_enabled': True,
        'preferred_update_time': '',
        
        # Feature toggles
        'features': {
            'voice': True,
            'avatar': True,
            'emotions': True,
            'notifications': True,
            'hotkeys': True,
            'observers': True,
        },
        
        # Debug settings for development
        'debug': {
            'enabled': False,
            'verbosity': 0,  # 0=off, 1=basic, 2=detailed, 3=everything
            'save_all_audio': False,
            'save_failed_wake_words': True,
            'show_confidence_scores': True,
            'log_all_transcripts': False,
            'show_audio_levels': False,
            'profile_performance': False,
        },
        
        # Paths configuration
        'paths': {
            'data_dir': '~/.local/share/goose-perception',
            'recordings_dir': 'recordings',
            'debug_dir': 'debug_output',
            'logs_dir': 'logs',
            'state_dir': 'avatar_state',
        },
        
        # Experimental features for testing
        'experimental': {
            'test_mode': False,  # Use smaller models, shorter timeouts
            'fail_fast': True,   # Fail immediately on errors
            'mock_emotion_detection': False,  # Use fake emotion data
            'mock_audio_input': False,  # Use test audio files
            'bypass_wake_word': False,  # Skip wake word for testing
            'use_tiny_models': False,  # Force tiny Whisper models
            'short_timeouts': False,  # Use shorter timeouts everywhere
        },
        
        # Voice settings
        'voice': {
            'wake_word': 'goose',
            'context_seconds': 30,
            'silence_seconds': 3,
            'fuzzy_threshold': 80,
            'confidence_threshold': 0.6,
        },
        
        # Audio processing settings (exact values from original hardcoded constants)
        'audio': {
            'sample_rate': 16000,  # Whisper expects 16kHz audio
            'channels': 1,         # Mono audio  
            'buffer_duration': 2,  # Duration in seconds for each audio chunk
            'long_buffer_duration': 60,  # Duration for longer context (1 minute)
            'thresholds': {
                'silence': 0.008,           # Lower silence threshold
                'noise_floor': 0.003,       # Lower noise floor
                'speech_activity': 0.01,    # Very sensitive - catch very quiet speech
                'max_noise_ratio': 0.9,     # Almost no noise filtering
                'proximity': 0.02,          # Very low signal level for proximity detection
                'distant_speech': 0.005,    # Extremely low threshold for distant speech
            }
        },
        
        # Whisper model settings
        'whisper': {
            'main_model': 'small',
            'wake_word_model': 'base',
            'device': 'cpu',
            'compute_type': 'int8',
        },
        
        # Avatar settings
        'avatar': {
            'personality': 'comedian',
            'timings': {
                'message_spacing_ms': 2000,
                'idle_check_ms': 45000,
                'idle_suggestion_chance': 0.15,
                'min_suggestion_minutes': 3,
                'max_recent_suggestions': 8,
                'default_message_duration_ms': 20000,
                'actionable_message_duration_ms': 75000,
                'emergency_timeout_ms': 120000,
            }
        },
        
        # Emotion settings
        'emotions': {
            'interval': 60,
            'confidence_threshold': 0.5,
            'calibration_duration': 30,
        },
        
        # Observer settings
        'observers': {
            'intervals': {
                'suggestions_minutes': 10,
                'idle_chatter_minutes': 12,
                'suggestion_show_minutes': 15,
                'actionable_show_minutes': 8,
                'chatter_minutes': 12,
                'min_suggestion_minutes': 3,
                'min_actionable_minutes': 3,
                'min_chitchat_minutes': 3,
            },
            'limits': {
                'max_remembered_actionable': 6,
                'max_suggestions_queue': 5,
                'max_chatter_queue': 3,
            }
        },
        
        # Performance settings
        'performance': {
            'recipe_timeout_seconds': 300,
            'max_concurrent_recipes': 2,
            'avatar_refresh_rate_ms': 1000,
            'qt_event_processing_ms': 100,
            'audio_queue_size': 100,
        },
        
        # File storage limits
        'storage': {
            'spoken_transcript_kb': 5,
            'emotions_log_lines': 500,
        },
        
        # Message queue settings
        'message_queue': {
            'default_max_age_hours': 24,
            'default_message_limit': 5,
        }
    }
    
    def __init__(self, config_path: Optional[Path] = None):
        """Initialize the config manager"""
        self.perception_dir = Path("~/.local/share/goose-perception").expanduser()
        self.perception_dir.mkdir(parents=True, exist_ok=True)
        
        # Use user_prefs.yaml instead of config.yaml
        self.config_path = config_path or (self.perception_dir / "user_prefs.yaml")
        self.config = self.load_config()
        
    def load_config(self) -> Dict[str, Any]:
        """Load configuration from YAML file or use defaults"""
        if not self.config_path.exists():
            print(f"📋 No config file found at {self.config_path}")
            print(f"   Using default configuration")
            return self.DEFAULT_CONFIG.copy()
            
        try:
            with open(self.config_path, 'r') as f:
                user_config = yaml.safe_load(f) or {}
            
            # Merge with defaults to ensure all keys exist
            config = self.DEFAULT_CONFIG.copy()
            self._deep_merge(config, user_config)
            
            print(f"✅ Loaded config from: {self.config_path}")
            return config
            
        except Exception as e:
            print(f"⚠️ Error loading config: {e}")
            print("   Using default configuration")
            return self.DEFAULT_CONFIG.copy()
    
    def save_config(self, config: Optional[Dict[str, Any]] = None) -> bool:
        """Save configuration to YAML file"""
        try:
            config_to_save = config or self.config
            with open(self.config_path, 'w') as f:
                yaml.dump(config_to_save, f, default_flow_style=False, sort_keys=False)
            print(f"💾 Saved config to: {self.config_path}")
            return True
        except Exception as e:
            print(f"❌ Error saving config: {e}")
            return False
    
    def _deep_merge(self, base: Dict, override: Dict) -> None:
        """Deep merge override dict into base dict"""
        for key, value in override.items():
            if key in base and isinstance(base[key], dict) and isinstance(value, dict):
                self._deep_merge(base[key], value)
            else:
                base[key] = value
    
    # Feature checks
    def is_voice_enabled(self) -> bool:
        """Check if voice recognition is enabled"""
        return self.config.get('features', {}).get('voice', True)
    
    def is_avatar_enabled(self) -> bool:
        """Check if avatar display is enabled"""
        return self.config.get('features', {}).get('avatar', True)
    
    def is_emotion_enabled(self) -> bool:
        """Check if emotion detection is enabled"""
        return self.config.get('features', {}).get('emotions', True)
    
    def is_notifications_enabled(self) -> bool:
        """Check if notifications are enabled"""
        return self.config.get('features', {}).get('notifications', True)
    
    def is_hotkeys_enabled(self) -> bool:
        """Check if hotkeys are enabled"""
        return self.config.get('features', {}).get('hotkeys', True)
    
    # Core getters
    def get_voice_wake_word(self) -> str:
        """Get the wake word for voice activation"""
        return self.config.get('voice', {}).get('wake_word', 'goose')
    
    def get_voice_context_seconds(self) -> int:
        """Get seconds of context before wake word"""
        return self.config.get('voice', {}).get('context_seconds', 30)
    
    def get_voice_silence_seconds(self) -> int:
        """Get seconds of silence to end listening"""
        return self.config.get('voice', {}).get('silence_seconds', 3)
    
    def get_voice_fuzzy_threshold(self) -> int:
        """Get fuzzy matching threshold (0-100)"""
        return self.config.get('voice', {}).get('fuzzy_threshold', 80)
    
    def get_voice_confidence_threshold(self) -> float:
        """Get voice confidence threshold"""
        return self.config.get('voice', {}).get('confidence_threshold', 0.6)
    
    def get_avatar_personality(self) -> str:
        """Get the avatar personality"""
        return self.config.get('avatar', {}).get('personality', 'comedian')
    
    def get_interface_mode(self) -> str:
        """Get the interface mode (floating or menubar)"""
        # First check top-level interface_mode (where existing code stores it)
        interface_mode = self.config.get('interface_mode')
        if interface_mode:
            return interface_mode
        # Fall back to avatar section if present
        return self.config.get('avatar', {}).get('interface_mode', 'floating')
    
    def get_emotion_interval(self) -> int:
        """Get emotion detection interval in seconds"""
        return self.config.get('emotions', {}).get('interval', 60)
    
    # User preference getters (for existing fields)
    def get_team_channel(self) -> str:
        """Get the team Slack channel"""
        return self.config.get('team_channel', '')
    
    def get_announcement_channel(self) -> str:
        """Get the announcement Slack channel"""
        return self.config.get('announcement_channel', '')
    
    def is_email_updates_enabled(self) -> bool:
        """Check if email updates are enabled"""
        return self.config.get('send_email_updates', False)
    
    def get_email_recipients(self) -> str:
        """Get email recipients (comma-separated)"""
        return self.config.get('email_recipients', '')
    
    def get_notification_urgency(self) -> str:
        """Get notification urgency settings"""
        return self.config.get('notification_urgency', '')
    
    def is_reminders_enabled(self) -> bool:
        """Check if reminders are enabled"""
        return self.config.get('reminders_enabled', True)
    
    def get_preferred_update_time(self) -> str:
        """Get preferred update time"""
        return self.config.get('preferred_update_time', '')
    
    # Audio processing getters
    def get_audio_sample_rate(self) -> int:
        """Get audio sample rate"""
        return self.config.get('audio', {}).get('sample_rate', 16000)
    
    def get_audio_channels(self) -> int:
        """Get number of audio channels"""
        return self.config.get('audio', {}).get('channels', 1)
    
    def get_audio_buffer_duration(self) -> int:
        """Get audio buffer duration in seconds"""
        return self.config.get('audio', {}).get('buffer_duration', 2)
    
    def get_audio_long_buffer_duration(self) -> int:
        """Get long audio buffer duration in seconds"""
        return self.config.get('audio', {}).get('long_buffer_duration', 60)
    
    def get_audio_silence_threshold(self) -> float:
        """Get audio silence threshold"""
        return self.config.get('audio', {}).get('thresholds', {}).get('silence', 0.008)
    
    def get_audio_noise_floor_threshold(self) -> float:
        """Get audio noise floor threshold"""
        return self.config.get('audio', {}).get('thresholds', {}).get('noise_floor', 0.003)
    
    def get_audio_speech_activity_threshold(self) -> float:
        """Get audio speech activity threshold"""
        return self.config.get('audio', {}).get('thresholds', {}).get('speech_activity', 0.01)
    
    def get_audio_max_noise_ratio(self) -> float:
        """Get maximum noise ratio"""
        return self.config.get('audio', {}).get('thresholds', {}).get('max_noise_ratio', 0.9)
    
    def get_audio_proximity_threshold(self) -> float:
        """Get audio proximity threshold"""
        return self.config.get('audio', {}).get('thresholds', {}).get('proximity', 0.02)
    
    def get_audio_distant_speech_threshold(self) -> float:
        """Get distant speech threshold"""
        return self.config.get('audio', {}).get('thresholds', {}).get('distant_speech', 0.005)
    
    # Whisper model getters
    def get_whisper_main_model(self) -> str:
        """Get main Whisper model name"""
        return self.config.get('whisper', {}).get('main_model', 'small')
    
    def get_whisper_wake_word_model(self) -> str:
        """Get wake word Whisper model name"""
        return self.config.get('whisper', {}).get('wake_word_model', 'base')
    
    def get_whisper_device(self) -> str:
        """Get Whisper device (cpu/cuda)"""
        return self.config.get('whisper', {}).get('device', 'cpu')
    
    def get_whisper_compute_type(self) -> str:
        """Get Whisper compute type"""
        return self.config.get('whisper', {}).get('compute_type', 'int8')
    
    # Avatar timing getters
    def get_avatar_message_spacing_ms(self) -> int:
        """Get message spacing delay in milliseconds"""
        return self.config.get('avatar', {}).get('timings', {}).get('message_spacing_ms', 2000)
    
    def get_avatar_idle_check_ms(self) -> int:
        """Get idle check interval in milliseconds"""
        return self.config.get('avatar', {}).get('timings', {}).get('idle_check_ms', 45000)
    
    def get_avatar_idle_suggestion_chance(self) -> float:
        """Get idle suggestion chance (0-1)"""
        return self.config.get('avatar', {}).get('timings', {}).get('idle_suggestion_chance', 0.15)
    
    def get_avatar_min_suggestion_minutes(self) -> int:
        """Get minimum minutes between suggestions"""
        return self.config.get('avatar', {}).get('timings', {}).get('min_suggestion_minutes', 3)
    
    def get_avatar_min_suggestion_seconds(self) -> int:
        """Get minimum seconds between suggestions (for avatar_display.py compatibility)"""
        return self.get_avatar_min_suggestion_minutes() * 60
    
    def get_avatar_max_recent_suggestions(self) -> int:
        """Get maximum number of recent suggestions to remember"""
        return self.config.get('avatar', {}).get('timings', {}).get('max_recent_suggestions', 8)
    
    def get_avatar_default_message_duration_ms(self) -> int:
        """Get default message duration in milliseconds"""
        return self.config.get('avatar', {}).get('timings', {}).get('default_message_duration_ms', 20000)
    
    def get_avatar_actionable_message_duration_ms(self) -> int:
        """Get actionable message duration in milliseconds"""
        return self.config.get('avatar', {}).get('timings', {}).get('actionable_message_duration_ms', 75000)
    
    def get_avatar_emergency_timeout_ms(self) -> int:
        """Get emergency timeout in milliseconds"""
        return self.config.get('avatar', {}).get('timings', {}).get('emergency_timeout_ms', 120000)
    
    # Observer getters
    def is_observers_enabled(self) -> bool:
        """Check if observers are enabled"""
        return self.config.get('features', {}).get('observers', True)
    
    def get_observer_suggestions_interval_minutes(self) -> int:
        """Get observer suggestions interval in minutes"""
        return self.config.get('observers', {}).get('intervals', {}).get('suggestions_minutes', 10)
    
    def get_observer_idle_chatter_interval_minutes(self) -> int:
        """Get observer idle chatter interval in minutes"""
        return self.config.get('observers', {}).get('intervals', {}).get('idle_chatter_minutes', 12)
    
    def get_observer_suggestion_show_interval_minutes(self) -> int:
        """Get observer suggestion show interval in minutes"""
        return self.config.get('observers', {}).get('intervals', {}).get('suggestion_show_minutes', 15)
    
    def get_observer_actionable_show_interval_minutes(self) -> int:
        """Get observer actionable show interval in minutes"""
        return self.config.get('observers', {}).get('intervals', {}).get('actionable_show_minutes', 8)
    
    def get_observer_chatter_interval_minutes(self) -> int:
        """Get observer chatter interval in minutes"""
        return self.config.get('observers', {}).get('intervals', {}).get('chatter_minutes', 12)
    
    def get_observer_min_suggestion_interval_minutes(self) -> int:
        """Get minimum suggestion interval in minutes"""
        return self.config.get('observers', {}).get('intervals', {}).get('min_suggestion_minutes', 3)
    
    def get_observer_min_actionable_interval_minutes(self) -> int:
        """Get minimum actionable interval in minutes"""
        return self.config.get('observers', {}).get('intervals', {}).get('min_actionable_minutes', 3)
    
    def get_observer_min_chitchat_interval_minutes(self) -> int:
        """Get minimum chitchat interval in minutes"""
        return self.config.get('observers', {}).get('intervals', {}).get('min_chitchat_minutes', 3)
    
    def get_observer_max_remembered_actionable(self) -> int:
        """Get maximum remembered actionable items"""
        return self.config.get('observers', {}).get('limits', {}).get('max_remembered_actionable', 6)
    
    # Storage getters
    def get_storage_spoken_transcript_kb(self) -> int:
        """Get spoken transcript max size in KB"""
        return self.config.get('storage', {}).get('spoken_transcript_kb', 5)
    
    def get_storage_emotions_log_lines(self) -> int:
        """Get maximum lines in emotions log"""
        return self.config.get('storage', {}).get('emotions_log_lines', 500)
    
    # Message queue getters
    def get_message_queue_max_age_hours(self) -> float:
        """Get message queue max age in hours"""
        return self.config.get('message_queue', {}).get('default_max_age_hours', 24)
    
    def get_message_queue_limit(self) -> int:
        """Get message queue limit"""
        return self.config.get('message_queue', {}).get('default_message_limit', 5)
    
    # Emotion advanced getters
    def get_emotion_confidence_threshold(self) -> float:
        """Get emotion detection confidence threshold"""
        return self.config.get('emotions', {}).get('confidence_threshold', 0.5)
    
    def get_emotion_calibration_duration(self) -> int:
        """Get emotion calibration duration in seconds"""
        return self.config.get('emotions', {}).get('calibration_duration', 30)
    
    # Debug getters
    def is_debug_mode(self) -> bool:
        """Check if debug mode is enabled"""
        return self.config.get('debug', {}).get('enabled', False)
    
    def get_debug_verbosity(self) -> int:
        """Get debug verbosity level (0-3)"""
        return self.config.get('debug', {}).get('verbosity', 0)
    
    def should_save_all_audio(self) -> bool:
        """Check if all audio should be saved for debugging"""
        return self.config.get('debug', {}).get('save_all_audio', False)
    
    def should_save_failed_wake_words(self) -> bool:
        """Check if failed wake word audio should be saved"""
        return self.config.get('debug', {}).get('save_failed_wake_words', True)
    
    def should_show_confidence_scores(self) -> bool:
        """Check if ML confidence scores should be shown"""
        return self.config.get('debug', {}).get('show_confidence_scores', True)
    
    def should_log_all_transcripts(self) -> bool:
        """Check if all transcripts should be logged"""
        return self.config.get('debug', {}).get('log_all_transcripts', False)
    
    def should_show_audio_levels(self) -> bool:
        """Check if real-time audio levels should be shown"""
        return self.config.get('debug', {}).get('show_audio_levels', False)
    
    def should_profile_performance(self) -> bool:
        """Check if performance profiling is enabled"""
        return self.config.get('debug', {}).get('profile_performance', False)
    
    # Path getters
    def get_data_dir(self) -> Path:
        """Get data directory path"""
        path_str = self.config.get('paths', {}).get('data_dir', '~/.local/share/goose-perception')
        return Path(path_str).expanduser()
    
    def get_recordings_dir(self) -> Path:
        """Get recordings directory path"""
        path_str = self.config.get('paths', {}).get('recordings_dir', 'recordings')
        # If relative path, make it relative to data_dir
        if not Path(path_str).is_absolute():
            return self.get_data_dir() / path_str
        return Path(path_str).expanduser()
    
    def get_debug_dir(self) -> Path:
        """Get debug output directory path"""
        path_str = self.config.get('paths', {}).get('debug_dir', 'debug_output')
        # If relative path, make it relative to data_dir
        if not Path(path_str).is_absolute():
            return self.get_data_dir() / path_str
        return Path(path_str).expanduser()
    
    def get_logs_dir(self) -> Path:
        """Get logs directory path"""
        path_str = self.config.get('paths', {}).get('logs_dir', 'logs')
        # If relative path, make it relative to data_dir
        if not Path(path_str).is_absolute():
            return self.get_data_dir() / path_str
        return Path(path_str).expanduser()
    
    def get_state_dir(self) -> Path:
        """Get state directory path"""
        path_str = self.config.get('paths', {}).get('state_dir', 'avatar_state')
        # If relative path, make it relative to data_dir
        if not Path(path_str).is_absolute():
            return self.get_data_dir() / path_str
        return Path(path_str).expanduser()
    
    # Experimental getters
    def is_test_mode(self) -> bool:
        """Check if running in test mode"""
        return self.config.get('experimental', {}).get('test_mode', False)
    
    def should_fail_fast(self) -> bool:
        """Check if fail-fast mode is enabled"""
        return self.config.get('experimental', {}).get('fail_fast', True)
    
    def should_mock_emotion_detection(self) -> bool:
        """Check if emotion detection should be mocked"""
        return self.config.get('experimental', {}).get('mock_emotion_detection', False)
    
    def should_mock_audio_input(self) -> bool:
        """Check if audio input should be mocked"""
        return self.config.get('experimental', {}).get('mock_audio_input', False)
    
    def should_bypass_wake_word(self) -> bool:
        """Check if wake word should be bypassed for testing"""
        return self.config.get('experimental', {}).get('bypass_wake_word', False)
    
    def should_use_tiny_models(self) -> bool:
        """Check if tiny Whisper models should be forced"""
        return self.config.get('experimental', {}).get('use_tiny_models', False)
    
    def should_use_short_timeouts(self) -> bool:
        """Check if short timeouts should be used"""
        return self.config.get('experimental', {}).get('short_timeouts', False)
    
    # Performance getters
    def get_recipe_timeout_seconds(self) -> int:
        """Get recipe execution timeout in seconds"""
        if self.should_use_short_timeouts():
            return 30  # Short timeout for testing
        return self.config.get('performance', {}).get('recipe_timeout_seconds', 300)
    
    def get_max_concurrent_recipes(self) -> int:
        """Get maximum concurrent recipes"""
        if self.is_test_mode():
            return 1  # Single recipe for easier debugging
        return self.config.get('performance', {}).get('max_concurrent_recipes', 2)
    
    def get_avatar_refresh_rate_ms(self) -> int:
        """Get avatar refresh rate in milliseconds"""
        return self.config.get('performance', {}).get('avatar_refresh_rate_ms', 1000)
    
    def get_qt_event_processing_ms(self) -> int:
        """Get Qt event processing interval in milliseconds"""
        return self.config.get('performance', {}).get('qt_event_processing_ms', 100)
    
    def get_audio_queue_size(self) -> int:
        """Get maximum audio queue size"""
        if self.is_test_mode():
            return 10  # Smaller queue for testing
        return self.config.get('performance', {}).get('audio_queue_size', 100)
    
    # Observer limit getters
    def get_observer_max_suggestions_queue(self) -> int:
        """Get maximum suggestions in queue"""
        return self.config.get('observers', {}).get('limits', {}).get('max_suggestions_queue', 5)
    
    def get_observer_max_chatter_queue(self) -> int:
        """Get maximum chatter messages in queue"""
        return self.config.get('observers', {}).get('limits', {}).get('max_chatter_queue', 3)
    
    # Override Whisper models for testing
    def get_whisper_main_model(self) -> str:
        """Get main Whisper model name"""
        if self.should_use_tiny_models():
            return 'tiny'  # Force tiny for testing
        return self.config.get('whisper', {}).get('main_model', 'small')
    
    def get_whisper_wake_word_model(self) -> str:
        """Get wake word Whisper model name"""
        if self.should_use_tiny_models():
            return 'tiny'  # Force tiny for testing
        return self.config.get('whisper', {}).get('wake_word_model', 'base')
    
    # Feature setters
    def set_voice_enabled(self, enabled: bool) -> bool:
        """Enable or disable voice recognition"""
        if 'features' not in self.config:
            self.config['features'] = {}
        self.config['features']['voice'] = enabled
        return self.save_config()
    
    def set_avatar_enabled(self, enabled: bool) -> bool:
        """Enable or disable avatar display"""
        if 'features' not in self.config:
            self.config['features'] = {}
        self.config['features']['avatar'] = enabled
        return self.save_config()
    
    def set_emotion_enabled(self, enabled: bool) -> bool:
        """Enable or disable emotion detection"""
        if 'features' not in self.config:
            self.config['features'] = {}
        self.config['features']['emotions'] = enabled
        return self.save_config()
    
    def set_notifications_enabled(self, enabled: bool) -> bool:
        """Enable or disable notifications"""
        if 'features' not in self.config:
            self.config['features'] = {}
        self.config['features']['notifications'] = enabled
        return self.save_config()
    
    def set_hotkeys_enabled(self, enabled: bool) -> bool:
        """Enable or disable hotkeys"""
        if 'features' not in self.config:
            self.config['features'] = {}
        self.config['features']['hotkeys'] = enabled
        return self.save_config()
    
    def reload(self) -> None:
        """Reload configuration from file"""
        self.config = self.load_config()
        print("🔄 Configuration reloaded")
    
    def get_status(self) -> str:
        """Get a formatted status of current configuration"""
        status = "📋 Current Configuration:\n"
        status += "=" * 40 + "\n"
        
        # Features
        status += "Features:\n"
        for feature, enabled in self.config.get('features', {}).items():
            emoji = "✅" if enabled else "❌"
            status += f"  {emoji} {feature.capitalize()}: {'Enabled' if enabled else 'Disabled'}\n"
        
        # Core settings
        status += "\nCore Settings:\n"
        status += f"  • Wake word: {self.get_voice_wake_word()}\n"
        status += f"  • Avatar personality: {self.get_avatar_personality()}\n"
        status += f"  • Interface mode: {self.get_interface_mode()}\n"
        status += f"  • Emotion interval: {self.get_emotion_interval()}s\n"
        
        return status


# Global instance
_config_manager = None

def get_config_manager() -> ConfigManager:
    """Get the global ConfigManager instance"""
    global _config_manager
    if _config_manager is None:
        _config_manager = ConfigManager()
    return _config_manager


if __name__ == "__main__":
    # Test the config manager
    config = get_config_manager()
    print(config.get_status())
    
    # Test feature checks
    print(f"\nVoice enabled: {config.is_voice_enabled()}")
    print(f"Avatar enabled: {config.is_avatar_enabled()}")
    print(f"Emotions enabled: {config.is_emotion_enabled()}")
