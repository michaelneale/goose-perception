# Goose Voice

<img src="goose.png" alt="Goose Logo" width="150" align="right"/>

A real-time audio transcription tool using Whisper, with wake word detection and conversation capture.

## Setup

1. Create a virtual environment and install dependencies:
```bash
uv venv
source .venv/bin/activate
uv pip install -r requirements.txt
```

2. Run the application:
```bash
./run.sh
```

Or run with specific options:
```bash
python listen.py --model [tiny|base|small|medium|large] --device [device_number]
```

> **Note:** The application sets `TOKENIZERS_PARALLELISM=false` to avoid warnings from the Hugging Face tokenizers library. If you run into any issues with tokenizers, you can manually set this environment variable: `export TOKENIZERS_PARALLELISM=false`


## How It Works

The application uses a multi-scale transcription approach to balance responsiveness with context:

### Wake Word Detection

The system uses an ML-based classifier to determine if speech is addressed to Goose:

- Uses a fine-tuned DistilBERT model to determine if speech is addressed to Goose
- More accurate and context-aware than simple text matching
- Can distinguish between mentions of "goose" and actual commands to Goose

```
                                     ┌───────────────────────┐
                                     │                       │
                                     │    Audio Recording    │
                                     │                       │
                                     └───────────┬───────────┘
                                                 │
                                                 ▼
                                     ┌───────────────────────┐
                                     │                       │
                                     │  Whisper Transcription│
                                     │                       │
                                     └───────────┬───────────┘
                                                 │
                                                 ▼
                                     ┌──────────────────────┐
                                     │                      │
┌─────────────────────┐             │  Contains "goose"?    │ 
│                     │             │                       │
│  Continue Passive   │◄────No──────┤                       |
│    Listening        │             │                       │
│                     │             └───────────┬───────────┘
└─────────────────────┘                         │            
                                                │
                                               Yes
                                                │
                                                ▼
                                     ┌───────────────────────┐
                                     │                       │
                                     │  Wake Word Classifier │
                                     │  (DistilBERT Model)   │
                                     │                       │
                                     └───────────┬───────────┘
                                                 │
                                                 │
                 ┌───────────────────────────────┴───────────────────────────────┐
                 │                                                               │
                 ▼                                                               ▼
     ┌───────────────────────┐                                       ┌───────────────────────┐
     │                       │                                       │                       │
     │ Addressed to Goose?   │                                       │ Not Addressed to Goose│
     │ (Confidence > 0.5)    │                                       │ (Confidence ≤ 0.5)    │
     │                       │                                       │                       │
     └───────────┬───────────┘                                       └───────────┬───────────┘
                 │                                                               │
                 ▼                                                               ▼
     ┌───────────────────────┐                                       ┌───────────────────────┐
     │                       │                                       │                       │
     │  Activate Assistant   │                                       │  Continue Passive     │
     │  (Active Listening)   │                                       │     Listening         │
     │                       │                                       │                       │
     └───────────────────────┘                                       └───────────────────────┘
```

### Multi-Scale Transcription System

1. **Short Chunks (5 seconds)**
   - Used for real-time monitoring and wake word detection
   - Provides immediate feedback on what's being heard
   - Serves as building blocks for longer transcriptions

2. **Context Buffer (30 seconds)**
   - Maintains a rolling window of recent speech
   - Preserves what was said before the wake word
   - Composed of multiple 5-second chunks

3. **Active Listening (Variable Length)**
   - Triggered when wake word is detected
   - Continues until silence is detected (default: 3 seconds of silence)
   - Captures the complete interaction after the wake word

4. **Full Conversations**
   - Combines context buffer + active listening period
   - Captures speech before, during, and after wake word
   - Saved as complete audio and transcript files

5. **Periodic Long Transcriptions (60 seconds)**
   - Regular checkpoints saved every minute
   - Independent of wake word detection
   - Provides backup transcriptions of all audio

### Operating Modes

### Passive Listening Mode
1. Captures audio from your microphone in real-time
2. Processes the audio in 5-second chunks
3. Maintains a rolling buffer of recent speech (default: 30 seconds)
4. Continuously monitors for the wake word "goose"
5. Shows minimal output to indicate it's working

### Active Listening Mode
1. Triggered when the wake word is detected
2. Displays the context from before the wake word was spoken
3. Continues actively transcribing all speech
4. Monitors for a period of silence (default: 3 seconds)
5. When silence is detected, saves the entire conversation (context + active speech)
6. Returns to passive listening mode

### Conversation Capture
- Complete conversations are saved as both audio (.wav) and text (.txt) files
- Files are stored in the `recordings` directory with timestamps
- Each conversation includes speech from before the wake word was detected
- The system also saves periodic transcriptions every minute

## Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--context-seconds` | Seconds of speech to keep before wake word | 30 |
| `--silence-seconds` | Seconds of silence to end active listening | 3 |
| `--recordings-dir` | Directory to save audio and transcripts | "recordings" |
| `--model` | Whisper model size | "base" |
| `--language` | Language code (optional) | None (auto-detect) |
| `--device` | Audio input device number | None (default) |

### Note on Chunk Size

The system processes audio in 5-second chunks, which represents a balance between:
- **Responsiveness**: Short enough to detect wake words quickly
- **Transcription quality**: Long enough for Whisper to have sufficient context
- **Natural speech**: Aligns with typical spoken phrase length
- **Processing efficiency**: Optimizes CPU and memory usage

Shorter chunks would improve responsiveness but reduce transcription quality, while longer chunks would improve transcription but increase latency.

### Background Transcription

The system uses a background thread for transcription:

- **Non-blocking Design**: Audio capture continues even during transcription
- **Sequential Processing**: Each audio chunk is processed in order
- **Reliable Wake Word Detection**: The system processes each chunk fully before moving to the next
- **Focused Attention**: Once activated, the system captures the entire conversation without interruption

This design ensures that the system properly captures complete conversations while maintaining a simple and reliable architecture.

Press Ctrl+C to stop the application.