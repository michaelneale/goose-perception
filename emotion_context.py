#!/usr/bin/env python3
"""
emotion_context.py - Emotion Context Manager for goose-perception
Analyzes emotion patterns from emotions.log to provide context for adaptive system behavior
"""

import csv
import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any
from collections import Counter

class EmotionContext:
    """Manages emotion context analysis and provides emotional state information"""
    
    def __init__(self, emotions_file: Optional[str] = None, data_dir: Optional[Path] = None):
        if emotions_file:
            self.emotions_log_path = Path(emotions_file)
        else:
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
    
    def get_stress_analysis(self) -> Dict[str, Any]:
        """
        Analyze stress patterns and determine intervention needs.
        Returns stress level, patterns, and intervention recommendations.
        """
        emotions = self._parse_emotions_log(hours_back=4)
        if not emotions:
            return {
                'stress_score': 0.0,
                'stress_level': 'low',
                'patterns': {},
                'intervention_needed': False,
                'intervention_type': 'none',
                'duration_minutes': 0,
                'time_since_last_positive': None
            }
        
        now = datetime.now()
        stress_indicators = 0
        rapid_changes = 0
        prolonged_negative = 0
        face_away_periods = 0
        
        # Analyze patterns in last 2 hours
        recent_emotions = [e for e in emotions if (now - e['timestamp']).total_seconds() < 7200]
        
        if not recent_emotions:
            return {
                'stress_score': 0.0,
                'stress_level': 'low', 
                'patterns': {},
                'intervention_needed': False,
                'intervention_type': 'none',
                'duration_minutes': 0,
                'time_since_last_positive': None
            }
        
        # Check for stress indicators
        for emotion in recent_emotions:
            if emotion['emotion'] in ['tired', 'serious', 'angry', 'sad']:
                stress_indicators += 1
            elif emotion['emotion'] == 'no_face_detected':
                face_away_periods += 1
        
        # Check for rapid emotion changes (volatility)  
        prev_emotion = None
        for emotion in recent_emotions:
            if prev_emotion and emotion['emotion'] != prev_emotion and emotion['emotion'] != 'no_face_detected':
                rapid_changes += 1
            prev_emotion = emotion['emotion']
        
        # Check for prolonged negative states (>30 minutes)
        negative_streak = 0
        for emotion in reversed(recent_emotions[-6:]):  # Last 30 minutes
            if emotion['emotion'] in ['tired', 'serious', 'angry', 'sad']:
                negative_streak += 1
            else:
                break
        prolonged_negative = negative_streak
        
        # Find time since last positive emotion
        time_since_positive = None
        for emotion in reversed(recent_emotions):
            if emotion['emotion'] in self.positive_emotions:
                time_since_positive = (now - emotion['timestamp']).total_seconds() / 60
                break
        
        # Calculate stress score (0.0 to 1.0)
        total_recent = len(recent_emotions)
        if total_recent > 0:
            stress_ratio = stress_indicators / total_recent
            volatility_ratio = rapid_changes / max(1, total_recent - 1)
            prolonged_ratio = prolonged_negative / min(6, total_recent)
            avoidance_ratio = face_away_periods / total_recent
            
            stress_score = min(1.0, 
                             (stress_ratio * 0.4) + 
                             (volatility_ratio * 0.2) + 
                             (prolonged_ratio * 0.3) +
                             (avoidance_ratio * 0.1))
        else:
            stress_score = 0.0
        
        # Determine stress level and intervention
        if stress_score >= 0.6:
            stress_level = 'high'
            intervention_type = 'assertive'
            intervention_needed = True
        elif stress_score >= 0.35:
            stress_level = 'medium'
            intervention_type = 'specific'
            intervention_needed = True
        elif stress_score >= 0.15:
            stress_level = 'light'
            intervention_type = 'gentle'
            intervention_needed = True
        else:
            stress_level = 'low'
            intervention_type = 'none'
            intervention_needed = False
        
        # Calculate duration of current state
        duration_minutes = len(recent_emotions) * 5  # 5 minute intervals
        
        return {
            'stress_score': stress_score,
            'stress_level': stress_level,
            'patterns': {
                'stress_indicators': stress_indicators,
                'rapid_changes': rapid_changes,
                'prolonged_negative': prolonged_negative,
                'face_away_periods': face_away_periods,
                'total_readings': total_recent
            },
            'intervention_needed': intervention_needed,
            'intervention_type': intervention_type,
            'duration_minutes': duration_minutes,
            'time_since_last_positive': time_since_positive
        }
    
    def get_break_suggestions(self) -> List[Dict[str, str]]:
        """
        Generate appropriate break suggestions based on stress analysis.
        """
        stress_analysis = self.get_stress_analysis()
        intervention_type = stress_analysis['intervention_type']
        duration = stress_analysis['duration_minutes']
        time_since_positive = stress_analysis['time_since_last_positive']
        
        suggestions = []
        
        if intervention_type == 'gentle':
            suggestions = [
                {
                    'type': 'micro_break',
                    'title': 'Quick 2-Minute Stretch',
                    'description': 'Consider a gentle stretch to reset your posture',
                    'duration': '2 minutes',
                    'category': 'movement',
                    'urgency': 'low'
                },
                {
                    'type': 'breathing',
                    'title': 'Deep Breathing',
                    'description': 'Take a few deep breaths to center yourself',
                    'duration': '1 minute',
                    'category': 'mindfulness',
                    'urgency': 'low'
                },
                {
                    'type': 'posture_check',
                    'title': 'Posture Reset',
                    'description': 'Sit up straight, adjust your screen height, roll your shoulders',
                    'duration': '30 seconds',
                    'category': 'ergonomics',
                    'urgency': 'low'
                }
            ]
        
        elif intervention_type == 'specific':
            suggestions = [
                {
                    'type': 'walk_break',
                    'title': 'Walking Break',
                    'description': 'A short walk might help clear your head and reduce tension',
                    'duration': '5-10 minutes',
                    'category': 'movement',
                    'urgency': 'medium'
                },
                {
                    'type': 'hydration',
                    'title': 'Hydration & Stretch',
                    'description': 'Get some water and do a few stretches away from your screen',
                    'duration': '3-5 minutes',
                    'category': 'wellness',
                    'urgency': 'medium'
                },
                {
                    'type': 'music_break',
                    'title': 'Music Reset',
                    'description': 'Listen to a favorite song to shift your mental state',
                    'duration': '3-4 minutes',
                    'category': 'mental_reset',
                    'urgency': 'medium'
                },
                {
                    'type': 'eye_rest',
                    'title': '20-20-20 Rule',
                    'description': 'Look at something 20 feet away for 20 seconds every 20 minutes',
                    'duration': '20 seconds',
                    'category': 'vision',
                    'urgency': 'medium'
                }
            ]
        
        elif intervention_type == 'assertive':
            break_duration = "15-20 minutes"
            if duration > 120:  # More than 2 hours
                break_duration = "20-30 minutes"
            
            suggestions = [
                {
                    'type': 'full_break',
                    'title': 'Proper Break Time',
                    'description': f'You\'ve been working intensely for {duration//60:.1f} hours - time for a real break',
                    'duration': break_duration,
                    'category': 'recovery',
                    'urgency': 'high'
                },
                {
                    'type': 'nature_break',
                    'title': 'Step Outside',
                    'description': 'Fresh air and natural light can significantly reduce stress',
                    'duration': '10-15 minutes',
                    'category': 'environment',
                    'urgency': 'high'
                },
                {
                    'type': 'social_connection',
                    'title': 'Connect with Someone',
                    'description': 'Reach out to a friend or colleague for a brief chat',
                    'duration': '5-10 minutes',
                    'category': 'social',
                    'urgency': 'high'
                },
                {
                    'type': 'meditation',
                    'title': 'Mindfulness Practice',
                    'description': 'Try a brief meditation or mindfulness exercise',
                    'duration': '5-10 minutes',
                    'category': 'mindfulness',
                    'urgency': 'high'
                }
            ]
            
            # Add specific suggestion if it's been too long since positive emotion
            if time_since_positive and time_since_positive > 120:  # 2+ hours
                suggestions.insert(0, {
                    'type': 'mood_reset',
                    'title': 'Complete Change of Pace',
                    'description': f'It\'s been {time_since_positive//60:.0f}+ hours since you felt positive - consider stepping away entirely',
                    'duration': '20-30 minutes',
                    'category': 'mental_health',
                    'urgency': 'critical'
                })
        
        return suggestions
    
    def should_suggest_break_now(self) -> bool:
        """
        Determine if now is a good time to suggest a break based on timing intelligence.
        Considers work flow and receptivity.
        """
        receptivity = self.get_receptivity_score()
        stress_analysis = self.get_stress_analysis()
        
        # Don't interrupt if user is not receptive, unless stress is critical
        if receptivity < 0.3 and stress_analysis['stress_score'] < 0.7:
            return False
        
        # Always suggest breaks for critical stress levels
        if stress_analysis['stress_score'] >= 0.7:
            return True
        
        # Suggest breaks during medium receptivity if intervention is needed
        if receptivity >= 0.4 and stress_analysis['intervention_needed']:
            return True
        
        # High receptivity with any stress indication
        if receptivity >= 0.6 and stress_analysis['stress_score'] >= 0.15:
            return True
        
        return False
    
    def get_interaction_timing_analysis(self) -> Dict[str, Any]:
        """
        Advanced timing analysis for all types of interactions.
        Returns detailed timing intelligence and recommendations.
        """
        emotions = self._parse_emotions_log(hours_back=2)
        context = self.get_current_emotion_context()
        stress_analysis = self.get_stress_analysis()
        receptivity = self.get_receptivity_score()
        
        now = datetime.now()
        
        # Analyze emotional stability
        recent_emotions = [e for e in emotions if (now - e['timestamp']).total_seconds() < 1800]  # 30 minutes
        
        emotional_stability = 'stable'
        if len(recent_emotions) >= 4:
            unique_emotions = len(set(e['emotion'] for e in recent_emotions if e['emotion'] != 'no_face_detected'))
            if unique_emotions >= 4:
                emotional_stability = 'volatile'
            elif unique_emotions >= 3:
                emotional_stability = 'unstable'
        
        # Determine interaction receptivity levels
        interaction_receptivity = {
            'suggestions': self._calculate_suggestion_receptivity(context, stress_analysis, receptivity),
            'chatter': self._calculate_chatter_receptivity(context, receptivity, emotional_stability),
            'wellness': self._calculate_wellness_receptivity(stress_analysis, receptivity),
            'notifications': self._calculate_notification_receptivity(context, receptivity, emotional_stability)
        }
        
        # Calculate optimal timing delays
        timing_delays = self._calculate_timing_delays(context, stress_analysis, emotional_stability)
        
        # Determine priority levels for different message types
        message_priorities = self._calculate_message_priorities(context, stress_analysis)
        
        return {
            'timestamp': now.isoformat(),
            'emotional_stability': emotional_stability,
            'overall_receptivity': receptivity,
            'interaction_receptivity': interaction_receptivity,
            'timing_delays': timing_delays,
            'message_priorities': message_priorities,
            'recommendations': {
                'should_queue_suggestions': interaction_receptivity['suggestions'] < 0.4,
                'should_reduce_chatter': interaction_receptivity['chatter'] < 0.3,
                'priority_wellness': stress_analysis['intervention_needed'],
                'pause_non_urgent': receptivity < 0.3 and not stress_analysis['intervention_needed']
            }
        }
    
    def _calculate_suggestion_receptivity(self, context: Dict, stress_analysis: Dict, base_receptivity: float) -> float:
        """Calculate receptivity specifically for work/productivity suggestions"""
        receptivity = base_receptivity
        
        # Reduce receptivity during high stress (focus on wellness instead)
        if stress_analysis['stress_level'] == 'high':
            receptivity *= 0.3
        elif stress_analysis['stress_level'] == 'medium':
            receptivity *= 0.6
        
        # Increase receptivity during productive emotional states
        if context['recent_emotion'] in ['content', 'happy']:
            receptivity *= 1.2
        elif context['recent_emotion'] in ['serious']:
            receptivity *= 1.1  # Focused state, good for suggestions
        
        # Reduce during very tired or sad states
        if context['recent_emotion'] in ['tired', 'sad']:
            receptivity *= 0.4
        
        return max(0.0, min(1.0, receptivity))
    
    def _calculate_chatter_receptivity(self, context: Dict, base_receptivity: float, stability: str) -> float:
        """Calculate receptivity for casual chatter and non-essential interactions"""
        receptivity = base_receptivity
        
        # Reduce chatter during unstable emotional periods
        if stability == 'volatile':
            receptivity *= 0.2
        elif stability == 'unstable':
            receptivity *= 0.5
        
        # Adjust based on emotion
        if context['recent_emotion'] in ['happy', 'content']:
            receptivity *= 1.3  # More open to casual interaction
        elif context['recent_emotion'] in ['serious', 'angry']:
            receptivity *= 0.3  # Don't interrupt focus/distress
        elif context['recent_emotion'] in ['tired', 'sad']:
            receptivity *= 0.6  # Gentle interaction only
        
        return max(0.0, min(1.0, receptivity))
    
    def _calculate_wellness_receptivity(self, stress_analysis: Dict, base_receptivity: float) -> float:
        """Calculate receptivity for wellness and break suggestions"""
        receptivity = base_receptivity
        
        # Always high receptivity for wellness during stress
        if stress_analysis['intervention_needed']:
            if stress_analysis['stress_level'] == 'high':
                receptivity = max(0.8, receptivity)
            elif stress_analysis['stress_level'] == 'medium':
                receptivity = max(0.6, receptivity)
        
        return max(0.0, min(1.0, receptivity))
    
    def _calculate_notification_receptivity(self, context: Dict, base_receptivity: float, stability: str) -> float:
        """Calculate receptivity for notifications and alerts"""
        receptivity = base_receptivity
        
        # Reduce notifications during emotional volatility
        if stability == 'volatile':
            receptivity *= 0.1
        elif stability == 'unstable':
            receptivity *= 0.4
        
        # Very low receptivity when angry or in no_face_detected state
        if context['recent_emotion'] in ['angry', 'no_face_detected']:
            receptivity *= 0.1
        
        return max(0.0, min(1.0, receptivity))
    
    def _calculate_timing_delays(self, context: Dict, stress_analysis: Dict, stability: str) -> Dict[str, int]:
        """Calculate appropriate delays (in minutes) before showing different types of content"""
        delays = {
            'suggestions': 0,
            'chatter': 0,
            'notifications': 0,
            'non_urgent': 0
        }
        
        # Base delays for different emotional states
        if context['recent_emotion'] == 'angry':
            delays.update({'suggestions': 30, 'chatter': 60, 'notifications': 90, 'non_urgent': 120})
        elif context['recent_emotion'] in ['sad', 'tired']:
            delays.update({'suggestions': 15, 'chatter': 10, 'notifications': 20, 'non_urgent': 30})
        elif context['recent_emotion'] == 'serious':
            delays.update({'suggestions': 5, 'chatter': 20, 'notifications': 10, 'non_urgent': 30})
        
        # Additional delays for emotional instability
        if stability == 'volatile':
            for key in delays:
                delays[key] += 20
        elif stability == 'unstable':
            for key in delays:
                delays[key] += 10
        
        # Reduce delays during high stress (wellness takes priority)
        if stress_analysis['stress_level'] == 'high':
            delays['suggestions'] = max(0, delays['suggestions'] - 10)
        
        return delays
    
    def _calculate_message_priorities(self, context: Dict, stress_analysis: Dict) -> Dict[str, str]:
        """Calculate priority levels for different message types"""
        priorities = {
            'wellness': 'medium',
            'suggestions': 'medium', 
            'chatter': 'low',
            'notifications': 'medium'
        }
        
        # Elevate wellness priority during stress
        if stress_analysis['intervention_needed']:
            if stress_analysis['stress_level'] == 'high':
                priorities['wellness'] = 'critical'
            elif stress_analysis['stress_level'] == 'medium':
                priorities['wellness'] = 'high'
        
        # Adjust based on emotional state
        if context['recent_emotion'] in ['happy', 'content']:
            priorities['suggestions'] = 'high'  # Good time for productivity suggestions
            priorities['chatter'] = 'medium'    # Open to casual interaction
        elif context['recent_emotion'] in ['sad', 'tired']:
            priorities['suggestions'] = 'low'   # Not ideal for work suggestions
            priorities['wellness'] = 'high'     # Supportive content priority
        elif context['recent_emotion'] == 'angry':
            priorities['suggestions'] = 'low'
            priorities['chatter'] = 'very_low'
            priorities['notifications'] = 'low'
        
        return priorities


# Global instance for easy access
emotion_context = EmotionContext()


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