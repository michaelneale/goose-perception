#!/usr/bin/env python3
"""
Screenshot Capture Service for Goose Perception
Handles continuous screenshot capture without scheduling logic
(Scheduling is now handled by GooseSchedule)
"""

import os
import time
import signal
import sys
import subprocess
from pathlib import Path
from datetime import datetime

class ScreenshotCapture:
    """Handles continuous screenshot capture for goose-perception"""
    
    def __init__(self, screenshot_dir="/tmp/screenshots", interval=20):
        self.screenshot_dir = Path(screenshot_dir)
        self.interval = interval
        self.running = True
        
        # Create screenshots directory
        self.screenshot_dir.mkdir(parents=True, exist_ok=True)
        
        # Create goose-perception activity log directory
        self.perception_dir = Path.home() / ".local/share/goose-perception"
        self.perception_dir.mkdir(parents=True, exist_ok=True)
        
        # Set up signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
        print(f"📸 Screenshot capture initialized")
        print(f"   Directory: {self.screenshot_dir}")
        print(f"   Interval: {self.interval} seconds")
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        print(f"\n🛑 Received signal {signum}, shutting down...")
        self.running = False
    
    def log_activity(self, message):
        """Log activity to the activity log"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_file = self.perception_dir / "ACTIVITY-LOG.md"
        
        with open(log_file, "a") as f:
            f.write(f"**{timestamp}**: {message}\n")
        
        print(f"{timestamp}: {message}")
    
    def get_display_count(self):
        """Get the number of displays"""
        try:
            result = subprocess.run(
                ["system_profiler", "SPDisplaysDataType"],
                capture_output=True, text=True, check=True
            )
            return result.stdout.count("Resolution:")
        except subprocess.CalledProcessError:
            return 0
    
    def capture_screenshots(self):
        """Capture screenshots of all displays"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        num_displays = self.get_display_count()
        
        if num_displays == 0:
            print("⚠️  No displays detected, skipping capture")
            return False
        
        success_count = 0
        
        # Capture each display
        for display_num in range(1, num_displays + 1):
            filename = f"screen_{timestamp}_display{display_num}.png"
            filepath = self.screenshot_dir / filename
            
            try:
                subprocess.run([
                    "screencapture", "-x", "-D", str(display_num), str(filepath)
                ], check=True, capture_output=True)
                success_count += 1
            
            except subprocess.CalledProcessError as e:
                print(f"❌ Failed to capture display {display_num}: {e}")
        
        if success_count > 0:
            print(f"📸 Captured {success_count}/{num_displays} displays at {timestamp}")
            return True
        else:
            print(f"❌ Failed to capture any displays")
            return False
    
    def cleanup_old_screenshots(self, max_age_hours=24):
        """Clean up screenshots older than max_age_hours"""
        cutoff_time = time.time() - (max_age_hours * 3600)
        cleaned = 0
        
        for screenshot in self.screenshot_dir.glob("screen_*.png"):
            try:
                if screenshot.stat().st_mtime < cutoff_time:
                    screenshot.unlink()
                    cleaned += 1
            except OSError:
                pass
        
        if cleaned > 0:
            print(f"🧹 Cleaned up {cleaned} old screenshots")
        
        return cleaned
    
    def run(self):
        """Main capture loop"""
        print("🚀 Starting screenshot capture service...")
        print("   Press Ctrl+C to stop")
        
        self.log_activity("Screenshot capture service started")
        
        # Initial screenshot
        self.capture_screenshots()
        
        cleanup_counter = 0
        
        try:
            while self.running:
                # Wait for the specified interval
                time.sleep(self.interval)
                
                if not self.running:
                    break
                
                # Capture screenshots
                self.capture_screenshots()
                
                # Periodic cleanup (every hour)
                cleanup_counter += 1
                if cleanup_counter >= (3600 // self.interval):  # approximately every hour
                    self.cleanup_old_screenshots()
                    cleanup_counter = 0
        
        except KeyboardInterrupt:
            print("\n🛑 Interrupted by user")
        
        finally:
            self.log_activity("Screenshot capture service stopped")
            print("👋 Screenshot capture service stopped")

def main():
    """Main function"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Screenshot Capture Service for Goose Perception")
    parser.add_argument("--interval", "-i", type=int, default=20,
                       help="Screenshot interval in seconds (default: 20)")
    parser.add_argument("--screenshot-dir", "-d", default="/tmp/screenshots",
                       help="Screenshot directory (default: /tmp/screenshots)")
    parser.add_argument("--cleanup-hours", type=int, default=24,
                       help="Clean up screenshots older than this many hours (default: 24)")
    
    args = parser.parse_args()
    
    # Validate arguments
    if args.interval < 1:
        print("❌ Interval must be at least 1 second")
        sys.exit(1)
    
    # Create and run capture service
    capture = ScreenshotCapture(
        screenshot_dir=args.screenshot_dir,
        interval=args.interval
    )
    
    try:
        capture.run()
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 