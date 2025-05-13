# Goose Voice

<img src="goose.png" alt="Goose Logo" width="150" align="right"/>

A real-time audio agent activation tool using local transcription models, with custom wake word detection model and conversation capture.

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

The application uses a sequential processing approach with continuous audio capture:

### Wake Word Detection Flow

1. **Audio Capture** (continuous background thread)
   - Captures audio from the microphone in real-time
   - Buffers audio in a queue for processing
   - Runs in a separate thread that never blocks

2. **Audio Processing** (main thread)
   - Collects 5-second chunks of audio from the queue
   - Saves each chunk to a temporary file
   - Submits the chunk for transcription in a background thread

3. **Transcription** (background thread)
   - Transcribes the audio chunk using Whisper
   - Runs in a background thread to avoid blocking audio capture
   - Returns the transcribed text to the main thread

4. **Wake Word Detection** (main thread)
   - Checks if the transcribed text contains "goose"
   - If found, uses the classifier to determine if it's addressed to Goose
   - The classifier check is fast and doesn't block audio capture

5. **Mode Switching**
   - If addressed to Goose: switches to active listening mode
   - If not: stays in passive listening mode

The system maintains continuous audio capture throughout all these steps, ensuring no audio is missed during processing or classification.

### Wake Word Detection

The system uses an enhanced ML-based classifier to determine if speech is addressed to Goose:

- **Two-Model Approach**: Uses a lightweight model (tiny) for wake word detection and a higher-quality model for full transcription
- **Fuzzy Text Matching**: Can detect variations of "goose" using fuzzy string matching
- **Confidence Thresholds**: Configurable confidence threshold for wake word classification
- **ML-Based Classification**: Uses a fine-tuned DistilBERT model to determine if speech is addressed to Goose
- **More accurate and context-aware** than simple text matching
- **Can distinguish** between mentions of "goose" and actual commands to Goose

```
┌────────────────────┐     ┌────────────────────┐     ┌────────────────────┐
│                    │     │                    │     │                    │
│   Audio Capture    │────▶│  5-second Chunks   │────▶│ Quick Transcription│
│  (Background)      │     │  (Main Thread)     │     │ (Lightweight Model)│
│                    │     │                    │     │                    │
└────────────────────┘     └────────────────────┘     └──────────┬─────────┘
                                                                 │
                                                                 ▼
┌────────────────────┐                             ┌─────────────────────────┐
│                    │                             │                         │
│  Passive Listening │◀────────── No ─────────────┤ Contains "goose"?       │
│                    │                             │ (Fuzzy Match)           │
└────────────────────┘                             └─────────────┬───────────┘
                                                                 │
                                                                Yes
                                                                 │
                                                                 ▼
┌────────────────────┐                             ┌─────────────────────────┐
│                    │                             │                         │
│  Passive Listening │◀────────── No ─────────────┤  Addressed to Goose?    │
│                    │                             │  (Classifier Check)     │
└────────────────────┘                             └─────────────┬───────────┘
                                                                 │
                                                                Yes
                                                                 │
                                                                 ▼
┌────────────────────┐                             ┌─────────────────────────┐
│                    │                             │                         │
│  Switch to Active  │─────────────────────────────▶  Active Listening      │
│  Mode              │                             │  (Main Model)           │
└────────────────────┘                             └─────────────┬───────────┘
                                                                 │
                                                                 ▼
                                                   ┌─────────────────────────┐
                                                   │                         │
                                                   │  Monitor Until Silence  │
                                                   │                         │
                                                   └─────────────┬───────────┘
                                                                 │
                                                                 ▼
                                                   ┌─────────────────────────┐
                                                   │                         │
                                                   │  Full Transcription     │
                                                   │  (Using Main Model)     │
                                                   └─────────────┬───────────┘
                                                                 │
                                                                 ▼
                                                   ┌─────────────────────────┐
                                                   │                         │
                                                   │   Save Conversation     │
                                                   │                         │
                                                   └─────────────┬───────────┘
                                                                 │
                                                                 ▼
                                                   ┌─────────────────────────┐
                                                   │                         │
                                                   │   Invoke Agent          │
                                                   │   (if configured)       │
                                                   └─────────────────────────┘
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
   - Re-transcribes the entire audio using the main model
   - Saved as complete audio and transcript files

5. **Periodic Long Transcriptions (60 seconds)**
   - Regular checkpoints saved every minute
   - Independent of wake word detection
   - Provides backup transcriptions of all audio

### Operating Modes

#### Passive Listening Mode
1. Captures audio from your microphone in real-time (continuous)
2. Processes the audio in 5-second chunks (sequential)
3. Maintains a rolling buffer of recent speech (default: 30 seconds)
4. Continuously monitors for the wake word "goose"
5. Shows minimal output to indicate it's working

#### Active Listening Mode
1. Triggered when the wake word is detected and verified by the classifier
2. Preserves the context from before the wake word was spoken
3. Continues actively transcribing all speech
4. Monitors for a period of silence (default: 3 seconds)
5. When silence is detected, saves the entire conversation (context + active speech)
6. Returns to passive listening mode

During active listening, the system prioritizes capturing the complete conversation. It continues to buffer audio in the background, ensuring no speech is missed even during transcription.

### Conversation Capture
- Complete conversations are saved as both audio (.wav) and text (.txt) files
- Files are stored in the `recordings` directory with timestamps
- Each conversation includes speech from before the wake word was detected
- The system also saves periodic transcriptions every minute

### Agent Integration

The system can invoke an external agent script when a conversation is complete:

- Specify an agent script with `--agent path/to/agent.py`
- The agent receives the transcript and audio file paths as arguments
- A default agent.py is provided that demonstrates basic intent detection
- The agent runs as a subprocess, allowing for independent processing
- Agents can be written in any language as long as they accept the transcript and audio paths

Example agent invocation:
```bash
./agent.py path/to/transcript.txt path/to/audio.wav
```

#### Continuous Conversation Support

The system supports continuous conversations without requiring silence between commands:

- During active listening, it continues to monitor for additional wake words
- If a wake word is detected during active listening, the silence counter is reset
- This allows for chained commands without waiting for silence
- Example: "Hey Goose, what's the weather? Hey Goose, set a timer for 5 minutes."

## Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--context-seconds` | Seconds of speech to keep before wake word | 30 |
| `--silence-seconds` | Seconds of silence to end active listening | 3 |
| `--recordings-dir` | Directory to save audio and transcripts | "recordings" |
| `--model` | Whisper model size | "base" |
| `--language` | Language code (optional) | None (auto-detect) |
| `--device` | Audio input device number | None (default) |
| `--use-lightweight-model` | Use lightweight model for wake word detection | True |
| `--no-lightweight-model` | Don't use lightweight model for wake word detection | False |
| `--fuzzy-threshold` | Fuzzy matching threshold for wake word (0-100) | 80 |
| `--classifier-threshold` | Confidence threshold for classifier (0-1) | 0.6 |
| `--agent` | Path to agent script to invoke when conversation is complete | None |

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