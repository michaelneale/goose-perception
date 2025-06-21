#!/usr/bin/env python3
"""
Menu Bar Avatar System - Hybrid approach with menu bar icon + popup window
"""
import sys
import os
from pathlib import Path
from PyQt6.QtWidgets import (QApplication, QWidget, QLabel, QVBoxLayout, 
                            QPushButton, QHBoxLayout, QTextEdit, QMenu, QLineEdit, 
                            QSystemTrayIcon, QMainWindow)
from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QObject, QSize, QPoint, QRect, QRectF, QThread, QPointF
from PyQt6.QtGui import QPixmap, QColor, QPainter, QPen, QBrush, QFont, QTransform, QIcon, QAction, QFontMetrics, QMovie, QPainterPath
import random
import json
from datetime import datetime
import re
import time
import yaml
import subprocess

# Import from existing avatar system
from .avatar_display import get_user_prefs, save_user_prefs, AvatarCommunicator

class MenuBarAvatar(QObject):
    """Menu bar avatar with popup interaction window"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.app = QApplication.instance()
        self.is_enabled = False
        self.popup_window = None
        self.tray_icon = None
        self.menu = None
        self.current_message = None
        self.message_queue = []
        
        # Load avatar images
        self.avatar_images = {}
        self.load_avatar_images()
        
        # Initialize if enabled in preferences
        self.check_and_initialize()
    
    def check_and_initialize(self):
        """Check user preferences and initialize if menu bar mode is enabled"""
        user_prefs = get_user_prefs()
        if user_prefs.get('menu_bar_mode', False):
            self.enable_menu_bar_mode()
    
    def enable_menu_bar_mode(self):
        """Enable the menu bar avatar"""
        if self.is_enabled:
            return
            
        self.is_enabled = True
        self.create_system_tray()
        print("🍎 Menu bar avatar enabled")
    
    def disable_menu_bar_mode(self):
        """Disable the menu bar avatar"""
        if not self.is_enabled:
            return
            
        self.is_enabled = False
        if self.tray_icon:
            self.tray_icon.hide()
            self.tray_icon = None
        if self.popup_window:
            self.popup_window.close()
            self.popup_window = None
        print("🍎 Menu bar avatar disabled")
    
    def load_avatar_images(self):
        """Load avatar images from the avatar directory"""
        self.avatar_images = {}
        avatar_dir = Path(__file__).parent
        
        try:
            avatar_files = {
                'idle': 'first.png',
                'talking': 'second.png',
                'pointing': 'third.png',
                'sleeping': 'sleep.png'
            }
            
            for state, filename in avatar_files.items():
                image_path = avatar_dir / filename
                if image_path.exists():
                    pixmap = QPixmap(str(image_path))
                    # Scale to menu bar size
                    scaled_pixmap = pixmap.scaled(22, 22, Qt.AspectRatioMode.KeepAspectRatio, 
                                                 Qt.TransformationMode.SmoothTransformation)
                    self.avatar_images[state] = scaled_pixmap
                    print(f"✅ Loaded menu bar {state} avatar: {filename}")
                else:
                    print(f"❌ Menu bar avatar image not found: {image_path}")
        except Exception as e:
            print(f"Error loading menu bar avatar images: {e}")
    
    def create_system_tray(self):
        """Create the system tray icon and menu"""
        if not QSystemTrayIcon.isSystemTrayAvailable():
            print("❌ System tray is not available")
            return False
        
        # Create system tray icon
        self.tray_icon = QSystemTrayIcon()
        
        # Set icon (default to idle state)
        if 'idle' in self.avatar_images:
            self.tray_icon.setIcon(QIcon(self.avatar_images['idle']))
        else:
            # Fallback icon
            goose_icon_path = Path(__file__).parent / "goose.png"
            if goose_icon_path.exists():
                icon = QIcon(str(goose_icon_path))
                self.tray_icon.setIcon(icon)
        
        # Create context menu
        self.create_context_menu()
        
        # Connect signals
        self.tray_icon.activated.connect(self.on_tray_icon_activated)
        self.tray_icon.messageClicked.connect(self.on_notification_clicked)
        
        # Show the tray icon
        self.tray_icon.show()
        
        return True
    
    def create_context_menu(self):
        """Create the context menu for the system tray icon"""
        self.menu = QMenu()
        
        # Status section
        self.status_action = QAction("Status: Ready")
        self.status_action.setEnabled(False)
        self.menu.addAction(self.status_action)
        self.menu.addSeparator()
        
        # Quick actions
        listen_action = QAction("🎙️ Activate Listen Mode")
        listen_action.triggered.connect(self.activate_listen_mode)
        self.menu.addAction(listen_action)
        
        work_action = QAction("📋 Show Recent Work")
        work_action.triggered.connect(self.show_recent_work)
        self.menu.addAction(work_action)
        
        status_action = QAction("🖥️ System Status")
        status_action.triggered.connect(self.show_system_status)
        self.menu.addAction(status_action)
        
        self.menu.addSeparator()
        
        # Interaction window
        popup_action = QAction("💬 Open Chat Window")
        popup_action.triggered.connect(self.show_popup_window)
        self.menu.addAction(popup_action)
        
        self.menu.addSeparator()
        
        # Settings
        settings_action = QAction("⚙️ Preferences")
        settings_action.triggered.connect(self.show_preferences)
        self.menu.addAction(settings_action)
        
        # Toggle modes  
        toggle_action = QAction("🪟 Switch to Floating Avatar")
        toggle_action.triggered.connect(self.toggle_to_floating_mode)
        self.menu.addAction(toggle_action)
        
        self.menu.addSeparator()
        
        # Exit
        quit_action = QAction("❌ Quit")
        quit_action.triggered.connect(self.quit_application)
        self.menu.addAction(quit_action)
        
        self.tray_icon.setContextMenu(self.menu)
    
    def on_tray_icon_activated(self, reason):
        """Handle tray icon activation"""
        if reason == QSystemTrayIcon.ActivationReason.DoubleClick:
            self.show_popup_window()
        elif reason == QSystemTrayIcon.ActivationReason.Trigger:
            # Single click - show brief status or latest message
            if self.current_message:
                self.show_notification("Goose", self.current_message)
    
    def show_popup_window(self):
        """Show the popup interaction window"""
        if self.popup_window and self.popup_window.isVisible():
            self.popup_window.raise_()
            self.popup_window.activateWindow()
            return
        
        self.popup_window = MenuBarPopupWindow(self)
        self.popup_window.show()
        self.popup_window.raise_()
        self.popup_window.activateWindow()
    
    def show_message(self, message, duration=None, avatar_state='talking', action_data=None):
        """Show a message via menu bar (notification + status update)"""
        if not self.is_enabled:
            return
        
        self.current_message = message
        
        # Update status in menu
        self.status_action.setText(f"Status: {message[:50]}...")
        
        # Update tray icon to reflect state
        if avatar_state in self.avatar_images:
            self.tray_icon.setIcon(QIcon(self.avatar_images[avatar_state]))
        
        # Show notification
        self.show_notification("Goose", message, duration or 5000)
        
        # If there's action data, show the popup for interaction
        if action_data:
            self.show_popup_window()
            if self.popup_window:
                self.popup_window.show_actionable_message(message, action_data)
    
    def show_notification(self, title, message, duration=5000):
        """Show a system notification"""
        if self.tray_icon:
            self.tray_icon.showMessage(title, message, 
                                     QSystemTrayIcon.MessageIcon.Information, 
                                     duration)
    
    def on_notification_clicked(self):
        """Handle notification click"""
        self.show_popup_window()
    
    def set_avatar_state(self, state):
        """Update the menu bar icon to reflect avatar state"""
        if state in self.avatar_images and self.tray_icon:
            self.tray_icon.setIcon(QIcon(self.avatar_images[state]))
    
    # Menu action handlers
    def activate_listen_mode(self):
        """Activate listen mode"""
        try:
            # Import and call the existing listen mode functionality
            from ..perception import activate_listen_mode
            activate_listen_mode()
            self.show_notification("Goose", "Listen mode activated")
        except Exception as e:
            print(f"Error activating listen mode: {e}")
    
    def show_recent_work(self):
        """Show recent work"""
        self.show_popup_window()
        if self.popup_window:
            self.popup_window.show_recent_work()
    
    def show_system_status(self):
        """Show system status"""
        self.show_popup_window()
        if self.popup_window:
            self.popup_window.show_system_status()
    
    def show_preferences(self):
        """Show preferences window"""
        self.show_popup_window()
        if self.popup_window:
            self.popup_window.show_preferences()
    
    def toggle_to_floating_mode(self):
        """Switch to floating avatar mode"""
        user_prefs = get_user_prefs()
        user_prefs['interface_mode'] = 'floating'
        user_prefs['menu_bar_mode'] = False
        save_user_prefs(user_prefs)
        
        self.show_notification("Goose", "Switching to floating avatar mode...")
        
        # Disable menu bar mode
        self.disable_menu_bar_mode()
        
        # Show restart message
        self.show_notification("Goose", "Please restart Goose to switch to floating avatar mode")
    
    def quit_application(self):
        """Quit the application"""
        QApplication.quit()


class MenuBarPopupWindow(QMainWindow):
    """Popup window for complex interactions when using menu bar avatar"""
    
    def __init__(self, menu_bar_avatar):
        super().__init__()
        self.menu_bar_avatar = menu_bar_avatar
        self.current_action_data = None
        
        self.setWindowTitle("Goose")
        self.setFixedSize(450, 600)
        
        # Set window properties
        self.setWindowFlags(
            Qt.WindowType.WindowStaysOnTopHint |
            Qt.WindowType.Tool
        )
        
        # Create central widget
        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        
        # Create layout
        self.layout = QVBoxLayout()
        self.central_widget.setLayout(self.layout)
        
        # Create UI elements
        self.create_ui()
        
        # Position window near menu bar
        self.position_window()
    
    def create_ui(self):
        """Create the UI for the popup window"""
        # Header with avatar
        header_layout = QHBoxLayout()
        
        # Avatar icon
        avatar_label = QLabel()
        if 'idle' in self.menu_bar_avatar.avatar_images:
            # Scale up for window display
            pixmap = self.menu_bar_avatar.avatar_images['idle'].scaled(
                64, 64, Qt.AspectRatioMode.KeepAspectRatio, 
                Qt.TransformationMode.SmoothTransformation)
            avatar_label.setPixmap(pixmap)
        
        # Title
        title_label = QLabel("Goose Assistant")
        title_label.setStyleSheet("""
            QLabel {
                font-size: 18px;
                font-weight: bold;
                color: #2c3e50;
                padding: 10px;
            }
        """)
        
        header_layout.addWidget(avatar_label)
        header_layout.addWidget(title_label)
        header_layout.addStretch()
        
        self.layout.addLayout(header_layout)
        
        # Message area
        self.message_area = QTextEdit()
        self.message_area.setReadOnly(True)
        self.message_area.setMaximumHeight(200)
        self.message_area.setStyleSheet("""
            QTextEdit {
                border: 1px solid #bdc3c7;
                border-radius: 8px;
                padding: 10px;
                background-color: #f8f9fa;
                font-size: 13px;
            }
        """)
        self.message_area.setPlainText("Ready to help! Use the menu bar icon or interact here.")
        
        self.layout.addWidget(self.message_area)
        
        # Input area
        self.input_area = QLineEdit()
        self.input_area.setPlaceholderText("Type a message or command...")
        self.input_area.setStyleSheet("""
            QLineEdit {
                border: 2px solid #3498db;
                border-radius: 8px;
                padding: 10px;
                font-size: 13px;
            }
        """)
        self.input_area.returnPressed.connect(self.handle_input)
        
        self.layout.addWidget(self.input_area)
        
        # Action buttons area (hidden by default)
        self.action_buttons_widget = QWidget()
        self.action_buttons_layout = QVBoxLayout()
        self.action_buttons_widget.setLayout(self.action_buttons_layout)
        self.action_buttons_widget.hide()
        
        self.layout.addWidget(self.action_buttons_widget)
        
        # Status area
        self.status_label = QLabel("Status: Ready")
        self.status_label.setStyleSheet("""
            QLabel {
                color: #7f8c8d;
                font-size: 11px;
                padding: 5px;
            }
        """)
        
        self.layout.addWidget(self.status_label)
        
        # Spacer
        self.layout.addStretch()
        
        # Bottom buttons
        bottom_layout = QHBoxLayout()
        
        close_button = QPushButton("Close")
        close_button.clicked.connect(self.close)
        close_button.setStyleSheet("""
            QPushButton {
                background-color: #95a5a6;
                color: white;
                border: none;
                border-radius: 6px;
                padding: 8px 16px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #7f8c8d;
            }
        """)
        
        bottom_layout.addStretch()
        bottom_layout.addWidget(close_button)
        
        self.layout.addLayout(bottom_layout)
    
    def position_window(self):
        """Position the window near the menu bar"""
        if self.menu_bar_avatar.app:
            screen = self.menu_bar_avatar.app.primaryScreen()
            screen_rect = screen.availableGeometry()
            
            # Position at top-right of screen
            x = screen_rect.width() - self.width() - 20
            y = 50  # Below menu bar
            
            self.move(x, y)
    
    def show_actionable_message(self, message, action_data):
        """Show an actionable message with buttons"""
        self.current_action_data = action_data
        
        # Update message area
        self.message_area.setPlainText(message)
        
        # Clear existing action buttons
        for i in reversed(range(self.action_buttons_layout.count())):
            self.action_buttons_layout.itemAt(i).widget().setParent(None)
        
        # Create action buttons
        if isinstance(action_data, dict) and 'actions' in action_data:
            for action in action_data['actions']:
                button = QPushButton(action.get('name', 'Action'))
                button.setStyleSheet("""
                    QPushButton {
                        background-color: #3498db;
                        color: white;
                        border: none;
                        border-radius: 6px;
                        padding: 10px;
                        margin: 2px;
                        font-weight: bold;
                    }
                    QPushButton:hover {
                        background-color: #2980b9;
                    }
                """)
                button.clicked.connect(lambda checked, a=action: self.execute_action(a))
                self.action_buttons_layout.addWidget(button)
            
            self.action_buttons_widget.show()
        else:
            self.action_buttons_widget.hide()
    
    def execute_action(self, action):
        """Execute an action"""
        try:
            action_command = action.get('action_command')
            if action_command:
                self.status_label.setText(f"Status: Executing {action.get('name', 'action')}...")
                
                # Execute the action (this would integrate with existing action system)
                import subprocess
                result = subprocess.run(action_command, shell=True, capture_output=True, text=True)
                
                if result.returncode == 0:
                    self.message_area.setPlainText(f"✅ Action completed successfully!")
                    self.status_label.setText("Status: Action completed")
                else:
                    self.message_area.setPlainText(f"❌ Action failed: {result.stderr}")
                    self.status_label.setText("Status: Action failed")
            
            # Hide action buttons after execution
            self.action_buttons_widget.hide()
            
        except Exception as e:
            self.message_area.setPlainText(f"❌ Error executing action: {e}")
            self.status_label.setText("Status: Error")
    
    def handle_input(self):
        """Handle user input"""
        text = self.input_area.text().strip()
        if not text:
            return
        
        self.input_area.clear()
        
        # Add user message to display
        current_text = self.message_area.toPlainText()
        new_text = f"{current_text}\n\n> {text}\n\nProcessing..."
        self.message_area.setPlainText(new_text)
        
        # Scroll to bottom
        cursor = self.message_area.textCursor()
        cursor.movePosition(cursor.MoveOperation.End)
        self.message_area.setTextCursor(cursor)
        
        # TODO: Integrate with existing command processing
        # For now, just show a simple response
        QTimer.singleShot(1000, lambda: self.show_response(f"I received: {text}"))
    
    def show_response(self, response):
        """Show a response message"""
        current_text = self.message_area.toPlainText()
        updated_text = current_text.replace("Processing...", response)
        self.message_area.setPlainText(updated_text)
        
        # Scroll to bottom
        cursor = self.message_area.textCursor()
        cursor.movePosition(cursor.MoveOperation.End)
        self.message_area.setTextCursor(cursor)
    
    def show_recent_work(self):
        """Show recent work in the message area"""
        try:
            from pathlib import Path
            work_file = Path("~/.local/share/goose-perception/LATEST_WORK.md").expanduser()
            if work_file.exists():
                content = work_file.read_text()
                self.message_area.setPlainText(f"Recent Work:\n\n{content}")
            else:
                self.message_area.setPlainText("No recent work found.")
        except Exception as e:
            self.message_area.setPlainText(f"Error loading recent work: {e}")
    
    def show_system_status(self):
        """Show system status"""
        import psutil
        
        # Get system info
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        
        status_text = f"""System Status:

