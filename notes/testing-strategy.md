# TinyAgent/Mac Automation Testing Strategy

## Overview

The Mac automation (internally called TinyAgent) pipeline has these components:

1. **User Query** → Natural language request
2. **ToolRAG** → Selects relevant tools based on query keywords
3. **LLM Planner** → Generates execution plan in LLMCompiler format
4. **Parser** → Parses plan into executable tasks with dependencies
5. **Task Executor** → Executes tasks in dependency order
6. **AppleScriptBridge** → Executes actual AppleScript commands
7. **Joinner** → Evaluates results, decides finish/replan

## Testing Layers

### Layer 1: Unit Tests (No System Access Required)

**Target: LLMCompilerParser**
- Test parsing various plan formats
- Test argument extraction (strings, numbers, arrays, references)
- Test dependency resolution
- Test edge cases (empty args, special chars, Unicode)

**Target: escapeForAppleScript**
- Test escaping quotes, backslashes, newlines, tabs
- Test Unicode passthrough
- Test empty strings and edge cases

**How to run:**
```bash
GoosePerception --test-applescript --dry-run
```

### Layer 2: Integration Tests (Requires Permissions)

**Target: AppleScriptBridge methods**
- Test each app integration: Contacts, Reminders, Calendar, Notes, Mail, Messages, Maps
- Verify permission prompts work correctly
- Test error handling for denied permissions

**How to run:**
```bash
GoosePerception --test-applescript --app contacts
GoosePerception --test-applescript --app reminders
# etc.
```

### Layer 3: End-to-End Tests (Full Pipeline)

**Target: Complete TinyAgent flow**
- Test with known queries that should trigger specific tools
- Verify ToolRAG selects appropriate tools
- Verify parser handles LLM output variations
- Verify execution produces expected results

**Test queries:**
1. "Get John's phone number" → get_phone_number tool
2. "Create a reminder for tomorrow at 9am" → create_reminder tool
3. "Send a text to Mom saying I'm running late" → get_phone_number + send_sms
4. "Open Maps to San Francisco" → maps_open_location

## Known Issues & Debugging

### AppleScript Formatting Issues

**Symptoms:** AppleScript execution fails intermittently

**Root causes to check:**
1. **Date formatting** - AppleScript can't parse ISO8601 strings directly
   - Solution: Use `(current date) + seconds` approach
   - Or: Set date components individually

2. **String escaping** - Quotes and backslashes in user content
   - Solution: escapeForAppleScript() must handle: \\ " \n \r \t
   - Check: Multi-line strings in templates

3. **Calendar name mismatch** - Default calendar may not be named "Calendar"
   - Solution: Query available calendars first, or use "default calendar"

4. **Notes folder mismatch** - Default folder may not be named "Notes"
   - Solution: Use "default account" instead of hardcoded name

### Permission Errors

**Symptoms:** "not allowed to send Apple events" errors

**Solution:**
1. System Settings > Privacy & Security > Automation
2. Find GoosePerception and enable each app
3. If not listed, trigger by running a test command

**Quick permission test buttons are in Dashboard > Actions tab**

### Debugging Tips

1. **Add logging to AppleScriptBridge:**
   ```swift
   logger.debug("Executing AppleScript: \(script.prefix(200))")
   ```

2. **Test scripts manually:**
   ```bash
   osascript -e 'tell application "Reminders" to get name of first list'
   ```

3. **Check Activity Log tab** - Shows all service activity with timestamps

4. **Use --verbose flag** with test harness for full output

## Test Harness Commands

```bash
# Full self-test (existing)
GoosePerception --self-test

# Test harness with options
GoosePerception --test-harness --test-database
GoosePerception --test-harness --test-analysis --mock

# AppleScript-specific tests (new)
GoosePerception --test-applescript --dry-run      # Escaping only
GoosePerception --test-applescript --verbose      # Full output
GoosePerception --test-applescript --app calendar # Specific app
```

## UI Testing Notes

- **Don't call it "TinyAgent"** in user-facing UI
- Use "Mac Automation" or "Run Automation" instead
- Window title should be "Goose Perception" (not "...Dashboard")
- Test that title doesn't get cut off at various window sizes
