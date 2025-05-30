# Goose Perception

> [!NOTE]
> This is experimental and very much a work in progress and showcase of async goose and recipes, use at own risk

<img src="goose.png" alt="Goose Logo" width="150" align="right"/>

Always watching, and listening and perceiving.

Goose can interact with you proactively, solving and taking on tasks while you are busy doing other things, or suggesting improvements.
This makes use of many goose powered agents (which use recipes!) to observe you as you go about your day, learn about your work, projects and more so it can suggest improvements and take actions. 
It works by watching how you work (screens, interactions, collaboration) and literally listening, uses many MCPs and recipes asynchronously.

<img src="example.png" alt="Example notification" width="400" align="right"/>


It also includes a real-time audio agent activation tool using local transcription models, with custom wake word detection model and conversation capture.
No audio leaves your machine.


Some of the recipes for example will prompt you when appropriate with suggestions on how to order your tasks or day.
It will communicate with you via notifications (if it must), voice, or presenting ideas and reports from time to time: 



## Usage

Once running - just go about your day, you don't need to do anything, it will do something. 
You can if you like ask goose to do something, just talk, mention goose, it will detect that you are talking to it (vs about it).

## What it can do for you

  <img src="desktop.png" alt="Goose Perception in action - AI-blurred screenshot showing Goose preparing for the day" width="400" style="border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);"/>
  
> [!NOTE]
>This is a real screenshot (blurred with AI) of a meeting where it was early morning, and goose was prepping me for the day, noting any important actions in slack and email I needed to take (knowing that I am terrible at reading email until much later in the day).
    
Let it run for a while (ie run it all the time in the background), over time goose will start either showing things to you (with windows showing up with little web apps or reports), it will put things quietly on your calendar to remind you, prepare documents for you for up coming things.
    
It will also do a weekly "hype doc" summary celebrating all your hard work! There are many other things it may do, they all combine together as it learns what you do.

You can also use verbal commands to ask it to do something (and it has the benefit of that learned context). 
A normal goose session can also benefit from this context as well. 


## Setup

Prerequisites:
- `just` command runner

The application will:
1. Create a virtual environment with Python 3.12
2. Install all required dependencies
3. Download models when first needed
4. Train the classifiers on first run


> **Note:** The application sets `TOKENIZERS_PARALLELISM=false` to avoid warnings from the Hugging Face tokenizers library. If you run into any issues with tokenizers, you can manually set this environment variable: `export TOKENIZERS_PARALLELISM=false`

### Available Commands

```bash
just run              # Run the application
just train-classifier # run the classifier (won't usually need to)
```


## Models and data

The voice models (currently whisper) and locally trained models (distilbert based) all run locally when listening in to the environment and for commands, no audio leaves your machine. 
Screen shots are taken periodically but cleaned out, goose is used to summarised those into a rolling log

### Local models and personal data

Goose will use whatever default models are configured for it, so they can be local models, but if they are remote ones then screenshots will be sent as will information that other recipes gather. 
For running all locally, this is possibly by via goose config, but also possibly with screen analysis with ollama models which are fine tuned for screen analysis 
(I wasn't able to run any multimodal models on my local machine, meaning that the goose agent loop won't work with the local models if images are needed on my machine, but with a more powerful one a totally local flow would be possible). 
There are models such as `llava:3b` (ideally 13b or up) which can read screen content for summarization, but need to be used in concert with other models (think of it as mode like fancy OCR!)
This is an emerging space so keep an eye out


## How It Works

# Observing and learning

The `observers` directory has many recipes for learning about you - these will run from time to time, some continuously. 

### Screen watching

The `work` recipe looks at your screen content and will summarise, learn and note what you are working on, who you interact with, and what has changed. It will even work out when you are asleep (well not at your computer).
This keeps a rolling log of activity and up to date latest one.

### Interactions and contributions

other recipes will examine your communications history and contributions, and form a picture and some metrics of what you have been doing recently and with whom. 
They will then proactively go to work (checkout `observers` dir).



# Voice commands

Voice input is useful as it is always listening and knows the context of which you ask for something to be done. Best for async tasks, not conversation.

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
                                                   │   Invoke Goose Agent    │
                                                   │   (via agent.py)        │
                                                   └─────────────┬───────────┘
                                                                 │
                                                                 ▼
                                                   ┌─────────────────────────┐
                                                   │                         │
                                                   │   Goose Process         │
                                                   │   (Background Thread)   │
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

### Activation Logging for Training
- The system logs all wake word activations for analysis and model improvement
- Successful activations are saved as `activation_triggered_[timestamp].txt`
- Bypassed activations (when "goose" is detected but not addressed to Goose) are saved as `activation_bypassed_[timestamp].txt`
- Each log includes the transcript, confidence score, and timestamp
- These logs can be used to retrain the wake word classifier to improve accuracy

### Agent Integration

The system directly integrates with Goose through the `agent.py` module:

- When a conversation is complete, `listen.py` directly calls `agent.process_conversation()`
- The agent reads the transcript and prepares it for Goose with appropriate instructions
- Goose is invoked with the command: `goose run --name voice -t "The user has spoken the following..."`
- The Goose process runs in a separate thread to avoid blocking the main application
- All Goose interactions happen in the `~/Documents/voice` directory

#### Concurrency Model

The system uses a multi-threaded approach to handle Goose interactions:

1. **Main Thread (listen.py)**
   - Detects wake words, processes conversations
   - Calls `agent.process_conversation()` when a conversation is complete
   - Continues listening for new wake words immediately

2. **Agent Thread (agent.py)**
   - Created by `agent.process_conversation()`
   - Runs `run_goose_in_background()` in a daemon thread
   - Daemon threads don't block program exit

3. **Goose Process**
   - Started by the agent thread using `subprocess.call()`
   - Runs the Goose CLI with the transcript
   - Operates independently from the main application

This design ensures that:
- The voice recognition system continues to function while Goose processes requests
- Multiple conversations can be handled sequentially
- The application remains responsive during Goose processing

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
