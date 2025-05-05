"""
Wakeword detection model using PyTorch.
"""
import os
import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
import numpy as np
from typing import Tuple, Optional, Dict, Any

class WakewordModel(nn.Module):
    """
    CNN-based model for wakeword detection.
    Based on common keyword spotting architectures.
    """
    
    def __init__(self, n_mfcc: int = 40, n_time_frames: int = 98, n_classes: int = 2):
        """
        Initialize the wakeword detection model.
        
        Args:
            n_mfcc: Number of MFCC features
            n_time_frames: Number of time frames in the input
            n_classes: Number of output classes (typically 2: wakeword or not)
        """
        super(WakewordModel, self).__init__()
        
        # Convolutional layers
        self.conv1 = nn.Conv2d(1, 32, kernel_size=3, stride=1, padding=1)
        self.bn1 = nn.BatchNorm2d(32)
        self.pool1 = nn.MaxPool2d(kernel_size=2, stride=2)
        
        self.conv2 = nn.Conv2d(32, 64, kernel_size=3, stride=1, padding=1)
        self.bn2 = nn.BatchNorm2d(64)
        self.pool2 = nn.MaxPool2d(kernel_size=2, stride=2)
        
        self.conv3 = nn.Conv2d(64, 128, kernel_size=3, stride=1, padding=1)
        self.bn3 = nn.BatchNorm2d(128)
        self.pool3 = nn.MaxPool2d(kernel_size=2, stride=2)
        
        # Calculate the size after convolutions and pooling
        # After 3 pooling layers with stride 2, dimensions are reduced by factor of 8
        conv_output_height = n_mfcc // 8
        conv_output_width = n_time_frames // 8
        
        # Fully connected layers
        self.fc1 = nn.Linear(128 * conv_output_height * conv_output_width, 256)
        self.dropout = nn.Dropout(0.5)
        self.fc2 = nn.Linear(256, n_classes)
    
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Forward pass through the network.
        
        Args:
            x: Input tensor of shape [batch_size, 1, n_mfcc, n_time_frames]
            
        Returns:
            Output tensor of shape [batch_size, n_classes]
        """
        # Convolutional layers
        x = self.pool1(F.relu(self.bn1(self.conv1(x))))
        x = self.pool2(F.relu(self.bn2(self.conv2(x))))
        x = self.pool3(F.relu(self.bn3(self.conv3(x))))
        
        # Flatten
        x = x.view(x.size(0), -1)
        
        # Fully connected layers
        x = F.relu(self.fc1(x))
        x = self.dropout(x)
        x = self.fc2(x)
        
        return x


class WakewordDetector:
    """
    Class for training and using the wakeword detection model.
    """
    
    def __init__(self, model: Optional[WakewordModel] = None, 
                 device: str = "cuda" if torch.cuda.is_available() else "cpu",
                 n_mfcc: int = 40, n_time_frames: int = 98, n_classes: int = 2):
        """
        Initialize the wakeword detector.
        
        Args:
            model: Pre-initialized model (if None, a new one will be created)
            device: Device to run the model on ('cuda' or 'cpu')
            n_mfcc: Number of MFCC features
            n_time_frames: Number of time frames in the input
            n_classes: Number of output classes
        """
        self.device = device
        self.n_mfcc = n_mfcc
        self.n_time_frames = n_time_frames
        self.n_classes = n_classes
        
        if model is None:
            self.model = WakewordModel(n_mfcc, n_time_frames, n_classes)
        else:
            self.model = model
            
        self.model.to(self.device)
        self.optimizer = None
        self.criterion = None
    
    def train(self, train_loader, val_loader=None, epochs: int = 20, 
             learning_rate: float = 0.001, weight_decay: float = 1e-5) -> Dict[str, list]:
        """
        Train the wakeword detection model.
        
        Args:
            train_loader: DataLoader for training data
            val_loader: DataLoader for validation data (optional)
            epochs: Number of training epochs
            learning_rate: Learning rate for optimizer
            weight_decay: Weight decay for regularization
            
        Returns:
            Dictionary with training history
        """
        self.model.train()
        self.optimizer = optim.Adam(
            self.model.parameters(), 
            lr=learning_rate, 
            weight_decay=weight_decay
        )
        self.criterion = nn.CrossEntropyLoss()
        
        history = {
            'train_loss': [],
            'train_acc': [],
            'val_loss': [],
            'val_acc': []
        }
        
        for epoch in range(epochs):
            # Training
            self.model.train()
            train_loss = 0.0
            correct = 0
            total = 0
            
            for inputs, targets in train_loader:
                inputs, targets = inputs.to(self.device), targets.to(self.device)
                
                # Zero the parameter gradients
                self.optimizer.zero_grad()
                
                # Forward pass
                outputs = self.model(inputs)
                loss = self.criterion(outputs, targets)
                
                # Backward pass and optimize
                loss.backward()
                self.optimizer.step()
                
                # Statistics
                train_loss += loss.item()
                _, predicted = outputs.max(1)
                total += targets.size(0)
                correct += predicted.eq(targets).sum().item()
            
            train_loss = train_loss / len(train_loader)
            train_acc = 100.0 * correct / total
            history['train_loss'].append(train_loss)
            history['train_acc'].append(train_acc)
            
            # Validation
            if val_loader is not None:
                val_loss, val_acc = self.evaluate(val_loader)
                history['val_loss'].append(val_loss)
                history['val_acc'].append(val_acc)
                
                print(f"Epoch {epoch+1}/{epochs} - "
                      f"Train Loss: {train_loss:.4f}, Train Acc: {train_acc:.2f}% - "
                      f"Val Loss: {val_loss:.4f}, Val Acc: {val_acc:.2f}%")
            else:
                print(f"Epoch {epoch+1}/{epochs} - "
                      f"Train Loss: {train_loss:.4f}, Train Acc: {train_acc:.2f}%")
        
        return history
    
    def evaluate(self, data_loader) -> Tuple[float, float]:
        """
        Evaluate the model on a dataset.
        
        Args:
            data_loader: DataLoader for evaluation data
            
        Returns:
            Tuple of (loss, accuracy)
        """
        self.model.eval()
        eval_loss = 0.0
        correct = 0
        total = 0
        
        with torch.no_grad():
            for inputs, targets in data_loader:
                inputs, targets = inputs.to(self.device), targets.to(self.device)
                outputs = self.model(inputs)
                loss = self.criterion(outputs, targets)
                
                eval_loss += loss.item()
                _, predicted = outputs.max(1)
                total += targets.size(0)
                correct += predicted.eq(targets).sum().item()
        
        eval_loss = eval_loss / len(data_loader)
        accuracy = 100.0 * correct / total
        
        return eval_loss, accuracy
    
    def predict(self, features: np.ndarray) -> Tuple[int, float]:
        """
        Make a prediction using the model.
        
        Args:
            features: MFCC features as numpy array [n_mfcc, n_time_frames]
            
        Returns:
            Tuple of (predicted_class, confidence)
        """
        self.model.eval()
        
        # Prepare input: add batch and channel dimensions
        x = torch.from_numpy(features).float().unsqueeze(0).unsqueeze(0)
        x = x.to(self.device)
        
        # Make prediction
        with torch.no_grad():
            outputs = self.model(x)
            probabilities = F.softmax(outputs, dim=1)
            
            # Get predicted class and confidence
            confidence, predicted = torch.max(probabilities, 1)
        
        return predicted.item(), confidence.item()
    
    def save_model(self, path: str):
        """
        Save the model to a file.
        
        Args:
            path: Path to save the model
        """
        # Create directory if it doesn't exist
        os.makedirs(os.path.dirname(path), exist_ok=True)
        
        # Save model state dict and metadata
        torch.save({
            'model_state_dict': self.model.state_dict(),
            'n_mfcc': self.n_mfcc,
            'n_time_frames': self.n_time_frames,
            'n_classes': self.n_classes
        }, path)
        
        print(f"Model saved to {path}")
    
    @classmethod
    def load_model(cls, path: str, device: str = None) -> 'WakewordDetector':
        """
        Load a model from a file.
        
        Args:
            path: Path to the saved model
            device: Device to load the model on (if None, use available)
            
        Returns:
            Loaded WakewordDetector instance
        """
        if device is None:
            device = "cuda" if torch.cuda.is_available() else "cpu"
            
        # Load model state dict and metadata
        checkpoint = torch.load(path, map_location=device)
        
        # Create model with the same architecture
        model = WakewordModel(
            n_mfcc=checkpoint['n_mfcc'],
            n_time_frames=checkpoint['n_time_frames'],
            n_classes=checkpoint['n_classes']
        )
        
        # Load weights
        model.load_state_dict(checkpoint['model_state_dict'])
        
        # Create detector
        detector = cls(
            model=model,
            device=device,
            n_mfcc=checkpoint['n_mfcc'],
            n_time_frames=checkpoint['n_time_frames'],
            n_classes=checkpoint['n_classes']
        )
        
        return detector
    
    def export_to_onnx(self, path: str):
        """
        Export the model to ONNX format.
        
        Args:
            path: Path to save the ONNX model
        """
        # Create a dummy input tensor
        dummy_input = torch.randn(1, 1, self.n_mfcc, self.n_time_frames, 
                                 device=self.device)
        
        # Export the model
        torch.onnx.export(
            self.model,
            dummy_input,
            path,
            export_params=True,
            opset_version=11,
            do_constant_folding=True,
            input_names=['input'],
            output_names=['output'],
            dynamic_axes={'input': {0: 'batch_size'},
                         'output': {0: 'batch_size'}}
        )
        
        print(f"Model exported to ONNX format at {path}")