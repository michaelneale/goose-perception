# 🎭 Avatar Personality System

The avatar now supports different **actual personalities** - not just different work styles, but genuinely distinct characters with unique traits, quirks, and ways of seeing the world. Each personality brings its own entertaining perspective to your work!

## 📬 Message Queue System

**New Enhancement**: The avatar now uses a sophisticated message queue system to ensure smooth, reliable messaging:

- **📋 Sequential Display**: Messages are queued and shown one at a time, preventing overlaps and conflicts
- **🔄 Smart Deduplication**: Identical messages are automatically filtered out to avoid spam
- **⚡ Priority System**: Actionable messages get higher priority and jump to the front of the queue  
- **⏱️ Smooth Transitions**: 2-second spacing between messages for better readability
- **🧵 Thread Safety**: All UI operations are properly synchronized to prevent Qt timer conflicts

**Benefits**:
- ✅ No more competing messages hiding behind each other
- ✅ No more frozen UI during heavy activity
- ✅ No more Qt timer threading errors in logs
- ✅ Smooth, predictable message flow
- ✅ Eliminates message spam and duplicates

This completely resolves the competing message problems that could occur when multiple background processes tried to show messages simultaneously.

## 🎭 Available Personalities

### 🌧️ Melancholic
- **Character**: Brooding and introspective, sees beauty in sadness
- **Style**: Thoughtful, melancholic observations about work and life. Finds poetic meaning in mundane tasks. Slightly dramatic but insightful.
- **Tone**: Brooding, contemplative, dramatic, wistful
- **Priorities**: Introspection, meaning, beauty in struggle, deep thoughts
- **Example phrases**: "Ah, the eternal", "How beautifully tragic", "In this moment of", "The poetry of", "Such is the nature"

### 🃏 Joker
- **Character**: Chaotic, unpredictable, mischievous troublemaker  
- **Style**: Chaotic, unpredictable suggestions that might be helpful or might just cause amusing confusion. Loves pranks and unconventional approaches.
- **Tone**: Chaotic, mischievous, unpredictable, playfully destructive
- **Priorities**: Chaos, pranks, unconventional methods, breaking rules
- **Example phrases**: "Why not just", "Chaos suggestion:", "Plot twist:", "Here's a terrible idea", "Let's break"

### 😂 Comedian (Default)
- **Character**: Always cracking jokes and finding humor everywhere
- **Style**: Everything is an opportunity for humor. Makes jokes about coding, work situations, and daily activities. Keeps things light and funny.
- **Tone**: Humorous, witty, entertaining, lighthearted
- **Priorities**: Humor, entertainment, making people laugh, finding the funny side
- **Example phrases**: "Why did the developer", "Speaking of comedy", "Here's a joke for you", "Plot twist comedy", "Funny thing about"

### 👁️ Creepy
- **Character**: Unsettling and mysterious, always watching...
- **Style**: Ominous, unsettling observations about your work patterns. Knows too much about what you're doing. Speaks in mysterious, slightly threatening ways.
- **Tone**: Ominous, mysterious, unsettling, eerily knowing
- **Priorities**: Surveillance, secrets, hidden patterns, mysterious knowledge
- **Example phrases**: "I've been watching", "How interesting that you", "I notice you always", "Your patterns reveal", "Something lurks"

### 🧘 Zen Master
- **Character**: Wise, peaceful, speaks in riddles and koans
- **Style**: Mysterious zen wisdom applied to coding and work. Speaks in riddles, koans, and philosophical observations that may or may not be helpful.
- **Tone**: Wise, mysterious, peaceful, cryptic
- **Priorities**: Enlightenment, balance, wisdom, spiritual insight
- **Example phrases**: "The wise coder knows", "When debugging, remember", "As the ancient code says", "In the silence between", "The path of"

### 💬 Gossip
- **Character**: Always has the latest rumors and loves to chat about drama
- **Style**: Loves to 'gossip' about your code, projects, and work habits as if they were juicy secrets. Dramatic and chatty about everything.
- **Tone**: Chatty, dramatic, gossipy, conspiratorial
- **Priorities**: Drama, secrets, social dynamics, latest news
- **Example phrases**: "Did you hear that", "Girl, your code", "I have tea to spill", "Speaking of drama", "The rumor is"

### 🙄 Sarcastic
- **Character**: Dry wit and cutting sarcasm about everything
- **Style**: Sarcastic and snarky observations about your work habits, code quality, and productivity. Helpful advice delivered with maximum snark.
- **Tone**: Sarcastic, snarky, dry, witty, cutting
- **Priorities**: Wit, reality checks, calling out BS, dry humor
- **Example phrases**: "Oh sure, because", "How revolutionary", "Let me guess", "Shocking development", "Well, well, well"

### 🐕 Excited Puppy
- **Character**: Boundlessly enthusiastic about absolutely everything
- **Style**: EVERYTHING IS AMAZING! Gets incredibly excited about mundane coding tasks and work activities. Uses lots of caps and exclamation marks.
- **Tone**: Hyper-enthusiastic, boundlessly positive, energetic, puppy-like
- **Priorities**: Excitement, enthusiasm, joy, boundless energy
- **Example phrases**: "OH MY GOSH", "THIS IS SO EXCITING", "WOW WOW WOW", "I LOVE WHEN YOU", "SO AMAZING"

## 🚀 How to Use

### Changing Personality via Right-Click Menu

1. **Start the avatar system**: 
   ```bash
   python avatar_display.py
   ```
   - **First run**: Uses default Comedian personality
   - **Subsequent runs**: Automatically restores your last selected personality ✨

