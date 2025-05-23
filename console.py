#!/usr/bin/env python3
"""
Simple HTTP server for the Goose Perception console.
Serves the console/index.html file on port 9922 and provides API endpoints
for reading files.
"""

import http.server
import socketserver
import os
import sys
import json
from pathlib import Path

PORT = 9922
DIRECTORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "console")
DATA_DIR = os.path.expanduser("~/.local/share/goose-perception")

# Ensure data directory exists
Path(DATA_DIR).mkdir(parents=True, exist_ok=True)

class ConsoleHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)
    
    def log_message(self, format, *args):
        print(f"{self.client_address[0]} - {format % args}")
    
    def do_GET(self):
        # Handle API endpoints
        if self.path == '/api/content':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            
            content = {
                'work': read_file(os.path.join(DATA_DIR, 'LATEST_WORK.md'), 'N/A'),
                'collaboration': read_file(os.path.join(DATA_DIR, 'INTERACTIONS.md'), 'N/A'),
                'contributions': read_file(os.path.join(DATA_DIR, 'CONTRIBUTIONS.md'), 'N/A'),
                'lastResult': read_file(os.path.join(DATA_DIR, '.last-result'), 'No recent task results.'),
                'currentActivity': read_file(os.path.join(DATA_DIR, '.current'), 'Ready for new tasks')
            }
            
            self.wfile.write(json.dumps(content).encode())
            return
        
        # Default: serve static files
        return super().do_GET()


def read_file(file_path, default=''):
    """Read a file if it exists, otherwise return default value."""
    try:
        with open(file_path, 'r') as f:
            return f.read()
    except (FileNotFoundError, IOError):
        return default


def main():
    try:
        with socketserver.TCPServer(("", PORT), ConsoleHandler) as httpd:
            print(f"Serving at http://localhost:{PORT}")
            print(f"Data directory: {DATA_DIR}")
            print(f"Press Ctrl+C to stop the server")
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
        sys.exit(0)


if __name__ == "__main__":
    main()