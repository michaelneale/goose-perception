#!/usr/bin/env python3
"""
Schedule Manager for Goose Perception
Automatically discovers and manages scheduled jobs from recipe files
"""

import subprocess
import json
import sys
import os
try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False
    print("⚠️  Warning: PyYAML not installed. Schedule discovery from recipe files will be limited.")
    print("   Install with: pip install PyYAML")
    print("   Or use: ./.use-hermit python3 schedule_manager.py")
    print()

from typing import Dict, List, Optional, Tuple, Union
from dataclasses import dataclass
from pathlib import Path

@dataclass
class ScheduleConfig:
    """Configuration for a scheduled recipe"""
    recipe_path: str
    frequency: str
    weekday_only: bool = False
    time_of_day: Optional[str] = None  # morning, afternoon, evening
    description: str = ""
    enabled: bool = True

class ScheduleManager:
    """Manages GooseSchedule jobs for goose-perception recipes"""
    
    def __init__(self):
        self.observers_dir = Path("observers")
        self.local_observers_dir = Path("observers/local-observers")
        self.root_dir = Path(".")
        
        # Define all scheduled recipes with their configurations
        self.schedules = {
            # System recipes
            "screenshot-capture": ScheduleConfig(
                recipe_path="observers/recipe-screenshot-capture.yaml",
                frequency="20s",  # Every 20 seconds - GooseSchedule supports 6-field cron with seconds!
                weekday_only=False,
                description="Capture screenshots every 20 seconds (original frequency restored)"
            ),
            
            # Main observation recipes
            "work": ScheduleConfig(
                recipe_path="observers/recipe-work.yaml",
                frequency="20m",
                weekday_only=True,
                description="Work summary every 20 minutes on weekdays"
            ),
            "contributions": ScheduleConfig(
                recipe_path="observers/recipe-contributions.yaml", 
                frequency="hourly",
                weekday_only=True,
                description="Contributions summary every hour on weekdays"
            ),
            "focus": ScheduleConfig(
                recipe_path="observers/recipe-focus.yaml",
                frequency="55m", 
                weekday_only=True,
                description="Focus analysis every 55 minutes on weekdays"
            ),
            "hypedoc": ScheduleConfig(
                recipe_path="observers/recipe-hypedoc.yaml",
                frequency="weekly",
                description="Hypedoc generation weekly"
            ),
            "garbage-collect": ScheduleConfig(
                recipe_path="observers/recipe-garbage-collect.yaml",
                frequency="weekly",
                weekday_only=True,
                description="Garbage collection weekly on weekdays"
            ),
            "projects": ScheduleConfig(
                recipe_path="observers/recipe-projects.yaml",
                frequency="daily",
                weekday_only=True,
                time_of_day="morning",
                description="Projects review daily in the morning on weekdays"
            ),
            "work-personal": ScheduleConfig(
                recipe_path="observers/recipe-work-personal.yaml",
                frequency="daily",
                time_of_day="evening",
                description="Work-personal analysis daily in the evening"
            ),
            "interactions": ScheduleConfig(
                recipe_path="observers/recipe-interactions.yaml",
                frequency="hourly",
                description="Interactions summary every hour"
            ),
            "chrome-history": ScheduleConfig(
                recipe_path="observers/recipe-chrome-history.yaml",
                frequency="4h",
                weekday_only=True,
                description="Chrome history analysis every 4 hours on weekdays"
            ),
            "important-attention-message": ScheduleConfig(
                recipe_path="observers/recipe-important-attention-message.yaml",
                frequency="hourly",
                weekday_only=True,
                description="Important attention messages every hour on weekdays"
            ),
            "interests": ScheduleConfig(
                recipe_path="observers/recipe-interests.yaml",
                frequency="daily",
                description="Interests analysis daily"
            ),
            "morning-attention": ScheduleConfig(
                recipe_path="observers/recipe-morning-attention.yaml",
                frequency="daily",
                weekday_only=True,
                time_of_day="morning",
                description="Morning attention daily on weekdays"
            ),
            "upcoming": ScheduleConfig(
                recipe_path="observers/recipe-upcoming.yaml",
                frequency="daily",
                weekday_only=True,
                time_of_day="afternoon",
                description="Upcoming tasks daily in the afternoon on weekdays"
            ),
            "what-working-on": ScheduleConfig(
                recipe_path="observers/recipe-what-working-on.yaml",
                frequency="daily",
                weekday_only=True,
                time_of_day="evening",
                description="What working on daily in the evening on weekdays"
            ),
            "optimize": ScheduleConfig(
                recipe_path="observers/recipe-optimize.yaml",
                frequency="weekly",
                description="Optimization analysis weekly"
            ),
            "meetings-actions": ScheduleConfig(
                recipe_path="observers/recipe-meetings-actions.yaml",
                frequency="daily",
                weekday_only=True,
                time_of_day="morning",
                description="Meetings actions daily in the morning on weekdays"
            ),
            "apps-preferences": ScheduleConfig(
                recipe_path="observers/recipe-apps-preferences.yaml",
                frequency="daily",
                weekday_only=True,
                description="Apps preferences analysis daily on weekdays"
            ),
            "start-fixing": ScheduleConfig(
                recipe_path="observers/recipe-start-fixing.yaml",
                frequency="daily",
                time_of_day="evening",
                description="Start fixing analysis daily in the evening"
            ),
            "background-tasks": ScheduleConfig(
                recipe_path="observers/recipe-background-tasks.yaml",
                frequency="15m",
                description="Background tasks every 15 minutes"
            ),
            "background-technical": ScheduleConfig(
                recipe_path="observers/recipe-background-technical.yaml",
                frequency="15m",
                description="Background technical analysis every 15 minutes"
            ),
            "follow-up-content": ScheduleConfig(
                recipe_path="observers/recipe-follow-up-content.yaml",
                frequency="daily",
                weekday_only=True,
                time_of_day="morning",
                description="Follow-up content daily in the morning on weekdays"
            ),
            "take-time-back": ScheduleConfig(
                recipe_path="observers/recipe-take-time-back.yaml",
                frequency="weekly",
                weekday_only=True,
                description="Take time back analysis weekly on weekdays"
            ),
            "adapt-recipes": ScheduleConfig(
                recipe_path="adapt-recipes.yaml",
                frequency="weekly",
                description="Recipe adaptation weekly"
            ),
            "actionable-suggestions": ScheduleConfig(
                recipe_path="observers/recipe-actionable-suggestions.yaml",
                frequency="daily",
                weekday_only=True,
                description="Generate actionable avatar suggestions daily on weekdays"
            ),
            "avatar-chatter": ScheduleConfig(
                recipe_path="observers/recipe-avatar-chatter.yaml",
                frequency="daily",
                weekday_only=True,
                description="Generate casual avatar chatter daily on weekdays"
            ),
            "avatar-suggestions": ScheduleConfig(
                recipe_path="observers/recipe-avatar-suggestions.yaml",
                frequency="daily",
                weekday_only=True,
                description="Generate contextual avatar suggestions daily on weekdays"
            ),
            "stress-wellness": ScheduleConfig(
                recipe_path="observers/recipe-stress-wellness.yaml",
                frequency="daily",
                weekday_only=True,
                description="Monitor stress levels and wellness daily on weekdays"
            ),
            
            # Local observer recipes
            "local-work-simple": ScheduleConfig(
                recipe_path="observers/local-observers/recipe-work-simple.yaml",
                frequency="20m",
                description="Local work analysis every 20 minutes"
            ),
            "local-focus-simple": ScheduleConfig(
                recipe_path="observers/local-observers/recipe-focus-simple.yaml",
                frequency="hourly",
                description="Local focus analysis every hour"
            ),
            "local-contributions-simple": ScheduleConfig(
                recipe_path="observers/local-observers/recipe-contributions-simple.yaml",
                frequency="daily",
                description="Local contributions analysis daily"
            ),
            "local-interactions-simple": ScheduleConfig(
                recipe_path="observers/local-observers/recipe-interactions-simple.yaml",
                frequency="daily",
                description="Local interactions analysis daily"
            ),
            "local-follow-up-content": ScheduleConfig(
                recipe_path="observers/local-observers/recipe-follow-up-content.yaml",
                frequency="hourly",
                description="Local follow-up content every hour"
            ),
        }
        
        # Note: system-setup recipe is run manually at startup, not scheduled
    
    def frequency_to_cron(self, frequency: str, weekday_only: bool = False, time_of_day: Optional[str] = None) -> str:
        """Convert custom frequency to cron expression (supports 6-field with seconds)"""
        
        # Handle time-of-day frequencies (always 5-field)
        if time_of_day:
            if time_of_day == "morning":
                base_cron = "0 9 * * *"  # 9 AM
            elif time_of_day == "afternoon": 
                base_cron = "0 14 * * *"  # 2 PM
            elif time_of_day == "evening":
                base_cron = "0 18 * * *"  # 6 PM
            else:
                raise ValueError(f"Unknown time_of_day: {time_of_day}")
        else:
            # Handle frequencies - use 6-field for seconds, 5-field for others
            if frequency.endswith('s'):
                # Seconds-based frequency - use 6-field cron: second minute hour day month weekday
                seconds = frequency[:-1]
                if frequency == "20s":
                    base_cron = "*/20 * * * * *"
                elif frequency == "30s":
                    base_cron = "*/30 * * * * *"
                else:
                    base_cron = f"*/{seconds} * * * * *"
            else:
                # Minute/hour/day based - use 5-field cron or shorthand
                if not weekday_only and not time_of_day:
                    if frequency == "hourly":
                        return "@hourly"
                    elif frequency == "daily":
                        return "@daily"
                    elif frequency == "weekly":
                        return "@weekly"
                
                # Regular frequencies (5-field)
                if frequency == "15m":
                    base_cron = "*/15 * * * *"
                elif frequency == "20m":
                    base_cron = "*/20 * * * *"
                elif frequency == "55m":
                    base_cron = "*/55 * * * *"
                elif frequency == "1m":
                    base_cron = "*/1 * * * *"
                elif frequency == "hourly":
                    base_cron = "0 * * * *"
                elif frequency == "4h":
                    base_cron = "0 */4 * * *"
                elif frequency == "daily":
                    base_cron = "0 9 * * *"  # Default to 9 AM for daily
                elif frequency == "weekly":
                    base_cron = "0 9 * * 1"  # Monday at 9 AM
                else:
                    raise ValueError(f"Unknown frequency: {frequency}")
        
        # Handle weekday-only schedules
        if weekday_only:
            parts = base_cron.split()
            if len(parts) == 5:  # 5-field cron
                parts[4] = "1-5"  # Monday through Friday
            elif len(parts) == 6:  # 6-field cron
                parts[5] = "1-5"  # Monday through Friday
            base_cron = " ".join(parts)
                
        return base_cron
    
    def get_existing_schedules(self) -> Dict[str, Dict]:
        """Get existing scheduled jobs from GooseSchedule"""
        try:
            result = subprocess.run(
                ["goose", "schedule", "list"],
                capture_output=True,
                text=True,
                check=True
            )
            
            schedules = {}
            if result.stdout.strip():
                # Parse the human-readable output
                lines = result.stdout.strip().split('\n')
                current_job = {}
                
                for line in lines:
                    line = line.strip()
                    if line.startswith("- ID: "):
                        # If we have a previous job, add it to schedules
                        if current_job.get("id"):
                            schedules[current_job["id"]] = current_job
                        # Start new job
                        current_job = {"id": line[6:]}  # Remove "- ID: " prefix
                    elif line.startswith("Status: "):
                        current_job["status"] = line[8:]
                    elif line.startswith("Cron: "):
                        current_job["cron"] = line[6:]
                    elif line.startswith("Recipe Source"):
                        current_job["recipe_source"] = line.split(": ", 1)[1] if ": " in line else ""
                    elif line.startswith("Last Run: "):
                        current_job["last_run"] = line[10:]
                
                # Don't forget the last job
                if current_job.get("id"):
                    schedules[current_job["id"]] = current_job
                    
            return schedules
        except subprocess.CalledProcessError as e:
            print(f"⚠️  Warning: Failed to get existing schedules: {e}")
            return {}
    
    def add_schedule(self, job_id: str, config: ScheduleConfig) -> bool:
        """Add a schedule to GooseSchedule"""
        if not config.enabled:
            print(f"Skipping disabled schedule: {job_id}")
            return False
            
        try:
            cron_expr = self.frequency_to_cron(
                config.frequency,
                config.weekday_only,
                config.time_of_day
            )
            
            # Convert to absolute path for Temporal
            recipe_path = Path(config.recipe_path).resolve()
            
            # Check if recipe file exists
            if not recipe_path.exists():
                print(f"Warning: Recipe file {recipe_path} does not exist, skipping {job_id}")
                return False
            
            print(f"Adding schedule {job_id}: {cron_expr} -> {recipe_path}")
            print(f"  Description: {config.description}")
            
            result = subprocess.run([
                "goose", "schedule", "add",
                "--id", job_id,
                "--cron", cron_expr,
                "--recipe-source", str(recipe_path)
            ], capture_output=True, text=True, check=True)
            
            print(f"✓ Successfully added schedule: {job_id}")
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"✗ Failed to add schedule {job_id}: {e}")
            if e.stderr:
                print(f"  Error: {e.stderr}")
            return False
        except Exception as e:
            print(f"✗ Error adding schedule {job_id}: {e}")
            return False
    
    def remove_schedule(self, job_id: str) -> bool:
        """Remove a schedule from GooseSchedule"""
        try:
            result = subprocess.run([
                "goose", "schedule", "remove", "--id", job_id
            ], capture_output=True, text=True, check=True)
            
            print(f"✓ Removed schedule: {job_id}")
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"✗ Failed to remove schedule {job_id}: {e}")
            if e.stderr:
                print(f"  Error details: {e.stderr.strip()}")
            if e.stdout:
                print(f"  Output: {e.stdout.strip()}")
            return False
        except Exception as e:
            print(f"✗ Unexpected error removing schedule {job_id}: {e}")
            return False
    
    def sync_schedules(self, dry_run: bool = False, remove_extra: bool = True) -> Tuple[int, int, int]:
        """Sync schedules with GooseSchedule - add missing, remove extras"""
        existing = self.get_existing_schedules()
        
        added = 0
        removed = 0
        skipped = 0
        
        print(f"Found {len(existing)} existing schedules")
        print(f"Managing {len(self.schedules)} configured schedules")
        print()
        
        # Add missing schedules
        for job_id, config in self.schedules.items():
            if job_id not in existing:
                print(f"Schedule {job_id} is missing")
                if not dry_run:
                    if self.add_schedule(job_id, config):
                        added += 1
                    else:
                        skipped += 1
                else:
                    print(f"  Would add: {job_id}")
                    added += 1
            else:
                print(f"✓ Schedule {job_id} already exists")
        
        print()
        
        # Remove extra schedules that aren't in our config (if enabled)
        if remove_extra:
            extra_schedules = [job_id for job_id in existing if job_id not in self.schedules]
            if extra_schedules:
                print(f"Found {len(extra_schedules)} extra schedules to clean up:")
                for job_id in extra_schedules:
                    print(f"  - {job_id}")
                print()
                
                for job_id in extra_schedules:
                    print(f"Removing extra schedule: {job_id}")
                    if not dry_run:
                        if self.remove_schedule(job_id):
                            removed += 1
                        else:
                            print(f"  ⚠️  Could not remove {job_id} (might be managed elsewhere)")
                    else:
                        print(f"  Would remove: {job_id}")
                        removed += 1
            else:
                print("✓ No extra schedules found")
        else:
            extra_count = len([job_id for job_id in existing if job_id not in self.schedules])
            if extra_count > 0:
                print(f"ℹ️  Found {extra_count} extra schedules (removal disabled)")
        
        return added, removed, skipped
    
    def list_schedules(self):
        """List all configured schedules with their cron expressions"""
        print("Configured Schedules:")
        print("=" * 80)
        
        for job_id, config in self.schedules.items():
            try:
                cron_expr = self.frequency_to_cron(
                    config.frequency,
                    config.weekday_only,
                    config.time_of_day
                )
                weekday_str = " (weekdays)" if config.weekday_only else ""
                time_str = f" ({config.time_of_day})" if config.time_of_day else ""
                enabled_str = "" if config.enabled else " [DISABLED]"
                
                print(f"{job_id:25} {cron_expr:15} {config.recipe_path}{enabled_str}")
                print(f"{'':25} {config.frequency}{weekday_str}{time_str}")
                print(f"{'':25} {config.description}")
                print()
            except Exception as e:
                print(f"{job_id:25} ERROR: {e}")
                print()
    
    def status(self):
        """Show status of all schedules"""
        existing = self.get_existing_schedules()
        
        print("Schedule Status:")
        print("=" * 80)
        
        enabled_count = 0
        for job_id, config in self.schedules.items():
            if config.enabled:
                enabled_count += 1
                status = "✓ ACTIVE" if job_id in existing else "✗ MISSING"
                print(f"{job_id:25} {status}")
            else:
                print(f"{job_id:25} ⏸️  DISABLED")
        
        print()
        print(f"Total schedules: {len(self.schedules)}")
        print(f"Enabled: {enabled_count}")
        print(f"Disabled: {len(self.schedules) - enabled_count}")
        
        # Show extra schedules
        extras = [job_id for job_id in existing if job_id not in self.schedules]
        if extras:
            print()
            print("Extra schedules (not in config):")
            for job_id in extras:
                print(f"  {job_id}")
    
    def add_schedule_to_recipe(self, recipe_file: Path, schedule_config: Dict):
        """Add schedule configuration to a recipe file"""
        if not HAS_YAML:
            print("❌ PyYAML is required to add schedule configuration to recipe files")
            print("   Install with: pip install PyYAML")
            print("   Or use: ./.use-hermit python3 schedule_manager.py")
            return False
            
        try:
            with open(recipe_file, 'r') as f:
                content = f.read()
            
            # Parse existing YAML
            data = yaml.safe_load(content) or {}
            
            # Add schedule section
            data['schedule'] = schedule_config
            
            # Write back to file
            with open(recipe_file, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, sort_keys=False)
                
            print(f"✓ Added schedule configuration to {recipe_file}")
            return True
            
        except Exception as e:
            print(f"✗ Failed to add schedule to {recipe_file}: {e}")
            return False

