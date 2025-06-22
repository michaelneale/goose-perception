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

### Smart Fallback System

- Primary: Native osascript notifications with sound
- Fallback: Qt system tray notifications (if osascript fails)
- Enhanced Qt messages for actionable notifications

### Actionable Notifications

For notifications with action data:

- Shows native notification with "Tap to interact" subtitle
- Stores action data for menu bar interaction
- Enhanced Qt fallback with "(Click menu bar for actions)" indicator
- Single-click menu bar icon opens interaction popup

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

## Benefits Over Qt Notifications

### Native Experience

- Appears in macOS notification center
- Follows system notification preferences
- Consistent with other Mac apps
- Better accessibility support

### Enhanced Functionality

- Rich sound support
- Better visual styling
- Notification history
- System-level do not disturb integration

### Better User Engagement

- More noticeable than Qt system tray popups
- Clear actionable message indicators
- Seamless menu bar integration

## Sound Reference

### Available macOS Notification Sounds

- **Glass**: Default, success, regular notifications
- **Submarine**: Important, actionable, work in progress
- **Basso**: Errors, failures
- **Blow**: Alternative attention sound
- **Bottle**: Alternative notification sound
- **Frog**: Alternative notification sound
- **Funk**: Alternative notification sound
- **Hero**: Alternative success sound
- **Morse**: Alternative attention sound
- **Ping**: Alternative notification sound
- **Pop**: Alternative notification sound
- **Purr**: Alternative gentle sound
- **Sosumi**: Alternative notification sound
- **Tink**: Alternative gentle sound

## Troubleshooting

### Notifications Not Appearing

1. Check macOS notification permissions for Terminal/Python
2. Verify `osascript` command works: `osascript -e 'display notification "test"'`
3. Check System Preferences → Notifications & Focus → Do Not Disturb

### No Sound

1. Check system volume settings
2. Verify notification sound settings in System Preferences
3. Test with different sound names

### Actionable Messages Not Working

1. Ensure menu bar mode is enabled
2. Check that popup window opens on menu bar click
3. Verify action data structure is correct

## Future Enhancements

- **Rich Notifications**: Support for images and complex layouts
- **Custom Sounds**: Add Goose-specific notification sounds
- **Notification Grouping**: Group related notifications
- **User Preferences**: Configurable notification settings
- **Notification Actions**: True macOS notification action buttons (requires advanced setup)

---

_This enhancement provides a more native macOS experience while maintaining full compatibility with the existing avatar system._
