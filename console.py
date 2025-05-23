#!/usr/bin/env python3
"""
Simple HTTP server for the Goose Perception console.
Serves the console/index.html file on port 9922 and provides API endpoints
for reading and writing files.
"""

import http.server
import socketserver
import os
import sys
import json
import urllib.parse
from pathlib import Path
import time

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
    
    def do_POST(self):
        if self.path == '/api/save':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length).decode('utf-8')
            data = json.loads(post_data)
            
            # Save the content to the appropriate file
            if 'field' in data and 'content' in data:
                file_path = None
                if data['field'] == 'work':
                    file_path = os.path.join(DATA_DIR, 'LATEST_WORK.md')
                elif data['field'] == 'collaboration':
                    file_path = os.path.join(DATA_DIR, 'INTERACTIONS.md')
                elif data['field'] == 'contributions':
                    file_path = os.path.join(DATA_DIR, 'CONTRIBUTIONS.md')
                
                if file_path:
                    with open(file_path, 'w') as f:
                        f.write(data['content'])
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'success'}).encode())
            return
        
        elif self.path == '/api/command':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length).decode('utf-8')
            data = json.loads(post_data)
            
            if 'command' in data:
                print(f"Command received: {data['command']}")
                
                # Save the command to .last-result for demonstration
                with open(os.path.join(DATA_DIR, '.last-result'), 'w') as f:
                    f.write(f"Command received: {data['command']}\nTimestamp: {time.strftime('%Y-%m-%d %H:%M:%S')}")
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'success'}).encode())
            return
        
        self.send_response(404)
        self.end_headers()


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