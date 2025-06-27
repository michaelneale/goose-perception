#!/usr/bin/env python3
"""
Schedule Manager for Goose Perception
Manages scheduled jobs using GooseSchedule instead of hard-coded cron logic
"""

import subprocess
import json
import sys
import os
from typing import Dict, List, Optional, Tuple
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

class ScheduleManager:
    """Manages GooseSchedule jobs for goose-perception recipes"""
    
    def __init__(self):
        self.observers_dir = Path("observers")
        self.local_observers_dir = Path("observers/local-observers")
        
        # Define all scheduled recipes with their configurations
        self.schedules = {
            # Main observation recipes
            "work-summary": ScheduleConfig(
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
            "projects-morning": ScheduleConfig(
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
            "important-attention": ScheduleConfig(
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
            "meetings-morning": ScheduleConfig(
                recipe_path="observers/recipe-meetings-actions.yaml",
                frequency="daily",
                weekday_only=True,
                time_of_day="morning",
                description="Meetings actions daily in the morning on weekdays"
            ),
            "meetings-evening": ScheduleConfig(
                recipe_path="observers/recipe-meetings-actions.yaml",
                frequency="daily",
                weekday_only=True,
                time_of_day="evening", 
                description="Meetings actions daily in the evening on weekdays"
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
            
            # Local observer recipes
            "local-work": ScheduleConfig(
                recipe_path="observers/local-observers/recipe-work-simple.yaml",
                frequency="20m",
                description="Local work analysis every 20 minutes"
            ),
            "local-focus": ScheduleConfig(
                recipe_path="observers/local-observers/recipe-focus-simple.yaml",
                frequency="hourly",
                description="Local focus analysis every hour"
            ),
            "local-contributions": ScheduleConfig(
                recipe_path="observers/local-observers/recipe-contributions-simple.yaml",
                frequency="daily",
                description="Local contributions analysis daily"
            ),
            "local-interactions": ScheduleConfig(
                recipe_path="observers/local-observers/recipe-interactions-simple.yaml",
                frequency="daily",
                description="Local interactions analysis daily"
            ),
            "local-follow-up": ScheduleConfig(
                recipe_path="observers/local-observers/recipe-follow-up-content.yaml",
                frequency="hourly",
                description="Local follow-up content every hour"
            ),
        }
    
    def frequency_to_cron(self, frequency: str, weekday_only: bool = False, time_of_day: Optional[str] = None) -> str:
        """Convert custom frequency to cron expression"""
        
        # For simple frequencies without weekday restrictions, use shorthand when possible
        if not weekday_only and not time_of_day:
            if frequency == "hourly":
                return "@hourly"
            elif frequency == "daily":
                return "@daily"
            elif frequency == "weekly":
                return "@weekly"
        
        # Handle time-of-day frequencies
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
            # Handle regular frequencies
            if frequency == "15m":
                base_cron = "*/15 * * * *"
            elif frequency == "20m":
                base_cron = "*/20 * * * *"
            elif frequency == "55m":
                base_cron = "*/55 * * * *"
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
            if len(parts) == 5:
                parts[4] = "1-5"  # Monday through Friday
                base_cron = " ".join(parts)
                
        return base_cron
    
    def get_existing_schedules(self) -> Dict[str, Dict]:
        """Get existing scheduled jobs from GooseSchedule"""
        try:
            result = subprocess.run(
                ["goose", "schedule", "list", "--format", "json"],
                capture_output=True,
                text=True,
                check=True
            )
            if result.stdout.strip():
                return {job["id"]: job for job in json.loads(result.stdout)}
            return {}
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            return {}
    
    def add_schedule(self, job_id: str, config: ScheduleConfig) -> bool:
        """Add a schedule to GooseSchedule"""
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
            subprocess.run([
                "goose", "schedule", "remove", job_id
            ], capture_output=True, text=True, check=True)
            
            print(f"✓ Removed schedule: {job_id}")
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"✗ Failed to remove schedule {job_id}: {e}")
            return False
    
    def sync_schedules(self, dry_run: bool = False) -> Tuple[int, int, int]:
        """Sync schedules with GooseSchedule - add missing, remove extras"""
        existing = self.get_existing_schedules()
        
        added = 0
        removed = 0
        skipped = 0
        
        print(f"Found {len(existing)} existing schedules")
        print(f"Managing {len(self.schedules)} defined schedules")
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
                print(f"Schedule {job_id} already exists")
        
        print()
        
        # Remove extra schedules that aren't in our config
        for job_id in existing:
            if job_id not in self.schedules:
                print(f"Extra schedule found: {job_id}")
                if not dry_run:
                    if self.remove_schedule(job_id):
                        removed += 1
                else:
                    print(f"  Would remove: {job_id}")
                    removed += 1
        
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
                
                print(f"{job_id:25} {cron_expr:15} {config.recipe_path}")
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
        
        for job_id, config in self.schedules.items():
            status = "✓ ACTIVE" if job_id in existing else "✗ MISSING"
            print(f"{job_id:25} {status}")
        
        print()
        
        # Show extra schedules
        extras = [job_id for job_id in existing if job_id not in self.schedules]
        if extras:
            print("Extra schedules (not in config):")
            for job_id in extras:
                print(f"  {job_id}")

def main():
    """Main CLI interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Manage GooseSchedule jobs for goose-perception")
    parser.add_argument("action", choices=["sync", "list", "status", "dry-run"], 
                       help="Action to perform")
    parser.add_argument("--force", action="store_true", 
                       help="Force sync even if it will remove schedules")
    
    args = parser.parse_args()
    
    manager = ScheduleManager()
    
    if args.action == "list":
        manager.list_schedules()
    elif args.action == "status":
        manager.status()
    elif args.action == "dry-run":
        print("DRY RUN - No changes will be made")
        print()
        added, removed, skipped = manager.sync_schedules(dry_run=True)
        print()
        print(f"Summary: Would add {added}, remove {removed}, skip {skipped}")
    elif args.action == "sync":
        added, removed, skipped = manager.sync_schedules(dry_run=False)
        print()
        print(f"Summary: Added {added}, removed {removed}, skipped {skipped}")

if __name__ == "__main__":
    main() 