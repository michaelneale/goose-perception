# Interface Modes System 🍎🪟

The Goose Perception project supports two interface modes to suit different user preferences and workflows.

## Interface Modes

### 1. 🪟 Floating Avatar (Default)

- **Description**: The classic floating goose avatar that appears on your screen
- **Features**:
  - Always visible floating window
  - Draggable positioning
  - Chat bubbles for interactions
  - Personality system with different expressions
- **Best for**: Users who want the full "AI companion" experience with constant visual presence

### 2. 🍎 Menu Bar Mode

- **Description**: Goose lives in your Mac menu bar as a discrete icon with popup window
- **Features**:
  - Minimal menu bar presence (32x32 icon)
  - Native macOS system notifications with sound
  - Right-click context menu for quick actions
  - Popup window for complex interactions and chat
  - Actionable notifications with clickable buttons
- **Best for**: Users who prefer minimal visual impact and native Mac experience

## Configuration

### Initial Setup

By default, Goose starts in floating avatar mode. To configure your preferred interface mode, use the configuration tool:

```bash
python configure_interface.py
```

### Configuration Options

The tool presents these options:

1. **Floating Avatar** - Classic floating window
2. **Menu Bar Icon** - Menu bar integration
3. **Show current configuration** - View current settings
4. **Exit** - Close configuration tool

After changing modes, restart Goose for changes to take effect.

## Menu Bar Features

### Context Menu Options

- **● Status: Ready**: Shows current status (click to open chat window)
- **📊 Run Report**: Execute optimization analysis report
- **🎤 Activate Listen Mode**: Start voice command mode
- **📝 Show Recent Work**: Display your latest work summary in popup
- **⚙️ System Status**: Show system information in popup
- **💬 Open Chat Window**: Launch the interaction popup window
- **⚙️ Preferences**: View current settings in popup
- **↔️ Switch to Floating Avatar**: Switch to floating avatar mode
- **✕ Quit**: Exit the application

### Popup Window

The popup window (380x370px) provides a compact interface with:

- **Interactive chat**: Type commands and see responses with rich formatting
- **Quick action buttons**: 📊 Report, 🎤 Listen, 📝 Work, 📋 Status
- **Dynamic action buttons**: For actionable suggestions and commands
- **System information display**: Recent work, system status, preferences
- **Automatic positioning**: Top-right of screen, stays on top
- **Dark/light mode support**: Adapts to system theme

### Notifications

- **Native macOS notifications**: Using system notification center with custom sounds
- **Sound customization**: Different sounds for different message types:
  - `Submarine` - Actionable messages requiring attention
  - `Glass` - General updates and success messages
  - `Basso` - Error or failure notifications
- **Clickable notifications**: Click to open popup window
- **Icon state changes**: Menu bar icon reflects avatar state (idle, talking, sleeping)
- **Actionable notifications**: Some notifications include action buttons for immediate response

## Technical Implementation

### Architecture

```
Main Application (PyQt6)
├── Interface Mode Detection
│   ├── User Preferences Loader
│   └── Mode Router
├── Floating Avatar Mode
│   ├── AvatarDisplay (QWidget)
│   ├── Chat Bubble System
│   ├── Drag & Drop Positioning
│   └── Personality State Manager
└── Menu Bar Mode
    ├── MenuBarAvatar (QSystemTrayIcon)
    ├── Context Menu (QMenu)
    ├── Popup Window (QMainWindow)
    ├── Native Notification System
    └── Action Handler System
```

### File Structure

- `avatar/avatar_display.py` - Floating avatar implementation with chat bubbles
- `avatar/menu_bar_avatar.py` - Menu bar implementation with popup window
- `configure_interface.py` - Interface configuration tool
- `~/.local/share/goose-perception/user_prefs.yaml` - User preferences storage

### Configuration Keys

```yaml
interface_mode: "floating" | "menubar"  # Main interface mode setting
```

## Usage Examples

### Floating Avatar Workflow

1. **Always visible**: Avatar window stays on screen for constant access
2. **Chat bubbles**: Rich interactions with actionable suggestions and responses
3. **Drag and position**: Click and drag avatar to reposition anywhere on screen
4. **Visual personality**: Different expressions and states (idle, talking, pointing, sleeping)
5. **Direct interaction**: Click avatar to interact, chat bubbles appear above/beside

