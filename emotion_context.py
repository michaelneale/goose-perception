#!/usr/bin/env python3
"""
emotion_context.py - Emotion Context Manager for goose-perception
Analyzes emotion patterns from emotions.log to provide context for adaptive system behavior
"""

import csv
import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional
from collections import Counter

class EmotionContext:
    """Manages emotion context analysis and provides emotional state information"""
    
    def __init__(self, data_dir: Optional[Path] = None):
        self.data_dir = data_dir or Path.home() / ".local" / "share" / "goose-perception"
        self.emotions_log_path = self.data_dir / "emotions.log"
        
        # Emotion categorization for analysis
        self.positive_emotions = {"happy", "content", "surprised"}
        self.negative_emotions = {"sad", "tired", "serious", "angry"}
        self.stress_indicators = {"serious", "tired", "angry"}
        
        # Energy level mapping
        self.high_energy_emotions = {"happy", "surprised"}
        self.low_energy_emotions = {"sad", "tired", "serious", "angry"}
    
    def _parse_emotions_log(self, hours_back: int = 24) -> List[Dict]:
        """Parse emotions.log and return recent entries within specified hours"""
        if not self.emotions_log_path.exists():
            return []
        
        cutoff_time = datetime.now() - timedelta(hours=hours_back)
        emotions = []
        
        try:
            with open(self.emotions_log_path, 'r') as f:
                reader = csv.reader(f)
                for row in reader:
                    if len(row) >= 3:
                        timestamp_str, emotion, face_id = row[0], row[1], row[2]
                        try:
                            timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                            if timestamp.tzinfo:
                                timestamp = timestamp.replace(tzinfo=None)
                            
                            if timestamp >= cutoff_time:
                                emotions.append({
                                    'timestamp': timestamp,
                                    'emotion': emotion,
                                    'face_id': face_id
                                })
                        except ValueError:
                            continue
        except Exception as e:
            print(f"Warning: Could not parse emotions.log: {e}")
            return []
        
        return sorted(emotions, key=lambda x: x['timestamp'])
    
    def get_current_emotion_context(self) -> Dict:
        """Get comprehensive emotion context for the current moment"""
        recent_emotions = self._parse_emotions_log(hours_back=8)
        
        if not recent_emotions:
            return self._get_default_context()
        
        context = {
            'timestamp': datetime.now().isoformat(),
            'recent_emotion': self._get_recent_emotion(recent_emotions),
            'dominant_emotion': self._get_dominant_emotion(recent_emotions),
            'emotional_trend': self._analyze_emotional_trend(recent_emotions),
            'energy_level': self._assess_energy_level(recent_emotions),
            'stress_level': self._assess_stress_level(recent_emotions),
            'personality_modifiers': self._generate_personality_modifiers(recent_emotions)
        }
        
        return context
    
    def _get_default_context(self) -> Dict:
        """Return default context when no emotion data is available"""
        return {
            'timestamp': datetime.now().isoformat(),
            'recent_emotion': 'neutral',
            'dominant_emotion': 'neutral',
            'emotional_trend': 'stable',
            'energy_level': 'medium',
            'stress_level': 'low',
            'personality_modifiers': {
                'energy_boost': 0.0,
                'supportiveness_boost': 0.0,
                'humor_adjustment': 0.0,
                'focus_intensity': 0.0
            }
        }
    
    def _get_recent_emotion(self, emotions: List[Dict], minutes: int = 5) -> str:
        """Get the most recent emotion within specified minutes"""
        cutoff = datetime.now() - timedelta(minutes=minutes)
        recent = [e for e in emotions if e['timestamp'] >= cutoff and e['emotion'] != 'no_face_detected']
        
        return recent[-1]['emotion'] if recent else 'neutral'
    
    def _get_dominant_emotion(self, emotions: List[Dict], minutes: int = 30) -> str:
        """Get the dominant emotion over the specified time period"""
        cutoff = datetime.now() - timedelta(minutes=minutes)
        recent = [e['emotion'] for e in emotions 
                 if e['timestamp'] >= cutoff and e['emotion'] != 'no_face_detected']
        
        if not recent:
            return 'neutral'
        
        emotion_counts = Counter(recent)
        return emotion_counts.most_common(1)[0][0]
    
    def _analyze_emotional_trend(self, emotions: List[Dict]) -> str:
        """Analyze if emotions are trending positive, negative, or stable"""
        if len(emotions) < 3:
            return 'stable'
        
        # Compare recent hour vs previous hour
        now = datetime.now()
        recent_hour = [e for e in emotions 
                      if now - timedelta(hours=1) <= e['timestamp'] <= now
                      and e['emotion'] != 'no_face_detected']
        previous_hour = [e for e in emotions 
                        if now - timedelta(hours=2) <= e['timestamp'] <= now - timedelta(hours=1)
                        and e['emotion'] != 'no_face_detected']
        
        if not recent_hour or not previous_hour:
            return 'stable'
        
        recent_positive = sum(1 for e in recent_hour if e['emotion'] in self.positive_emotions)
        previous_positive = sum(1 for e in previous_hour if e['emotion'] in self.positive_emotions)
        
        recent_ratio = recent_positive / len(recent_hour)
        previous_ratio = previous_positive / len(previous_hour)
        
        if recent_ratio > previous_ratio + 0.2:
            return 'improving'
        elif recent_ratio < previous_ratio - 0.2:
            return 'declining'
        else:
            return 'stable'
    
    def _assess_energy_level(self, emotions: List[Dict]) -> str:
        """Assess current energy level based on recent emotions"""
        cutoff = datetime.now() - timedelta(minutes=30)
        recent = [e['emotion'] for e in emotions 
                 if e['timestamp'] >= cutoff and e['emotion'] != 'no_face_detected']
        
        if not recent:
            return 'medium'
        
        high_energy_count = sum(1 for e in recent if e in self.high_energy_emotions)
        low_energy_count = sum(1 for e in recent if e in self.low_energy_emotions)
        
        high_ratio = high_energy_count / len(recent)
        low_ratio = low_energy_count / len(recent)
        
        if high_ratio > 0.6:
            return 'high'
        elif low_ratio > 0.6:
            return 'low'
        else:
            return 'medium'
    
    def _assess_stress_level(self, emotions: List[Dict]) -> str:
        """Assess stress level based on emotion patterns"""
        cutoff = datetime.now() - timedelta(hours=1)
        recent = [e for e in emotions 
                 if e['timestamp'] >= cutoff and e['emotion'] != 'no_face_detected']
        
        if not recent:
            return 'low'
        
        stress_count = sum(1 for e in recent if e['emotion'] in self.stress_indicators)
        stress_ratio = stress_count / len(recent)
        
        if stress_ratio > 0.7:
            return 'high'
        elif stress_ratio > 0.4:
            return 'medium'
        else:
            return 'low'
    
    def _generate_personality_modifiers(self, emotions: List[Dict]) -> Dict[str, float]:
        """Generate personality adjustment modifiers based on emotional context"""
        recent_emotion = self._get_recent_emotion(emotions)
        energy_level = self._assess_energy_level(emotions)
        stress_level = self._assess_stress_level(emotions)
        
        modifiers = {
            'energy_boost': 0.0,        # -1.0 to 1.0
            'supportiveness_boost': 0.0, # -1.0 to 1.0  
            'humor_adjustment': 0.0,     # -1.0 to 1.0
            'focus_intensity': 0.0       # -1.0 to 1.0
        }
        
        # Energy adjustments
        if energy_level == 'high':
            modifiers['energy_boost'] = 0.8
            modifiers['humor_adjustment'] = 0.6
        elif energy_level == 'low':
            modifiers['energy_boost'] = -0.6
            modifiers['supportiveness_boost'] = 0.7
        
        # Stress adjustments
        if stress_level == 'high':
            modifiers['supportiveness_boost'] = 0.9
            modifiers['humor_adjustment'] = -0.4
            modifiers['focus_intensity'] = 0.8
        elif stress_level == 'low':
            modifiers['humor_adjustment'] = 0.3
        
        # Emotion-specific adjustments
        if recent_emotion in ['happy', 'content']:
            modifiers['energy_boost'] += 0.4
            modifiers['humor_adjustment'] += 0.5
        elif recent_emotion in ['sad', 'tired']:
            modifiers['supportiveness_boost'] += 0.8
            modifiers['energy_boost'] -= 0.3
        elif recent_emotion in ['serious', 'angry']:
            modifiers['focus_intensity'] += 0.6
            modifiers['humor_adjustment'] -= 0.5
        
        # Clamp values to [-1.0, 1.0]
        for key in modifiers:
            modifiers[key] = max(-1.0, min(1.0, modifiers[key]))
        
        return modifiers
    
    def get_receptivity_score(self) -> float:
        """Get user's current receptivity to interactions (0.0 to 1.0)"""
        context = self.get_current_emotion_context()
        
        base_score = 0.5
        
        # Adjust based on recent emotion
        emotion = context['recent_emotion']
        if emotion in ['happy', 'content']:
            base_score += 0.3
        elif emotion in ['sad', 'tired']:
            base_score -= 0.2
        elif emotion in ['angry', 'serious']:
            base_score -= 0.4
        elif emotion == 'no_face_detected':
            base_score -= 0.5
        
        # Adjust based on stress level
        stress = context['stress_level']
        if stress == 'high':
            base_score -= 0.3
        elif stress == 'low':
            base_score += 0.2
        
        return max(0.0, min(1.0, base_score))


# Global instance for easy access
_emotion_context = None

def get_emotion_context() -> EmotionContext:
    """Get the global emotion context instance"""
    global _emotion_context
    if _emotion_context is None:
        _emotion_context = EmotionContext()
    return _emotion_context


if __name__ == "__main__":
    # Test the emotion context system
    print("🎭 Testing Emotion Context System...")
    
    context_manager = EmotionContext()
    
    # Get current context
    context = context_manager.get_current_emotion_context()
    print(f"\n📊 Current Emotion Context:")
    print(json.dumps(context, indent=2))
    
    # Get receptivity score
    receptivity = context_manager.get_receptivity_score()
    print(f"\n📈 Receptivity Score: {receptivity:.2f}") 