"""
Script for training a wakeword detection model.
"""
import os
import argparse
import torch
import numpy as np
import matplotlib.pyplot as plt
from datetime import datetime

from src.audio.processor import AudioProcessor
from src.models.wakeword import WakewordDetector
from src.models.dataset import WakewordDataProcessor

def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Train a wakeword detection model")
    
    parser.add_argument("--data_dir", type=str, required=True,
                       help="Directory containing audio data (with class subdirectories)")
    parser.add_argument("--output_dir", type=str, default="models",
                       help="Directory to save the trained model")
    parser.add_argument("--model_name", type=str, default=None,
                       help="Name for the trained model (default: wakeword_YYYYMMDD_HHMMSS)")
    parser.add_argument("--epochs", type=int, default=20,
                       help="Number of training epochs")
    parser.add_argument("--batch_size", type=int, default=32,
                       help="Batch size for training")
    parser.add_argument("--learning_rate", type=float, default=0.001,
                       help="Learning rate for optimizer")
    parser.add_argument("--target_length", type=float, default=1.0,
                       help="Target audio length in seconds")
    parser.add_argument("--val_split", type=float, default=0.2,
                       help="Fraction of data to use for validation")
    parser.add_argument("--test_split", type=float, default=0.1,
                       help="Fraction of data to use for testing")
    parser.add_argument("--augment", action="store_true",
                       help="Whether to augment the training data")
    parser.add_argument("--augment_factor", type=int, default=2,
                       help="Number of augmented samples to create per original sample")
    parser.add_argument("--device", type=str, default=None,
                       help="Device to train on (cuda or cpu, default: auto-detect)")
    parser.add_argument("--export_onnx", action="store_true",
                       help="Whether to export the model to ONNX format")
    
    return parser.parse_args()

def plot_training_history(history, output_path):
    """
    Plot training history and save to file.
    
    Args:
        history: Training history dictionary
        output_path: Path to save the plot
    """
    plt.figure(figsize=(12, 5))
    
    # Plot training & validation loss
    plt.subplot(1, 2, 1)
    plt.plot(history['train_loss'], label='Train')
    plt.plot(history['val_loss'], label='Validation')
    plt.title('Loss')
    plt.xlabel('Epoch')
    plt.ylabel('Loss')
    plt.legend()
    
    # Plot training & validation accuracy
    plt.subplot(1, 2, 2)
    plt.plot(history['train_acc'], label='Train')
    plt.plot(history['val_acc'], label='Validation')
    plt.title('Accuracy')
    plt.xlabel('Epoch')
    plt.ylabel('Accuracy (%)')
    plt.legend()
    
    plt.tight_layout()
    plt.savefig(output_path)
    plt.close()

def main():
    """Main training function."""
    args = parse_args()
    
    # Set device
    if args.device is None:
        device = "cuda" if torch.cuda.is_available() else "cpu"
    else:
        device = args.device
    
    print(f"Using device: {device}")
    
    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Generate model name if not provided
    if args.model_name is None:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        args.model_name = f"wakeword_{timestamp}"
    
    # Initialize processors
    audio_processor = AudioProcessor()
    data_processor = WakewordDataProcessor(audio_processor)
    
    # Process audio files
    print(f"Processing audio files from {args.data_dir}...")
    features, labels, label_mapping = data_processor.process_audio_files(
        args.data_dir, target_length=args.target_length
    )
    
    print(f"Processed {len(labels)} audio files")
    print(f"Label mapping: {label_mapping}")
    
    # Augment data if requested
    if args.augment:
        print(f"Augmenting data with factor {args.augment_factor}...")
        features, labels = data_processor.augment_data(
            features, labels, augmentation_factor=args.augment_factor
        )
        print(f"Data size after augmentation: {len(labels)} samples")
    
    # Create data loaders
    print("Creating data loaders...")
    data_loaders = data_processor.create_data_loaders(
        features, labels,
        val_split=args.val_split,
        test_split=args.test_split,
        batch_size=args.batch_size
    )
    
    # Get input dimensions from the first batch
    for inputs, _ in data_loaders['train']:
        input_shape = inputs.shape
        break
    
    n_mfcc = input_shape[2]  # Height of the MFCC features
    n_time_frames = input_shape[3]  # Width of the MFCC features
    n_classes = len(label_mapping)
    
    print(f"Input shape: {input_shape}")
    print(f"n_mfcc: {n_mfcc}, n_time_frames: {n_time_frames}, n_classes: {n_classes}")
    
    # Initialize model
    detector = WakewordDetector(
        model=None,
        device=device,
        n_mfcc=n_mfcc,
        n_time_frames=n_time_frames,
        n_classes=n_classes
    )
    
    # Train model
    print(f"Training model for {args.epochs} epochs...")
    history = detector.train(
        train_loader=data_loaders['train'],
        val_loader=data_loaders['val'],
        epochs=args.epochs,
        learning_rate=args.learning_rate
    )
    
    # Evaluate on test set
    test_loss, test_acc = detector.evaluate(data_loaders['test'])
    print(f"Test Loss: {test_loss:.4f}, Test Accuracy: {test_acc:.2f}%")
    
    # Save model
    model_path = os.path.join(args.output_dir, f"{args.model_name}.pt")
    detector.save_model(model_path)
    
    # Export to ONNX if requested
    if args.export_onnx:
        onnx_path = os.path.join(args.output_dir, f"{args.model_name}.onnx")
        detector.export_to_onnx(onnx_path)
    
    # Plot training history
    history_path = os.path.join(args.output_dir, f"{args.model_name}_history.png")
    plot_training_history(history, history_path)
    
    # Save training metadata
    metadata = {
        "model_name": args.model_name,
        "n_mfcc": n_mfcc,
        "n_time_frames": n_time_frames,
        "n_classes": n_classes,
        "label_mapping": label_mapping,
        "test_accuracy": test_acc,
        "test_loss": test_loss,
        "training_args": vars(args)
    }
    
    import json
    metadata_path = os.path.join(args.output_dir, f"{args.model_name}_metadata.json")
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print(f"Model saved to {model_path}")
    print(f"Training history plot saved to {history_path}")
    print(f"Metadata saved to {metadata_path}")

if __name__ == "__main__":
    main()