def main():
    """Main CLI interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Manage GooseSchedule jobs for goose-perception")
    parser.add_argument("action", choices=["sync", "list", "status", "dry-run", "add-schedule", "clean"], 
                       help="Action to perform")
    parser.add_argument("--force", action="store_true", 
                       help="Force sync even if it will remove schedules")
    parser.add_argument("--no-remove", action="store_true",
                       help="Don't remove extra schedules during sync")
    parser.add_argument("--recipe", help="Recipe file to add schedule to (for add-schedule)")
    parser.add_argument("--frequency", default="daily", help="Schedule frequency")
    parser.add_argument("--weekday-only", action="store_true", help="Only run on weekdays")
    parser.add_argument("--time-of-day", choices=["morning", "afternoon", "evening"], 
                       help="Specific time of day")
    
    args = parser.parse_args()
    
    manager = ScheduleManager()
    
    if args.action == "list":
        manager.list_schedules()
    elif args.action == "status":
        manager.status()
    elif args.action == "dry-run":
        print("DRY RUN - No changes will be made")
        print()
        added, removed, skipped = manager.sync_schedules(dry_run=True, remove_extra=not args.no_remove)
        print()
        print(f"Summary: Would add {added}, remove {removed}, skip {skipped}")
    elif args.action == "sync":
        added, removed, skipped = manager.sync_schedules(dry_run=False, remove_extra=not args.no_remove)
        print()
        print(f"Summary: Added {added}, removed {removed}, skipped {skipped}")
    elif args.action == "clean":
        # Special action to just clean up extra schedules
        print("🧹 Cleaning up extra schedules...")
        existing = manager.get_existing_schedules()
        extra_schedules = [job_id for job_id in existing if job_id not in manager.schedules]
        
        if not extra_schedules:
            print("✅ No extra schedules found")
            return
            
        print(f"Found {len(extra_schedules)} extra schedules:")
        for job_id in extra_schedules:
            print(f"  - {job_id}")
        
        if not args.force:
            response = input("\nRemove these schedules? (y/N): ")
            if response.lower() != 'y':
                print("Cancelled")
                return
        
        removed = 0
        for job_id in extra_schedules:
            if manager.remove_schedule(job_id):
                removed += 1
        
        print(f"\n✅ Cleaned up {removed}/{len(extra_schedules)} extra schedules")
    elif args.action == "add-schedule":
        if not args.recipe:
            print("Error: --recipe is required for add-schedule")
            sys.exit(1)
            
        recipe_file = Path(args.recipe)
        if not recipe_file.exists():
            print(f"Error: Recipe file {recipe_file} does not exist")
            sys.exit(1)
            
        schedule_config = {
            "frequency": args.frequency,
            "weekday_only": args.weekday_only,
            "enabled": True
        }
        
        if args.time_of_day:
            schedule_config["time_of_day"] = args.time_of_day
            
        success = manager.add_schedule_to_recipe(recipe_file, schedule_config)
        if success:
            print("Schedule configuration added successfully!")
        else:
            sys.exit(1)

if __name__ == "__main__":
    main() 