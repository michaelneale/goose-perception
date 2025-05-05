#!/usr/bin/env python3
"""
Text classifier using Ollama's Gemma 3:12B model to determine if text is addressed to someone.
"""

import argparse
import json
import requests
import sys

def classify_text(text):
    """
    Classify if the input text is addressed to someone using Gemma 3:12B via Ollama.
    
    Args:
        text (str): The text to classify
        
    Returns:
        dict: Classification result with label and confidence
    """
    # Ollama API endpoint
    url = "http://localhost:11434/api/generate"
    
    # Prompt engineering to get the model to classify
    prompt = f"""
You are a text classifier that determines if a piece of text is addressed to someone.

Examples:
- "Can you tell me the weather today?" - ADDRESSED_TO_SOMEONE
- "I went to the store yesterday." - NOT_ADDRESSED_TO_SOMEONE
- "Please help me with my homework." - ADDRESSED_TO_SOMEONE
- "The sky is blue." - NOT_ADDRESSED_TO_SOMEONE
- "Would you mind passing the salt?" - ADDRESSED_TO_SOMEONE

Classify the following text as either ADDRESSED_TO_SOMEONE or NOT_ADDRESSED_TO_SOMEONE.
Respond with only one of these two labels and nothing else.

Text: "{text}"
Classification:
"""
    
    # Prepare the payload for Ollama API
    payload = {
        "model": "gemma3:12b",
        "prompt": prompt,
        "stream": False
    }
    
    try:
        # Make the API request
        response = requests.post(url, json=payload)
        response.raise_for_status()
        
        # Extract the response
        result = response.json()
        output = result.get("response", "").strip()
        
        # Validate the output
        if output not in ["ADDRESSED_TO_SOMEONE", "NOT_ADDRESSED_TO_SOMEONE"]:
            print(f"Warning: Unexpected model output: {output}")
            print("Falling back to best guess based on output...")
            
            if "ADDRESSED" in output:
                if "NOT" in output:
                    output = "NOT_ADDRESSED_TO_SOMEONE"
                else:
                    output = "ADDRESSED_TO_SOMEONE"
            else:
                # Default fallback
                output = "CLASSIFICATION_ERROR"
        
        return {
            "text": text,
            "classification": output,
            "addressed_to_someone": output == "ADDRESSED_TO_SOMEONE"
        }
        
    except requests.exceptions.RequestException as e:
        print(f"Error connecting to Ollama: {e}", file=sys.stderr)
        return {
            "text": text,
            "classification": "ERROR",
            "error": str(e),
            "addressed_to_someone": None
        }

def main():
    """Parse command line arguments and run the classifier"""
    parser = argparse.ArgumentParser(description="Classify if text is addressed to someone using Gemma 3:12B")
    parser.add_argument("text", help="The text to classify")
    parser.add_argument("--json", action="store_true", help="Output result as JSON")
    args = parser.parse_args()
    
    result = classify_text(args.text)
    
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"Text: {result['text']}")
        print(f"Classification: {result['classification']}")
        if result['addressed_to_someone'] is not None:
            print(f"Addressed to someone: {'Yes' if result['addressed_to_someone'] else 'No'}")

if __name__ == "__main__":
    main()