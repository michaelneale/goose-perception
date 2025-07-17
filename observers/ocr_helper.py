#!/usr/bin/env python3

import sys
import os
from ocrmac import ocrmac

def perform_ocr(image_path):
    """
    Perform OCR on an image using ocrmac (Apple Vision Framework)
    Returns filtered text or an error message
    """
    try:
        if not os.path.exists(image_path):
            return f"Error: Image file {image_path} does not exist"
        
        # Use ocrmac to perform OCR
        # Using 'accurate' recognition level for better quality
        annotations = ocrmac.OCR(image_path, recognition_level='accurate').recognize()
        
        # Extract text from annotations
        # annotations is a list of tuples: (text, confidence, bounding_box)
        text_lines = []
        for annotation in annotations:
            text = annotation[0]  # First element is the text
            confidence = annotation[1]  # Second element is confidence
            
            # Only include text with reasonable confidence (>0.5)
            if confidence > 0.5 and text.strip():
                text_lines.append(text.strip())
        
        # Join all text lines
        full_text = '\n'.join(text_lines)
        
        if not full_text.strip():
            return "No text detected in image"
        
        return full_text
        
    except Exception as e:
        return f"OCR Error: {str(e)}"

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 ocr_helper.py <image_path>")
        sys.exit(1)
    
    image_path = sys.argv[1]
    result = perform_ocr(image_path)
    print(result) 