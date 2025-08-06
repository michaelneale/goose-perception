#!/usr/bin/env python3
"""
Minimal configuration manager for Goose Perception
Handles loading and managing core feature toggles from a YAML config file
"""

import yaml
from pathlib import Path
from typing import Dict, Any, Optional

class ConfigManager:
    """Manages configuration for Goose Perception features"""
    
    DEFAULT_CONFIG = {
        'features': {
            'voice': True,
            'avatar': True,
            'emotions': True,
            'notifications': True,
            'hotkeys': True,
        },
        'voice': {
            'wake_word': 'goose',
            'context_seconds': 30,
            'silence_seconds': 3,
            'fuzzy_threshold': 80,
            'confidence_threshold': 0.6,
        },
        'avatar': {
            'personality': 'comedian',
            'interface_mode': 'floating',
        },
        'emotions': {
            'interval': 60,
        }
    }
    
    def __init__(self, config_path: Optional[Path] = None):
        """Initialize the config manager"""
        self.perception_dir = Path("~/.local/share/goose-perception").expanduser()
        self.perception_dir.mkdir(parents=True, exist_ok=True)
        
        self.config_path = config_path or (self.perception_dir / "config.yaml")
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
        return self.config.get('avatar', {}).get('interface_mode', 'floating')
    
    def get_emotion_interval(self) -> int:
        """Get emotion detection interval in seconds"""
        return self.config.get('emotions', {}).get('interval', 60)
    
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
