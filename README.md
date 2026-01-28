# Goose Perception

Listens to you always, watches your screen and watches you via camera to learn from you. 

Totally local (really - all local models, all the time, no external LLMs)

<img width="1024" height="1536" alt="image" src="https://github.com/user-attachments/assets/8d64aef1-29b5-4ae0-bc7c-b1e8a65c926e" />


> **Experimental** - This project is actively evolving. The core capture and insight pipeline works, but the automated actions system (DSL-based macOS automation) is still being implemented and tested.

A macOS menu bar app that acts as a personal ambient intelligence assistant. Captures screen, voice, and face data, analyzes it with on-device LLMs, and surfaces insights to help you stay aware of your work patterns, collaborators, and wellbeing.

**100% local. No cloud. No tracking.**

## Quick Start

```bash
# Build the app
just build

# Run (builds if needed)
just run

# Clean build artifacts
just clean
```

Requires macOS 14+ and Apple Silicon (M1/M2/M3).

## Features

- **Screen Capture** - OCR text from your focused windows every 20 seconds
- **Voice Capture** - Speech-to-text using WhisperKit (local Whisper model)
- **Face Detection** - Presence and emotion tracking via Vision framework
- **Knowledge Extraction** - LLM identifies projects, collaborators, interests, and TODOs
- **Wellness Monitoring** - Detects overwork, stress, and late-night patterns
- **Smart Actions** - Popup notifications when you need a break or have pending tasks

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           DATA CAPTURE (continuous)                      │
│                                                                          │
│   Screen (20s) ──► OCR ───┐                                              │
│   Voice ──► WhisperKit ───┼──► SQLite Database                           │
│   Face ──► Vision ────────┘                                              │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    REFINERS (every 20 min)                               │
│                                                                          │
│   Raw data ──► LLM Refiners ──► Knowledge (projects, people, topics)     │
│                                                                          │
│   ProjectsRefiner │ CollaboratorsRefiner │ InterestsRefiner │ TodosRefiner
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    INSIGHT GENERATORS                                    │
│                                                                          │
│   Knowledge + Mood ──► Generators ──► Insights (observations)            │
│                                                                          │
│   WorkSummary │ PatternDetector │ Progress │ Collaboration │ Wellness    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    ACTION GENERATORS                                     │
│                                                                          │
│   Insights + Mood ──► Generators ──► Actions (popups/notifications)      │
│                                                                          │
│   WellnessAction │ ReminderAction │ FocusAction │ LateNightAction        │
└─────────────────────────────────────────────────────────────────────────┘
```

### Pipeline Summary

| Layer | Purpose | Output |
|-------|---------|--------|
| **Capture** | Raw data collection | screen_captures, voice_segments, face_events |
| **Refiners** | Extract structured knowledge | projects, collaborators, interests, todos |
| **Insight Generators** | Observe patterns, create observations | insights |
| **Action Generators** | Decide when to interrupt user | actions (popups) |

## Technology Stack

| Component | Technology |
|-----------|------------|
| Screen Capture | ScreenCaptureKit |
| OCR | Vision framework |
| Voice | WhisperKit (whisper-tiny.en, ~40MB) |
| Face/Emotion | Vision framework |
| LLM | MLX-Swift-LM (Qwen2.5-3B-Instruct-4bit, ~4GB) |
| Database | GRDB.swift (SQLite) |
| UI | SwiftUI + AppKit |

## Project Structure

```
GoosePerception/
├── App/
│   └── AppDelegate.swift          # Service init, menu bar, callbacks
├── Analysis/
│   └── AnalysisScheduler.swift    # Orchestrates analysis pipeline
├── Database/
│   ├── Database.swift             # GRDB wrapper, migrations
│   └── Models/                    # Data models (Action, Insight, etc.)
├── Services/
│   ├── ScreenCapture/             # Screenshot + OCR
│   ├── Voice/                     # WhisperKit transcription
│   ├── Face/                      # Camera + emotion detection
│   ├── FileActivity/              # Directory activity tracking
│   └── LLM/
│       ├── LLMService.swift       # MLX model runner
│       ├── Refiners/              # Knowledge extractors
│       └── Generators/            # Insight & Action generators
└── Views/
    ├── DashboardView.swift        # Main UI (Services, Knowledge, etc.)
    └── InsightPopupManager.swift  # Floating popups
```

## Database Schema

| Table | Purpose |
|-------|---------|
| screen_captures | OCR text from focused windows |
| voice_segments | Transcribed speech |
| face_events | Presence and emotion |
| projects | Extracted project names |
| collaborators | Extracted people |
| interests | Extracted topics |
| todos | Tasks found in screen text |
| insights | Generated observations |
| actions | Triggered popups/notifications |
| app_usage | Aggregated app usage stats |
| directory_activity | Recent file activity |

## Dashboard Tabs

| Tab | Shows |
|-----|-------|
| **Services** | Toggle Screen/Voice/Face capture, audio levels, current emotion |
| **Knowledge** | Mood summary, Projects, Collaborators, Interests, Apps, Directories, TODOs |
| **Insights** | Generated observations from analysis |
| **Actions** | Pending/completed/dismissed action items |
| **Activity** | Real-time event log |
| **Captures** | Historical screen captures with OCR preview |
| **LLM** | Full LLM session history |

## Generators

### Insight Generators

| Generator | Cooldown | Triggers When |
|-----------|----------|---------------|
| WorkSummary | 2h | 10+ captures, has projects |
| PatternDetector | 4h | 2+ projects, 20+ captures |
| ProgressTracker | 1h | Has pending TODOs |
| Collaboration | 3h | Has collaborators + voice activity |
| Wellness | 30m | 2h+ work, late night, or stress signals |

### Action Generators

| Generator | Cooldown | Triggers When |
|-----------|----------|---------------|
| Wellness | 45m | 2+ wellness-related insights |
| Reminder | 60m | TODOs pending > 2 hours |
| Focus | 45m | Insights about context-switching |
| LateNight | 60m | After 10pm + late-night insights |

## Privacy

- **100% local** - All processing on-device
- **No images stored** - Screenshots processed and discarded
- **No network** - Except for one-time model downloads
- **User control** - Toggle any capture service independently

## Development

```bash
# Watch for changes and rebuild
just watch

# Run tests
just test

# Check for issues
just lint
```

## License

Private / All rights reserved

## See Also

- `notes/plan.md` - Detailed implementation notes
- `notes/original-spec.md` - Original requirements
- `notes/agent-actions-implementation.md` - Future: CLI agent integration
