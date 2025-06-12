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
from pathlib import Path

from PyQt6.QtWidgets import (QApplication, QWidget, QLabel, QVBoxLayout, 
                            QHBoxLayout, QFrame, QPushButton, QTextEdit)
from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QObject, QThread

# Thread-safe communication system
class AvatarCommunicator(QObject):
    # Signals for thread-safe communication
    show_message_signal = pyqtSignal(str, int, str)  # message, duration, avatar_state
    show_suggestion_signal = pyqtSignal(str, str)    # observation_type, message
    hide_message_signal = pyqtSignal()
    set_state_signal = pyqtSignal(str)               # state
    
    def __init__(self):
        super().__init__()
from PyQt6.QtGui import QPixmap, QFont, QPalette, QColor, QPainter, QPen, QTransform

class GooseAvatar(QWidget):
    def __init__(self):
        super().__init__()
        self.app = None
        self.chat_bubble = None
        self.is_visible = False
        self.current_message = ""
        self.message_queue = []
        self.avatar_pixmap = None
        
        # Connect to thread-safe communicator
        self.communicator = None
        
        # Avatar positioning
        self.avatar_x = 50
        self.avatar_y = 50
        self.bubble_offset_x = -100  # Position bubble above avatar
        self.bubble_offset_y = -80   # Position bubble above avatar
        
        # Dragging support
        self.drag_start_pos = None
        self.is_dragging = False
        
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
        
    def connect_communicator(self, communicator):
        """Connect to the thread-safe communicator"""
        self.communicator = communicator
        if communicator:
            communicator.show_message_signal.connect(self.show_message)
            communicator.show_suggestion_signal.connect(self.show_observer_suggestion)
            communicator.hide_message_signal.connect(self.hide_message)
            communicator.set_state_signal.connect(self.set_avatar_state)
        
    def load_avatar_images(self):
        """Load avatar images from the avatar directory"""
        self.avatar_images = {}
        avatar_dir = Path("avatar")
        
        try:
            # Define avatar states and their corresponding files
            avatar_files = {
                'idle': 'first.png',      # Default idle state
                'talking': 'second.png',  # When showing messages
                'pointing': 'third.png'   # For suggestions/pointing out things
            }
            
            # Load each avatar state image
            for state, filename in avatar_files.items():
                image_path = avatar_dir / filename
                if image_path.exists():
                    pixmap = QPixmap(str(image_path))
                    # Scale to reasonable size while maintaining aspect ratio
                    scaled_pixmap = pixmap.scaled(80, 80, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
                    self.avatar_images[state] = scaled_pixmap
                    print(f"✅ Loaded {state} avatar: {filename}")
                else:
                    print(f"❌ Avatar image not found: {image_path}")
            
            # Set default avatar to idle state
            if 'idle' in self.avatar_images:
                self.current_state = 'idle'
                self.avatar_pixmap = self.avatar_images['idle']
            else:
                # Fallback to any available image
                if self.avatar_images:
                    self.current_state = list(self.avatar_images.keys())[0]
                    self.avatar_pixmap = list(self.avatar_images.values())[0]
                else:
                    # Create placeholder if no images found
                    self.avatar_pixmap = QPixmap(80, 80)
                    self.avatar_pixmap.fill(QColor('lightblue'))
                    self.current_state = 'placeholder'
                    print("⚠️ No avatar images found, using placeholder")
                
        except Exception as e:
            print(f"Error loading avatar images: {e}")
            # Create a simple placeholder
            self.avatar_pixmap = QPixmap(80, 80)
            self.avatar_pixmap.fill(QColor('lightblue'))
            self.current_state = 'placeholder'
    
    def init_ui(self):
        """Initialize the UI components"""
        # Set window properties for floating avatar - independent window that stays visible
        self.setWindowFlags(
            Qt.WindowType.WindowStaysOnTopHint | 
            Qt.WindowType.FramelessWindowHint
            # No Tool flag - makes it independent of parent process focus on macOS
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
        # Remove background - clean transparent look
        self.avatar_label.setStyleSheet("QLabel { background: transparent; }")
        
        # Make avatar clickable and draggable
        self.avatar_label.mousePressEvent = self.on_mouse_press
        self.avatar_label.mouseMoveEvent = self.on_mouse_move
        self.avatar_label.mouseReleaseEvent = self.on_mouse_release
        self.avatar_label.setCursor(Qt.CursorShape.PointingHandCursor)
        
        layout.addWidget(self.avatar_label)
        self.setLayout(layout)
        
        # Position the avatar window
        self.position_avatar()
        
        # Start the idle checking loop
        self.idle_timer.start(self.idle_check_interval)
    
    def position_avatar(self):
        """Position the avatar on screen"""
        # Get the QApplication instance
        if not self.app:
            self.app = QApplication.instance()
        
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
        """Show the avatar and keep it always visible as an overlay"""
        if not self.is_visible:
            self.show()
            self.is_visible = True
            # Only raise once when first showing, then let WindowStaysOnTopHint handle it
            self.raise_()
    
    def hide_avatar(self):
        """Hide the avatar"""
        if self.is_visible:
            self.hide()
            self.is_visible = False
            if self.chat_bubble:
                self.chat_bubble.close()
                self.chat_bubble = None
    
    def should_flip_avatar(self):
        """Determine if avatar should be flipped based on screen position"""
        if self.app:
            # Find which screen the avatar is currently on
            avatar_point = self.pos()
            current_screen = self.app.screenAt(avatar_point)
            if current_screen:
                screen_rect = current_screen.availableGeometry()
                # Flip if avatar is on the right half of its current screen
                return self.avatar_x > screen_rect.x() + screen_rect.width() / 2
        return False
    
    def get_avatar_pixmap(self, state):
        """Get the avatar pixmap, flipped if necessary"""
        if state not in self.avatar_images:
            return self.avatar_pixmap
        
        pixmap = self.avatar_images[state]
        if self.should_flip_avatar():
            # Flip horizontally - create a new transform
            transform = QTransform()
            transform.scale(-1, 1)
            return pixmap.transformed(transform)
        else:
            return pixmap
    
    def update_avatar_display(self):
        """Update the avatar display (useful when position changes)"""
        if hasattr(self, 'current_state') and self.current_state:
            self.avatar_pixmap = self.get_avatar_pixmap(self.current_state)
            if self.avatar_label:
                # Clear the label first to prevent ghosting
                self.avatar_label.clear()
                self.avatar_label.setPixmap(self.avatar_pixmap)
                # Force a repaint to ensure clean rendering
                self.avatar_label.repaint()
                self.repaint()
    
    def set_avatar_state(self, state):
        """Change the avatar to a specific state"""
        if state in self.avatar_images:
            self.current_state = state
            self.avatar_pixmap = self.get_avatar_pixmap(state)
            if self.avatar_label:
                # Clear the label first to prevent ghosting
                self.avatar_label.clear()
                self.avatar_label.setPixmap(self.avatar_pixmap)
                # Force a repaint to ensure clean rendering
                self.avatar_label.repaint()
            print(f"🎭 Avatar state changed to: {state}")
    
    def show_message(self, message, duration=None, avatar_state='talking'):
        """Show a chat bubble with a message"""
        if duration is None:
            duration = self.message_duration
            
        # Ensure avatar is always visible and on top
        self.show_avatar()
        
        # Change avatar state for talking
        self.set_avatar_state(avatar_state)
        
        # Create or update chat bubble
        if self.chat_bubble:
            self.chat_bubble.close()
        
        self.chat_bubble = ChatBubble(message, self)
        
        # Position bubble relative to avatar (above the avatar)
        bubble_x = self.avatar_x + self.bubble_offset_x
        bubble_y = self.avatar_y + self.bubble_offset_y
        
        # Ensure bubble stays on current screen where avatar is located
        if self.app:
            # Find which screen the avatar is currently on
            avatar_point = self.pos()
            current_screen = self.app.screenAt(avatar_point)
            if current_screen:
                screen_rect = current_screen.availableGeometry()
                
                # Adjust horizontal position if bubble goes off current screen
                if bubble_x < screen_rect.x():
                    bubble_x = screen_rect.x() + 10  # Keep some margin from left edge
                elif bubble_x + 300 > screen_rect.x() + screen_rect.width():
                    bubble_x = screen_rect.x() + screen_rect.width() - 310  # Keep some margin from right edge
                
                # Adjust vertical position if bubble goes off current screen
                if bubble_y < screen_rect.y():
                    bubble_y = self.avatar_y + 90  # Show below avatar instead
                
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
        
        # Return to idle state when not talking (but keep avatar visible)
        self.set_avatar_state('idle')
        
        # Check if there are more messages in queue
        if self.message_queue:
            next_message = self.message_queue.pop(0)
            # Show next message after a brief delay
            QTimer.singleShot(1000, lambda: self.show_message(next_message))
        # Note: Avatar stays visible, just returns to idle state
    
    def queue_message(self, message):
        """Add a message to the queue"""
        if self.current_message:
            # If currently showing a message, queue this one
            self.message_queue.append(message)
        else:
            # Show immediately
            self.show_message(message)
    
    def on_mouse_press(self, event):
        """Handle mouse press for dragging and clicking"""
        if event.button() == Qt.MouseButton.LeftButton:
            self.drag_start_pos = event.globalPosition().toPoint()
            self.is_dragging = False
    
    def on_mouse_move(self, event):
        """Handle mouse move for dragging"""
        if event.buttons() & Qt.MouseButton.LeftButton and self.drag_start_pos:
            # Calculate drag distance
            drag_distance = (event.globalPosition().toPoint() - self.drag_start_pos).manhattanLength()
            
            if drag_distance > 3:  # Minimum drag distance to avoid accidental drags
                self.is_dragging = True
                
                # Move the window
                new_pos = self.pos() + event.globalPosition().toPoint() - self.drag_start_pos
                self.move(new_pos)
                
                # Update avatar position for bubble placement
                self.avatar_x = new_pos.x()
                self.avatar_y = new_pos.y()
                
                # Update drag position
                self.drag_start_pos = event.globalPosition().toPoint()
                
                # Update avatar display to handle potential flipping
                self.update_avatar_display()
    
    def on_mouse_release(self, event):
        """Handle mouse release"""
        if event.button() == Qt.MouseButton.LeftButton:
            if not self.is_dragging:
                # This was a click, not a drag
                self.on_avatar_click(event)
            
            # Reset drag state
            self.drag_start_pos = None
            self.is_dragging = False
    
    def on_avatar_click(self, event):
        """Handle avatar clicks"""
        # If there's a message, hide it
        if self.current_message:
            self.hide_message()
        else:
            # Simple interaction message - real chit-chat comes from recipes
            self.show_message("👋 Click! What's up?", 2000)
    
    def check_for_suggestions(self):
        """Periodically check for new suggestions - now handled by observer recipes"""
        # Real suggestions now come from observer recipes, not hardcoded lists
        pass
    
    def show_observer_suggestion(self, observation_type, message):
        """Show a suggestion based on observer data using pointing avatar"""
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
        
        # Use pointing state for suggestions
        self.show_message(full_message, avatar_state='pointing')
    
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
        # Set window properties - independent bubble window
        self.setWindowFlags(
            Qt.WindowType.WindowStaysOnTopHint | 
            Qt.WindowType.FramelessWindowHint
            # No Tool flag - makes it independent of parent process focus on macOS
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

# Global instances
avatar_instance = None
app_instance = None
avatar_communicator = None

def start_avatar_system():
    """Start the avatar system - Initialize Qt properly"""
    global avatar_instance, app_instance, avatar_communicator
    
    # Create QApplication if it doesn't exist
    if not QApplication.instance():
        app_instance = QApplication(sys.argv)
        # Ensure the application doesn't quit when last window closes
        app_instance.setQuitOnLastWindowClosed(False)
    else:
        app_instance = QApplication.instance()
    
    # Create the thread-safe communicator
    avatar_communicator = AvatarCommunicator()
    
    # Create avatar instance
    avatar_instance = GooseAvatar()
    avatar_instance.app = app_instance
    avatar_instance.connect_communicator(avatar_communicator)
    avatar_instance.position_avatar()
    avatar_instance.show_avatar()  # Avatar will now stay visible always
    
    print("🤖 Goose Avatar system started... Always watching and ready to help!")
    
    return avatar_instance

def show_suggestion(observation_type, message):
    """Thread-safe function to show a suggestion via the avatar system"""
    global avatar_communicator
    if avatar_communicator:
        avatar_communicator.show_suggestion_signal.emit(observation_type, message)
    else:
        print(f"Avatar not initialized. Suggestion: {message}")

def show_message(message, duration=5000, avatar_state='talking'):
    """Thread-safe function to show a general message via the avatar system"""
    global avatar_communicator
    if avatar_communicator:
        avatar_communicator.show_message_signal.emit(message, duration, avatar_state)
    else:
        print(f"Avatar not initialized. Message: {message}")

def set_avatar_state(state):
    """Thread-safe function to set avatar state"""
    global avatar_communicator
    if avatar_communicator:
        avatar_communicator.set_state_signal.emit(state)
    else:
        print(f"Avatar not initialized. State: {state}")

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