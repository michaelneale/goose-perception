# Menu Bar Notifications with osascript 🔔

This document describes the enhanced notification system for the Goose menu bar interface using native macOS notifications via osascript.

## Overview

The menu bar interface now uses **native macOS notifications** via `osascript` instead of just Qt system tray notifications. This provides a more integrated macOS experience with:

- ✅ Native notification center integration
- 🔊 System sound support (Glass, Submarine, Basso)
- 🎯 Actionable notification support
- 🍎 Better macOS user experience
- 📱 Notifications appear in notification center history

## Features

### Sound-Based Notification Types

The system automatically chooses appropriate sounds based on context:

- **Glass** (default): Regular notifications, success messages
- **Submarine**: Actionable messages, important updates, work in progress
- **Basso**: Error messages, failures

## Implementation Details

### Core Functions

#### `show_notification(title, message, duration, action_data, sound_name)`

Enhanced notification method that:

1. Escapes special characters for AppleScript
2. Builds appropriate osascript command
3. Executes notification with sound
4. Falls back to Qt on error

#### `show_message(message, duration, avatar_state, action_data)`

Main message display method that:

1. Updates menu bar status
2. Chooses appropriate sound based on content
3. Shows osascript notification
4. Opens popup for actionable messages

### Sound Selection Logic

```python
if action_data:
    sound_name = "Submarine"  # Attention-grabbing
elif "error" in message.lower() or "failed" in message.lower():
    sound_name = "Basso"      # Error sound
elif "complete" in message.lower() or "success" in message.lower():
    sound_name = "Glass"      # Success sound
else:
    sound_name = "Glass"      # Default
```

### AppleScript Template

```applescript
# Regular notification
display notification "message" with title "title" sound name "sound"

# Actionable notification with error handling
try
    set theAlert to display notification "message" with title "title" subtitle "🔔 Tap notification or menu to interact" sound name "sound"
on error
    display notification "message" with title "title" subtitle "🔔 Click menu bar icon to interact" sound name "sound"
end try
```

## Usage Examples

### Regular Notification

```python
menu_bar.show_notification("Goose", "Task completed!", sound_name="Glass")
```

### Success Notification

```python
menu_bar.show_notification("Goose", "Analysis complete! ✅", sound_name="Glass")
```

### Error Notification

```python
menu_bar.show_notification("Goose", "Operation failed ❌", sound_name="Basso")
```

### Actionable Notification

```python
action_data = {
    'action_command': 'optimize-workflow',
    'action_type': 'optimization',
    'actions': [
        {'name': '✅ Do it!', 'action_command': 'run_optimize'},
        {'name': '⏸️ Skip', 'action_command': 'skip_action'}
    ]
}
menu_bar.show_message("Optimization suggestion ready!", action_data=action_data)
```

## Testing

### Quick Test Script

Run the included test script:

```bash
python test_menu_notifications.py
```

This tests:

1. Direct osascript functionality
2. Regular notifications with different sounds
3. Actionable notifications
4. Error handling

### Manual Testing Functions

```python
# Test regular notification
from avatar.menu_bar_avatar import show_menu_bar_notification
show_menu_bar_notification("Test", "Hello World!", "Glass")

# Test actionable notification
from avatar.menu_bar_avatar import test_menu_bar_notification
test_menu_bar_notification("Action needed!", actionable=True)
```

## Integration with Existing System

### Menu Bar Actions

All menu bar actions now use appropriate sounds:

- **Optimize Report**: Submarine → Glass/Basso (start → success/error)
- **Listen Mode**: Glass (activation) / Basso (error)
- **Mode Switching**: Glass (confirmation)

### Interaction Flow

1. **Notification appears** with native macOS styling and sound
2. **User sees notification** in notification center
3. **For actionable messages**: User clicks menu bar icon
4. **Popup window opens** with action buttons
5. **User interacts** with "✅ Do it!" or "Skip" buttons

## Troubleshooting

### Notifications Not Appearing

1. Check macOS notification permissions for Terminal/Python
2. Verify `osascript` command works: `osascript -e 'display notification "test"'`
3. Check System Preferences → Notifications & Focus → Do Not Disturb

### Recent macOS Updates (especially Sonoma/Sequoia)

There have been reports, particularly with recent macOS versions (like macOS Sonoma and the upcoming Sequoia), where notification behavior from osascript in Terminal has become inconsistent for some users. Sometimes running the display notification command once in Script Editor (Applications/Utilities/Script Editor.app) will "prime" the system and then it will start working from Terminal.

Here's how to do it:

1. Open Script Editor.app (you can find it in Applications/Utilities).
2. Paste a simple notification command:
```
display notification "Test from Script Editor" with title "Script Editor Test"
```
3. Click the "Run" button (the play icon) in Script Editor.
4. If it prompts you for permission to send notifications for "Script Editor," grant it.
5. See if this notification appears.

