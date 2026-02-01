# Goose Avatar System 🤖👁️

The Goose Perception project now includes a **creepy avatar system** that provides visual feedback and suggestions through a floating avatar with chat bubbles.

## Features

### 🎭 Creepy Avatar Display
- **Floating Avatar**: A semi-transparent avatar that floats on your screen (top-right corner by default)
- **Chat Bubbles**: Dark-themed speech bubbles that appear next to the avatar
- **Always Watching**: The avatar appears when Goose has suggestions or observations
- **Interactive**: Click the avatar to cycle through expressions and dismiss messages
- **Smart Positioning**: Automatically adjusts bubble placement to stay on screen

### 🧠 Intelligent Suggestions
The avatar provides different types of suggestions based on your activity:

- **🔍 Work Pattern Alerts**: "I've been watching your workflow... Want me to optimize it?"
- **📅 Meeting Notices**: "Your next meeting starts in 10 minutes. Should I prepare the agenda?"
- **🎯 Focus Suggestions**: "I notice you're switching between tasks frequently. Want help prioritizing?"
- **📈 Productivity Insights**: "Your most productive hours seem to be 9-11 AM. Plan important tasks then."
- **⏸️ Break Reminders**: "You've been working for 47 minutes. Time for a stretch?"
- **⚡ Optimization Tips**: "I could automate that repetitive task you just did..."

### 🔗 Observer Integration
The avatar system integrates with the existing observer recipes:
- Monitors work pattern files (`WORK.md`, `LATEST_WORK.md`)
- Tracks interactions and contributions
- Responds to activity changes
- Provides contextual suggestions based on observed patterns

## How It Works

### Architecture
```
Observer System → Observer-Avatar Bridge → Avatar Display → User
     ↓                      ↓                    ↓
  Work Analysis    Message Generation    Visual Feedback
```

1. **Observers** continuously monitor your activity and generate reports
2. **Bridge** monitors observer output files for changes
3. **Avatar System** displays appropriate messages based on context
4. **User** sees floating avatar with contextual suggestions

### Message Types
- **🎙️ Voice Processing**: Shows when processing voice commands
- **🖥️ Screen Analysis**: Appears during screen capture analysis
- **👁️ Passive Watching**: Random observations and suggestions
- **📊 Pattern Recognition**: Insights based on work patterns
- **⚠️ Attention Alerts**: Important notifications

## Usage

### Automatic Mode
Once started, the avatar runs automatically:
- Appears when Goose has suggestions
- Shows processing status during voice/screen commands
- Provides periodic insights based on observed patterns
- Auto-hides after displaying messages

### Interactive Mode
- **Click Avatar**: Cycle through expressions, dismiss current message
- **Click Bubble**: Dismiss current message immediately
- **Multiple Messages**: Messages queue up and display sequentially

### Testing
Run the test script to see the avatar in action:
```bash
python test_avatar.py
```

## Configuration

### Avatar Appearance
- **Size**: 80x80 pixels (configurable in `load_avatar_images()`)
- **Position**: Top-right corner (configurable in `position_avatar()`)
- **Transparency**: 90% opacity (configurable via `attributes('-alpha', 0.9)`)
- **Images**: Uses `avatar/goose.png` from avatar directory

### Message Timing
- **Display Duration**: 8 seconds (configurable via `message_duration`)
- **Check Interval**: 30 seconds between observation checks
- **Random Suggestions**: 30% chance during periodic checks

### Bubble Styling
- **Background**: Dark theme (`#2c3e50`)
- **Text**: White text with Arial font
- **Width**: Auto-wrap at 250 pixels
- **Positioning**: Smart placement to avoid screen edges

## Integration Points

### With Listen.py
- Starts automatically when Goose Perception launches
- Shows status during voice command processing
- Provides feedback for hotkey screen captures

### With Agent.py
- Displays processing messages during Goose invocation
- Shows completion status for voice/screen requests
- Integrates with background processing notifications

### With Observer System
- Monitors observer output files for changes
- Triggers contextual suggestions based on work patterns
- Provides insights from accumulated data

## Customization

### Adding New Avatar Images
1. Add image files to the project root
2. Modify `load_avatar_images()` in `avatar_display.py`
3. Images will be resized to 80x80 automatically

### Custom Message Templates
Edit `observer_avatar_bridge.py` to customize:
- Message templates in `message_templates` dict
- Trigger conditions in `_handle_*` methods
- Random message probability in `_process_file_change()`

### Positioning and Appearance
Modify `avatar_display.py`:
- `position_avatar()`: Change screen position
- `show_message()`: Modify bubble appearance
- Window attributes: Adjust transparency, always-on-top behavior

## Creepy Features 👻

The avatar is designed to be subtly unsettling while helpful:

- **Persistent Watching**: "👁️ I notice everything..."
- **Predictive Insights**: "🔮 Based on your patterns, you'll need coffee in 23 minutes..."
- **Efficiency Monitoring**: "📈 Your productivity dipped 12 minutes ago..."
- **Pattern Recognition**: "🧠 I've learned your preferences. Want me to anticipate your next move?"
- **Omniscient Suggestions**: "🎯 I can predict what you need before you realize it yourself."

## Files

- `avatar_display.py`: Main avatar display system
- `observer_avatar_bridge.py`: Bridge between observers and avatar
- `test_avatar.py`: Test script for avatar functionality
- `AVATAR_SYSTEM.md`: This documentation

## Future Enhancements

- **Multiple Avatar Expressions**: Different goose images for different moods
- **Voice Synthesis**: Avatar speaking suggestions aloud
- **Gesture Animations**: Simple animations for avatar interactions
- **Contextual Positioning**: Moving avatar based on active application
- **Smart Notifications**: Integration with system notifications
- **Learning System**: Avatar adapts messages based on user responses

## Troubleshooting

### Avatar Not Appearing
- Check if Pillow is installed: `pip install pillow`
- Verify `avatar/goose.png` exists in avatar directory
- Check console for error messages

### Messages Not Triggering
- Ensure observer system is running (`just run`)
- Check if perception directory exists: `~/.local/share/goose-perception/`
- Verify observer files are being created and updated

### Performance Issues
- Adjust check intervals in `observer_avatar_bridge.py`
- Reduce message probability in random triggers
- Optimize image loading in `avatar_display.py`

---

*"I'm always watching, always learning, always ready to help... whether you asked for it or not." - Goose* 👁️🤖 