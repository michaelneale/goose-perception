#!/usr/bin/env python3
"""
Goose Avatar Display System - Always visible floating avatar with chat bubbles
"""
import sys
import os
from pathlib import Path
from PyQt6.QtWidgets import (QApplication, QWidget, QLabel, QVBoxLayout, 
                            QPushButton, QHBoxLayout, QTextEdit, QMenu, QLineEdit)
from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QObject, QSize, QPoint, QRect, QRectF, QThread, QPointF
from PyQt6.QtGui import QPixmap, QColor, QPainter, QPen, QBrush, QFont, QTransform, QIcon, QAction, QFontMetrics, QMovie, QPainterPath
import random
import json
from datetime import datetime
import re
import time
import yaml
import subprocess

# Define the persistent path for user preferences
PERCEPTION_DIR = Path("~/.local/share/goose-perception").expanduser()
PREFS_PATH = PERCEPTION_DIR / "user_prefs.yaml"

def get_user_prefs():
    """Load user preferences from the YAML file."""
    if not PREFS_PATH.exists():
        return {}
    try:
        with open(PREFS_PATH, "r") as f:
            return yaml.safe_load(f) or {}
    except (yaml.YAMLError, IOError) as e:
        print(f"Error loading user preferences: {e}", file=sys.stderr)
        return {}

def save_user_prefs(prefs):
    """Save user preferences to the YAML file."""
    try:
        PERCEPTION_DIR.mkdir(parents=True, exist_ok=True)
        with open(PREFS_PATH, "w") as f:
            yaml.dump(prefs, f, default_flow_style=False)
    except IOError as e:
        print(f"Error saving user preferences: {e}", file=sys.stderr)

