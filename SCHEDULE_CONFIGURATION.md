# Schedule Configuration for GooseSchedule

This document explains how to configure schedules for your goose-perception recipes using GooseSchedule.

## Overview

The schedule manager manages all scheduled recipes through a centralized configuration in `schedule_manager.py`. This provides:
- **Single source of truth**: All schedules are defined in one place
- **Consistent configuration**: Unified schedule format across all recipes
- **Easy management**: Simple commands to sync and manage schedules
- **Recipe-based approach**: Uses goose recipes instead of shell scripts

## System Recipes

The system includes special recipes for core functionality:

### Screenshot Capture
- **Recipe**: `observers/recipe-screenshot-capture.yaml`
- **Schedule**: Every 20 seconds (`20s`)
- **Purpose**: Captures screenshots for work analysis (original frequency restored)

### System Setup  
- **Recipe**: `observers/recipe-system-setup.yaml`
- **Schedule**: Run once at startup (not scheduled)
- **Purpose**: Creates necessary directory structure

## Schedule Configuration

All schedules are configured in the `ScheduleManager` class in `schedule_manager.py`. Each schedule is defined with:

```python
"schedule-name": ScheduleConfig(
    recipe_path="path/to/recipe.yaml",
    frequency="20m",           # How often to run
    weekday_only=True,         # Only run on weekdays (Mon-Fri)
    time_of_day="morning",     # Specific time (morning/afternoon/evening)
    description="Description of what this does",
    enabled=True               # Whether this schedule is active
),
```

### Frequency Options
- `"20s"`, `"30s"` - Run every N seconds (uses 6-field cron)
- `"1m"`, `"15m"`, `"20m"`, `"55m"` - Run every N minutes
- `"hourly"` - Run every hour
- `"4h"` - Run every 4 hours
- `"daily"` - Run once per day
- `"weekly"` - Run once per week

**Note**: GooseSchedule supports 6-field cron expressions with seconds for sub-minute scheduling!

### Time of Day Options
- `"morning"` - Run at 9 AM
- `"afternoon"` - Run at 2 PM  
- `"evening"` - Run at 6 PM

## Managing Schedules

### Sync all schedules
```bash
just sync-schedules
```

### List configured schedules
```bash
just schedule-list
```

### Check schedule status
```bash
just schedule-status
```

### Dry run (see what would change)
```bash
just schedule-dry-run
```

### Get help with schedule commands
```bash
just schedule-help
```

## Adding New Recipes

To add a new scheduled recipe:

1. **Create the recipe file** in `observers/` directory
2. **Add schedule configuration** to `schedule_manager.py`:

```python
"my-new-recipe": ScheduleConfig(
    recipe_path="observers/recipe-my-new.yaml",
    frequency="daily",
    weekday_only=True,
    description="Description of what this recipe does"
),
```

3. **Sync schedules** to activate:
```bash
just sync-schedules
```

## Example Recipe Structure

```yaml
version: 1.0.0
title: My Custom Recipe
author:
  contact: developer
description: What this recipe accomplishes
extensions:
- type: builtin
  name: developer
  display_name: Developer
  timeout: 300
  bundled: true
prompt: |
  Instructions for what this recipe should do.
  
  This recipe will be run automatically according to its schedule.
  Keep prompts focused and actionable.
```

## Current Configured Schedules

The system currently includes schedules for:

- **screenshot-capture**: Screenshots every minute
- **work**: Work analysis every 20 minutes (weekdays)
- **focus**: Focus analysis every 55 minutes (weekdays)
- **contributions**: Contribution tracking hourly (weekdays)
- **chrome-history**: Browser analysis every 4 hours (weekdays)
- **background-tasks**: Background processing every 15 minutes
- **meetings-actions**: Meeting follow-ups daily morning (weekdays)
- **adapt-recipes**: Recipe optimization weekly
- Plus many more observation and analysis recipes

## Troubleshooting

### Schedule not appearing
1. Check that the recipe file exists and is valid YAML
2. Verify the schedule configuration in `schedule_manager.py`
3. Run `just schedule-dry-run` to see what would be added
4. Run `just sync-schedules` to apply changes

### Schedule not running
1. Check GooseSchedule status: `just status`
2. Ensure Temporal services are running
3. Check for recipe errors by running manually: `goose run --recipe path/to/recipe.yaml`

### Disabling a schedule
Set `enabled=False` in the schedule configuration, then run `just sync-schedules`.

## Migration Benefits

This approach provides several advantages over shell scripts:

- ✅ **Goose-native**: Uses goose recipes instead of external scripts
- ✅ **Better error handling**: Goose provides better error reporting
- ✅ **Consistent interface**: All tasks use the same goose recipe format
- ✅ **Easier debugging**: Can run recipes manually for testing
- ✅ **No shell dependencies**: Pure goose/Python implementation
- ✅ **Integrated logging**: Goose handles logging and output consistently 