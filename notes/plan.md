# GoosePerception - Development Plan

Working document for tracking implementation progress and next steps.

## Current Status: TinyAgent Integration Complete

The main capture → refine → insight → action pipeline is fully functional.
TinyAgent (Mac automation via LLMCompiler) has been integrated and tested.

---

## Completed Features

### TinyAgent Mac Automation (NEW)
- [x] TinyAgentService - main orchestrator for Mac automation
- [x] ToolRegistry - actor-based registry for 16 Mac automation tools
- [x] LLMCompilerParser - parses numbered action format with dependencies
- [x] ToolRAGService - keyword-based tool selection
- [x] TaskExecutor - parallel execution with dependency resolution
- [x] AppleScriptBridge - osascript integration for macOS APIs
- [x] 16 tools: Contacts, Calendar, Reminders, Mail, Notes, Messages, Maps, Files, Zoom
- [x] Self-test coverage (Tests 6-8: Registry, ToolRAG, Parser)

### Data Capture Layer
- [x] Screen capture with ScreenCaptureKit (every 20s)
- [x] OCR via Vision framework
- [x] Voice capture with WhisperKit (local whisper-tiny.en)
- [x] Face detection and emotion analysis via Vision
- [x] Directory activity tracking via Spotlight
- [x] App usage aggregation from captures

### Knowledge Refiners
- [x] ProjectsRefiner - extracts project names
- [x] CollaboratorsRefiner - extracts people
- [x] InterestsRefiner - extracts topics
- [x] TodosRefiner - extracts tasks from screen text

### Insight Generators
- [x] WorkSummaryGenerator (2h cooldown)
- [x] PatternGenerator (4h cooldown)
- [x] ProgressGenerator (1h cooldown, no LLM)
- [x] CollaborationGenerator (3h cooldown)
- [x] WellnessInsightGenerator (30m cooldown)

### Action Generators
- [x] WellnessActionGenerator - triggers on accumulated wellness insights
- [x] ReminderActionGenerator - triggers on old pending TODOs
- [x] FocusActionGenerator - triggers on context-switching patterns
- [x] LateNightActionGenerator - triggers after 10pm with work activity

### UI
- [x] Menu bar app with status icon
- [x] Dashboard with tabs: Services, Knowledge, Insights, Actions, Activity, Captures, LLM
- [x] Service toggles with real-time status (audio level, emotion)
- [x] Mood summary card in Knowledge tab
- [x] Action popups with dismiss/snooze/complete
- [x] Toast notifications
- [x] Preferences persistence

### Database
- [x] All tables: screen_captures, voice_segments, face_events, projects, collaborators, interests, todos, insights, actions, app_usage, directory_activity
- [x] Migrations system
- [x] CRUD operations for all entities

---

## Known Issues

### Minor
- [ ] `AVAuthorizationStatus` conformance warning (cosmetic)
- [ ] Async warning in snooze checker (cosmetic)

### To Investigate
- [ ] Screen capture permission sometimes needs re-grant after rebuild
- [ ] WhisperKit model download progress not shown in UI

---

## Next Steps

### Short Term
1. **Test the full pipeline end-to-end** - Verify captures → refiners → insights → actions flow
2. **Tune generator thresholds** - Current settings may be too conservative
3. **Add insight popup trigger** - Currently insights only go to the list, not popups

### Medium Term
1. **Settings UI** - Allow users to configure intervals, thresholds, cooldowns
2. **Data retention** - Auto-cleanup old captures/events
3. **Export** - Export knowledge to markdown/JSON

### Phase 2: Agent Actions (In Progress)
See `notes/agent-actions-implementation.md` for the full plan:
1. **Recipe System** - User-configurable triggers and actions
2. **Agent Runner** - CLI bridge to goose/claude/amp  
3. **Context Compiler** - Rich prompt templates with knowledge injection
4. **Scheduled Actions** - Cron-like triggers for recurring tasks

**TinyAgent Integration Status:**
- ✅ Tool Registry and 16 Mac tools implemented
- ✅ LLMCompiler parser for plan parsing
- ✅ ToolRAG for tool selection
- ✅ TaskExecutor for parallel execution
- ⏳ End-to-end testing with actual AppleScript execution
- ⏳ UI integration for automation results

---

## Architecture Notes

### Pipeline Flow
```
Capture (continuous) → Database
                           ↓
Analysis (every 20min) → Refiners → Knowledge tables
                           ↓
                      Insight Generators → insights table
                           ↓
                      Action Generators → actions table → Popup
```

### Key Principles
1. **Refiners** extract structured knowledge, passing existing items to avoid duplicates
2. **Insight Generators** observe and create observations (low bar)
3. **Action Generators** decide when to interrupt (high bar, need accumulated evidence)
4. **Mood** comes from face detection, not LLM - it's an input to generators
5. **Actions** are separate from **TODOs** - actions are system-generated, TODOs are extracted from screen

### Generator Context
- `GeneratorContext` for insight generators: projects, collaborators, interests, todos, face events, captures, voice
- `ActionContext` for action generators: recent insights, recent actions, recent dismissals, mood, work duration

---

## File Reference

| File | Purpose |
|------|---------|
| `App/AppDelegate.swift` | Service init, menu bar, callbacks |
| `Analysis/AnalysisScheduler.swift` | Pipeline orchestration |
| `Services/LLM/LLMService.swift` | MLX model runner |
| `Services/LLM/Refiners/*.swift` | Knowledge extractors |
| `Services/LLM/Generators/*.swift` | Insight & Action generators |
| `Services/TinyAgent/TinyAgentService.swift` | Mac automation orchestrator |
| `Services/TinyAgent/TinyAgentTool.swift` | Tool protocol + registry |
| `Services/TinyAgent/LLMCompilerParser.swift` | Plan parser |
| `Services/TinyAgent/TaskExecutor.swift` | Parallel task execution |
| `Services/TinyAgent/Tools/*.swift` | 16 Mac automation tools |
| `Views/DashboardView.swift` | Main UI |
| `Views/InsightPopupManager.swift` | Popups and toasts |
| `Views/AutomationResultSheet.swift` | TinyAgent results UI |
| `Database/Database.swift` | GRDB wrapper |

---

## Commands

```bash
just build    # Build .app bundle
just run      # Build and launch
just clean    # Clean artifacts
just test     # Run tests (if available)
```