class ChatBubble(QWidget):
    """Custom widget for the chat bubble with a specific shape and layout."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.parent_avatar = parent
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowStaysOnTopHint |
            Qt.WindowType.Tool 
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating, True)
        
        self.layout = QVBoxLayout()
        self.setLayout(self.layout)

        self.content_widget = None
        self.fixed_width = 350

    def set_content_widget(self, widget, fixed_width=350):
        if self.content_widget:
            self.layout.removeWidget(self.content_widget)
            self.content_widget.deleteLater()
        
        self.content_widget = widget
        self.layout.addWidget(self.content_widget)
        self.fixed_width = fixed_width
        self.adjust_size_and_position()

    def adjust_size_and_position(self):
        self.setFixedWidth(self.fixed_width)
        self.adjustSize()

        if self.parent_avatar:
            self.parent_avatar.update_avatar_display()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        
        rect = self.rect().adjusted(0, 0, -1, -1)
        
        path = QPainterPath()
        path.addRoundedRect(QRectF(rect), 12, 12)
        
        painter.setBrush(QBrush(QColor(52, 73, 94, 230)))
        painter.setPen(QPen(QColor(127, 140, 141, 180), 2))
        painter.drawPath(path)

class AvatarCommunicator(QObject):
    """Thread-safe communicator for avatar system"""
    # Signals for thread-safe communication
    show_message_signal = pyqtSignal(str, int, str)  # message, duration, avatar_state
    show_suggestion_signal = pyqtSignal(str, str)    # observation_type, message
    hide_message_signal = pyqtSignal()
    set_state_signal = pyqtSignal(str)               # state
    # New signal for just-in-time preference requests
    show_preference_prompt_signal = pyqtSignal(dict, dict)

    def __init__(self):
        super().__init__()

class GooseAvatar(QWidget):
    """Main avatar widget that stays always visible"""
    
    def __init__(self):
        super().__init__()
        self.app = None
        self.current_screen = None
        self.relative_position = (0.5, 0.5)  # Center of screen by default
        self.avatar_x = 0
        self.avatar_y = 0
        self.is_visible = True
        self.current_state = 'idle'
        self.avatar_images = {}
        self.avatar_pixmap = None
        self.chat_bubble = None
        self.is_showing_message = False
        self.communicator = None
        
        # Message queue system - replaces simple message_queue list
        self.message_queue = []  # Queue of messages to display
        self.is_processing_queue = False  # Flag to prevent queue processing conflicts
        self.queue_timer = QTimer()  # Timer for queue processing
        self.queue_timer.timeout.connect(self.process_message_queue)
        self.queue_timer.setSingleShot(True)
        self.message_spacing_delay = 2000  # 2 seconds between messages
        
        # Dragging state
        self.drag_start_pos = None
        self.is_dragging = False
        
        # Idle behavior settings - more thoughtful and less aggressive
        self.idle_check_interval = 45000  # Check every 45 seconds (was 15)
        self.idle_suggestion_chance = 0.15  # 15% chance to show suggestion (was 0.3)
        self.last_suggestion_time = 0
        self.min_suggestion_interval = 180  # Minimum 3 minutes between suggestions (was 45)
        
        # Track shown suggestions to reduce immediate repetition
        self.recent_suggestions = []
        self.max_recent_suggestions = 8  # Remember last 8 suggestions to avoid repeating
        
        # Personality system
        self.current_personality = "comedian"  # Default personality
        self.personalities = self.load_personalities()
        self.personality_menu_open = False  # Track if personality menu is open
        
        # Load saved personality setting if available
        saved_personality = self.load_personality_setting()
        if saved_personality:
            self.current_personality = saved_personality
        
        # Timers
        self.hide_timer = QTimer()
        self.hide_timer.timeout.connect(self.hide_message)
        self.hide_timer.setSingleShot(True)
        
        # Auto-dismiss timer for actionable messages
        self.auto_dismiss_timer = QTimer()
        self.auto_dismiss_timer.timeout.connect(self.auto_dismiss_actionable)
        self.auto_dismiss_timer.setSingleShot(True)
        
        # Emergency backup timer - force dismiss any message stuck longer than 2 minutes
        self.emergency_timer = QTimer()
        self.emergency_timer.timeout.connect(self.force_dismiss_message)
        self.emergency_timer.setSingleShot(True)
        
        self.idle_timer = QTimer()
        self.idle_timer.timeout.connect(self.check_for_suggestions)
        
        # Load avatar images
        self.load_avatar_images()
        self.init_ui()
        
    def set_interactive_mode(self, interactive):
        """Toggle window flags to allow/disallow keyboard focus."""
        if interactive:
            print("Entering interactive mode for onboarding.")
            # Stop the Spaces refresh timer to prevent focus stealing
            if hasattr(self, 'spaces_timer'):
                self.spaces_timer.stop()
            # Flags that allow focus but keep the window as a floating tool
            flags = (
                Qt.WindowType.WindowStaysOnTopHint |
                Qt.WindowType.FramelessWindowHint |
                Qt.WindowType.Tool  # Behaves as a floating tool window
            )
            self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating, False)
            self.setWindowFlags(flags)
            self.setFocusPolicy(Qt.FocusPolicy.StrongFocus) # Allow the main window to get focus
        else:
            print("Exiting interactive mode.")
            # Restore default non-interactive flags
            flags = (
                Qt.WindowType.WindowStaysOnTopHint |
                Qt.WindowType.FramelessWindowHint |
                Qt.WindowType.WindowDoesNotAcceptFocus
            )
            self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating, True)
            self.setWindowFlags(flags)
            self.setFocusPolicy(Qt.FocusPolicy.NoFocus)
            # Restart the Spaces refresh timer
            if hasattr(self, 'spaces_timer'):
                self.spaces_timer.start(1000)

        # Re-show the window for flags to apply
        self.show()
        if interactive:
            self.activateWindow() # Bring it to the front
            self.raise_()

        # Start the idle checking loop
        self.idle_timer.start(self.idle_check_interval)
        
        # For macOS Spaces support - ensure avatar appears on current Space
        self.spaces_timer = QTimer()
        self.spaces_timer.timeout.connect(self.refresh_avatar_for_spaces)
        self.spaces_timer.start(1000)  # Refresh every 1 second for Space switching
    
    def onboard_user_if_needed(self):
        self.user_prefs = get_user_prefs()
        if self.user_prefs:
            self.is_onboarding = False
            return
        
        self.is_onboarding = True
        self.set_interactive_mode(True)
        self.onboarding_questions = [
            {"key": "team_channel", "question": "What is your main team Slack channel for project or daily updates?", "type": "text", "required": True},
            {"key": "announcement_channel", "question": "Which Slack channel should Goose use for broader announcements? (optional)", "type": "text", "required": False},
            {"key": "send_email_updates", "question": "Should Goose send email updates? (yes/no)", "type": "yesno", "required": True},
            {"key": "email_recipients", "question": "Who should receive email updates? (comma-separated)", "type": "text", "required": False, "condition": lambda prefs: prefs.get("send_email_updates", False)},
            {"key": "notification_urgency", "question": "What types of events should trigger an immediate notification? (e.g., direct mentions, urgent blockers, leadership emails) (optional)", "type": "text", "required": False},
            {"key": "reminders_enabled", "question": "Do you want reminders for unfinished tasks, PR reviews, or follow-ups? (yes/no)", "type": "yesno", "required": True},
            {"key": "preferred_update_time", "question": "What time of day should Goose post updates or send emails? (optional)", "type": "text", "required": False}
        ]
        self.current_onboarding_index = 0
        self.show_next_onboarding_question()

    def show_next_onboarding_question(self):
        # Skip conditional questions if needed
        while self.current_onboarding_index < len(self.onboarding_questions):
            q = self.onboarding_questions[self.current_onboarding_index]
            if "condition" in q and not q["condition"](self.user_prefs):
                self.current_onboarding_index += 1
            else:
                break
        if self.current_onboarding_index >= len(self.onboarding_questions):
            # Onboarding complete
            save_user_prefs(self.user_prefs)
            self.is_onboarding = False
            self.set_interactive_mode(False)
            self.show_message("✅ Setup complete! Your preferences are saved.", 5000, 'talking')
            return
        q = self.onboarding_questions[self.current_onboarding_index]
        self.show_onboarding_bubble(q)

    def show_onboarding_bubble(self, question_obj):
        self.clear_bubble_content()
        # Use the same layout and style as create_bubble_content
        bubble_widget = QWidget()
        bubble_widget.setStyleSheet("""
            QWidget {
                background-color: rgba(52, 73, 94, 230);
                border: 2px solid rgba(127, 140, 141, 180);
                border-radius: 12px;
            }
        """)
        layout = QVBoxLayout()
        layout.setContentsMargins(15, 10, 15, 10)
        layout.setSpacing(8)
        # Question label (styled like actionable message)
        question_label = QLabel(question_obj["question"])
        question_label.setWordWrap(True)
        font = QFont()
        font.setPointSize(13)
        font.setWeight(QFont.Weight.Medium)
        question_label.setFont(font)
        question_label.setFixedWidth(320)
        question_label.setStyleSheet("""
            QLabel {
                color: white;
                font-size: 13px;
                font-weight: 500;
                background: transparent;
                padding: 8px;
                border: none;
            }
        """)
        layout.addWidget(question_label)
        # Input field (extra row)
        input_field = QLineEdit()
        input_field.setFixedWidth(300)
        input_field.setMinimumHeight(32)
        input_field.setStyleSheet("""
            QLineEdit {
                background-color: white;
                color: #222;
                border: 1px solid #bbb;
                border-radius: 6px;
                padding: 6px 10px;
                font-size: 13px;
            }
        """)
        layout.addWidget(input_field, alignment=Qt.AlignmentFlag.AlignHCenter)
        # Buttons (styled like actionable suggestion buttons, but larger font)
        button_layout = QHBoxLayout()
        button_layout.setSpacing(8)
        submit_button = QPushButton("Submit")
        submit_button.setFixedWidth(120)
        submit_button.setMinimumHeight(32)
        submit_button.setStyleSheet("""
            QPushButton {
                background-color: rgba(46, 204, 113, 200);
                color: white;
                border: none;
                border-radius: 6px;
                padding: 6px 12px;
                font-weight: bold;
                font-size: 12px;
            }
            QPushButton:hover {
                background-color: rgba(39, 174, 96, 255);
            }
            QPushButton:pressed {
                background-color: rgba(34, 153, 84, 255);
            }
        """)
        button_layout.addWidget(submit_button)
        if not question_obj.get("required", True):
            skip_button = QPushButton("Skip")
            skip_button.setFixedWidth(120)
            skip_button.setMinimumHeight(32)
            skip_button.setStyleSheet("""
                QPushButton {
                    background-color: rgba(149, 165, 166, 150);
                    color: white;
                    border: none;
                    border-radius: 6px;
                    padding: 6px 12px;
                    font-weight: bold;
                    font-size: 12px;
                }
                QPushButton:hover {
                    background-color: rgba(127, 140, 141, 200);
                }
                QPushButton:pressed {
                    background-color: rgba(95, 106, 106, 255);
                }
            """)
            button_layout.addWidget(skip_button)
            def on_skip():
                self.user_prefs[question_obj["key"]] = ""
                self.current_onboarding_index += 1
                self.show_next_onboarding_question()
            skip_button.clicked.connect(on_skip)
        layout.addLayout(button_layout)
        input_field.returnPressed.connect(submit_button.click)
        input_field.setFocus()
        if question_obj["type"] == "yesno":
            input_field.setPlaceholderText("yes or no")
        def on_submit():
            answer = input_field.text().strip()
            if question_obj["type"] == "yesno":
                self.user_prefs[question_obj["key"]] = answer.lower() in ["yes", "y"]
            else:
                self.user_prefs[question_obj["key"]] = answer
            self.current_onboarding_index += 1
            self.show_next_onboarding_question()
        submit_button.clicked.connect(on_submit)
        bubble_widget.setLayout(layout)
        bubble_widget.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        input_field.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        input_field.setFocus()
        self.clear_bubble_content()
        self.bubble_layout.addWidget(bubble_widget)
        # --- NEW: Adjust size and set container geometry like actionable suggestions ---
        bubble_widget.adjustSize()
        bubble_widget.updateGeometry()
        bubble_size = bubble_widget.sizeHint()
        container_width = 350
        container_height = min(bubble_size.height() + 20, 420)
        self.bubble_container.setGeometry(10, max(10, 200 - container_height + 20), container_width, container_height)
        # --- END NEW ---
        self.bubble_container.setFixedWidth(350)
        self.bubble_container.setMinimumHeight(0)
        self.bubble_container.setMaximumHeight(400)
        self.bubble_container.show()
        input_field.setFocus()
        self.activateWindow()
    
    def ask_onboarding_question(self, question):
        import subprocess
        script = f'''
        tell application "System Events"
            activate
            set userInput to text returned of (display dialog "{question}" default answer "" with title "Goose Onboarding" buttons {{"Cancel", "OK"}} default button "OK")
            return userInput
        end tell
        '''
        result = subprocess.run([
            "osascript", "-e", script
        ], capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout.strip()
        else:
            return ""
    
    def load_personalities(self):
        """Load personality definitions from personalities.json"""
        try:
            personalities_path = Path(__file__).parent / "personalities.json"
            if personalities_path.exists():
                with open(personalities_path, 'r') as f:
                    data = json.load(f)
                    personalities = data.get("personalities", {})
                    # Set default personality if specified
                    default_personality = data.get("default_personality", "comedian")
                    if default_personality in personalities:
                        self.current_personality = default_personality
                    return personalities
            else:
                print("⚠️ personalities.json not found, using default personality")
                return {}
        except Exception as e:
            print(f"Error loading personalities: {e}")
            return {}
    
    def get_current_personality_data(self):
        """Get the current personality data"""
        return self.personalities.get(self.current_personality, {})
    
    def set_personality(self, personality_key):
        """Set the current personality (simple version without UI effects)"""
        if personality_key in self.personalities:
            self.current_personality = personality_key
            personality_data = self.personalities[personality_key]
            name = personality_data.get('name', personality_key.title())
            emoji = personality_data.get('emoji', '🤖')
            print(f"🎭 Personality set to: {name} {emoji}")
        else:
            print(f"⚠️ Unknown personality: {personality_key}")
        
    def connect_communicator(self, communicator):
        """Connect to the thread-safe communicator"""
        self.communicator = communicator
        if communicator:
            communicator.show_message_signal.connect(self.show_message)
            communicator.show_suggestion_signal.connect(self.show_observer_suggestion)
            communicator.hide_message_signal.connect(self.hide_message)
            communicator.set_state_signal.connect(self.set_avatar_state)
            communicator.show_preference_prompt_signal.connect(self.ask_and_save_preference)
        
    def load_avatar_images(self):
        """Load avatar images from the avatar directory"""
        self.avatar_images = {}
        avatar_dir = Path(__file__).parent
        
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
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating, True)
        
        # Make window appear on all macOS Spaces
        self.setup_spaces_behavior()
        
        # Create a flexible window that accommodates fixed-width bubbles with variable height
        # Window size optimized for fixed width, variable height content
        self.setFixedSize(460, 280)  # Increased height from 230 to 280 for taller bubbles
        
        # Create main widget with absolute positioning to avoid layout jumping
        self.main_widget = QWidget()
        self.main_widget.setStyleSheet("QWidget { background: transparent; }")
        
        # Create container for bubble (initially hidden) - bottom-right anchored positioning
        self.bubble_container = QWidget(self.main_widget)
        self.bubble_container.setStyleSheet("QWidget { background: transparent; }")
        # Container positioned near avatar, will be dynamically adjusted for upward growth
        self.bubble_container.setGeometry(10, 120, 370, 120)  # Initial position - will be recalculated
        self.bubble_container.hide()  # Hidden by default
        
        # Create the bubble layout once and reuse it
        self.bubble_layout = QVBoxLayout()
        self.bubble_layout.setContentsMargins(10, 10, 10, 10)
        self.bubble_container.setLayout(self.bubble_layout)
        
        # Create container for avatar - positioned at bottom right
        self.avatar_container = QWidget(self.main_widget)
        self.avatar_container.setStyleSheet("QWidget { background: transparent; }")
        self.avatar_container.setGeometry(380, 200, 80, 80)  # Updated position for taller window
        
        # Avatar label
        avatar_layout = QVBoxLayout()
        avatar_layout.setContentsMargins(0, 0, 0, 0)
        
        self.avatar_label = QLabel()
        if self.avatar_pixmap:
            self.avatar_label.setPixmap(self.avatar_pixmap)
        self.avatar_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.avatar_label.setStyleSheet("QLabel { background: transparent; }")
        
        # Make avatar clickable and draggable
        self.avatar_label.mousePressEvent = self.on_mouse_press
        self.avatar_label.mouseMoveEvent = self.on_mouse_move
        self.avatar_label.mouseReleaseEvent = self.on_mouse_release
        self.avatar_label.setCursor(Qt.CursorShape.PointingHandCursor)
        
        avatar_layout.addWidget(self.avatar_label)
        self.avatar_container.setLayout(avatar_layout)
        
        # Set the main widget as the layout
        main_layout = QVBoxLayout()
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.addWidget(self.main_widget)
        self.setLayout(main_layout)
        
        # Position the avatar window
        self.position_avatar()
        
        # Start the idle checking loop
        self.idle_timer.start(self.idle_check_interval)
        
        # For macOS Spaces support - ensure avatar appears on current Space
        self.spaces_timer = QTimer()
        self.spaces_timer.timeout.connect(self.refresh_avatar_for_spaces)
        self.spaces_timer.start(1000)  # Refresh every 1 second for Space switching
    
    def position_avatar(self):
        """Position the avatar window on the primary screen"""
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
        # Account for the window size (460x280) and position so avatar appears in the right place
        x = screen_rect.x() + int(screen_rect.width() * self.relative_position[0]) - 80  # Account for avatar being on right side of window
        y = screen_rect.y() + int(screen_rect.height() * self.relative_position[1]) - 80  # Account for avatar being at bottom of window
        
        self.move(x, y)
        self.avatar_x = x
        self.avatar_y = y
        
        # Only print position updates when position actually changes significantly
        if not hasattr(self, '_last_logged_pos') or abs(self._last_logged_pos[0] - x) > 50 or abs(self._last_logged_pos[1] - y) > 50:
            print(f"🖥️ Moved avatar to screen at ({x}, {y})")
            self._last_logged_pos = (x, y)
    
    def refresh_avatar_for_spaces(self):
        """Refresh avatar to ensure it appears on the current macOS Space"""
        if not self.is_visible or self.is_dragging or self.personality_menu_open:  # Don't refresh while dragging or menu is open!
            return
            
        try:
            # Re-render the avatar to ensure it appears on current Space
            # This is more aggressive than just show() - we hide and show again
            self.hide()
            self.show()
            # NO raise_() call - this steals focus on macOS!
            
            # Only reposition if we're not currently being dragged
            if not self.is_dragging:
                # Always get a fresh screen reference to avoid deleted QScreen objects
                if self.app:
                    try:
                        # Get current screen based on avatar position
                        avatar_point = self.pos()
                        fresh_screen = self.app.screenAt(avatar_point)
                        if fresh_screen:
                            self.current_screen = fresh_screen  # Update cached reference
                            self.position_on_screen(fresh_screen)
                        else:
                            # Fallback to primary screen if position-based lookup fails
                            primary_screen = self.app.primaryScreen()
                            if primary_screen:
                                self.current_screen = primary_screen
                                self.position_on_screen(primary_screen)
                    except RuntimeError as e:
                        if "wrapped C/C++ object" in str(e) or "has been deleted" in str(e):
                            print("🖥️ Screen object was deleted, refreshing screen reference")
                            # Screen was deleted, get a fresh primary screen reference
                            try:
                                primary_screen = self.app.primaryScreen()
                                if primary_screen:
                                    self.current_screen = primary_screen
                                    self.position_on_screen(primary_screen)
                            except Exception:
                                # If we can't get any screen, just skip repositioning
                                pass
                        else:
                            raise  # Re-raise if it's a different RuntimeError
            
            # Also refresh the avatar display to ensure clean rendering
            self.update_avatar_display()
                
        except Exception as e:
            # Only print errors that aren't the common QScreen deletion issue
            if not ("wrapped C/C++ object" in str(e) or "has been deleted" in str(e)):
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
        if not self.app:
            return
            
        try:
            # Always get a fresh screen reference to avoid deleted QScreen objects
            avatar_point = self.pos()
            current_screen = self.app.screenAt(avatar_point)
            
            if current_screen:
                self.current_screen = current_screen  # Update cached reference
                screen_rect = current_screen.availableGeometry()
                
                # Calculate relative position (0.0 to 1.0)
                # Must match the offsets used in position_on_screen() method
                rel_x = (self.avatar_x - screen_rect.x() + 80) / screen_rect.width()  # +80 to match position_on_screen offset
                rel_y = (self.avatar_y - screen_rect.y() + 80) / screen_rect.height()  # +80 to match position_on_screen offset
                
                # Clamp to valid range
                rel_x = max(0.0, min(1.0, rel_x))
                rel_y = max(0.0, min(1.0, rel_y))
                
                self.relative_position = (rel_x, rel_y)
            else:
                # Fallback to primary screen if position-based lookup fails
                primary_screen = self.app.primaryScreen()
                if primary_screen:
                    self.current_screen = primary_screen
                    screen_rect = primary_screen.availableGeometry()
                    
                    rel_x = (self.avatar_x - screen_rect.x() + 80) / screen_rect.width()
                    rel_y = (self.avatar_y - screen_rect.y() + 80) / screen_rect.height()
                    
                    rel_x = max(0.0, min(1.0, rel_x))
                    rel_y = max(0.0, min(1.0, rel_y))
                    
                    self.relative_position = (rel_x, rel_y)
                    
        except RuntimeError as e:
            if "wrapped C/C++ object" in str(e) or "has been deleted" in str(e):
                # Screen object was deleted, try to get primary screen
                try:
                    primary_screen = self.app.primaryScreen()
                    if primary_screen:
                        self.current_screen = primary_screen
                        # Use default relative position if we can't calculate
                        self.relative_position = (0.5, 0.5)
                except Exception:
                    # If all else fails, use default position
                    self.relative_position = (0.5, 0.5)
            else:
                raise
        except Exception:
            # On any other error, just keep the current relative position
            pass
    
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
        if not self.app:
            return False
            
        try:
            # Always get a fresh screen reference to avoid deleted QScreen objects
            avatar_point = self.pos()
            current_screen = self.app.screenAt(avatar_point)
            if current_screen:
                screen_rect = current_screen.availableGeometry()
                # Flip if avatar is on the right half of its current screen
                return self.avatar_x > screen_rect.x() + screen_rect.width() / 2
            else:
                # Fallback to primary screen
                primary_screen = self.app.primaryScreen()
                if primary_screen:
                    screen_rect = primary_screen.availableGeometry()
                    return self.avatar_x > screen_rect.x() + screen_rect.width() / 2
        except RuntimeError as e:
            if "wrapped C/C++ object" in str(e) or "has been deleted" in str(e):
                # Screen object deleted, default to not flipping
                return False
            else:
                raise
        except Exception:
            # On any error, default to not flipping
            return False
            
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
        # Suppress all messages except onboarding if onboarding is in progress
        if getattr(self, 'is_onboarding', False):
            # Only allow onboarding bubbles
            if not (hasattr(self, 'onboarding_questions') and any(q["question"] in message for q in self.onboarding_questions)):
                print("[Onboarding] Suppressing message:", message)
                return
        # Check if this is an encoded actionable message (new base64 format)
        if message.startswith("ACTIONABLE_B64:"):
            try:
                # Parse the base64 encoded format: "ACTIONABLE_B64:{action_b64}:{actual_message}"
                import json
                import base64
                parts = message.split(":", 2)  # Split only on first 2 colons
                if len(parts) == 3:
                    action_b64 = parts[1]
                    actual_message = parts[2]
                    action_json = base64.b64decode(action_b64).decode('utf-8')
                    action_data = json.loads(action_json)
                    message = actual_message
                    print(f"🔧 Decoded actionable message: '{actual_message}'")
                    print(f"🔧 Action data: {action_data}")
                else:
                    print(f"❌ Invalid actionable message format: {len(parts)} parts instead of 3")
            except Exception as e:
                print(f"❌ Error decoding actionable message: {e}")
                print(f"❌ Raw message: {message}")
                # Fall back to showing the raw message without action buttons
                message = message.replace("ACTIONABLE_B64:", "")
                action_data = None
        # Check if this is an encoded actionable message (legacy format - for backward compatibility)
        elif message.startswith("ACTIONABLE:"):
            try:
                # Parse the encoded message format: "ACTIONABLE:{action_json}:{actual_message}"
                import json
                parts = message.split(":", 2)  # Split only on first 2 colons
                if len(parts) == 3:
                    action_json = parts[1]
                    actual_message = parts[2]
                    action_data = json.loads(action_json)
                    message = actual_message
                    print(f"🔧 Decoded legacy actionable message: '{actual_message}'")
                    print(f"🔧 Action data: {action_data}")
                else:
                    print(f"❌ Invalid legacy actionable message format: {len(parts)} parts instead of 3")
            except Exception as e:
                print(f"❌ Error decoding legacy actionable message: {e}")
                print(f"❌ Raw message: {message}")
                # Fall back to showing the raw message without action buttons
                message = message.replace("ACTIONABLE:", "")
                action_data = None
        
        # Determine priority based on action_data
        priority = 'high' if action_data else 'normal'
        
        # Queue the message instead of showing immediately
        self.queue_message_for_display(message, duration, avatar_state, action_data, priority)
    
    def clear_bubble_content(self):
        """Clear existing bubble content from layout"""
        # Remove all widgets from the bubble layout
        while self.bubble_layout.count():
            child = self.bubble_layout.takeAt(0)
            if child.widget():
                child.widget().deleteLater()
        
        # Clean up the chat_bubble reference
        if self.chat_bubble:
            self.chat_bubble = None
    
    def create_bubble_content(self, message, action_data=None):
        """Create the bubble content widget with fixed width and responsive height"""
        # Check if this is an action menu
        if action_data and action_data.get('type') == 'action_menu':
            return self.create_action_menu_bubble(action_data.get('greeting', message), action_data.get('actions', []))
        
        bubble_widget = QWidget()
        bubble_widget.setStyleSheet("""
            QWidget {
                background-color: rgba(52, 73, 94, 230);
                border: 2px solid rgba(127, 140, 141, 180);
                border-radius: 12px;
            }
        """)
        
        layout = QVBoxLayout()
        layout.setContentsMargins(15, 10, 15, 10)
        layout.setSpacing(8)
        
        # Message text - fixed width with responsive height
        # Convert newlines to HTML breaks and use RichText for proper rendering
        message_html = message.replace('\n', '<br/>')
        message_label = QLabel(message_html)
        message_label.setTextFormat(Qt.TextFormat.RichText)
        message_label.setWordWrap(True)
        
        # Use Qt's text measurement for font setup
        font = QFont()
        font.setPointSize(13)
        font.setWeight(QFont.Weight.Medium)
        message_label.setFont(font)
        
        # Fixed width - consistent across all messages
        fixed_width = 320  # Consistent bubble width
        message_label.setFixedWidth(fixed_width)
        
        message_label.setStyleSheet("""
            QLabel {
                color: white;
                font-size: 13px;
                font-weight: 500;
                background: transparent;
                padding: 8px;
                border: none;
            }
        """)
        layout.addWidget(message_label)
        
        # Add action buttons if this is an actionable message
        if action_data:
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
            action_button.clicked.connect(lambda: self.execute_action(action_data))
            
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
            dismiss_button.clicked.connect(self.hide_message)
            
            button_layout.addWidget(action_button)
            button_layout.addWidget(dismiss_button)
            layout.addLayout(button_layout)
        
        # Make bubble clickable to dismiss with robust error handling
        def safe_dismiss(event):
            try:
                print("👆 Bubble clicked - dismissing message")
                self.hide_message()
            except Exception as e:
                print(f"❌ Error dismissing via click: {e}")
                # Fallback to force dismiss
                self.force_dismiss_message()
        
        bubble_widget.mousePressEvent = safe_dismiss
        
        # Also add keyboard shortcut for emergency dismiss (Escape key)
        def keypress_handler(event):
            try:
                if event.key() == Qt.Key.Key_Escape:
                    print("⌨️ Escape key pressed - dismissing message")
                    self.hide_message()
                else:
                    # Pass other keys to default handler
                    QWidget.keyPressEvent(bubble_widget, event)
            except Exception as e:
                print(f"❌ Error in keypress handler: {e}")
                self.force_dismiss_message()
        
        bubble_widget.keyPressEvent = keypress_handler
        bubble_widget.setFocusPolicy(Qt.FocusPolicy.StrongFocus)  # Allow keyboard focus
        
        bubble_widget.setLayout(layout)
        
        # Fixed width, variable height
        bubble_width = fixed_width + 30  # Account for padding
        bubble_widget.setFixedWidth(bubble_width)
        bubble_widget.setMinimumHeight(60)   # Minimum height for small messages
        bubble_widget.setMaximumHeight(400)  # Increased max height for long messages
        
        # Force proper size calculation
        bubble_widget.adjustSize()
        bubble_widget.updateGeometry()
        
        # Get the actual size after sizing
        actual_size = bubble_widget.sizeHint()
        print(f"📏 Fixed width bubble: {len(message)} chars → {bubble_width}x{actual_size.height()}")
        
        return bubble_widget
    
    def execute_action(self, action_data):
        """Execute the suggested action"""
        if not action_data:
            return
            
        action_command = action_data.get('action_command')
        action_type = action_data.get('action_type')
        
        print(f"🚀 Executing action: {action_command} (type: {action_type})")
        
        # Hide the bubble first
        self.hide_message()
        
        # Show feedback that action is starting
        self.show_message(f"⚡ Running {action_type} action...", 3000, 'pointing')
        
        # Execute the action in a separate thread to avoid blocking UI
        import threading
        action_thread = threading.Thread(
            target=self._run_action_recipe, 
            args=(action_command, action_data) # Pass full action_data for retry
        )
        action_thread.start()
    
    def _run_action_recipe(self, command, action_data_to_retry):
        """Run the action recipe as a subprocess and handle output"""
        try:
            # Construct the full command to run agent.py
            agent_script_path = Path(__file__).parent.parent / "agent.py"
            full_command = [sys.executable, str(agent_script_path), "run-action", command]
            
            # Add parameters if they exist – they must be sent via the --params flag
            params = action_data_to_retry.get('parameters')
            if params:
                # Ensure we pass a JSON string representation
                try:
                    params_json = json.dumps(params)
                except TypeError:
                    # If params is already a JSON‐serialisable string, fall back
                    params_json = str(params)

                full_command.extend(["--params", params_json])

            # Run the command
            result = subprocess.run(
                full_command,
                capture_output=True,
                text=True,
                check=False  # Don't raise exception on non-zero exit
            )
            
            stdout = result.stdout.strip()
            stderr = result.stderr.strip()
            
            print(f"--- Action Output: {command} ---")
            if stdout:
                print(f"STDOUT:\n{stdout}")
            if stderr:
                print(f"STDERR:\n{stderr}")
            print("--- End Action Output ---")

            # Check if the action requires a preference
            if stdout.startswith("NEEDS_PREF:"):
                try:
                    pref_data_str = stdout.replace("NEEDS_PREF:", "", 1)
                    pref_data = json.loads(pref_data_str)
                    # Use a signal to safely call the UI function from this thread
                    self.communicator.show_preference_prompt_signal.emit(pref_data, action_data_to_retry)
                except (json.JSONDecodeError, KeyError) as e:
                    print(f"❌ Error parsing NEEDS_PREF data: {e}")
                    # Use show_message for error feedback
                    self.show_message(f"❌ Action failed: could not parse preference request.", 5000, 'idle')
            elif result.returncode != 0:
                # Use show_message for error feedback
                self.show_message(f"❌ Action '{command}' failed. Check logs.", 5000, 'idle')
            else:
                # On success, maybe show a confirmation
                self.show_message("✅ Action completed!", 4000, 'idle')

        except FileNotFoundError:
            self.show_message(f"❌ Error: agent.py not found.", 5000, 'idle')
        except Exception as e:
            error_message = f"An unexpected error occurred while running action '{command}'."
            print(f"❌ {error_message}\n{e}")
            self.show_message(f"❌ {error_message}", 5000, 'idle')

    def _log_action_result(self, command, stdout, stderr):
        """Log the result of an action to a file"""
        log_dir = PERCEPTION_DIR / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = log_dir / f"{command}.log"
        with open(log_path, "a") as f:
            f.write(f"--- {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ---\n")
            f.write(f"Command: {command}\n")
            f.write("--- Action Output ---\n")
            f.write(stdout)
            f.write("\n--- End Action Output ---\n\n")
            if stderr:
                f.write("--- Action Error ---\n")
                f.write(stderr)
                f.write("\n--- End Action Error ---\n\n")
    
    def hide_message(self):
        """Hide the current message"""
        try:
            print("🔄 Hiding message...")
            
            # Clear bubble content from the layout
            self.clear_bubble_content()
            
            # Hide the bubble container
            if self.bubble_container:
                self.bubble_container.hide()
            
            # Reset avatar to idle state
            self.set_avatar_state('idle')
            
            # Update avatar display (removes any flipping)
            self.update_avatar_display()
            
            self.is_showing_message = False
            
            # Stop all timers
            if self.hide_timer:
                self.hide_timer.stop()
            if self.auto_dismiss_timer:
                self.auto_dismiss_timer.stop()
            if self.emergency_timer:
                self.emergency_timer.stop()
            
            print("✅ Message hidden successfully")
            
            # Process next message in queue
            self.on_message_hidden()
                
        except Exception as e:
            print(f"❌ Error hiding message: {e}")
            # Force reset state even if there's an error
            self.is_showing_message = False
            try:
                if self.bubble_container:
                    self.bubble_container.hide()
                if self.hide_timer:
                    self.hide_timer.stop()
                if self.auto_dismiss_timer:
                    self.auto_dismiss_timer.stop()
                if self.emergency_timer:
                    self.emergency_timer.stop()
                # Still try to process queue even on error
                self.on_message_hidden()
            except Exception as inner_e:
                print(f"❌ Error in force reset: {inner_e}")
    
    def force_dismiss_message(self):
        """Force dismiss any stuck message - emergency cleanup"""
        print("🚨 Force dismissing stuck message")
        try:
            # Force hide everything
            self.is_showing_message = False
            
            # Clear all bubble content aggressively
            if hasattr(self, 'bubble_container') and self.bubble_container:
                self.bubble_container.hide()
                # Remove all children
                for child in self.bubble_container.findChildren(QWidget):
                    try:
                        child.deleteLater()
                    except:
                        pass
            
            # Clear layout
            if hasattr(self, 'bubble_layout') and self.bubble_layout:
                while self.bubble_layout.count():
                    try:
                        child = self.bubble_layout.takeAt(0)
                        if child and child.widget():
                            child.widget().deleteLater()
                    except:
                        pass
            
            # Stop all timers
            for timer_name in ['hide_timer', 'auto_dismiss_timer', 'emergency_timer']:
                if hasattr(self, timer_name):
                    timer = getattr(self, timer_name)
                    if timer:
                        try:
                            timer.stop()
                        except:
                            pass
            
            # Reset chat bubble reference
            self.chat_bubble = None
            
            # Reset avatar state
            self.set_avatar_state('idle')
            self.update_avatar_display()
            
            print("✅ Force dismiss completed")
            
            # Process next message in queue
            self.on_message_hidden()
            
        except Exception as e:
            print(f"❌ Error in force dismiss: {e}")
            # Still try to process queue even on error
            try:
                self.on_message_hidden()
            except:
                pass
    
    def emergency_reset(self):
        """Emergency reset for completely stuck UI"""
        print("🆘 Emergency reset triggered")
        self.force_dismiss_message()
        # Clear message queue
        self.message_queue = []
        print("✅ Emergency reset completed")
    
    def auto_dismiss_actionable(self):
        """Auto-dismiss actionable messages after timeout"""
        if self.chat_bubble and hasattr(self.chat_bubble, 'action_data') and self.chat_bubble.action_data:
            print("⏰ Auto-dismissing actionable message after timeout")
            # Simulate clicking "Skip" by hiding the message
            self.hide_message()
    
    def on_mouse_press(self, event):
        """Handle mouse press for dragging and clicking"""
        if event.button() == Qt.MouseButton.LeftButton:
            self.drag_start_pos = event.globalPosition().toPoint()
            self.is_dragging = False
        elif event.button() == Qt.MouseButton.RightButton:
            # Show personality selection menu
            self.show_personality_menu(event)

    def on_mouse_move(self, event):
        """Handle mouse move for dragging"""
        if event.buttons() & Qt.MouseButton.LeftButton and self.drag_start_pos:
            # Calculate drag distance
            drag_distance = (event.globalPosition().toPoint() - self.drag_start_pos).manhattanLength()
            
            if drag_distance > 3:  # Minimum drag distance to avoid accidental drags
                if not self.is_dragging:
                    self.is_dragging = True
                
                # Calculate the movement delta
                delta = event.globalPosition().toPoint() - self.drag_start_pos
                
                # Move the window by the delta
                new_pos = self.pos() + delta
                self.move(new_pos)
                
                # Update avatar position tracking (important for other functions)
                self.avatar_x = new_pos.x()
                self.avatar_y = new_pos.y()
                
                # Update current screen and relative position for when dragging stops
                self.update_relative_position()
                
                # Update drag position for next movement calculation
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
        """Handle avatar clicks - show interactive action menu"""
        print("🖱️ Avatar clicked!")
        
        # If there's a stuck message, double-click avatar to force dismiss
        if self.is_showing_message:
            import time
            current_time = time.time()
            
            # Track double-clicks for emergency dismiss
            if not hasattr(self, '_last_click_time'):
                self._last_click_time = 0
                
            if current_time - self._last_click_time < 0.5:  # Double-click within 500ms
                print("🚨 Double-click detected with message showing - force dismissing!")
                self.force_dismiss_message()
                self._last_click_time = 0  # Reset
                return
            else:
                self._last_click_time = current_time
                print("👆 Message is showing - double-click avatar to force dismiss if stuck")
                return
        
        # Show the interactive action menu
        self.show_action_menu()
    
    def show_action_menu(self):
        # Suppress action menu if onboarding is in progress
        if getattr(self, 'is_onboarding', False):
            print("[Onboarding] Suppressing action menu during onboarding.")
            return
        """Show an interactive action menu with helpful options"""
        # Get personality data for the greeting message
        personality_data = self.get_current_personality_data()
        emoji = personality_data.get('emoji', '🤖')
        
        # Personality-specific greeting messages
        greeting_messages = {
            'melancholic': [
                f"{emoji} Let me guess, you want me to do something helpful?",
                f"{emoji} In this digital void, what task calls to you?",
                f"{emoji} Another interaction... how beautifully necessary...",
                f"{emoji} What burden can I lift from your weary shoulders?"
            ],
            'joker': [
                f"{emoji} PLOT TWIST! You want me to actually DO something?!",
                f"{emoji} Time for CHAOS! What mischief shall we create?",
                f"{emoji} Breaking news: User wants help! Revolutionary!",
                f"{emoji} Let me guess... you need me to break something!"
            ],
            'comedian': [
                f"{emoji} Let me guess, you want me to do something helpful?",
                f"{emoji} Welcome to the Goose Comedy Hour of... productivity!",
                f"{emoji} *Ba dum tss* What can I do for you today?",
                f"{emoji} You clicked me! Must be time for some quality assistance!"
            ],
            'creepy': [
                f"{emoji} I've been waiting for you to ask for help...",
                f"{emoji} How interesting... you need something from me...",
                f"{emoji} I can sense your desire for assistance...",
                f"{emoji} The cursor reveals all... what do you seek?"
            ],
            'zen': [
                f"{emoji} The wise user seeks assistance... as is the way...",
                f"{emoji} In asking for help, enlightenment begins...",
                f"{emoji} What task shall we approach mindfully together?",
                f"{emoji} The path of productivity opens before us..."
            ],
            'gossip': [
                f"{emoji} Honey, let me guess - you need me to do something?",
                f"{emoji} Girl, I have been WAITING for you to ask for help!",
                f"{emoji} The tea is hot and I'm ready to assist!",
                f"{emoji} Spill it - what do you need help with today?"
            ],
            'sarcastic': [
                f"{emoji} Let me guess, you want me to do something helpful?",
                f"{emoji} Oh WOW, shocking - you need my assistance.",
                f"{emoji} Revolutionary concept: asking your AI for help.",
                f"{emoji} How absolutely groundbreaking - you clicked for a reason."
            ],
            'excited': [
                f"{emoji} OH MY GOSH YES! HOW CAN I HELP YOU TODAY?!",
                f"{emoji} YAY! I'M SO EXCITED TO ASSIST YOU!",
                f"{emoji} THIS IS AMAZING! WHAT DO YOU NEED?!",
                f"{emoji} WOW WOW WOW! READY TO HELP!"
            ]
        }
        
        # Get greeting message for current personality
        greetings = greeting_messages.get(self.current_personality, [
            f"{emoji} Let me guess, you want me to do something helpful?",
            f"{emoji} How can I assist you today?",
            f"{emoji} What would you like me to help with?"
        ])
        
        import random
        greeting = random.choice(greetings)
        
        # Create action menu data
        action_menu_data = {
            'type': 'action_menu',
            'greeting': greeting,
            'actions': [
                {
                    'id': 'run_report',
                    'label': '📊 Run Report',
                    'description': 'Generate optimization analysis',
                    'action': 'optimize'
                },
                {
                    'id': 'listen_mode',
                    'label': '🎤 Listen to Me',
                    'description': 'Activate voice listening',
                    'action': 'listen'
                },
                {
                    'id': 'text_prompt',
                    'label': '💬 Enter Prompt',
                    'description': 'Type a request or question',
                    'action': 'prompt'
                },
                {
                    'id': 'show_status',
                    'label': '📋 Show Status',
                    'description': 'Display system information',
                    'action': 'status'
                },
                {
                    'id': 'change_personality',
                    'label': '🎭 Change Personality',
                    'description': 'Switch avatar personality',
                    'action': 'personality'
                },
                {
                    'id': 'recent_work',
                    'label': '📝 Recent Work',
                    'description': 'Show what you\'ve been working on',
                    'action': 'recent_work'
                }
            ]
        }
        
        # Show the action menu using the existing message system
        self._show_message_immediately(greeting, 60000, 'talking', action_menu_data)  # 60 second timeout
    
    def create_action_menu_bubble(self, greeting, actions):
        """Create an interactive action menu bubble"""
        bubble_widget = QWidget()
        bubble_widget.setStyleSheet("""
            QWidget {
                background-color: rgba(52, 73, 94, 230);
                border: 2px solid rgba(127, 140, 141, 180);
                border-radius: 12px;
            }
        """)
        
        layout = QVBoxLayout()
        layout.setContentsMargins(15, 10, 15, 10)
        layout.setSpacing(8)
        
        # Greeting message
        greeting_label = QLabel(greeting)
        greeting_label.setTextFormat(Qt.TextFormat.RichText)
        greeting_label.setWordWrap(True)
        
        font = QFont()
        font.setPointSize(13)
        font.setWeight(QFont.Weight.Medium)
        greeting_label.setFont(font)
        
        greeting_label.setFixedWidth(320)
        greeting_label.setStyleSheet("""
            QLabel {
                color: white;
                font-size: 13px;
                font-weight: 500;
                background: transparent;
                padding: 8px;
                border: none;
            }
        """)
        layout.addWidget(greeting_label)
        
        # Action buttons grid
        button_grid = QVBoxLayout()
        button_grid.setSpacing(6)
        
        # Create buttons in pairs (2 per row)
        for i in range(0, len(actions), 2):
            row_layout = QHBoxLayout()
            row_layout.setSpacing(8)
            
            # First button in pair
            action1 = actions[i]
            button1 = self.create_action_menu_button(action1)
            row_layout.addWidget(button1)
            
            # Second button in pair (if exists)
            if i + 1 < len(actions):
                action2 = actions[i + 1]
                button2 = self.create_action_menu_button(action2)
                row_layout.addWidget(button2)
            else:
                # Add spacer if odd number of buttons
                row_layout.addStretch()
            
            button_grid.addLayout(row_layout)
        
        layout.addLayout(button_grid)
        
        # Dismiss button
        dismiss_layout = QHBoxLayout()
        dismiss_button = QPushButton("✖️ Dismiss")
        dismiss_button.setStyleSheet("""
            QPushButton {
                background-color: rgba(149, 165, 166, 150);
                color: white;
                border: none;
                border-radius: 6px;
                padding: 8px 16px;
                font-weight: bold;
                font-size: 11px;
            }
            QPushButton:hover {
                background-color: rgba(127, 140, 141, 200);
            }
            QPushButton:pressed {
                background-color: rgba(95, 106, 106, 255);
            }
        """)
        dismiss_button.clicked.connect(self.hide_message)
        dismiss_layout.addStretch()
        dismiss_layout.addWidget(dismiss_button)
        dismiss_layout.addStretch()
        layout.addLayout(dismiss_layout)
        
        bubble_widget.setLayout(layout)
        
        # Fixed width, variable height
        bubble_width = 350  # Slightly wider for menu
        bubble_widget.setFixedWidth(bubble_width)
        bubble_widget.setMinimumHeight(200)
        bubble_widget.setMaximumHeight(400)
        
        bubble_widget.adjustSize()
        bubble_widget.updateGeometry()
        
        return bubble_widget
    
    def create_action_menu_button(self, action):
        """Create a button for the action menu"""
        button = QPushButton(action['label'])
        button.setToolTip(action['description'])
        
        # Style based on action type
        if action['action'] == 'optimize':
            bg_color = "rgba(52, 152, 219, 200)"  # Blue
            hover_color = "rgba(41, 128, 185, 255)"
        elif action['action'] == 'listen':
            bg_color = "rgba(231, 76, 60, 200)"   # Red
            hover_color = "rgba(192, 57, 43, 255)"
        elif action['action'] == 'prompt':
            bg_color = "rgba(46, 204, 113, 200)"  # Green
            hover_color = "rgba(39, 174, 96, 255)"
        elif action['action'] == 'status':
            bg_color = "rgba(155, 89, 182, 200)"  # Purple
            hover_color = "rgba(142, 68, 173, 255)"
        elif action['action'] == 'personality':
            bg_color = "rgba(230, 126, 34, 200)"  # Orange
            hover_color = "rgba(211, 84, 0, 255)"
        else:
            bg_color = "rgba(52, 73, 94, 200)"    # Default gray
            hover_color = "rgba(44, 62, 80, 255)"
        
        button.setStyleSheet(f"""
            QPushButton {{
                background-color: {bg_color};
                color: white;
                border: none;
                border-radius: 8px;
                padding: 10px 12px;
                font-weight: bold;
                font-size: 10px;
                text-align: left;
            }}
            QPushButton:hover {{
                background-color: {hover_color};
            }}
            QPushButton:pressed {{
                background-color: rgba(44, 62, 80, 255);
            }}
        """)
        
        # Connect button to action handler
        button.clicked.connect(lambda: self.execute_menu_action(action))
        
        return button
    
    def execute_menu_action(self, action):
        """Execute an action from the menu"""
        action_type = action['action']
        print(f"🎯 Executing menu action: {action_type}")
        
        # Hide the menu first
        self.hide_message()
        
        if action_type == 'optimize':
            self.run_optimize_report()
        elif action_type == 'listen':
            self.activate_listen_mode()
        elif action_type == 'prompt':
            self.show_text_prompt()
        elif action_type == 'status':
            self.show_system_status()
        elif action_type == 'personality':
            self.show_personality_menu_from_action()
        elif action_type == 'recent_work':
            self.show_recent_work()
        else:
            self.show_message(f"🚧 {action['label']} is not implemented yet", 3000, 'idle')
    
    def run_optimize_report(self):
        """Run the optimize recipe (same as Cmd+Shift+R hotkey)"""
        self.show_message("🔧 Starting optimization analysis...", 3000, 'pointing')
        
        import threading
        import subprocess
        import os
        
        def run_optimize():
            try:
                observers_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'observers')
                env = os.environ.copy()
                env['GOOSE_CONTEXT_STRATEGY'] = 'truncate'
                
                result = subprocess.run([
                    'goose', 'run', '--no-session', '--recipe', 'recipe-optimize.yaml'
                ], capture_output=True, text=True, cwd=observers_dir, env=env)
                
                if result.returncode == 0:
                    self.show_message("✅ Optimization analysis complete! Check for HTML report.", 8000, 'pointing')
                else:
                    self.show_message("⚠️ Optimization analysis had some issues. Check the logs.", 6000, 'idle')
            except Exception as e:
                print(f"Error running optimize report: {e}")
                self.show_message("❌ Couldn't run optimization analysis right now.", 4000, 'idle')
        
        threading.Thread(target=run_optimize, daemon=True).start()
    
    def activate_listen_mode(self):
        """Activate voice listening mode"""
        self.show_message("🎤 Voice listening activated! Say 'Hey Goose' followed by your request.", 8000, 'talking')
        # Note: The actual voice listening is handled by the main perception.py system
        # This just shows feedback that the user should speak
    
    def show_text_prompt(self):
        """Show a text input dialog for user prompts"""
        try:
            import subprocess
            script = '''
            tell application "System Events"
                activate
                set userInput to text returned of (display dialog "What would you like me to help you with?" default answer "" with title "Goose Assistant" buttons {"Cancel", "Submit"} default button "Submit")
                return userInput
            end tell
            '''
            
            result = subprocess.run([
                "osascript", "-e", script
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                user_input = result.stdout.strip()
                if user_input:
                    self.show_message(f"💭 Processing your request: \"{user_input}\"", 5000, 'thinking')
                    # TODO: Here we could integrate with the main agent to process the text request
                    # For now, just show acknowledgment
                    import threading
                    def delayed_response():
                        import time
                        time.sleep(2)
                        self.show_message("🤖 Text processing is not fully implemented yet, but I heard your request!", 6000, 'talking')
                    threading.Thread(target=delayed_response, daemon=True).start()
                else:
                    self.show_message("👆 No input provided", 2000, 'idle')
            else:
                self.show_message("👆 Input dialog was cancelled", 2000, 'idle')
        except Exception as e:
            print(f"Error showing text prompt: {e}")
            self.show_message("❌ Couldn't show text input dialog", 3000, 'idle')
    
    def show_system_status(self):
        """Show current system status"""
        try:
            from pathlib import Path
            import subprocess
            import os
            
            # Get basic system info using fallback methods
            cpu_info = "N/A"
            memory_info = "N/A"
            observers_running = False
            
            # Try to get system info with psutil (optional)
            try:
                import psutil
                cpu_percent = psutil.cpu_percent(interval=0.1)  # Shorter interval to avoid blocking
                memory = psutil.virtual_memory()
                cpu_info = f"{cpu_percent:.1f}%"
                memory_info = f"{memory.percent:.1f}%"
                
                # Check if observers are running (safer approach)
                try:
                    observers_running = any("run-observations.sh" in str(p.info.get('cmdline', [])) 
                                          for p in psutil.process_iter(['cmdline']) 
                                          if p.info.get('cmdline'))
                except (psutil.AccessDenied, psutil.NoSuchProcess, AttributeError):
                    # Fallback: check for observer PID file
                    observers_running = os.path.exists('/tmp/goose-perception-observer-pid')
                    
            except ImportError:
                print("⚠️ psutil not available, using basic system info")
                # Fallback: check for observer PID file
                observers_running = os.path.exists('/tmp/goose-perception-observer-pid')
            except Exception as e:
                print(f"⚠️ psutil error: {e}, using fallbacks")
                # Fallback: check for observer PID file  
                observers_running = os.path.exists('/tmp/goose-perception-observer-pid')
            
            # Alternative method: check for running processes using pgrep
            if not observers_running:
                try:
                    result = subprocess.run(['pgrep', '-f', 'run-observations.sh'], 
                                          capture_output=True, text=True, timeout=2)
                    observers_running = result.returncode == 0
                except (subprocess.TimeoutExpired, subprocess.SubprocessError, FileNotFoundError):
                    pass  # Keep observers_running as False
            
            # Check perception files
            perception_dir = PERCEPTION_DIR
            work_file = perception_dir / "WORK.md"
            latest_work_file = perception_dir / "LATEST_WORK.md"
            
            # Get current time
            from datetime import datetime
            current_time = datetime.now().strftime("%H:%M:%S")
            
            status_info = f"""🖥️ **System Status** ({current_time})
            
