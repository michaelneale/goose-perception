#!/usr/bin/env python3

import json
import sys
from Quartz import (
    CGWindowListCopyWindowInfo,
    kCGWindowListOptionOnScreenOnly,
    kCGNullWindowID
)

def get_window_info():
    """Get information about all visible windows"""
    try:
        # Get all on-screen windows
        window_list = CGWindowListCopyWindowInfo(
            kCGWindowListOptionOnScreenOnly, 
            kCGNullWindowID
        )
        
        windows = []
        for window in window_list:
            # Extract relevant information
            window_id = window.get('kCGWindowNumber')
            app_name = window.get('kCGWindowOwnerName', 'Unknown')
            window_name = window.get('kCGWindowName', '')
            bounds = window.get('kCGWindowBounds', {})
            layer = window.get('kCGWindowLayer', 0)
            
            # Skip windows that are too small or system windows
            if (bounds.get('Height', 0) < 50 or 
                bounds.get('Width', 0) < 50 or 
                layer < 0 or
                app_name in ['Window Server', 'WindowServer']):
                continue
                
            # Skip windows without names for most apps (except some system apps)
            if not window_name and app_name not in ['Finder', 'Desktop', 'Dock']:
                continue
                
            windows.append({
                'window_id': int(window_id),
                'app_name': str(app_name),
                'window_name': str(window_name),
                'bounds': {
                    'Height': float(bounds.get('Height', 0)),
                    'Width': float(bounds.get('Width', 0)),
                    'X': float(bounds.get('X', 0)),
                    'Y': float(bounds.get('Y', 0))
                },
                'layer': int(layer)
            })
        
        # Sort by layer (front to back) then by app name
        windows.sort(key=lambda x: (x['layer'], x['app_name']))
        
        return windows
        
    except Exception as e:
        print(f"Error getting window info: {e}", file=sys.stderr)
        return []

def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--json':
        # Output as JSON for programmatic use
        windows = get_window_info()
        print(json.dumps(windows, indent=2))
    else:
        # Output as human-readable format
        windows = get_window_info()
        for window in windows:
            print(f"ID: {window['window_id']} | App: {window['app_name']} | Window: {window['window_name']}")

if __name__ == "__main__":
    main() 