#!/usr/bin/env python3
"""
Startup script for goose-perception
Ensures all schedules are properly configured with GooseSchedule
"""

import sys
import os
import time
from pathlib import Path
from schedule_manager import ScheduleManager

def startup_sync():
    """Sync schedules on startup"""
    print("=" * 60)
    print("🚀 Goose Perception Startup")
    print("=" * 60)
    print()
    
    # Check if goose schedule is available
    import subprocess
    try:
        result = subprocess.run(["goose", "schedule", "--help"], 
                              capture_output=True, text=True, check=True)
        print("✓ GooseSchedule is available")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("✗ GooseSchedule is not available")
        print("  Please ensure you have a recent version of goose installed")
        return False
    
    # Initialize schedule manager
    print("📋 Initializing schedule manager...")
    manager = ScheduleManager()
    
    # Sync schedules
    print("🔄 Syncing schedules...")
    print()
    
    try:
        added, removed, skipped = manager.sync_schedules(dry_run=False)
        
        print()
        print("=" * 60)
        print("📊 Schedule Sync Summary")
        print("=" * 60)
        print(f"✅ Added: {added}")
        print(f"🗑️  Removed: {removed}")
        print(f"⏭️  Skipped: {skipped}")
        
        if added > 0 or removed > 0:
            print()
            print("✨ Schedule sync completed successfully!")
            print("🎯 All observation recipes are now scheduled with GooseSchedule")
        else:
            print()
            print("✅ All schedules were already up to date")
        
        return True
        
    except Exception as e:
        print(f"❌ Error during schedule sync: {e}")
        return False

def main():
    """Main startup function"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Goose Perception Startup Script")
    parser.add_argument("--check-interval", type=int, default=0,
                       help="Check interval in minutes (0 = run once and exit)")
    parser.add_argument("--verbose", "-v", action="store_true",
                       help="Verbose output")
    
    args = parser.parse_args()
    
    # Run initial sync
    success = startup_sync()
    
    if not success:
        print("❌ Startup failed")
        sys.exit(1)
    
    # If check interval is specified, run periodically
    if args.check_interval > 0:
        print()
        print(f"🔄 Running periodic checks every {args.check_interval} minutes...")
        print("   Press Ctrl+C to stop")
        
        try:
            while True:
                time.sleep(args.check_interval * 60)
                
                if args.verbose:
                    print(f"\n🔍 Periodic check at {time.strftime('%Y-%m-%d %H:%M:%S')}")
                
                manager = ScheduleManager()
                added, removed, skipped = manager.sync_schedules(dry_run=False)
                
                if added > 0 or removed > 0:
                    print(f"🔄 Sync: +{added} -{removed} ⏭{skipped}")
                elif args.verbose:
                    print("✅ All schedules up to date")
                    
        except KeyboardInterrupt:
            print("\n👋 Stopping periodic checks")
    
    print("\n🎉 Startup complete!")

if __name__ == "__main__":
    main() 