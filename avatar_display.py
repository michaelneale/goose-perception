#!/usr/bin/env python3
"""
Goose Avatar Display System - Always visible floating avatar with chat bubbles
"""
import sys
import os
from pathlib import Path
from PyQt6.QtWidgets import (QApplication, QWidget, QLabel, QVBoxLayout, 
                            QPushButton, QHBoxLayout, QTextEdit)
from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QObject
from PyQt6.QtGui import QPixmap, QColor, QPainter, QPen, QBrush, QFont
import random

class AvatarCommunicator(QObject):
    """Thread-safe communicator for avatar system"""
    # Signals for thread-safe communication
    show_message_signal = pyqtSignal(str, int, str)  # message, duration, avatar_state
    show_suggestion_signal = pyqtSignal(str, str)    # observation_type, message
    hide_message_signal = pyqtSignal()
    set_state_signal = pyqtSignal(str)               # state

    def __init__(self):
        super().__init__()
from PyQt6.QtGui import QPixmap, QFont, QPalette, QColor, QPainter, QPen, QTransform


class GooseAvatar(QWidget):
    """Main avatar widget that stays always visible"""
    
    def __init__(self):
        super().__init__()
        self.app = None
        self.current_screen = None
        self.relative_position = (0.95, 0.15)  # Top-right corner by default
        self.avatar_x = 0
        self.avatar_y = 0
        self.is_visible = True
        self.current_state = 'idle'
        self.avatar_images = {}
        self.avatar_pixmap = None
        self.chat_bubble = None
        self.bubble_offset_x = -220  # Bubble appears to the left of avatar
        self.bubble_offset_y = -10   # Slightly above avatar
        self.message_queue = []
        self.is_showing_message = False
        self.communicator = None
        
        # Dragging state
        self.drag_start_pos = None
        self.is_dragging = False
        
        # Idle behavior settings - much more frequent and immediate
        self.idle_check_interval = 15000  # Check every 15 seconds (was 30)
        self.idle_suggestion_chance = 0.3  # 30% chance to show suggestion (was 0.1)
        self.last_suggestion_time = 0
        self.min_suggestion_interval = 45  # Minimum 45 seconds between suggestions (was 120)
        
        # Timers
        self.hide_timer = QTimer()
        self.hide_timer.timeout.connect(self.hide_message)
        self.hide_timer.setSingleShot(True)
        
        # Auto-dismiss timer for actionable messages
        self.auto_dismiss_timer = QTimer()
        self.auto_dismiss_timer.timeout.connect(self.auto_dismiss_actionable)
        self.auto_dismiss_timer.setSingleShot(True)
        
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
        # Set window properties for floating avatar - appears on ALL macOS Spaces
        self.setWindowFlags(
            Qt.WindowType.WindowStaysOnTopHint | 
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowDoesNotAcceptFocus  # Prevent focus stealing - NO Tool flag!
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        
        # Make window appear on all macOS Spaces
        self.setup_spaces_behavior()
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
        
        # For macOS Spaces support - ensure avatar appears on current Space
        self.spaces_timer = QTimer()
        self.spaces_timer.timeout.connect(self.refresh_avatar_for_spaces)
        self.spaces_timer.start(1000)  # Refresh every 1 second for Space switching
    
    def position_avatar(self):
        """Position the avatar on screen"""
        # Get the QApplication instance
        if not self.app:
            self.app = QApplication.instance()
        
        if self.app:
            # Use primary screen for initial positioning
            screen = self.app.primaryScreen()
            self.current_screen = screen
            self.position_on_screen(screen)
    
    def position_on_screen(self, screen):
        """Position the avatar on a specific screen using relative positioning"""
        if not screen:
            return
            
        screen_rect = screen.availableGeometry()
        
        # Calculate position based on relative coordinates (0.0 to 1.0)
        x = screen_rect.x() + int(screen_rect.width() * self.relative_position[0]) - 40  # Center avatar
        y = screen_rect.y() + int(screen_rect.height() * self.relative_position[1])
        
        self.move(x, y)
        self.avatar_x = x
        self.avatar_y = y
        
        # Only print position updates when position actually changes significantly
        if not hasattr(self, '_last_logged_pos') or abs(self._last_logged_pos[0] - x) > 50 or abs(self._last_logged_pos[1] - y) > 50:
            print(f"🖥️ Moved avatar to screen at ({x}, {y})")
            self._last_logged_pos = (x, y)
    
    def refresh_avatar_for_spaces(self):
        """Refresh avatar to ensure it appears on the current macOS Space"""
        if not self.is_visible:
            return
            
        try:
            # Re-render the avatar to ensure it appears on current Space
            # This is more aggressive than just show() - we hide and show again
            self.hide()
            self.show()
            # NO raise_() call - this steals focus on macOS!
            
            # Ensure it stays in the correct position
            if hasattr(self, 'current_screen') and self.current_screen:
                # Refresh position to make sure it's still correct
                self.position_on_screen(self.current_screen)
            
            # Also refresh the avatar display to ensure clean rendering
            self.update_avatar_display()
                
        except Exception as e:
            print(f"Error refreshing avatar for Spaces: {e}")
    
    def setup_spaces_behavior(self):
        """Set up the window to appear on all macOS Spaces"""
        try:
            # Import macOS specific modules
            import objc
            from Cocoa import NSApp, NSWindow
            
            # Schedule the space setup for after the window is fully created
            def setup_after_show():
                try:
                    win_id = int(self.winId())
                    # Find the native NSWindow
                    app = NSApp
                    if app:
                        for window in app.windows():
                            if window.windowNumber() == win_id:
                                # Set collection behavior to appear on all Spaces
                                # NSWindowCollectionBehaviorCanJoinAllSpaces = 1
                                window.setCollectionBehavior_(1)
                                print("✨ Set window to appear on all Spaces")
                                break
                except Exception as e:
                    print(f"Could not set Spaces behavior: {e}")
            
            # Use a timer to set up after the window is shown
            QTimer.singleShot(100, setup_after_show)
            
        except ImportError:
            print("⚠️ macOS Cocoa modules not available - Spaces behavior may not work")
        except Exception as e:
            print(f"Error setting up Spaces behavior: {e}")
    
    def update_relative_position(self):
        """Update the relative position based on current absolute position"""
        if not self.app or not self.current_screen:
            return
            
        # Find which screen the avatar is currently on
        avatar_point = self.pos()
        current_screen = self.app.screenAt(avatar_point)
        
        if current_screen:
            self.current_screen = current_screen
            screen_rect = current_screen.availableGeometry()
            
            # Calculate relative position (0.0 to 1.0)
            rel_x = (self.avatar_x - screen_rect.x() + 40) / screen_rect.width()  # +40 to account for centering
            rel_y = (self.avatar_y - screen_rect.y()) / screen_rect.height()
            
            # Clamp to valid range
            rel_x = max(0.0, min(1.0, rel_x))
            rel_y = max(0.0, min(1.0, rel_y))
            
            self.relative_position = (rel_x, rel_y)
    
    def show_avatar(self):
        """Show the avatar"""
        self.is_visible = True
        self.show()
        print("👁️ Avatar is now visible")
    
    def hide_avatar(self):
        """Hide the avatar"""
        self.is_visible = False
        self.hide()
        if self.chat_bubble:
            self.chat_bubble.hide()
        print("👁️ Avatar is now hidden")
    
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
        """Update the avatar display with current state and potential flipping"""
        if self.avatar_label and self.current_state in self.avatar_images:
            pixmap = self.get_avatar_pixmap(self.current_state)
            self.avatar_label.setPixmap(pixmap)
    
    def set_avatar_state(self, state):
        """Set the avatar state and update display"""
        if state in self.avatar_images or state == 'placeholder':
            self.current_state = state
            self.update_avatar_display()
            print(f"🎭 Avatar state changed to: {state}")
        else:
            print(f"⚠️ Unknown avatar state: {state}")
    
    def show_message(self, message, duration=None, avatar_state='talking', action_data=None):
        """Show a message with the avatar"""
        # Set default durations based on message type
        if duration is None:
            if action_data:
                duration = 75000  # 75 seconds for actionable messages
            else:
                duration = 20000  # 20 seconds for regular messages
        
        # Change avatar state
        self.set_avatar_state(avatar_state)
        
        # Hide any existing bubble first
        if self.chat_bubble:
            self.chat_bubble.hide()
            self.chat_bubble.deleteLater()
            self.chat_bubble = None
        
        # Create and show new bubble
        self.chat_bubble = ChatBubble(message, self, action_data)
        
        # Position the bubble relative to avatar
        bubble_x = self.avatar_x + self.bubble_offset_x
        bubble_y = self.avatar_y + self.bubble_offset_y
        
        # Ensure bubble stays on screen
        if self.app:
            screen = self.app.primaryScreen()
            if screen:
                screen_rect = screen.availableGeometry()
                
                # Adjust horizontal position if bubble goes off screen
                if bubble_x < screen_rect.x():
                    bubble_x = screen_rect.x() + 10  # Keep some margin from left edge
                    # Move bubble to right side of avatar
                    self.bubble_offset_x = 100
                    bubble_x = self.avatar_x + self.bubble_offset_x
                elif bubble_x + 300 > screen_rect.x() + screen_rect.width():
                    bubble_x = screen_rect.x() + screen_rect.width() - 310  # Keep some margin from right edge
                
                # Adjust vertical position if bubble goes off screen
                if bubble_y < screen_rect.y():
                    bubble_y = self.avatar_y + 90  # Show below avatar instead
        
        self.chat_bubble.move(bubble_x, bubble_y)
        self.chat_bubble.show()
        
        # Update avatar display to handle potential flipping
        self.update_avatar_display()
        
        # Set up auto-hide timer
        self.hide_timer.stop()  # Stop any existing timer
        self.hide_timer.start(duration)
        
        # Set up auto-dismiss for actionable messages (75 seconds)
        if action_data:
            self.auto_dismiss_timer.stop()
            self.auto_dismiss_timer.start(75000)  # Auto-dismiss after 75 seconds
            print(f"📝 Actionable message (will auto-dismiss in 75s)")
        else:
            print(f"📝 Regular message (no action buttons)")
        
        self.is_showing_message = True
        print(f"💬 Message shown - will hide in {duration/1000} seconds")
    
    def hide_message(self):
        """Hide the current message"""
        if self.chat_bubble:
            self.chat_bubble.hide()
            self.chat_bubble.deleteLater()
            self.chat_bubble = None
        
        # Reset avatar to idle state
        self.set_avatar_state('idle')
        
        # Reset bubble position to default (left side)
        self.bubble_offset_x = -220
        self.bubble_offset_y = -10
        
        # Update avatar display (removes any flipping)
        self.update_avatar_display()
        
        self.is_showing_message = False
        self.hide_timer.stop()
        self.auto_dismiss_timer.stop()
        
        # Process any queued messages
        if self.message_queue:
            next_message = self.message_queue.pop(0)
            self.show_message(**next_message)
    
    def auto_dismiss_actionable(self):
        """Auto-dismiss actionable messages after timeout"""
        if self.chat_bubble and hasattr(self.chat_bubble, 'action_data') and self.chat_bubble.action_data:
            print("⏰ Auto-dismissing actionable message after timeout")
            # Simulate clicking "Skip" by hiding the message
            self.hide_message()
    
    def queue_message(self, message):
        """Queue a message to show after current one finishes"""
        self.message_queue.append(message)
        print(f"📬 Message queued (queue length: {len(self.message_queue)})")
    
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
                if not self.is_dragging:
                    self.is_dragging = True
                
                # Move the window
                new_pos = self.pos() + event.globalPosition().toPoint() - self.drag_start_pos
                self.move(new_pos)
                
                # Update avatar position
                self.avatar_x = new_pos.x()
                self.avatar_y = new_pos.y()
                
                # Update current screen and relative position
                self.update_relative_position()
                
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
        print("🖱️ Avatar clicked!")
        
        # Cycle through avatar states for testing
        states = list(self.avatar_images.keys())
        if states:
            current_index = states.index(self.current_state) if self.current_state in states else 0
            next_index = (current_index + 1) % len(states)
            next_state = states[next_index]
            self.set_avatar_state(next_state)
        
        # Show a test message
        test_messages = [
            "👋 Hello! I'm your Goose avatar!",
            "🤖 I'm always here watching and ready to help!",
            "✨ Click me to cycle through my expressions!",
            "🎯 I can show suggestions and help with your work!",
            "💡 Try dragging me around the screen!"
        ]
        message = random.choice(test_messages)
        self.show_message(message, 15000, self.current_state)
    
    def check_for_suggestions(self):
        """Check if we should show an idle suggestion - much more frequent now"""
        import time
        current_time = time.time()
        
        # Only suggest if not currently showing a message and enough time has passed
        if (not self.is_showing_message and 
            current_time - self.last_suggestion_time > self.min_suggestion_interval):
            
            # Much higher chance of showing suggestion (30% vs previous 10%)
            if random.random() < self.idle_suggestion_chance:
                self.show_idle_suggestion()
                self.last_suggestion_time = current_time
    
    def show_idle_suggestion(self):
        """Show a random idle suggestion - more varied and contextual"""
        suggestions = [
            "💡 I'm watching your workflow - let me know if you need help!",
            "🔍 I can help analyze your code or suggest improvements.",
            "⚡ Need a quick code review? I'm here to help!",
            "🎯 I notice you're working hard - want me to suggest some optimizations?",
            "🤖 I'm your coding companion - always ready to assist!",
            "✨ I can help with debugging, refactoring, or new features.",
            "🚀 Ready to boost your productivity? Just ask!",
            "🔧 I'm monitoring for opportunities to help improve your code.",
            "💭 I have some ideas that might help with your current work.",
            "🎨 I can suggest better patterns or cleaner implementations.",
            "📊 Want me to analyze your code structure and suggest improvements?",
            "🔍 I'm always watching for ways to make your code better!",
            "⚡ I can help speed up your development process.",
            "🎯 I notice patterns in your code - want some suggestions?",
            "🤝 I'm here as your pair programming partner!"
        ]
        
        message = random.choice(suggestions)
        # Show immediately without probability delays - much more reactive
        self.show_observer_suggestion("idle_chatter", message)
    
    def show_observer_suggestion(self, observation_type, message):
        """Show a suggestion from the observer system"""
        # Show suggestions immediately with longer duration
        duration = 25000  # 25 seconds for suggestions (was much shorter)
        self.show_message(f"💡 {message}", duration, 'pointing')
        print(f"🔍 Observer suggestion ({observation_type}): {message}")
    
    def closeEvent(self, event):
        """Handle window close event"""
        if self.chat_bubble:
            self.chat_bubble.close()
        event.accept()

class ChatBubble(QWidget):
    """Chat bubble widget for displaying messages"""
    
    def __init__(self, message, parent_avatar, action_data=None):
        super().__init__()
        self.parent_avatar = parent_avatar
        self.action_data = action_data
        self.init_ui(message)
    
    def init_ui(self, message):
        """Initialize the chat bubble UI"""
        # Set window properties
        self.setWindowFlags(
            Qt.WindowType.WindowStaysOnTopHint | 
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowDoesNotAcceptFocus
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        
        # Create main layout
        layout = QVBoxLayout()
        layout.setContentsMargins(15, 10, 15, 10)
        layout.setSpacing(8)
        
        # Message text
        message_label = QLabel(message)
        message_label.setWordWrap(True)
        message_label.setMaximumWidth(280)
        message_label.setStyleSheet("""
            QLabel {
                color: white;
                font-size: 13px;
                font-weight: 500;
                background: transparent;
                padding: 8px;
            }
        """)
        layout.addWidget(message_label)
        
        # Add action buttons if this is an actionable message
        if self.action_data:
            self.add_action_buttons(layout)
        
        self.setLayout(layout)
        
        # Style the bubble
        self.setStyleSheet("""
            QWidget {
                background-color: rgba(52, 73, 94, 230);
                border: 2px solid rgba(127, 140, 141, 180);
                border-radius: 12px;
            }
        """)
        
        # Make bubble clickable to dismiss
        self.mousePressEvent = self.on_bubble_click
        
        # Set size
        self.setFixedWidth(300)
        self.adjustSize()
    
    def add_action_buttons(self, layout):
        """Add action buttons for actionable messages"""
        button_layout = QHBoxLayout()
        button_layout.setSpacing(8)
        
        # Action button
        action_button = QPushButton("✅ Do it!")
        action_button.setStyleSheet("""
            QPushButton {
                background-color: rgba(46, 204, 113, 200);
                color: white;
                border: none;
                border-radius: 6px;
                padding: 6px 12px;
                font-weight: bold;
                font-size: 10px;
            }
            QPushButton:hover {
                background-color: rgba(39, 174, 96, 255);
            }
            QPushButton:pressed {
                background-color: rgba(34, 153, 84, 255);
            }
        """)
        action_button.clicked.connect(self.execute_action)
        
        # Dismiss button
        dismiss_button = QPushButton("Skip")
        dismiss_button.setStyleSheet("""
            QPushButton {
                background-color: rgba(149, 165, 166, 150);
                color: white;
                border: none;
                border-radius: 6px;
                padding: 6px 12px;
                font-weight: bold;
                font-size: 10px;
            }
            QPushButton:hover {
                background-color: rgba(127, 140, 141, 200);
            }
            QPushButton:pressed {
                background-color: rgba(95, 106, 106, 255);
            }
        """)
        dismiss_button.clicked.connect(self.on_bubble_click)
        
        button_layout.addWidget(action_button)
        button_layout.addWidget(dismiss_button)
        layout.addLayout(button_layout)
    
    def execute_action(self):
        """Execute the suggested action"""
        if not self.action_data:
            return
            
        action_command = self.action_data.get('action_command')
        action_type = self.action_data.get('action_type')
        
        print(f"🚀 Executing action: {action_command} (type: {action_type})")
        
        # Hide the bubble first
        self.parent_avatar.hide_message()
        
        # Show feedback that action is starting
        self.parent_avatar.show_message(f"⚡ Running {action_type} action...", 3000, 'pointing')
        
        # Execute the action in a separate thread to avoid blocking UI
        import threading
        action_thread = threading.Thread(
            target=self._run_action_recipe, 
            args=(action_command,), 
            daemon=True
        )
        action_thread.start()
    
    def _run_action_recipe(self, action_command):
        """Run the action recipe in background"""
        try:
            import subprocess
            
            # Map action commands to recipe files
            recipe_path = f"actions/{action_command}.yaml"
            
            print(f"Running recipe: {recipe_path}")
            
            # Run the goose recipe
            result = subprocess.run([
                "goose", "run", "--no-session", 
                "--recipe", recipe_path
            ], capture_output=True, text=True, timeout=180)
            
            if result.returncode == 0:
                print(f"✅ Action {action_command} completed successfully")
                # Show success feedback
                self.parent_avatar.show_message("✅ Action completed! Check the results.", 5000, 'pointing')
            else:
                print(f"❌ Action {action_command} failed: {result.stderr}")
                self.parent_avatar.show_message("⚠️ Action had some issues. Check the logs.", 4000, 'idle')
                
        except subprocess.TimeoutExpired:
            print(f"⏰ Action {action_command} timed out")
            self.parent_avatar.show_message("⏰ Action is taking longer than expected...", 4000, 'idle')
        except Exception as e:
            print(f"Error running action {action_command}: {e}")
            self.parent_avatar.show_message("❌ Couldn't execute that action right now.", 3000, 'idle')
    
    def on_bubble_click(self, event=None):
        """Handle bubble clicks"""
        self.parent_avatar.hide_message()

# Global instances
avatar_instance = None
app_instance = None
avatar_communicator = None

def start_avatar_system():
    """Start the avatar system - Initialize Qt properly for main thread"""
    global avatar_instance, app_instance, avatar_communicator
    
    # Create QApplication if it doesn't exist (must be on main thread)
    if not QApplication.instance():
        app_instance = QApplication(sys.argv)
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
    
    return app_instance, avatar_instance

def process_qt_events():
    """Process Qt events without blocking - safe to call from any thread"""
    global app_instance
    if app_instance:
        try:
            app_instance.processEvents()
        except Exception as e:
            print(f"Qt event processing error: {e}")
            pass

def show_suggestion(observation_type, message):
    """Thread-safe function to show a suggestion via the avatar system"""
    global avatar_communicator
    if avatar_communicator:
        avatar_communicator.show_suggestion_signal.emit(observation_type, message)
    else:
        print(f"Avatar not initialized. Suggestion: {message}")

def show_message(message, duration=None, avatar_state='talking', action_data=None):
    """Thread-safe function to show a general message via the avatar system"""
    global avatar_communicator, avatar_instance
    if avatar_instance:
        # Use the avatar instance directly for better control
        avatar_instance.show_message(message, duration, avatar_state, action_data)
    elif avatar_communicator:
        # Fallback to communicator
        duration = duration or 20000  # Default 20 seconds
        avatar_communicator.show_message_signal.emit(message, duration, avatar_state)
    else:
        print(f"Avatar not initialized. Message: {message}")

def show_actionable_message(message, action_data, duration=None, avatar_state='pointing'):
    """Thread-safe function to show an actionable message with buttons"""
    global avatar_instance
    if avatar_instance:
        # Use default actionable duration (75 seconds) if not specified
        avatar_instance.show_message(message, duration, avatar_state, action_data)
    else:
        print(f"Avatar not initialized. Actionable message: {message}")

def set_avatar_state(state):
    """Thread-safe function to set avatar state"""
    global avatar_communicator
    if avatar_communicator:
        avatar_communicator.set_state_signal.emit(state)
    else:
        print(f"Avatar not initialized. State: {state}")

def show_error_message(error_msg, context=""):
    """Show an error message through the avatar"""
    global avatar_instance
    if avatar_instance:
        full_message = f"⚠️ Error detected: {error_msg}"
        if context:
            full_message += f" (Context: {context})"
        avatar_instance.show_message(full_message, duration=25000, avatar_state='talking')
        print(f"🚨 Avatar showing error: {error_msg}")
    else:
        print(f"Avatar not available for error: {error_msg}")

def show_process_status(status_msg, is_error=False):
    """Show process status updates through the avatar"""
    global avatar_instance
    if avatar_instance:
        if is_error:
            message = f"🔴 Process issue: {status_msg}"
            state = 'talking'
            duration = 25000
        else:
            message = f"🟢 Process update: {status_msg}"
            state = 'idle'
            duration = 15000
        
        avatar_instance.show_message(message, duration=duration, avatar_state=state)
        print(f"📊 Avatar showing status: {status_msg}")
    else:
        print(f"Avatar not available for status: {status_msg}")

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