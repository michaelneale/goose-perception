#!/usr/bin/env python3
"""
recent_docs_apps.py - A script to show recently modified files and running applications on macOS
One-shot script that writes output to ~/.local/share/goose-perception/files-docs.txt
Can be called periodically from other scripts like continuous_screenshots.sh
"""

import os
import subprocess
import datetime
import sys
import time
from pathlib import Path

def run_command(command):
    """Run a shell command and return the output"""
    try:
        result = subprocess.run(command, shell=True, check=True, text=True, 
                               capture_output=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}")
        return ""

def get_recent_files(directory="~/", days=2, limit=200):
    """Get recently modified files in the specified directory"""
    home_dir = os.path.expanduser(directory)
    print(f"\n\033[1m🕒 Recently Modified Files in {directory} (last {days} days):\033[0m")
    
    # Use ls for top-level files/directories
    print("\n\033[1mTop-level items:\033[0m")
    cmd = f"ls -lt {home_dir} | head -n {limit+1}"
    result = run_command(cmd)
    print(result)
    
    # Use mdfind for more comprehensive search across subdirectories
    print(f"\n\033[1mRecently modified files (across subdirectories):\033[0m")
    cmd = f"mdfind -onlyin {home_dir} 'kMDItemFSContentChangeDate >= $time.today(-{days})' | grep -v '/Library/' | head -n {limit}"
    result = run_command(cmd)
    
    # Format the output to be more readable
    files = result.split('\n')
    for file in files:
        if file:
            try:
                rel_path = os.path.relpath(file, os.path.expanduser('~'))
                print(f"~/{'/' if not rel_path.startswith('/') else ''}{rel_path}")
            except:
                print(file)

def get_running_apps(limit=20):
    """Get currently running applications"""
    print(f"\n\033[1m📱 Currently Running Applications:\033[0m")
    
    # Use ps to get running applications
    cmd = "ps aux | grep -v grep | grep -i 'Applications.*\\.app' | awk '{print $11}' | sort | uniq | head -n " + str(limit)
    result = run_command(cmd)
    
    apps = {}
    for line in result.split('\n'):
        if '/Applications/' in line:
            app_name = line.split('/Applications/')[-1].split('.app')[0]
            if app_name and '.app' not in app_name and app_name not in apps:
                apps[app_name] = True
    
    for app in apps:
        print(f"- {app}")

def get_open_windows():
    """Get currently open windows using AppleScript"""
    print(f"\n\033[1m🪟 Currently Open Windows:\033[0m")
    
    # Use AppleScript to get window names
    script = """
    tell application "System Events"
        set windowList to {}
        set processNames to name of every process whose visible is true
        repeat with processName in processNames
            try
                set windowNames to name of every window of process processName
                repeat with windowName in windowNames
                    if windowName is not "" then
                        set end of windowList to windowName
                    end if
                end repeat
            end try
        end repeat
        return windowList
    end tell
    """
    
    cmd = f"osascript -e '{script}'"
    result = run_command(cmd)
    
    if result:
        windows = result.split(', ')
        for window in windows:
            print(f"- {window}")
    else:
        print("Unable to retrieve window information")

def generate_report(days=7, limit=20):
    """Generate the report and return it as a string"""
    # Create a string buffer to capture the output
    import io
    from contextlib import redirect_stdout
    
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        print("\033[1m===== Recent Files and Running Applications =====\033[0m")
        print(f"Generated on: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        
        # Get recent files
        get_recent_files("~/", days, limit)
        
        # Get running apps
        get_running_apps(limit)
        
        # Get open windows
        get_open_windows()
        
        print("\n\033[1m===== End of Report =====\033[0m")
    
    return buffer.getvalue()

def write_to_file(content, filepath):
    """Write content to the specified file"""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, 'w') as f:
        f.write(content)
    print(f"Report written to: {filepath}")

def main():
    """Main function to run the script"""
    # Parse command line arguments
    days = 7
    limit = 20
    run_continuous = False
    
    if len(sys.argv) > 1:
        if sys.argv[1] == "--continuous":
            run_continuous = True
        else:
            try:
                days = int(sys.argv[1])
            except ValueError:
                print(f"Invalid days value: {sys.argv[1]}. Using default: 7")
    
    if len(sys.argv) > 2:
        try:
            limit = int(sys.argv[2])
        except ValueError:
            print(f"Invalid limit value: {sys.argv[2]}. Using default: 20")
    
    # Output file path
    output_file = os.path.expanduser("~/.local/share/goose-perception/files-docs.txt")
    
    if run_continuous:
        # Run continuously every 30 minutes
        print(f"Running in continuous mode. Writing to {output_file} every 30 minutes.")
        print(f"Press Ctrl+C to stop.")
        
        try:
            while True:
                report = generate_report(days, limit)
                write_to_file(report, output_file)
                print(f"Report generated at {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
                # Sleep for 30 minutes (1800 seconds)
                time.sleep(1800)
        except KeyboardInterrupt:
            print("\nScript terminated by user.")
    else:
        # Default: Run once and exit
        report = generate_report(days, limit)
        write_to_file(report, output_file)
        # Only print a short confirmation, not the full report
        print(f"Report generated at {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Report written to: {output_file}")
    
    if run_continuous:
        print(f"Usage: {sys.argv[0]} [days] [limit] [--continuous]")
        print(f"  days: Number of days to look back (default: 7)")
        print(f"  limit: Maximum number of items to show (default: 20)")
        print(f"  --continuous: Run continuously every 30 minutes (default: run once and exit)")

if __name__ == "__main__":
    main()