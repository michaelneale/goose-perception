#!/usr/bin/env python3
"""
classifier.py - Wake word classifier for detecting if text is addressed to Goose
"""

import os
import argparse
import json
from transformers import AutoModelForSequenceClassification, AutoTokenizer, pipeline

# Default model path
MODEL_PATH = os.path.join(os.path.dirname(__file__), "model/final")

class GooseWakeClassifier:
    """Classifier to determine if text is addressed to Goose"""
    
    def __init__(self, model_path=MODEL_PATH):
        """Initialize the classifier with the given model path"""
        self.model_path = model_path
        self._load_model()
    
    def _load_model(self):
        """Load the model and tokenizer"""
        try:
            self.tokenizer = AutoTokenizer.from_pretrained(self.model_path)
            self.model = AutoModelForSequenceClassification.from_pretrained(self.model_path)
            self.classifier = pipeline(
                "text-classification", 
                model=self.model, 
                tokenizer=self.tokenizer,
                return_all_scores=True
            )
            print(f"Model loaded from {self.model_path}")
        except Exception as e:
            print(f"Error loading model: {e}")
            print("Falling back to default classifier")
            self.model = None
            self.tokenizer = None
            self.classifier = None
    
    def classify(self, text):
        """
        Classify if the input text is addressed to Goose
        
        Args:
            text (str): The text to classify
            
        Returns:
            dict: Classification result with label and confidence
        """
        if self.classifier:
            # Use the fine-tuned model
            try:
                result = self.classifier(text)
                scores = result[0]
                
                # Get the probability for "addressed to Goose" (label 1)
                addressed_score = next(score["score"] for score in scores if score["label"] == "LABEL_1")
                not_addressed_score = next(score["score"] for score in scores if score["label"] == "LABEL_0")
                
                # Determine classification
                is_addressed = addressed_score > not_addressed_score
                
                return {
                    "text": text,
                    "classification": "ADDRESSED_TO_GOOSE" if is_addressed else "NOT_ADDRESSED_TO_GOOSE",
                    "addressed_to_goose": is_addressed,
                    "confidence": float(addressed_score if is_addressed else not_addressed_score)
                }
            except Exception as e:
                print(f"Error during classification: {e}")
                # Fall back to rule-based classifier
                return self._rule_based_classify(text)
        else:
            # Fall back to rule-based classifier
            return self._rule_based_classify(text)
    
    def _rule_based_classify(self, text):
        """Simple rule-based classifier as fallback"""
        text_lower = text.lower()
        
        # Check for direct mentions of "goose"
        contains_goose = "goose" in text_lower
        
        # Check for question or command indicators
        question_indicators = ["?", "can you", "could you", "would you", "will you", "please"]
        has_question = any(indicator in text_lower for indicator in question_indicators)
        
        # Determine if addressed to Goose
        is_addressed = contains_goose and has_question
        
        # Calculate a simple confidence score
        confidence = 0.9 if is_addressed else 0.7
        
        return {
            "text": text,
            "classification": "ADDRESSED_TO_GOOSE" if is_addressed else "NOT_ADDRESSED_TO_GOOSE",
            "addressed_to_goose": is_addressed,
            "confidence": confidence,
            "note": "Using rule-based fallback classifier"
        }

def main():
    """Parse command line arguments and run the classifier"""
    parser = argparse.ArgumentParser(description="Classify if text is addressed to Goose")
    parser.add_argument("text", help="The text to classify")
    parser.add_argument("--model", help="Path to the model directory", default=MODEL_PATH)
    parser.add_argument("--json", action="store_true", help="Output result as JSON")
    args = parser.parse_args()
    
    classifier = GooseWakeClassifier(model_path=args.model)
    result = classifier.classify(args.text)
    
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"Text: {result['text']}")
        print(f"Classification: {result['classification']}")
        print(f"Addressed to Goose: {'Yes' if result['addressed_to_goose'] else 'No'}")
        print(f"Confidence: {result['confidence']:.4f}")
        if "note" in result:
            print(f"Note: {result['note']}")

if __name__ == "__main__":
    main()