### Menu Bar Workflow

1. **Discrete presence**: Small 32x32 goose icon in menu bar
2. **Quick actions**: Right-click menu for instant access to common tasks
3. **Popup interactions**:
   - **Double-click** icon for detailed chat window
   - **Single-click** when actionable notifications are pending
4. **Native notifications**: macOS system notifications with custom sounds
5. **Context switching**: Easy toggle between floating and menu bar modes

## Benefits

### Flexibility & Choice

- **Two distinct experiences**: Full companion vs minimal assistant
- **Easy switching**: Toggle between modes without losing settings
- **User preference driven**: Choose what works for your workflow

### Native macOS Experience

- **System integration**: Menu bar follows standard Mac conventions
- **Native notifications**: Uses macOS notification center with proper sounds
- **Familiar interactions**: Right-click menus, system tray behavior
- **Performance**: Lightweight system tray implementation

## Switching Between Modes

### From Floating to Menu Bar

1. **Using Configuration Tool**:

   ```bash
   python configure_interface.py
   ```

   - Choose option 2 (Menu Bar Icon)
   - Restart Goose
   - Look for the goose icon in your menu bar

2. **Runtime switching**: Currently requires restart after configuration change

### From Menu Bar to Floating

1. **Using Menu Bar**: Right-click goose icon → "↔️ Switch to Floating Avatar"
2. **Using Configuration Tool**:
   ```bash
   python configure_interface.py
   ```
   - Choose option 1 (Floating Avatar)
3. **Restart Goose** to see the floating avatar on your screen

## Troubleshooting

### Menu Bar Icon Not Appearing

- **System Requirements**: Requires macOS with system tray support
- **Permissions**: Check System Preferences > Security & Privacy for app permissions
- **Restart Required**: Some changes require restarting Goose
- **Check Configuration**: Verify `~/.local/share/goose-perception/user_prefs.yaml` contains `interface_mode: "menubar"`

### Context Menu Not Working

- **Right-click**: Ensure you're right-clicking the menu bar icon
- **Menu Refresh**: If menu appears empty, try clicking away and right-clicking again
- **macOS Quirks**: Sometimes menu creation needs a moment after app start

### Popup Window Issues

- **Hidden Behind Windows**: Popup may appear behind other applications
- **Force Show**: Use context menu → "💬 Open Chat Window"
- **Positioning**: Window appears at top-right by default
- **Stay on Top**: Window should stay above other applications

### Configuration Problems

- **File Permissions**: Ensure write access to `~/.local/share/goose-perception/`
- **YAML Syntax**: Check preferences file for syntax errors
- **User Context**: Run configuration tool as the same user who runs Goose
- **Reset Settings**: Delete `user_prefs.yaml` to reset to defaults

## Advanced Features

### Testing & Debugging

```bash
# Test menu bar notifications
python -c "from avatar.menu_bar_avatar import test_menu_bar_notification; test_menu_bar_notification('Test message')"

# Test actionable notifications
python -c "from avatar.menu_bar_avatar import test_menu_bar_notification; test_menu_bar_notification('Action test', actionable=True)"

# Debug menu status
python -c "from avatar.menu_bar_avatar import get_menu_bar_avatar; get_menu_bar_avatar().debug_menu_status()"
```

### Customization

- **Icon States**: Menu bar icon automatically changes based on avatar state
- **Sound Preferences**: Different notification sounds for different contexts
- **Window Positioning**: Popup window auto-positions at top-right of screen
- **Theme Adaptation**: UI adapts to system dark/light mode

## Known Limitations

- **Restart Required**: Mode switching requires application restart
- **macOS Only**: Menu bar mode is macOS-specific (uses QSystemTrayIcon)
- **Single Instance**: Only one popup window can be open at a time
- **Configuration Sync**: Minor inconsistency between `interface_mode` and `menu_bar_mode` settings

## Summary

The interface mode system provides flexibility between two distinct experiences:

- **🪟 Floating Avatar**: Full visual companion with persistent presence
- **🍎 Menu Bar Mode**: Minimal, native Mac integration with on-demand interaction

Choose the mode that best fits your workflow and productivity needs. Both modes provide full access to Goose's capabilities with different interaction paradigms.
