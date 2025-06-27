#!/usr/bin/env python3

"""
Setup script for goose-perception directory structure.
Extracted from the old bash scripts to preserve useful functionality.
"""

import os
import shutil
from pathlib import Path
from datetime import datetime


def setup_directories():
    """Create necessary directories for goose-perception."""
    perception_dir = Path.home() / ".local/share/goose-perception"
    screenshot_dir = Path("/tmp/screenshots")
    
    # Create main directories
    directories = [
        perception_dir,
        perception_dir / "automated-actions/daily",
        perception_dir / "automated-actions/weekly", 
        perception_dir / "adapted-observers",
        screenshot_dir
    ]
    
    for directory in directories:
        directory.mkdir(parents=True, exist_ok=True)
        print(f"Created directory: {directory}")
    
    return perception_dir


def copy_goosehints(perception_dir):
    """Copy .goosehints file to subdirectories."""
    goosehints_file = Path("observers/.goosehints")
    
    if not goosehints_file.exists():
        print(f"Warning: {goosehints_file} not found, skipping .goosehints setup")
        return
    
    target_dirs = [
        perception_dir / "automated-actions/daily",
        perception_dir / "automated-actions/weekly",
        perception_dir / "adapted-observers"
    ]
    
    for target_dir in target_dirs:
        target_file = target_dir / ".goosehints"
        shutil.copy2(goosehints_file, target_file)
        print(f"Copied .goosehints to {target_file}")


def log_activity(perception_dir, message):
    """Log activity to the activity log."""
    log_file = perception_dir / "ACTIVITY-LOG.md"
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    with open(log_file, "a") as f:
        f.write(f"**{timestamp}**: {message}\n")
    
    print(f"{timestamp}: {message}")


def main():
    """Run the setup process."""
    print("Setting up goose-perception directories...")
    
    perception_dir = setup_directories()
    copy_goosehints(perception_dir)
    log_activity(perception_dir, "Directory setup completed")
    
    print("Setup complete!")


if __name__ == "__main__":
    main() 