#!/usr/bin/env python3
"""
Script to find and filter Notes app entries mentioning 'goose' 
that were modified in the last 24 hours.
"""

import subprocess
import json
from datetime import datetime, timedelta
import re
import os


def run_osascript(script):
    """Run an AppleScript command and return the output."""
    try:
        result = subprocess.run(
            ['osascript', '-e', script],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running AppleScript: {e}")
        print(f"Error output: {e.stderr}")
        return None


def get_note_names():
    """Get the names of notes 1 through 10."""
    script = 'tell application "Notes" to get name of notes 1 thru 10'
    result = run_osascript(script)
    
    if result:
        # Parse the comma-separated list returned by AppleScript
        # Remove any surrounding quotes and split by comma
        names = []
        # AppleScript returns items separated by ", "
        raw_names = result.split(', ')
        for name in raw_names:
            # Clean up any quotes
            clean_name = name.strip()
            if clean_name:
                names.append(clean_name)
        return names
    return []


def get_note_modification_date(note_index):
    """Get the modification date of a specific note by index."""
    script = f'tell application "Notes" to get modification date of note {note_index}'
    result = run_osascript(script)
    
    if result:
        # Parse the date string returned by AppleScript
        # Format is like "date Saturday, 16 August 2025 at 9:04:47 pm"
        try:
            # Clean up the string
            date_str = result
            
            # Remove "date " prefix if present
            if date_str.startswith('date '):
                date_str = date_str[5:]
            
            # Remove the day name (e.g., "Saturday, ")
            date_str = re.sub(r'^[A-Za-z]+, ', '', date_str)
            
            # Replace "at" with space and handle non-breaking spaces
            date_str = date_str.replace(' at ', ' ')
            date_str = date_str.replace('\u202f', ' ')  # Replace non-breaking space
            date_str = date_str.replace('\xa0', ' ')    # Replace another type of non-breaking space
            
            # Normalize multiple spaces to single space
            date_str = ' '.join(date_str.split())
            
            # Store original for debugging
            original_date_str = date_str
            
            # Parse the date - try different formats
            # Format could be "16 August 2025 9:04:47 pm" or "August 28, 2025 7:53:17 AM"
            try:
                # Try format: "August 28, 2025 7:53:17 AM" (most common from error log)
                date_obj = datetime.strptime(date_str, '%B %d, %Y %I:%M:%S %p')
            except ValueError:
                try:
                    # Try format: "16 August 2025 9:04:47 pm"
                    date_obj = datetime.strptime(date_str, '%d %B %Y %I:%M:%S %p')
                except ValueError:
                    # If both fail, try without comma
                    date_obj = datetime.strptime(date_str, '%B %d %Y %I:%M:%S %p')
            return date_obj
        except ValueError as e:
            print(f"Error parsing date '{result}': {e}")
            print(f"Cleaned string: '{original_date_str}'")
            return None
    return None


def get_note_content(note_index):
    """Get the content of a specific note by index."""
    script = f'tell application "Notes" to get plaintext of note {note_index}'
    result = run_osascript(script)
    return result if result else ""


def filter_notes_with_goose():
    """Main function to filter notes with 'goose' in title, modified in last 24 hours, not ending with '-- goose'."""
    # Get note names
    note_names = get_note_names()
    
    if not note_names:
        return []
    
    # Calculate 24 hours ago from now
    twenty_four_hours_ago = datetime.now() - timedelta(hours=24)
    
    # Track notes that match our criteria
    matching_notes = []
    
    # Check each note
    for i, name in enumerate(note_names, 1):
        # Only check notes with "goose" in the title/name (case-insensitive)
        if 'goose' in name.lower():
            # Get modification date
            mod_date = get_note_modification_date(i)
            
            if mod_date and mod_date > twenty_four_hours_ago:
                # Get content to check if it ends with "-- goose"
                content = get_note_content(i)
                content_stripped = content.strip() if content else ""
                
                if not content_stripped.endswith("-- goose"):
                    # This note matches all criteria
                    matching_notes.append({
                        'index': i,
                        'name': name,
                        'modified': mod_date,
                        'content': content
                    })
    
    return matching_notes


def write_notes_todo(matching_notes):
    """Write matching notes to the notes-todo.txt file."""
    # Define the path for the notes-todo file
    data_dir = os.path.expanduser("~/.local/share/goose-perception")
    os.makedirs(data_dir, exist_ok=True)
    todo_file = os.path.join(data_dir, "notes-todo.txt")
    
    # Write the notes to the file
    with open(todo_file, 'w') as f:
        if matching_notes:
            f.write(f"# Notes requiring attention\n")
            f.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"# Found {len(matching_notes)} note(s) with 'goose' in title that need processing\n\n")
            
            for note in matching_notes:
                f.write(f"## Note: {note['name']}\n")
                f.write(f"Modified: {note['modified']}\n")
                f.write(f"Index: {note['index']}\n\n")
                f.write(f"Content:\n")
                f.write(f"{note['content']}\n")
                f.write(f"\n{'='*60}\n\n")
        else:
            f.write(f"# No notes requiring attention\n")
            f.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"# No notes with 'goose' in title need processing at this time.\n")
    
    return todo_file


if __name__ == "__main__":
    try:
        # Import os if not already imported
        import os
        
        results = filter_notes_with_goose()
        
        # Write results to the notes-todo.txt file
        todo_file = write_notes_todo(results)
        
        # Print minimal output for logging
        if results:
            print(f"Found {len(results)} note(s) requiring attention - written to {todo_file}")
        else:
            print(f"No notes requiring attention - status written to {todo_file}")
                
    except Exception as e:
        print(f"An error occurred: {e}")