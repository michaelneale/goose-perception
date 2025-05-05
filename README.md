# Goose Voice

A real-time audio transcription tool using Whisper.

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

## Available Commands

- List audio devices:
```bash
python listen.py --list-devices
```

- Use a specific model:
```bash
python listen.py --model tiny  # Fastest
python listen.py --model base  # Default
python listen.py --model small  # Better quality
python listen.py --model medium  # Even better quality
python listen.py --model large  # Best quality but slowest
```

- Specify a language (optional):
```bash
python listen.py --language en
```

## How It Works

The application:
1. Captures audio from your microphone in real-time
2. Processes the audio in 5-second chunks
3. Transcribes each chunk using OpenAI's Whisper
4. Outputs the transcription to the console

Press Ctrl+C to stop the application.