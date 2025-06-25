import json
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
from emotion_context import EmotionContext

# Import the global instance
try:
    from emotion_context import emotion_context
except ImportError:
    # Create a default instance if not available
    emotion_context = EmotionContext()


@dataclass
class QueuedMessage:
    """Represents a message in the queue with metadata"""
    id: str
    message_type: str  # 'suggestion', 'chatter', 'wellness', 'notification'
    priority: str      # 'critical', 'high', 'medium', 'low', 'very_low'
    content: Dict[str, Any]
    created_at: str
    deliver_after: str  # ISO timestamp - earliest delivery time
    max_age_hours: float  # How long message stays relevant
    context_requirements: Dict[str, Any]  # Requirements for delivery
    delivery_attempts: int = 0
    last_attempt: Optional[str] = None


class EmotionAwareMessageQueue:
    """
    Smart message queue that manages delivery timing based on emotional receptivity.
    Handles priority-based queuing, emotional context requirements, and adaptive delivery.
    """
    
    def __init__(self, queue_file: str = None):
        """Initialize message queue with persistent storage"""
        if queue_file is None:
            # Use same directory as emotions.log
            data_dir = os.path.expanduser("~/.local/share/goose-perception")
            os.makedirs(data_dir, exist_ok=True)
            queue_file = os.path.join(data_dir, "message_queue.json")
        
        self.queue_file = queue_file
        self.messages: List[QueuedMessage] = []
        self._load_queue()
    
    def _load_queue(self):
        """Load queue from persistent storage"""
        try:
            if os.path.exists(self.queue_file):
                with open(self.queue_file, 'r') as f:
                    data = json.load(f)
                    self.messages = [QueuedMessage(**msg) for msg in data]
                    # Clean expired messages on load
                    self._clean_expired_messages()
        except Exception as e:
            print(f"Warning: Could not load message queue: {e}")
            self.messages = []
    
    def _save_queue(self):
        """Save queue to persistent storage"""
        try:
            with open(self.queue_file, 'w') as f:
                json.dump([asdict(msg) for msg in self.messages], f, indent=2)
        except Exception as e:
            print(f"Warning: Could not save message queue: {e}")
    
    def add_message(self, 
                   message_type: str,
                   content: Dict[str, Any],
                   priority: str = 'medium',
                   delay_minutes: int = 0,
                   max_age_hours: float = 24.0,
                   context_requirements: Dict[str, Any] = None) -> str:
        """
        Add a message to the queue with smart timing based on emotional context.
        
        Args:
            message_type: Type of message ('suggestion', 'chatter', 'wellness', 'notification')
            content: Message content and parameters
            priority: Message priority level
            delay_minutes: Minimum delay before delivery (in addition to emotional timing)
            max_age_hours: How long message stays relevant
            context_requirements: Specific emotional context requirements for delivery
        
        Returns:
            Message ID
        """
        now = datetime.now()
        message_id = f"{message_type}_{now.strftime('%Y%m%d_%H%M%S')}_{len(self.messages)}"
        
        # Get timing analysis for smart delay calculation
        timing_analysis = emotion_context.get_interaction_timing_analysis()
        
        # Calculate smart delivery delay based on emotional context
        emotional_delays = timing_analysis['timing_delays']
        emotional_delay = emotional_delays.get(message_type, 0)
        
        # Use the longer of requested delay or emotional delay
        total_delay = max(delay_minutes, emotional_delay)
        
        # Set default context requirements based on message type
        if context_requirements is None:
            context_requirements = self._get_default_context_requirements(message_type, priority)
        
        # Create queued message
        message = QueuedMessage(
            id=message_id,
            message_type=message_type,
            priority=priority,
            content=content,
            created_at=now.isoformat(),
            deliver_after=(now + timedelta(minutes=total_delay)).isoformat(),
            max_age_hours=max_age_hours,
            context_requirements=context_requirements
        )
        
        self.messages.append(message)
        self._save_queue()
        
        return message_id
    
    def get_ready_messages(self, limit: int = 5) -> List[QueuedMessage]:
        """
        Get messages that are ready for delivery based on timing and emotional context.
        
        Args:
            limit: Maximum number of messages to return
            
        Returns:
            List of messages ready for delivery, sorted by priority and age
        """
        now = datetime.now()
        timing_analysis = emotion_context.get_interaction_timing_analysis()
        
        ready_messages = []
        
        for message in self.messages:
            # Check if message is old enough to deliver
            deliver_after = datetime.fromisoformat(message.deliver_after)
            if now < deliver_after:
                continue
            
            # Check if message meets emotional context requirements
            if not self._meets_context_requirements(message, timing_analysis):
                continue
            
            ready_messages.append(message)
        
        # Sort by priority and age
        priority_order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3, 'very_low': 4}
        ready_messages.sort(key=lambda m: (
            priority_order.get(m.priority, 2),  # Priority first
            datetime.fromisoformat(m.created_at)  # Then age (older first)
        ))
        
        return ready_messages[:limit]
    
    def mark_delivered(self, message_id: str) -> bool:
        """
        Mark a message as delivered and remove it from the queue.
        
        Args:
            message_id: ID of the message to mark as delivered
            
        Returns:
            True if message was found and removed, False otherwise
        """
        for i, message in enumerate(self.messages):
            if message.id == message_id:
                del self.messages[i]
                self._save_queue()
                return True
        return False
    
    def mark_delivery_attempted(self, message_id: str) -> bool:
        """
        Mark that a delivery attempt was made for a message.
        
        Args:
            message_id: ID of the message
            
        Returns:
            True if message was found and updated, False otherwise
        """
        for message in self.messages:
            if message.id == message_id:
                message.delivery_attempts += 1
                message.last_attempt = datetime.now().isoformat()
                self._save_queue()
                return True
        return False
    
    def get_queue_stats(self) -> Dict[str, Any]:
        """Get statistics about the current queue state"""
        now = datetime.now()
        timing_analysis = emotion_context.get_interaction_timing_analysis()
        
        stats = {
            'total_messages': len(self.messages),
            'ready_now': 0,
            'waiting_for_time': 0,
            'waiting_for_context': 0,
            'by_type': {},
            'by_priority': {},
            'avg_age_hours': 0.0,
            'oldest_message_hours': 0.0
        }
        
        if not self.messages:
            return stats
        
        ages = []
        for message in self.messages:
            created = datetime.fromisoformat(message.created_at)
            age_hours = (now - created).total_seconds() / 3600
            ages.append(age_hours)
            
            # Count by type and priority
            stats['by_type'][message.message_type] = stats['by_type'].get(message.message_type, 0) + 1
            stats['by_priority'][message.priority] = stats['by_priority'].get(message.priority, 0) + 1
            
            # Check readiness
            deliver_after = datetime.fromisoformat(message.deliver_after)
            if now < deliver_after:
                stats['waiting_for_time'] += 1
            elif not self._meets_context_requirements(message, timing_analysis):
                stats['waiting_for_context'] += 1
            else:
                stats['ready_now'] += 1
        
        stats['avg_age_hours'] = sum(ages) / len(ages)
        stats['oldest_message_hours'] = max(ages)
        
        return stats
    
    def _get_default_context_requirements(self, message_type: str, priority: str) -> Dict[str, Any]:
        """Get default context requirements for a message type and priority"""
        requirements = {
            'min_receptivity': 0.3,  # Default minimum receptivity
            'max_stress_level': 'high',  # Allow up to high stress
            'blocked_emotions': [],  # Emotions that block delivery
            'required_stability': None  # Required emotional stability
        }
        
        # Adjust based on message type
        if message_type == 'wellness':
            requirements.update({
                'min_receptivity': 0.1,  # Wellness messages can interrupt more
                'blocked_emotions': []   # No emotional blocks for wellness
            })
        elif message_type == 'chatter':
            requirements.update({
                'min_receptivity': 0.4,  # Need higher receptivity for casual chat
                'blocked_emotions': ['angry', 'serious'],
                'required_stability': 'stable'
            })
        elif message_type == 'suggestion':
            requirements.update({
                'min_receptivity': 0.3,
                'blocked_emotions': ['angry'],
                'max_stress_level': 'medium'  # Don't suggest during high stress
            })
        elif message_type == 'notification':
            requirements.update({
                'min_receptivity': 0.2,
                'blocked_emotions': ['angry']
            })
        
        # Adjust based on priority
        if priority == 'critical':
            requirements.update({
                'min_receptivity': 0.0,  # Critical messages override receptivity
                'blocked_emotions': [],
                'max_stress_level': 'high'
            })
        elif priority == 'high':
            requirements.update({
                'min_receptivity': 0.2,
                'blocked_emotions': ['angry']
            })
        elif priority in ['low', 'very_low']:
            requirements.update({
                'min_receptivity': 0.5,  # Need good receptivity for low priority
                'blocked_emotions': ['angry', 'serious', 'tired'],
                'required_stability': 'stable'
            })
        
        return requirements
    
    def _meets_context_requirements(self, message: QueuedMessage, timing_analysis: Dict[str, Any]) -> bool:
        """Check if current emotional context meets message delivery requirements"""
        requirements = message.context_requirements
        context = emotion_context.get_current_emotion_context()
        
        # Check minimum receptivity
        message_receptivity = timing_analysis['interaction_receptivity'].get(message.message_type, 0.0)
        if message_receptivity < requirements.get('min_receptivity', 0.3):
            return False
        
        # Check blocked emotions
        blocked_emotions = requirements.get('blocked_emotions', [])
        if context['recent_emotion'] in blocked_emotions:
            return False
        
        # Check stress level
        stress_analysis = emotion_context.get_stress_analysis()
        max_stress = requirements.get('max_stress_level', 'high')
        stress_levels = {'low': 0, 'medium': 1, 'high': 2}
        if (stress_levels.get(stress_analysis['stress_level'], 0) > 
            stress_levels.get(max_stress, 2)):
            return False
        
        # Check emotional stability
        required_stability = requirements.get('required_stability')
        if (required_stability and 
            timing_analysis['emotional_stability'] != required_stability):
            return False
        
        return True
    
    def _clean_expired_messages(self):
        """Remove messages that have exceeded their maximum age"""
        now = datetime.now()
        self.messages = [
            msg for msg in self.messages
            if (now - datetime.fromisoformat(msg.created_at)).total_seconds() / 3600
            < msg.max_age_hours
        ]
        self._save_queue()
    
    def clear_queue(self):
        """Clear all messages from the queue"""
        self.messages = []
        self._save_queue()


# Global message queue instance
message_queue = EmotionAwareMessageQueue() 