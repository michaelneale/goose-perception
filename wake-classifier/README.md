# Goose Wake Word Classifier

A fine-tuned model to detect whether text is specifically addressed to the "Goose" assistant.

## Overview

This classifier is designed to analyze transcribed speech and determine if the speaker is addressing Goose directly. It uses a fine-tuned transformer model (DistilBERT) that has been trained on examples of text that is and isn't addressed to Goose.

## Directory Structure

```
wake-classifier/
├── classifier.py         # Main inference script
├── train_classifier.py   # Script to train the model
├── generate_examples.py  # Script to generate synthetic training data
├── data/
│   ├── positive/         # Examples addressed to Goose
│   └── negative/         # Examples not addressed to Goose
└── model/                # Trained model files (created during training)
```

## Setup

1. Install dependencies:
```bash
# Dependencies are now in the main project's requirements.txt file
cd ..
pip install -r requirements.txt
```

2. Generate additional training examples:
```bash
python generate_examples.py
```

3. Train the model:
```bash
python train_classifier.py
```

## Usage

### Command Line

```bash
python classifier.py "Hey Goose, can you help me with this?"
```

Output:
```
Text: Hey Goose, can you help me with this?
Classification: ADDRESSED_TO_GOOSE
Addressed to Goose: Yes
Confidence: 0.9876
```

With JSON output:
```bash
python classifier.py "Is anyone there?" --json
```

### As a Library

```python
from classifier import GooseWakeClassifier

# Initialize the classifier
classifier = GooseWakeClassifier()

# Classify some text
result = classifier.classify("Goose, what's the weather like today?")
print(f"Is addressed to Goose: {result['addressed_to_goose']}")
print(f"Confidence: {result['confidence']}")
```

## Model Details

- Base model: DistilBERT (small, efficient transformer model)
- Fine-tuned on: Custom dataset of examples addressed/not addressed to Goose
- Input: Text strings (transcribed speech)
- Output: Binary classification with confidence score
- Performance: ~95% accuracy on test set

## Integration with Voice System

This classifier is integrated with the Goose Voice system to determine if transcribed speech is addressed to the Goose assistant. It's used in the `listen.py` script to enhance wake word detection.

Current integration:

```python
from classifier import GooseWakeClassifier

# Initialize the classifier
classifier = GooseWakeClassifier()

# In the transcription processing code:
def contains_wake_word(text, wake_word="goose", classifier=None):
    """Check if the text contains the wake word and is addressed to Goose"""
    # Use the classifier to determine if the text is addressed to Goose
    result = classifier.classify(text)
    return result["addressed_to_goose"]
```

## Extending the Model

To improve the model:

1. Add more examples to `data/positive/` and `data/negative/`
2. Modify `generate_examples.py` to create more diverse synthetic examples
3. Re-train the model with `python train_classifier.py`