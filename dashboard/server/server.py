#!/usr/bin/env python3
import http.server
import socketserver
import os
import sys

PORT = 3000
FRONTEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=FRONTEND_DIR, **kwargs)

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        super().end_headers()

def main():
    os.chdir(FRONTEND_DIR)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"[mcp-context-console] Serving console at http://localhost:{PORT}")
        print(f"[mcp-context-console] Root directory: {FRONTEND_DIR}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[mcp-context-console] Server stopped.")

if __name__ == "__main__":
    main()