CPU Usage: {cpu_percent}%
Memory Usage: {memory.percent}%
Available Memory: {memory.available // (1024*1024)} MB

Goose Status: Active
Mode: Menu Bar
"""
        self.message_area.setPlainText(status_text)
    
    def show_preferences(self):
        """Show preferences"""
        user_prefs = get_user_prefs()
        
        prefs_text = "Current Preferences:\n\n"
        for key, value in user_prefs.items():
            prefs_text += f"{key}: {value}\n"
        
        prefs_text += "\n\nTo modify preferences, use the configuration file or restart the application."
        
        self.message_area.setPlainText(prefs_text)


# Global instance
menu_bar_avatar_instance = None

def get_menu_bar_avatar():
    """Get the global menu bar avatar instance"""
    global menu_bar_avatar_instance
    if menu_bar_avatar_instance is None:
        menu_bar_avatar_instance = MenuBarAvatar()
    return menu_bar_avatar_instance

def show_message_menu_bar(message, duration=None, avatar_state='talking', action_data=None):
    """Show a message via menu bar avatar"""
    menu_bar = get_menu_bar_avatar()
    if menu_bar.is_enabled:
        menu_bar.show_message(message, duration, avatar_state, action_data)

def set_avatar_state_menu_bar(state):
    """Set avatar state for menu bar"""
    menu_bar = get_menu_bar_avatar()
    if menu_bar.is_enabled:
        menu_bar.set_avatar_state(state) 