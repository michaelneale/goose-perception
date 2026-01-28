# Perception2 Requirements

Native macOS SwiftUI application for ambient awareness and insight generation on Apple Silicon (32GB+ RAM).

---

## 1. Vision & Aims

Perception2 is a personal ambient intelligence assistant that quietly observes your digital environment—screen activity, voice, and presence—to build a continuously evolving understanding of your work, projects, and collaborators. 

The goal is not surveillance but **augmented self-awareness**: surfacing insights you'd miss, remembering context you'd forget, and gently prompting you with relevant information at the right moment. It runs entirely locally for privacy, using on-device LLMs to extract meaning from raw observations and present it through unobtrusive, beautiful UI.

**Core aims:**
- Build a living knowledge base of your projects, collaborators, interests, and action items
- Provide timely insights and reminders without disrupting flow
- Detect patterns in your work habits and emotional state to support wellbeing
- Keep everything local and private—no cloud, no tracking

---

## 2. Architecture Overview

**App Type:** Menu bar resident (tray app) with translucent popup windows  
**Platform:** macOS, Apple Silicon only  
**Storage:** SQLite (single database for all data)  
**LLM Runtime:** MLX or llama.cpp with GGUF models (local inference only)  
**Tool Calling:** None - text-in/text-out LLM interface only

---

## 3. Input Pipelines

### 3.1 Screen Capture Pipeline

| Stage | Interval | Action |
|-------|----------|--------|
| Capture | 20s | Screenshot all screens + focused window metadata → SQLite |
| OCR + Describe | 2min | Process pending captures: OCR text, optional vision narration. Delete images, store text in SQLite |
| LLM Analysis | 20min | Run analysis passes on recent screen data |

**Stored per capture:**
- Timestamp
- Active window (app name, window title)
- All open windows (JSON)
- OCR text (after processing)
- Vision narration (optional, after processing)
- Image path (temporary, cleared after processing)

### 3.2 Voice Pipeline

| Stage | Interval | Action |
|-------|----------|--------|
| Transcription | Continuous | Real-time speech-to-text → SQLite segments |
| LLM Analysis | 10min | Extract insights and actions from recent segments |

### 3.3 Face/Camera Pipeline

| Stage | Interval | Action |
|-------|----------|--------|
| Presence | Continuous | Detect face present/absent → SQLite |
| Identity | On change | Fingerprint known users (anonymous IDs) |
| Emotion | 60s | Classify emotional state when face detected |

---

## 4. Data Storage

Single SQLite database: `perception.db`

### Core Tables
- **screen_captures** — timestamp, focused app/window, all windows JSON, image path (temp), OCR text, vision narration, processed flag
- **voice_segments** — timestamp, transcript text, confidence
- **face_events** — timestamp, anonymous user ID, present flag, emotion, confidence

### Knowledge Tables
- **projects** — name, description, first/last seen, activity count
- **collaborators** — name, context, first/last seen, mention count
- **interests** — topic, first/last seen, frequency
- **actions** — source, content, status (pending/done/dismissed), remind time
- **insights** — type (summary/alert/reflection), content, shown flag

### System Tables
- **llm_runs** — pipeline name, prompt/output preview, token counts, duration (for debugging)
- **settings** — key/value store for app configuration

---

## 5. LLM Analysis Passes

All passes read from SQLite, write results back to SQLite.

| Pass | Input | Output | Frequency |
|------|-------|--------|-----------|
| Projects | recent screen captures + existing projects | upsert projects | 20min |
| Collaborators | screen + voice + existing collaborators | upsert collaborators | 20min |
| Work State | screen captures | insert insight (work pattern) | 20min |
| Interests | screen + voice | upsert interests | 20min |
| Screen Actions | screen captures | insert actions | 20min |
| Voice Insights | voice segments + projects | insert insights | 10min |
| Voice Actions | voice segments | insert actions | 10min |

**Pattern:** Query → Format prompt → LLM inference → Parse output → UPSERT → Log run

---

## 6. User Interface

### 6.1 Menu Bar
- Tray icon with status indicator
- Toggle sliders: screen watching, face detection, voice listening
- Quick stats (captures today, actions pending)
- Open dashboard / settings

### 6.2 Insight Popups
- **Triggers:** time-of-day, new action detected, unusual activity, user present + not focused
- **Appearance:** translucent vibrancy window, dismiss or "remind later" buttons
- **Content:** unshown insights from database

### 6.3 Dashboard
- Activity timeline (screen, voice, face events)
- Knowledge browser (projects, collaborators, interests)
- Action items with status management
- Debug view (LLM runs, raw captures)
- Stats and graphs

---

## 7. Native APIs Required

| Capability | Framework |
|------------|-----------|
| Screen capture | ScreenCaptureKit |
| OCR | Vision (VNRecognizeTextRequest) |
| Speech-to-text | Speech framework or whisper.cpp |
| Face detection/emotion | Vision + Core ML |
| Menu bar app | SwiftUI + NSStatusItem |
| Translucent windows | NSVisualEffectView |
| Local LLM | MLX-Swift or llama.cpp Swift |
| SQLite | GRDB.swift |

---

## 8. Model Requirements

| Task | Model | Size |
|------|-------|------|
| LLM (analysis) | Qwen2.5-7B-Instruct GGUF | ~4-8GB |
| Vision description | LLaVA or moondream2 | ~4GB |
| Speech-to-text | whisper.cpp (small) | ~500MB |
| Emotion | Core ML classifier | <100MB |

Models downloaded JIT on first use.

---

## 9. Privacy

- All processing local—no network for inference
- Images deleted immediately after OCR
- Database in user-controlled location
- Face IDs are anonymous hashes
- User can purge all data from settings

---

## 10. File Structure

```
~/.config/goose-perception/
├── perception.db              # SQLite database (all data)
├── models/                    # Downloaded GGUF/ML models
└── temp/
    └── screenshots/           # Temporary image buffer (auto-cleared)
```

---

## 11. Processing Intervals

| Pipeline | Capture | Process | LLM |
|----------|---------|---------|-----|
| Screen | 20s | 2min (OCR) | 20min |
| Voice | Continuous | — | 10min |
| Face | Continuous | 60s (emotion) | — |
| Insights | — | — | Periodic/trigger |

---

## 12. Phase 2 Features

- External CLI integration (goose, claude, codex)
- Natural language triggers → automated actions
- System event hooks (notifications, calendar)
- Anomaly detection (unusual patterns, potential scams)
- Workload warnings (too long, too many parallel tasks)
