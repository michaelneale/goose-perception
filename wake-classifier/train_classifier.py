#!/usr/bin/env python3
"""
train_classifier.py - Train a wake word classifier model
"""

import os
import json
import glob
import pandas as pd
import numpy as np
from pathlib import Path
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score
import torch
from torch.utils.data import Dataset, DataLoader
from transformers import (
    AutoTokenizer, 
    AutoModelForSequenceClassification,
    TrainingArguments,
    Trainer,
    pipeline
)

# Configuration
MODEL_NAME = "distilbert-base-uncased"  # Small, efficient model
OUTPUT_DIR = "model"
BATCH_SIZE = 16
EPOCHS = 3
LEARNING_RATE = 2e-5
MAX_LENGTH = 128
RANDOM_SEED = 42

# Set random seeds for reproducibility
torch.manual_seed(RANDOM_SEED)
np.random.seed(RANDOM_SEED)

class WakeWordDataset(Dataset):
    """Dataset for wake word classification"""
    
    def __init__(self, texts, labels, tokenizer, max_length=128):
        self.texts = texts
        self.labels = labels
        self.tokenizer = tokenizer
        self.max_length = max_length
        
    def __len__(self):
        return len(self.texts)
    
    def __getitem__(self, idx):
        text = self.texts[idx]
        label = self.labels[idx]
        
        encoding = self.tokenizer(
            text,
            truncation=True,
            padding="max_length",
            max_length=self.max_length,
            return_tensors="pt"
        )
        
        # Remove batch dimension added by tokenizer
        item = {key: val.squeeze(0) for key, val in encoding.items()}
        item["labels"] = torch.tensor(label)
        
        return item

def load_data():
    """Load data from positive and negative examples directories (recursively)"""
    data = {"texts": [], "labels": []}
    
    # Load positive examples (label 1)
    positive_files = []
    for root, _, files in os.walk("data/positive"):
        for file in files:
            if file.endswith(".txt"):
                positive_files.append(os.path.join(root, file))
    
    for file_path in positive_files:
        try:
            with open(file_path, "r") as f:
                text = f.read().strip()
                data["texts"].append(text)
                data["labels"].append(1)
        except Exception as e:
            print(f"Error reading {file_path}: {e}")
    
    # Load negative examples (label 0)
    negative_files = []
    for root, _, files in os.walk("data/negative"):
        for file in files:
            if file.endswith(".txt"):
                negative_files.append(os.path.join(root, file))
    
    for file_path in negative_files:
        try:
            with open(file_path, "r") as f:
                text = f.read().strip()
                data["texts"].append(text)
                data["labels"].append(0)
        except Exception as e:
            print(f"Error reading {file_path}: {e}")
    
    # Convert to pandas DataFrame
    df = pd.DataFrame(data)
    
    # Shuffle the data
    df = df.sample(frac=1, random_state=RANDOM_SEED).reset_index(drop=True)
    
    print(f"Loaded {len(df)} examples ({len(positive_files)} positive, {len(negative_files)} negative)")
    
    return df

def compute_metrics(eval_pred):
    """Compute metrics for evaluation"""
    logits, labels = eval_pred
    predictions = np.argmax(logits, axis=-1)
    
    # Return metrics
    return {
        "accuracy": accuracy_score(labels, predictions),
        "classification_report": classification_report(labels, predictions, output_dict=True)
    }

def train_model(df):
    """Train the wake word classifier model"""
    # Split data into train and test sets
    train_df, test_df = train_test_split(df, test_size=0.2, random_state=RANDOM_SEED)
    
    print(f"Training on {len(train_df)} examples, testing on {len(test_df)} examples")
    
    # Load tokenizer and model
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME, num_labels=2)
    
    # Create datasets
    train_dataset = WakeWordDataset(
        train_df["texts"].tolist(),
        train_df["labels"].tolist(),
        tokenizer,
        MAX_LENGTH
    )
    
    test_dataset = WakeWordDataset(
        test_df["texts"].tolist(),
        test_df["labels"].tolist(),
        tokenizer,
        MAX_LENGTH
    )
    
    # Define training arguments
    training_args = TrainingArguments(
        output_dir=OUTPUT_DIR,
        evaluation_strategy="epoch",
        save_strategy="epoch",
        learning_rate=LEARNING_RATE,
        per_device_train_batch_size=BATCH_SIZE,
        per_device_eval_batch_size=BATCH_SIZE,
        num_train_epochs=EPOCHS,
        weight_decay=0.01,
        load_best_model_at_end=True,
        metric_for_best_model="accuracy",
        push_to_hub=False,
    )
    
    # Create trainer
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
        eval_dataset=test_dataset,
        compute_metrics=compute_metrics,
    )
    
    # Train the model
    print("Training model...")
    trainer.train()
    
    # Evaluate the model
    print("Evaluating model...")
    results = trainer.evaluate()
    print(f"Evaluation results: {results}")
    
    # Save the model and tokenizer
    model_path = os.path.join(OUTPUT_DIR, "final")
    model.save_pretrained(model_path)
    tokenizer.save_pretrained(model_path)
    print(f"Model and tokenizer saved to {model_path}")
    
    return model, tokenizer

def test_classifier(model, tokenizer, test_texts):
    """Test the classifier on some examples"""
    classifier = pipeline(
        "text-classification", 
        model=model, 
        tokenizer=tokenizer,
        return_all_scores=True
    )
    
    for text in test_texts:
        result = classifier(text)
        scores = result[0]
        
        # Get the probability for "addressed to Goose" (label 1)
        addressed_score = next(score["score"] for score in scores if score["label"] == "LABEL_1")
        
        print(f"Text: {text}")
        print(f"Is addressed to Goose: {addressed_score > 0.5} (confidence: {addressed_score:.4f})")
        print("-" * 50)

def main():
    """Main function"""
    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Load data
    df = load_data()
    
    # Train model
    model, tokenizer = train_model(df)
    
    # Test examples
    test_texts = [
        "Hey Goose, what's the weather like today?",
        "I'm just talking to myself here.",
        "Could you help me with this problem, Goose?",
        "The sky is blue and the grass is green.",
        "Goose, I need you to analyze this data for me.",
        "Hey Siri, set a timer for 5 minutes."
    ]
    
    test_classifier(model, tokenizer, test_texts)
    
    print("Done!")

if __name__ == "__main__":
    main()