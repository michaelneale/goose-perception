#!/usr/bin/env python3
"""
setup_emotion_detection.py - Setup script for lightweight emotion detection
"""

import subprocess
import sys
import importlib

def install_package(package):
    """Install a package using pip"""
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])
        return True
    except subprocess.CalledProcessError:
        return False

def check_package(package_name, import_name=None):
    """Check if a package is installed"""
    if import_name is None:
        import_name = package_name
    
    try:
        importlib.import_module(import_name)
        return True
    except ImportError:
        return False

def main():
    print("🎭 Setting up lightweight emotion detection system...")
    
    # Required packages for lightweight emotion detection
    packages = [
        ("opencv-python", "cv2"),
        ("deepface", "deepface"),
        ("tensorflow", "tensorflow"),  # Required by DeepFace
        ("numpy", "numpy"),
        ("pillow", "PIL"),
    ]
    
    installed_packages = []
    failed_packages = []
    
    for package, import_name in packages:
        print(f"📦 Checking {package}...")
        
        if check_package(package, import_name):
            print(f"✅ {package} already installed")
            installed_packages.append(package)
        else:
            print(f"📥 Installing {package}...")
            if install_package(package):
                print(f"✅ {package} installed successfully")
                installed_packages.append(package)
            else:
                print(f"❌ Failed to install {package}")
                failed_packages.append(package)
    
    print("\n📊 Installation Summary:")
    print(f"✅ Successfully installed/verified: {len(installed_packages)} packages")
    for package in installed_packages:
        print(f"   - {package}")
    
    if failed_packages:
        print(f"❌ Failed to install: {len(failed_packages)} packages")
        for package in failed_packages:
            print(f"   - {package}")
        print("\n⚠️ Some packages failed to install. The system will use fallback methods.")
    
    # Test the emotion detection system
    print("\n🧪 Testing emotion detection system...")
    try:
        from emotion_detector_v2 import LightweightEmotionDetector
        
        detector = LightweightEmotionDetector()
        if detector.is_initialized:
            print("✅ Emotion detection system is ready!")
            
            # Get summary
            summary = detector.get_emotion_summary()
            print(f"📊 System status: {summary.get('status', 'unknown')}")
        else:
            print("⚠️ Emotion detection system initialized with limited functionality")
        
        detector.cleanup()
        
    except Exception as e:
        print(f"❌ Error testing emotion detection: {e}")
    
    print("\n🎉 Setup complete!")
    print("💡 The emotion detection system will automatically download AI models on first use.")
    print("💡 Use 'python emotion_detector_v2.py' to test the system manually.")

if __name__ == "__main__":
    main() 