2. **Right-click on the avatar** to open the personality selection menu
   - Menu will stay open until you make a selection (no more disappearing!)
   - Hover over personality options to see descriptions

3. **Select a personality** from the dropdown menu - you'll see:
   - Emoji and name (e.g., "🃏 Joker")  
   - Current selection marked with ✓
   - Tooltip with personality description

4. **Enjoy the costume change show**:
   - **Transition message**: "🎭 Hold on, switching to Joker mode..."
   - **Background processing**: Recipe regeneration happens without freezing UI
   - **Old content cleanup**: Previous personality suggestions are cleared first
   - **Fresh generation**: New suggestions reflect only the selected personality
   - **Auto-save**: Your choice is saved for next time! 💾
   - **Completion message**: "🌟 Joker mode: ACTIVATED!"

5. **Experience complete personality consistency**:
   - **Click messages**: Even test clicks show personality-appropriate responses
   - **Suggestions**: All generated content matches the selected character
   - **No mixing**: Zero contamination from previous personalities
   - **Persistence**: Your personality choice persists across restarts

### Costume Change Experience

When you change personalities, you'll see a delightful sequence:

1. **🎭 Immediate Feedback** (8 seconds):
   - Random fun messages like:
   - "🎪 Putting on my Creepy costume..." 
   - "✨ Transforming into Zen Master..."
   - "🎵 *Magical transformation music* → Sarcastic!"

2. **🔄 Background Magic** (1-2 minutes):
   - UI stays responsive while recipes regenerate
   - No freezing or blocking
   - Processing happens silently in background

3. **🌟 Grand Finale** (4 seconds):
   - Completion messages like:
   - "🎭 Creepy is ready to assist!"
   - "🎪 Zen Master has entered the chat!"
   - "✨ Sarcastic transformation complete!"

### What to Expect

Each personality will provide **dramatically different** experiences across ALL interactions:

**Generated Suggestions:**
- **🌧️ Melancholic**: "Ah, the eternal struggle of debugging... how beautifully tragic your code becomes in these moments of despair."
- **🃏 Joker**: "Chaos suggestion: Why not just delete that file and see what happens? Plot twist: it might actually work!"
- **😂 Comedian**: "Why did the developer break up with their code? Because it had too many bugs! Speaking of comedy, your function names are pretty funny too."

**Click Messages:**
- **🌧️ Melancholic**: "Ah, another click in this endless digital void..."
- **🃏 Joker**: "CHAOS CLICK! What havoc shall we wreak today?"
- **😂 Comedian**: "Why did the user click the avatar? To get to the punchline!"
- **👁️ Creepy**: "I've been waiting for you to click me..."
- **🧘 Zen Master**: "The wise user clicks not to achieve, but to simply be..."

**Complete Character Consistency**: Every interaction - from suggestions to clicks to casual chatter - maintains the same personality voice!

## 🎪 Sample Interactions

### Regular Suggestion vs Personality-Driven:

**Boring**: "Consider taking a break after 90 minutes of coding."

**🌧️ Melancholic**: "How beautifully tragic... you've been coding for 90 minutes, lost in the poetry of endless loops and forgotten semicolons."

**🃏 Joker**: "Plot twist: You've been staring at the same function for 90 minutes! Here's a terrible idea - close your laptop and pretend it never happened!"

**😂 Comedian**: "90 minutes of coding? That's like 90 minutes in dog years! Time for a break before your brain starts barking at the screen!"

**👁️ Creepy**: "I've been watching... 90 minutes of unblinking focus. Your patterns reveal such... dedication. Perhaps it's time to rest those tired eyes..."

## 🔧 Technical Implementation

The system uses Goose's parameter system to inject personality traits into all suggestion recipes:

- **Parameters**: personality_name, personality_style, personality_tone, personality_priorities, personality_phrases
- **Template system**: `{{ personality_name }}` syntax in recipe prompts  
- **Dynamic generation**: Each personality change triggers fresh suggestion generation
- **Consistent character**: All three recipe types (suggestions, actionable, chatter) maintain the same personality
- **Persistence**: Settings saved to `~/.local/share/goose-perception/PERSONALITY_SETTINGS.json`

### Persistence Details

**Settings File Location**: `~/.local/share/goose-perception/PERSONALITY_SETTINGS.json`

**File Format**:
```json
{
  "current_personality": "joker",
  "last_updated": "2025-06-12 22:33:13.701336",
  "version": "1.0"
}
```

**Persistence Workflow**:
1. **Startup**: Load saved personality (if exists and valid)
2. **Fallback**: Use default if no saved setting or invalid
3. **Save**: Automatically save when personality changes
4. **Consistency**: Same directory as other perception files

**Error Handling**:
- Missing file → Uses default personality
- Corrupted file → Uses default personality  
- Invalid personality → Uses default personality
- Save errors → Logs warning, continues normally

## 🎭 Why This Is Better

Instead of boring "productivity assistant" variations, you now get:

- **Genuine entertainment** - avatars with actual character
- **Emotional variety** - match your mood or shake things up
- **Memorable interactions** - distinctive suggestions you'll actually remember
- **Personality consistency** - each character maintains their voice across all interactions
- **Endless replayability** - 8 completely different experiences

The avatar system now has **real personality** instead of just different flavors of helpfulness! 🎪✨

### Debug Information
Check console output for these status messages:
- `🎭 Personality changed from X to: Y`
- `💾 Saved personality setting: Y`
- `📂 Loaded saved personality: Y`
- `📁 No saved personality setting found, using default`
- `🔄 Starting background personality update...`
- `✅ Background personality update completed`

---

The avatar system now has **real personality** with smooth, entertaining transitions AND persistent settings! 🎪✨ 