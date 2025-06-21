# Hybrid Interface System 🍎🪟

The Goose Perception project now supports multiple interface modes to suit different user preferences and workflows.

## Interface Modes

### 1. 🪟 Floating Avatar (Traditional)

- **Description**: The classic floating goose avatar that appears on your screen
- **Features**:
  - Always visible floating window
  - Draggable positioning
  - Chat bubbles for interactions
  - Personality system with different expressions
- **Best for**: Users who want the full "AI companion" experience

### 2. 🍎 Menu Bar Mode (Minimal)

- **Description**: Goose lives in your Mac menu bar as a small icon
- **Features**:
  - Unobtrusive menu bar presence
  - System notifications for messages
  - Right-click context menu for quick actions
  - Popup window for complex interactions
- **Best for**: Users who prefer minimal visual impact

### 3. 📱 Hybrid Mode (Best of Both)

- **Description**: Both floating avatar AND menu bar icon
- **Features**:
  - All floating avatar features
  - Plus menu bar convenience
  - Messages appear on both interfaces
  - User can choose which to interact with
- **Best for**: Power users who want maximum flexibility

## Configuration

### During Initial Setup

When you first run Goose, you'll be asked to choose your preferred interface mode:

```
How would you like to interact with Goose?

Options:
- floating: Traditional floating avatar (default)
- menubar: Menu bar icon with popup window
- hybrid: Both floating avatar and menu bar
```

### After Setup

Use the configuration tool to change modes:

```bash
python configure_interface.py
```

This will show your current configuration and allow you to switch modes.

## Menu Bar Features

### Context Menu Options

- **🎙️ Activate Listen Mode**: Start voice command mode
- **📋 Show Recent Work**: Display your latest work summary
- **🖥️ System Status**: Show system information
- **💬 Open Chat Window**: Launch the interaction popup
- **⚙️ Preferences**: View current settings
- **🔄 Switch to Floating Avatar**: Toggle interface modes
- **❌ Quit**: Exit the application

### Popup Window

- **Interactive chat**: Type commands and see responses
- **Action buttons**: For actionable suggestions
- **Work display**: View recent work and status
- **System info**: Monitor Goose's status

### Notifications

- System notifications for important messages
- Click notifications to open the popup window
- Icon changes color/state based on activity

## Technical Implementation

### Architecture

```
Main Application
├── Floating Avatar (if enabled)
│   ├── QWidget with chat bubbles
│   ├── Positioning system
│   └── Personality system
├── Menu Bar Avatar (if enabled)
│   ├── QSystemTrayIcon
│   ├── Context menu
│   └── Popup window (QMainWindow)
└── Shared Message System
    ├── Routes to active interfaces
    └── Handles actionable content
```

### File Structure

- `avatar/avatar_display.py` - Original floating avatar system
- `avatar/menu_bar_avatar.py` - New menu bar implementation
- `configure_interface.py` - Configuration tool
- User preferences stored in `~/.local/share/goose-perception/user_prefs.yaml`

## Usage Examples

### Hybrid Mode Workflow

1. **Quick status check**: Click menu bar icon
2. **Complex interaction**: Use floating avatar chat bubbles
3. **Background notifications**: Receive via menu bar notifications
4. **Voice commands**: Available through both interfaces

### Menu Bar Only Workflow

1. **Daily monitoring**: Passive menu bar presence
2. **Quick actions**: Right-click context menu
3. **Detailed work**: Double-click to open popup window
4. **Notifications**: System notifications for important updates

## Benefits

### Reduced Visual Clutter

- Menu bar mode eliminates floating windows
- Users can choose their preferred level of visual presence
- Hybrid mode allows situational choice

### Native macOS Experience

- Menu bar integration follows Mac conventions
- System notifications use native APIs
- Feels like other Mac productivity apps

### Improved Productivity

- Less screen real estate used (menu bar mode)
- Faster access to common functions (context menu)
- Better integration with Mac workflow

## Migration Guide

### From Floating to Menu Bar

1. Run `python configure_interface.py`
2. Choose option 2 (Menu Bar Icon)
3. Restart Goose
4. Look for the goose icon in your menu bar

### From Menu Bar to Hybrid

1. Run `python configure_interface.py`
2. Choose option 3 (Hybrid)
3. Restart Goose
4. Enjoy both interfaces!

## Troubleshooting

### Menu Bar Icon Not Appearing

- Check that system tray is available: Menu bar icons require macOS system tray support
- Verify permissions: Some security settings may block menu bar apps
- Try restarting Goose

### Popup Window Not Opening

- Check if window is behind other windows
- Try clicking the menu bar icon again
- Use the context menu option "Open Chat Window"

### Configuration Not Saving

- Ensure write permissions to `~/.local/share/goose-perception/`
- Check for YAML syntax errors in preferences file
- Try running `python configure_interface.py` as the same user

## Future Enhancements

- **Keyboard shortcuts**: Global hotkeys for menu bar mode
- **Notification settings**: Customize notification types and frequency
- **Custom menu items**: User-configurable menu bar options
- **Theme support**: Different icon styles for menu bar
- **Multiple popup windows**: Support for specialized interaction windows

## Feedback

The hybrid interface system is designed to make Goose more accessible and less intrusive while maintaining all its powerful features. Try different modes and see what works best for your workflow!