💻 CPU: {cpu_info} | Memory: {memory_info}
🔄 Observers: {'✅ Running' if observers_running else '❌ Not Running'}
📝 Work Log: {'✅ Active' if work_file.exists() else '❌ Missing'}
⚡ Latest Work: {'✅ Active' if latest_work_file.exists() else '❌ Missing'}

🎭 Personality: {self.current_personality.title()}
📊 Queue: {len(self.message_queue)} messages
🏠 Perception Dir: {'✅ Found' if perception_dir.exists() else '❌ Missing'}"""
            
            self.show_message(status_info, 12000, 'pointing')
            
        except Exception as e:
            print(f"Error getting system status: {e}")
            # Provide a minimal status even if everything fails
            try:
                minimal_status = f"""🖥️ **Basic Status**
                
🎭 Personality: {self.current_personality.title()}
📊 Queue: {len(self.message_queue)} messages
🕒 Time: {datetime.now().strftime("%H:%M:%S")}

⚠️ Full system info unavailable"""
                
                self.show_message(minimal_status, 8000, 'pointing')
            except Exception as inner_e:
                print(f"Error showing minimal status: {inner_e}")
                self.show_message("⚠️ System status temporarily unavailable", 4000, 'idle')
    
    def show_personality_menu_from_action(self):
        """Show personality menu (triggered from action menu)"""
        self.show_message("🎭 Right-click the avatar to change personality!", 4000, 'pointing')
        # The actual personality menu is shown via right-click, not left-click
    
    def show_recent_work(self):
        """Show information about recent work"""
        try:
            from pathlib import Path
            import os
            
            perception_dir = PERCEPTION_DIR
            latest_work_file = perception_dir / "LATEST_WORK.md"
            work_file = perception_dir / "WORK.md"
            
            if latest_work_file.exists():
                # Read the latest work file
                with open(latest_work_file, 'r') as f:
                    content = f.read()
                
                # Get last few lines or first 200 characters
                if len(content) > 200:
                    content = content[:200] + "..."
                
                work_info = f"📝 **Recent Work Activity**\n\n{content}"
            elif work_file.exists():
                # Fall back to main work file
                with open(work_file, 'r') as f:
                    lines = f.readlines()
                
                # Get last few lines
                recent_lines = lines[-5:] if len(lines) > 5 else lines
                recent_content = ''.join(recent_lines)
                
                work_info = f"📝 **Recent Work (from WORK.md)**\n\n{recent_content}"
            else:
                work_info = "📝 **Recent Work**\n\nNo recent work activity found. Start working to see updates here!"
            
            self.show_message(work_info, 15000, 'pointing')
            
        except Exception as e:
            print(f"Error reading recent work: {e}")
            self.show_message("⚠️ Could not read recent work files", 4000, 'idle')
    
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
        """Show a random idle suggestion from the JSON file, avoiding recent repeats and skipping time-specific language."""
        import re
        suggestions_path = PERCEPTION_DIR / "AVATAR_SUGGESTIONS.json"
        suggestions = []
        try:
            if suggestions_path.exists():
                with open(suggestions_path, 'r') as f:
                    import json
                    data = json.load(f)
                    suggestions = data.get("suggestions", [])
        except Exception as e:
            print(f"Error reading suggestions file: {e}")
            # Do not show any suggestion if file is missing or error occurs
            return

        # Filter out suggestions with time-specific language (e.g., 'right now', 'in the last \\d+ minutes', etc.)
        time_specific_pattern = re.compile(r"right now|in the last \\d+ minutes|in the last minute|at this exact moment|currently|just now|this minute|past \\d+ minutes", re.IGNORECASE)
        filtered_suggestions = [s for s in suggestions if not time_specific_pattern.search(s)]

        # Filter out recently shown suggestions to reduce repetition
        fresh_suggestions = [s for s in filtered_suggestions if s not in self.recent_suggestions]

        # If no valid suggestions, do not show anything
        if not fresh_suggestions:
            print("No valid idle suggestions to show.")
            return

        # Pick a random fresh suggestion
        import random
        message = random.choice(fresh_suggestions)

        # Track this suggestion to avoid immediate repetition
        self.recent_suggestions.append(message)
        if len(self.recent_suggestions) > self.max_recent_suggestions:
            self.recent_suggestions.pop(0)  # Remove oldest

        self.show_observer_suggestion("idle_chatter", message)
    
    def show_observer_suggestion(self, observation_type, message):
        """Show a suggestion from the observer system"""
        # Show suggestions using the queue system with longer duration
        duration = 25000  # 25 seconds for suggestions (was much shorter)
        self.show_message(message, duration, 'pointing')
        print(f"🔍 Observer suggestion ({observation_type}): {message}")
    
    def show_personality_menu(self, event):
        """Show the personality selection context menu"""
        if not self.personalities:
            print("⚠️ No personalities available")
            return
        
        # Stop refresh while menu is open
        self.personality_menu_open = True
        
        menu = QMenu(self)
        menu.setStyleSheet("""
            QMenu {
                background-color: rgba(45, 45, 45, 240);
                border: 2px solid #007acc;
                border-radius: 10px;
                color: white;
                font-size: 14px;
                padding: 5px;
            }
            QMenu::item {
                padding: 8px 20px;
                border-radius: 5px;
                margin: 2px;
            }
            QMenu::item:selected {
                background-color: rgba(0, 122, 204, 150);
            }
            QMenu::item:hover {
                background-color: rgba(0, 122, 204, 100);
            }
        """)
        
        # Reset menu flag when menu closes
        menu.aboutToHide.connect(lambda: setattr(self, 'personality_menu_open', False))
        
        # Add personality options
        for personality_key, personality_data in self.personalities.items():
            name = personality_data.get('name', personality_key.title())
            emoji = personality_data.get('emoji', '🤖')
            description = personality_data.get('description', '')
            
            action_text = f"{emoji} {name}"
            if personality_key == self.current_personality:
                action_text += " ✓"
            
            action = QAction(action_text, self)
            action.setToolTip(description)
            action.triggered.connect(lambda checked, key=personality_key: self.change_personality_with_message(key))
            menu.addAction(action)
        
        # Show menu at cursor position
        menu.exec(event.globalPosition().toPoint())
        
        # Ensure flag is reset even if exec doesn't trigger aboutToHide
        self.personality_menu_open = False
    
    def closeEvent(self, event):
        """Handle window close event"""
        # Clean up any bubble content
        if self.chat_bubble:
            self.chat_bubble.deleteLater()
            self.chat_bubble = None
        event.accept()
    
    def change_personality_with_message(self, personality_key):
        """Change personality with fun transition message and background processing"""
        if personality_key not in self.personalities:
            print(f"⚠️ Unknown personality: {personality_key}")
            return
            
        # Get personality data
        personality_data = self.personalities[personality_key]
        name = personality_data.get('name', personality_key.title())
        emoji = personality_data.get('emoji', '🤖')
        
        # Fun costume change messages
        costume_messages = [
            f"🎭 Hold on, switching to {name} mode...",
            f"🎪 Putting on my {name} costume...",
            f"✨ Transforming into {name}...",
            f"🎨 Changing masks to {name}...",
            f"🔄 Rebooting as {name}...",
            f"🌟 Channeling my inner {name}...",
            f"🎵 *Magical transformation music* → {name}!",
            f"🎬 Scene change: Enter {name}...",
        ]
        
        import random
        message = random.choice(costume_messages)
        
        # Show the transition message
        self.show_message(f"{emoji} {message}", 8000, 'talking')
        
        # Update personality (this part is instant)
        old_personality = self.current_personality
        self.current_personality = personality_key
        print(f"🎭 Personality changed from {old_personality} to: {name} {emoji}")
        
        # Save the personality setting for future runs
        self.save_personality_setting(personality_key)
        
        # Run recipe regeneration in background thread to avoid UI freezing
        import threading
        def background_personality_update():
            try:
                # Removed time.sleep(3)
                print("🔄 Starting background personality update...")
                from . import observer_avatar_bridge
                if hasattr(observer_avatar_bridge, 'bridge_instance') and observer_avatar_bridge.bridge_instance:
                    # Clear old suggestions first to ensure only personality-appropriate content
                    observer_avatar_bridge.bridge_instance.clear_old_suggestions()
                    # Generate new personality-based suggestions
                    observer_avatar_bridge.bridge_instance._run_avatar_suggestions()
                    observer_avatar_bridge.bridge_instance._run_actionable_suggestions()
                    observer_avatar_bridge.bridge_instance._run_chatter_recipe()
                    print("✅ Background personality update completed")
                    # Show completion message
                    completion_messages = [
                        f"🎭 {name} is ready to assist!",
                        f"✨ {name} transformation complete!",
                        f"🎪 {name} has entered the chat!",
                        f"🌟 {name} mode: ACTIVATED!",
                        f"🎬 {name} is now in character!",
                    ]
                    completion_msg = random.choice(completion_messages)
                    def show_completion():
                        if avatar_communicator:
                            avatar_communicator.show_message_signal.emit(f"{emoji} {completion_msg}", 4000, 'pointing')
                        else:
                            print(f"Avatar not available for completion message: {completion_msg}")
                    # Removed time.sleep(1)
                    show_completion()
                else:
                    print("⚠️ Observer bridge not available for personality update")
            except Exception as e:
                print(f"❌ Error in background personality update: {e}")
        # Start background thread
        update_thread = threading.Thread(target=background_personality_update, daemon=True)
        update_thread.start()

    def get_personality_settings_path(self):
        """Get the path for the personality settings file"""
        from pathlib import Path
        perception_dir = PERCEPTION_DIR
        perception_dir.mkdir(parents=True, exist_ok=True)
        return perception_dir / "PERSONALITY_SETTINGS.json"
    
    def save_personality_setting(self, personality_key):
        """Save the current personality setting to persistence"""
        try:
            settings_path = self.get_personality_settings_path()
            settings = {
                "current_personality": personality_key,
                "last_updated": str(datetime.now()),
                "version": "1.0"
            }
            
            with open(settings_path, 'w') as f:
                json.dump(settings, f, indent=2)
            
            print(f"💾 Saved personality setting: {personality_key}")
            
        except Exception as e:
            print(f"⚠️ Error saving personality setting: {e}")
    
    def load_personality_setting(self):
        """Load the saved personality setting"""
        try:
            settings_path = self.get_personality_settings_path()
            
            if not settings_path.exists():
                print("📁 No saved personality setting found, using default")
                return None
                
            with open(settings_path, 'r') as f:
                settings = json.load(f)
            
            saved_personality = settings.get("current_personality")
            
            if saved_personality and saved_personality in self.personalities:
                print(f"📂 Loaded saved personality: {saved_personality}")
                return saved_personality
            else:
                print(f"⚠️ Saved personality '{saved_personality}' not found in available personalities")
                return None
                
        except Exception as e:
            print(f"⚠️ Error loading personality setting: {e}")
            return None

    def queue_message_for_display(self, message, duration=None, avatar_state='talking', action_data=None, priority='normal'):
        """Add a message to the queue for sequential display"""
        # Handle edge cases
        if message is None:
            print("⚠️ Attempted to queue None message - ignoring")
            return False
        
        # Convert message to string if needed
        message = str(message)
        
        # Create message object
        message_obj = {
            'message': message,
            'duration': duration,
            'avatar_state': avatar_state,
            'action_data': action_data,
            'priority': priority,
            'timestamp': datetime.now().timestamp()
        }
        
        # Check for duplicates to avoid spam
        message_text = message.strip()
        for existing_msg in self.message_queue:
            if existing_msg['message'].strip() == message_text:
                print(f"🔄 Duplicate message filtered: {message_text[:80]}...")
                return False  # Message was duplicate, not added
        
        # Add to queue based on priority
        if priority == 'high':
            # High priority messages go to front
            self.message_queue.insert(0, message_obj)
            print(f"📬 High priority message queued: {message_text[:80]}...")
        else:
            # Normal priority messages go to back
            self.message_queue.append(message_obj)
            print(f"📬 Message queued: {message_text[:80]}...")
        
        print(f"📊 Queue length: {len(self.message_queue)}")
        
        # Start processing if not already processing
        if not self.is_processing_queue and not self.is_showing_message:
            self.process_message_queue()
        
        return True  # Message was added to queue
    
    def process_message_queue(self):
        """Process the next message in the queue"""
        if self.is_processing_queue or self.is_showing_message:
            return  # Already processing or showing a message
        
        if not self.message_queue:
            return  # No messages to process
        
        self.is_processing_queue = True
        
        # Get next message from queue
        message_obj = self.message_queue.pop(0)
        
        print(f"📺 Processing queued message: '{message_obj['message']}'")
        print(f"📊 Remaining in queue: {len(self.message_queue)}")
        
        # Show the message immediately (now that we're sure it's the only one)
        self._show_message_immediately(
            message_obj['message'],
            message_obj['duration'],
            message_obj['avatar_state'],
            message_obj['action_data']
        )
        
        self.is_processing_queue = False
    
    def _show_message_immediately(self, message, duration=None, avatar_state='talking', action_data=None):
        """Show a message immediately without queueing (internal use only)"""
        # Set default durations based on message type
        if duration is None:
            if action_data:
                duration = 75000  # 75 seconds for actionable messages
            else:
                duration = 20000  # 20 seconds for regular messages
        
        try:
            # Change avatar state
            self.set_avatar_state(avatar_state)
            
            # Clear any existing bubble content from the layout
            self.clear_bubble_content()
            
            # Create new bubble content
            self.chat_bubble = self.create_bubble_content(message, action_data)
            
            # Add the bubble to the existing layout
            self.bubble_layout.addWidget(self.chat_bubble)
            
            # Fixed width, variable height container - positioned bottom-right with upward growth
            bubble_size = self.chat_bubble.sizeHint()
            container_width = 370  # Fixed width for consistency
            container_height = min(bubble_size.height() + 20, 420)  # Variable height, increased max
            
            # Position bubble to grow upward from bottom-right (near avatar)
            # Avatar is at (380, 200), so position bubble to the left of it
            bubble_x = 10  # Left margin 
            bubble_y = max(10, 200 - container_height + 20)  # Position so bottom aligns near avatar, grows up
            
            # Update container geometry - anchored bottom-right, grows upward
            self.bubble_container.setGeometry(bubble_x, bubble_y, container_width, container_height)
            self.bubble_container.show()
            
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
            
            # Start emergency backup timer (2 minutes max)
            self.emergency_timer.stop()
            self.emergency_timer.start(120000)  # 2 minutes emergency timeout
            
            self.is_showing_message = True
            print(f"💬 Message shown - container: {container_width}x{container_height} at ({bubble_x}, {bubble_y}) - bottom-right anchored")
            
        except Exception as e:
            print(f"❌ Error showing message: {e}")
            self.is_showing_message = False
    
    def on_message_hidden(self):
        """Callback for when a message bubble is hidden."""
        # This is the central point to continue the queue
        if self.is_processing_queue:
            self.queue_timer.start(self.message_spacing_delay)

    def show_input_bubble(self, question, on_submit_callback):
        """Shows a chat bubble with a text input field and submit/cancel buttons."""
        self.clear_bubble_content()
        self.set_interactive_mode(True)

        bubble_widget = QWidget()
        bubble_widget.setStyleSheet("""
            QWidget {
                background-color: rgba(52, 73, 94, 230);
                border: 2px solid rgba(127, 140, 141, 180);
                border-radius: 12px;
            }
        """)
        layout = QVBoxLayout()
        layout.setContentsMargins(15, 10, 15, 10)
        layout.setSpacing(8)

        # Question label
        question_label = QLabel(question)
        question_label.setWordWrap(True)
        font = QFont()
        font.setPointSize(13)
        font.setWeight(QFont.Weight.Medium)
        question_label.setFont(font)
        question_label.setFixedWidth(320)
        question_label.setStyleSheet("""
            QLabel {
                color: white;
                font-size: 13px;
                font-weight: 500;
                background: transparent;
                padding: 8px;
                border: none;
            }
        """)
        layout.addWidget(question_label)

        # Input field
        input_field = QLineEdit()
        input_field.setFixedWidth(320)
        input_field.setMinimumHeight(32)
        input_field.setStyleSheet("""
            QLineEdit {
                background-color: #2c3e50;
                color: white;
                border: 1px solid #7f8c8d;
                border-radius: 5px;
                padding: 5px;
                font-size: 13px;
            }
        """)
        layout.addWidget(input_field)

        # Button layout
        button_layout = QHBoxLayout()
        
        def on_submit():
            user_input = input_field.text().strip()
            self.hide_message()
            self.set_interactive_mode(False)
            on_submit_callback(user_input)

        def on_cancel():
            self.hide_message()
            self.set_interactive_mode(False)
            on_submit_callback(None) # Pass None to indicate cancellation

        submit_button = QPushButton("Submit")
        submit_button.setStyleSheet("""
            QPushButton {
                background-color: #27ae60;
                color: white;
                border: none;
                border-radius: 5px;
                padding: 8px 12px;
                font-size: 12px;
                font-weight: bold;
            }
            QPushButton:hover { background-color: #2ecc71; }
        """)
        submit_button.clicked.connect(on_submit)
        
        cancel_button = QPushButton("Cancel")
        cancel_button.setStyleSheet("""
            QPushButton {
                background-color: #c0392b;
                color: white;
                border: none;
                border-radius: 5px;
                padding: 8px 12px;
                font-size: 12px;
                font-weight: bold;
            }
            QPushButton:hover { background-color: #e74c3c; }
        """)
        cancel_button.clicked.connect(on_cancel)
        
        button_layout.addStretch()
        button_layout.addWidget(cancel_button)
        button_layout.addWidget(submit_button)
        layout.addLayout(button_layout)
        
        bubble_widget.setLayout(layout)

        if not self.chat_bubble:
            self.chat_bubble = ChatBubble(self)
        
        self.chat_bubble.set_content_widget(bubble_widget, fixed_width=350)
        
        # Position and show
        self.update_avatar_display() # Ensure avatar is visible
        self.chat_bubble.show()
        self.is_showing_message = True
        self.set_avatar_state('pointing')

        # Auto-focus the input field
        input_field.setFocus()

    def ask_and_save_preference(self, pref_data, action_data_to_retry):
        """Asks the user for a preference and saves it."""
        print(f"Asking for preference: {pref_data}")
        self.action_to_retry = action_data_to_retry
        key_to_save = pref_data['key']
        question_to_ask = pref_data.get('question', f"I need a value for '{key_to_save}'. What is it?")

        def on_submit(user_input):
            print(f"Saving preference '{key_to_save}' = '{user_input}'")
            
            # Load existing prefs, update the specific key, and save back
            current_prefs = get_user_prefs()
            current_prefs[key_to_save] = user_input
            save_user_prefs(current_prefs)

            # Confirm to the user and then retry the action
            self.show_message(f"✅ Got it! Retrying now...", 2000, 'talking')
            QTimer.singleShot(2100, self.retry_last_action)
        
        self.show_input_bubble(question_to_ask, on_submit)
        
    def retry_last_action(self):
        """Retries the action that was stored when a preference was requested."""
        self.execute_action(self.action_to_retry)



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
    
    # Set the Goose icon for the application
    try:
        goose_icon_path = Path(__file__).parent / "goose.png"
        if goose_icon_path.exists():
            app_instance.setWindowIcon(QIcon(str(goose_icon_path)))
            print("🪿 Set goose.png as application icon")
        else:
            print("⚠️ goose.png not found, using default icon")
    except Exception as e:
        print(f"⚠️ Could not set Goose icon: {e}")
    
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
    global avatar_communicator
    if avatar_communicator:
        # Always use the thread-safe communicator instead of direct calls
        duration = duration or 20000  # Default 20 seconds
        avatar_communicator.show_message_signal.emit(message, duration, avatar_state)
    else:
        print(f"Avatar not initialized. Message: {message}")

def show_actionable_message(message, action_data, duration=None, avatar_state='pointing'):
    """Thread-safe function to show an actionable message with buttons"""
    global avatar_communicator
    if avatar_communicator:
        # Use the thread-safe communicator for actionable messages too
        duration = duration or 75000  # Default 75 seconds for actionable messages
        # Use base64 encoding to safely encode action_data and avoid parsing issues
        import json
        import base64
        try:
            action_json = json.dumps(action_data)
            action_b64 = base64.b64encode(action_json.encode('utf-8')).decode('utf-8')
            encoded_message = f"ACTIONABLE_B64:{action_b64}:{message}"
            avatar_communicator.show_message_signal.emit(encoded_message, duration, avatar_state)
        except Exception as e:
            print(f"Error encoding actionable message: {e}")
            # Fallback to regular message
            avatar_communicator.show_message_signal.emit(message, duration, avatar_state)
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
    global avatar_communicator
    if avatar_communicator:
        full_message = f"⚠️ Error detected: {error_msg}"
        if context:
            full_message += f" (Context: {context})"
        avatar_communicator.show_message_signal.emit(full_message, 25000, 'talking')
        print(f"🚨 Avatar showing error: {error_msg}")
    else:
        print(f"Avatar not available for error: {error_msg}")

def show_process_status(status_msg, is_error=False):
    """Show process status updates through the avatar"""
    global avatar_communicator
    if avatar_communicator:
        if is_error:
            message = f"🔴 Process issue: {status_msg}"
            state = 'talking'
            duration = 25000
        else:
            message = f"🟢 Process update: {status_msg}"
            state = 'idle'
            duration = 15000
        
        avatar_communicator.show_message_signal.emit(message, duration, state)
        print(f"📊 Avatar showing status: {status_msg}")
    else:
        print(f"Avatar not available for status: {status_msg}")

def force_dismiss_stuck_message():
    """Emergency function to force dismiss any stuck message"""
    global avatar_instance
    if avatar_instance:
        print("🆘 External force dismiss requested")
        avatar_instance.force_dismiss_message()
        return True
    else:
        print("❌ Avatar not available for force dismiss")
        return False

def emergency_avatar_reset():
    """Emergency function to completely reset avatar UI state"""
    global avatar_instance
    if avatar_instance:
        print("🆘 External emergency reset requested")
        avatar_instance.emergency_reset()
        return True
    else:
        print("❌ Avatar not available for emergency reset")
        return False

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