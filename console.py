#!/usr/bin/env python3
"""
Simple HTTP server for the Goose Perception console.
Serves the console/index.html file on port 9922.
"""

import http.server
import socketserver
import os
import sys

PORT = 9922
DIRECTORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "console")

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)
    
    def log_message(self, format, *args):
        print(f"{self.client_address[0]} - {format % args}")

def main():
    try:
        with socketserver.TCPServer(("", PORT), Handler) as httpd:
            print(f"Serving at http://localhost:{PORT}")
            print(f"Press Ctrl+C to stop the server")
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
        sys.exit(0)

if __name__ == "__main__":
    main()