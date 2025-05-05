# Goose Voice - Wakeword Detection

A research project for building and deploying wakeword detection models with a simple API.

## Project Structure

```
goose-voice/
├── data/
│   ├── raw/           # Raw audio recordings
│   └── processed/     # Processed audio features
├── models/            # Saved models
├── src/
│   ├── api/           # API implementation
│   │   └── wakeword_api.py
│   ├── audio/         # Audio processing utilities
│   │   ├── processor.py
│   │   ├── recorder.py
│   │   └── collect_samples.py
│   ├── models/        # Model implementation
│   │   ├── wakeword.py
│   │   ├── dataset.py
│   │   └── train.py
│   └── demo.py        # Demo script
└── README.md
```

## Getting Started

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/goose-voice.git
   cd goose-voice
   ```

2. Create a virtual environment and install dependencies:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```

### Collecting Wakeword Samples

To train a wakeword model, you first need to collect audio samples:

```bash
python -m src.audio.collect_samples --wakeword "goose" --num_samples 20 --num_negative 20
```

This will guide you through recording:
- 20 samples of saying your wakeword ("goose")
- 20 negative samples (other words or background noise)

### Training a Wakeword Model

Train your model using the collected samples:

```bash
python -m src.models.train --data_dir data/raw --epochs 30 --augment
```

The trained model will be saved to the `models/` directory.

### Testing the Wakeword Detection

Test your trained model with real-time detection:

```bash
python -m src.demo --model_path models/your_model.pt --threshold 0.7
```

This will listen for your wakeword in real-time and print when it's detected.

### Running the API

Start the FastAPI server:

```bash
uvicorn src.api.wakeword_api:app --reload
```

The API will be available at http://localhost:8000. You can use the Swagger UI at http://localhost:8000/docs to test the API endpoints.

## API Endpoints

- `POST /load_model`: Load a wakeword detection model
- `GET /status`: Get the current status of the wakeword detector
- `POST /start_listening`: Start listening for wakeword
- `POST /stop_listening`: Stop listening for wakeword
- `WebSocket /ws`: WebSocket endpoint for real-time wakeword detection

## Using Pre-trained Models

You can use pre-trained models from the Google Speech Commands dataset:

1. Download the dataset:
   ```bash
   wget http://download.tensorflow.org/data/speech_commands_v0.02.tar.gz
   tar -xzf speech_commands_v0.02.tar.gz -C data/raw
   ```

2. Train a model using specific words as wakewords:
   ```bash
   python -m src.models.train --data_dir data/raw --epochs 30
   ```

## Model Export

Export your model to ONNX format for deployment:

```bash
python -m src.models.train --data_dir data/raw --export_onnx
```

## Requirements

Create a `requirements.txt` file with:

```
numpy
torch
torchaudio
librosa
soundfile
pyaudio
fastapi
uvicorn
matplotlib
tqdm
```

## References

- [Google Speech Commands Dataset](https://www.tensorflow.org/datasets/catalog/speech_commands)
- [Mycroft Precise](https://github.com/MycroftAI/mycroft-precise)
- [ARM Keyword Spotting](https://github.com/ARM-software/ML-KWS-for-MCU)