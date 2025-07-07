#!/usr/bin/env python3
"""
Schedule Synchronization Script for goose-perception
Ensures all schedules are properly configured with GooseSchedule
"""

import sys
import os
import time
from pathlib import Path
from schedule_manager import ScheduleManager

def sync_schedules():
    """Sync schedules with GooseSchedule"""
    print("=" * 60)
    print("🔄 Goose Perception Schedule Sync")
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
    
    # Run system setup recipe first
    print("🔧 Running system setup...")
    try:
        setup_result = subprocess.run([
            "goose", "run", "--recipe", "observers/recipe-system-setup.yaml"
        ], capture_output=True, text=True, timeout=120)
        
        if setup_result.returncode == 0:
            print("✓ System setup completed successfully")
        else:
            print("⚠️  System setup had issues, but continuing...")
            if setup_result.stderr:
                print(f"  Setup output: {setup_result.stderr.strip()}")
    except subprocess.TimeoutExpired:
        print("⚠️  System setup timed out, but continuing...")
    except Exception as e:
        print(f"⚠️  System setup error: {e}, but continuing...")
    
    print()
    
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
    """Main function for schedule synchronization"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Goose Perception Schedule Sync")
    parser.add_argument("--check-interval", type=int, default=0,
                       help="Check interval in minutes (0 = run once and exit)")
    parser.add_argument("--verbose", "-v", action="store_true",
                       help="Verbose output")
    
    args = parser.parse_args()
    
    # Run initial sync
    success = sync_schedules()
    
    if not success:
        print("❌ Schedule sync failed")
        sys.exit(1)
    
    # If check interval is specified, run periodically
    if args.check_interval > 0:
        print()
        print(f"🔄 Running periodic sync every {args.check_interval} minutes...")
        print("   Press Ctrl+C to stop")
        
        try:
            while True:
                time.sleep(args.check_interval * 60)
                
                if args.verbose:
                    print(f"\n🔍 Periodic sync at {time.strftime('%Y-%m-%d %H:%M:%S')}")
                
                manager = ScheduleManager()
                added, removed, skipped = manager.sync_schedules(dry_run=False)
                
                if added > 0 or removed > 0:
                    print(f"🔄 Sync: +{added} -{removed} ⏭{skipped}")
                elif args.verbose:
                    print("✅ All schedules up to date")
                    
        except KeyboardInterrupt:
            print("\n👋 Stopping periodic sync")
    
    print("\n🎉 Schedule sync complete!")

if __name__ == "__main__":
    main() 