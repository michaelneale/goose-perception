#!/usr/bin/env python3
"""
avatar_display.py - Creepy Goose Avatar Display System
Shows a persistent avatar that can pop up with suggestions and reminders
Uses PyQt6 for modern GUI capabilities
"""

import sys
import threading
import time
import random
from PIL import Image
import os
from datetime import datetime
import json

from PyQt6.QtWidgets import (QApplication, QWidget, QLabel, QVBoxLayout, 
                            QHBoxLayout, QFrame, QPushButton, QTextEdit)
from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QObject, QThread
from PyQt6.QtGui import QPixmap, QFont, QPalette, QColor, QPainter, QPen

class GooseAvatar(QWidget):
    def __init__(self):
        super().__init__()
        self.app = None
        self.chat_bubble = None
        self.is_visible = False
        self.current_message = ""
        self.message_queue = []
        self.avatar_pixmap = None
        
        # Avatar positioning
        self.avatar_x = 50
        self.avatar_y = 50
        self.bubble_offset_x = 120
        self.bubble_offset_y = -50
        
        # Timing settings
        self.message_duration = 8000  # 8 seconds
        self.idle_check_interval = 30000  # 30 seconds
        
        # Timers
        self.hide_timer = QTimer()
        self.hide_timer.timeout.connect(self.hide_message)
        self.hide_timer.setSingleShot(True)
        
        self.idle_timer = QTimer()
        self.idle_timer.timeout.connect(self.check_for_suggestions)
        
        # Load avatar images
        self.load_avatar_images()
        self.init_ui()
        
    def load_avatar_images(self):
        """Load avatar images from the project directory"""
        try:
            # Load the main goose image
            if os.path.exists("goose.png"):
                self.avatar_pixmap = QPixmap("goose.png")
                # Scale to reasonable size
                self.avatar_pixmap = self.avatar_pixmap.scaled(80, 80, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
            else:
                # Create a simple placeholder
                self.avatar_pixmap = QPixmap(80, 80)
                self.avatar_pixmap.fill(QColor('lightblue'))
                
        except Exception as e:
            print(f"Error loading avatar images: {e}")
            # Create a simple placeholder
            self.avatar_pixmap = QPixmap(80, 80)
            self.avatar_pixmap.fill(QColor('lightblue'))
    
    def init_ui(self):
        """Initialize the UI components"""
        # Set window properties for floating avatar
        self.setWindowFlags(
            Qt.WindowType.WindowStaysOnTopHint | 
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setFixedSize(80, 80)
        
        # Create layout
        layout = QVBoxLayout()
        layout.setContentsMargins(0, 0, 0, 0)
        
        # Avatar label
        self.avatar_label = QLabel()
        if self.avatar_pixmap:
            self.avatar_label.setPixmap(self.avatar_pixmap)
        self.avatar_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.avatar_label.setStyleSheet("""
            QLabel {
                border-radius: 40px;
                background-color: rgba(255, 255, 255, 200);
            }
        """)
        
        # Make avatar clickable
        self.avatar_label.mousePressEvent = self.on_avatar_click
        self.avatar_label.setCursor(Qt.CursorShape.PointingHandCursor)
        
        layout.addWidget(self.avatar_label)
        self.setLayout(layout)
        
        # Position the avatar window
        self.position_avatar()
        
        # Start the idle checking loop
        self.idle_timer.start(self.idle_check_interval)
    
    def position_avatar(self):
        """Position the avatar on screen"""
        if self.app:
            screen = self.app.primaryScreen()
            screen_rect = screen.availableGeometry()
            
            # Position in top-right corner by default
            x = screen_rect.width() - 150
            y = 50
            
            self.move(x, y)
            self.avatar_x = x
            self.avatar_y = y
    
    def show_avatar(self):
        """Show the avatar"""
        if not self.is_visible:
            self.show()
            self.raise_()
            self.activateWindow()
            self.is_visible = True
    
    def hide_avatar(self):
        """Hide the avatar"""
        if self.is_visible:
            self.hide()
            self.is_visible = False
            if self.chat_bubble:
                self.chat_bubble.close()
                self.chat_bubble = None
    
    def show_message(self, message, duration=None):
        """Show a chat bubble with a message"""
        if duration is None:
            duration = self.message_duration
            
        # Show avatar first
        self.show_avatar()
        
        # Create or update chat bubble
        if self.chat_bubble:
            self.chat_bubble.close()
        
        self.chat_bubble = ChatBubble(message, self)
        
        # Position bubble relative to avatar
        bubble_x = self.avatar_x + self.bubble_offset_x
        bubble_y = self.avatar_y + self.bubble_offset_y
        
        # Ensure bubble stays on screen
        if self.app:
            screen = self.app.primaryScreen()
            screen_rect = screen.availableGeometry()
            
            if bubble_x + 300 > screen_rect.width():
                bubble_x = self.avatar_x - 320  # Show on left side instead
            if bubble_y < 0:
                bubble_y = self.avatar_y + 100  # Show below instead
                
        self.chat_bubble.move(bubble_x, bubble_y)
        self.chat_bubble.show()
        
        # Store current message
        self.current_message = message
        
        # Auto-hide after duration
        self.hide_timer.start(duration)
    
    def hide_message(self):
        """Hide the current message bubble"""
        if self.chat_bubble:
            self.chat_bubble.close()
            self.chat_bubble = None
        self.current_message = ""
        
        # Check if there are more messages in queue
        if self.message_queue:
            next_message = self.message_queue.pop(0)
            # Show next message after a brief delay
            QTimer.singleShot(1000, lambda: self.show_message(next_message))
        else:
            # Hide avatar after a delay if no more messages
            QTimer.singleShot(3000, self.hide_avatar)
    
    def queue_message(self, message):
        """Add a message to the queue"""
        if self.current_message:
            # If currently showing a message, queue this one
            self.message_queue.append(message)
        else:
            # Show immediately
            self.show_message(message)
    
    def on_avatar_click(self, event):
        """Handle avatar clicks"""
        # If there's a message, hide it
        if self.current_message:
            self.hide_message()
        else:
            # Show a random idle message
            idle_messages = [
                "👁️ Watching...",
                "🤔 I'm thinking of ways to help you...",
                "📊 Analyzing your patterns...",
                "💡 Got any tasks for me?",
                "🔍 I notice everything...",
                "⏰ Time is passing...",
                "🎯 Focusing on efficiency..."
            ]
            random_message = random.choice(idle_messages)
            self.show_message(random_message, 3000)
    
    def check_for_suggestions(self):
        """Periodically check for new suggestions"""
        # This would integrate with the observer system
        # For now, we'll show random suggestions occasionally
        
        if random.random() < 0.3 and not self.current_message:  # 30% chance
            creepy_suggestions = [
                "🔍 I've been watching your workflow... Want me to optimize it?",
                "⚡ I noticed you're doing that task manually again...",
                "📈 Your productivity dipped 12 minutes ago. Need a break?",
                "🤖 I could automate that repetitive task you just did...",
                "👀 I see you checking email again. Want me to summarize?",
                "⏰ You've been working for 47 minutes. Time for a stretch?",
                "💻 That code pattern looks familiar... want a better approach?",
                "📝 Should I add that to your TODO list?",
                "🎯 I can help you focus on what matters most...",
                "🔮 Based on your patterns, you'll need coffee in 23 minutes..."
            ]
            
            suggestion = random.choice(creepy_suggestions)
            self.queue_message(suggestion)
    
    def show_observer_suggestion(self, observation_type, message):
        """Show a suggestion based on observer data"""
        prefix_messages = {
            'work': "🔍 Work Pattern Alert: ",
            'meetings': "📅 Meeting Notice: ",
            'focus': "🎯 Focus Suggestion: ",
            'productivity': "📈 Productivity Insight: ",
            'break': "⏸️ Break Reminder: ",
            'optimization': "⚡ Optimization Tip: "
        }
        
        prefix = prefix_messages.get(observation_type, "💡 Suggestion: ")
        full_message = prefix + message
        
        self.queue_message(full_message)
    
    def closeEvent(self, event):
        """Handle close event"""
        if self.chat_bubble:
            self.chat_bubble.close()
        event.accept()

class ChatBubble(QWidget):
    def __init__(self, message, parent_avatar):
        super().__init__()
        self.parent_avatar = parent_avatar
        self.init_ui(message)
    
    def init_ui(self, message):
        """Initialize the chat bubble UI"""
        # Set window properties
        self.setWindowFlags(
            Qt.WindowType.WindowStaysOnTopHint | 
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        
        # Create layout
        layout = QVBoxLayout()
        layout.setContentsMargins(5, 5, 5, 5)
        
        # Create frame for the bubble
        bubble_frame = QFrame()
        bubble_frame.setStyleSheet("""
            QFrame {
                background-color: rgba(44, 62, 80, 240);
                border-radius: 15px;
                border: 2px solid rgba(52, 73, 94, 255);
            }
        """)
        
        # Create layout for frame content
        frame_layout = QVBoxLayout()
        frame_layout.setContentsMargins(15, 10, 15, 10)
        
        # Message label
        message_label = QLabel(message)
        message_label.setStyleSheet("""
            QLabel {
                color: white;
                background: transparent;
                font-size: 11px;
                font-family: Arial, sans-serif;
            }
        """)
        message_label.setWordWrap(True)
        message_label.setMaximumWidth(250)
        
        frame_layout.addWidget(message_label)
        bubble_frame.setLayout(frame_layout)
        
        layout.addWidget(bubble_frame)
        self.setLayout(layout)
        
        # Make bubble clickable to dismiss
        bubble_frame.mousePressEvent = self.on_bubble_click
        message_label.mousePressEvent = self.on_bubble_click
        bubble_frame.setCursor(Qt.CursorShape.PointingHandCursor)
        
        # Adjust size to content
        self.adjustSize()
    
    def on_bubble_click(self, event):
        """Handle bubble clicks"""
        self.parent_avatar.hide_message()

# Global avatar instance
avatar_instance = None
app_instance = None

def start_avatar_system():
    """Start the avatar system"""
    global avatar_instance, app_instance
    
    def run_avatar():
        global avatar_instance, app_instance
        
        # Create QApplication if it doesn't exist
        if not QApplication.instance():
            app_instance = QApplication(sys.argv)
        else:
            app_instance = QApplication.instance()
        
        avatar_instance = GooseAvatar()
        avatar_instance.app = app_instance
        avatar_instance.position_avatar()
        avatar_instance.show_avatar()
        
        print("🤖 Goose Avatar system started... Watching...")
        
        # Don't call exec() here as it blocks
        # The application loop will be handled by the main thread
    
    avatar_thread = threading.Thread(target=run_avatar, daemon=True)
    avatar_thread.start()
    
    # Give it a moment to initialize
    time.sleep(1)
    return avatar_instance

def show_suggestion(observation_type, message):
    """Show a suggestion via the avatar system"""
    global avatar_instance
    if avatar_instance:
        avatar_instance.show_observer_suggestion(observation_type, message)
    else:
        print(f"Avatar not initialized. Suggestion: {message}")

def show_message(message):
    """Show a general message via the avatar system"""
    global avatar_instance
    if avatar_instance:
        avatar_instance.queue_message(message)
    else:
        print(f"Avatar not initialized. Message: {message}")

def run_app():
    """Run the Qt application event loop"""
    global app_instance
    if app_instance:
        app_instance.exec()

if __name__ == "__main__":
    # Test the avatar system
    app = QApplication(sys.argv)
    avatar = GooseAvatar()
    avatar.app = app
    avatar.show_avatar()
    
    # Show a test message after 2 seconds
    QTimer.singleShot(2000, lambda: avatar.show_message("🤖 Hello from PyQt6!"))
    
    sys.exit(app.exec()) 