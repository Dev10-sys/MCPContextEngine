#!/usr/bin/env python3
"""
MCP Context Console — Real-Time Developer Observability Server
Provides static asset serving for the dashboard frontend and a REST API
for ingesting and retrieving live telemetry emitted by MCPContextEngine runs.
"""

import http.server
import socketserver
import os
import sys
import json
from datetime import datetime

PORT = 3000
SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
FRONTEND_DIR = os.path.abspath(os.path.join(SERVER_DIR, "..", "frontend"))
DATA_DIR = os.path.join(SERVER_DIR, "data")

os.makedirs(DATA_DIR, exist_ok=True)
LATEST_FILE = os.path.join(DATA_DIR, "telemetry.json")
HISTORY_FILE = os.path.join(DATA_DIR, "telemetry_history.json")

# In-memory telemetry cache
telemetry_history = []
latest_telemetry = None

# Load cached data if available
if os.path.exists(LATEST_FILE):
    try:
        with open(LATEST_FILE, "r", encoding="utf-8") as f:
            latest_telemetry = json.load(f)
    except Exception:
        latest_telemetry = None

if os.path.exists(HISTORY_FILE):
    try:
        with open(HISTORY_FILE, "r", encoding="utf-8") as f:
            telemetry_history = json.load(f)
    except Exception:
        telemetry_history = []

class TelemetryHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=FRONTEND_DIR, **kwargs)

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        global latest_telemetry, telemetry_history
        if self.path == '/api/telemetry' or self.path.startswith('/api/telemetry?'):
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            payload = latest_telemetry if latest_telemetry else {}
            self.wfile.write(json.dumps(payload, indent=2).encode('utf-8'))
            return
        elif self.path == '/api/history':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(telemetry_history, indent=2).encode('utf-8'))
            return
        elif self.path == '/api/status':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            status = {
                "status": "online",
                "service": "mcp-context-console",
                "runs_recorded": len(telemetry_history),
                "has_latest": latest_telemetry is not None
            }
            self.wfile.write(json.dumps(status).encode('utf-8'))
            return
        
        # Fallback to serving static frontend files
        return super().do_GET()

    def do_POST(self):
        global latest_telemetry, telemetry_history
        if self.path == '/api/telemetry':
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length > 0:
                raw_body = self.rfile.read(content_length)
                try:
                    event = json.loads(raw_body.decode('utf-8'))
                    event["server_received_at"] = datetime.utcnow().isoformat() + "Z"
                    latest_telemetry = event
                    telemetry_history.append(event)
                    # Keep max 50 recent runs
                    if len(telemetry_history) > 50:
                        telemetry_history.pop(0)

                    # Persist to disk
                    with open(LATEST_FILE, "w", encoding="utf-8") as f:
                        json.dump(latest_telemetry, f, indent=2)
                    with open(HISTORY_FILE, "w", encoding="utf-8") as f:
                        json.dump(telemetry_history, f, indent=2)

                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    resp = {"status": "ok", "runId": event.get("runId", "unknown")}
                    self.wfile.write(json.dumps(resp).encode('utf-8'))
                    print(f"[mcp-context-console] Received telemetry run: {event.get('runId', 'N/A')} ({event.get('userQuery', '')[:40]}...)")
                    return
                except Exception as e:
                    self.send_response(400)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": str(e)}).encode('utf-8'))
                    return

        self.send_response(404)
        self.end_headers()

def main():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), TelemetryHandler) as httpd:
        print(f"[mcp-context-console] Serving console at http://localhost:{PORT}")
        print(f"[mcp-context-console] Telemetry API ready at http://localhost:{PORT}/api/telemetry")
        print(f"[mcp-context-console] Static frontend at: {FRONTEND_DIR}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[mcp-context-console] Server stopped.")

if __name__ == "__main__":
    main()
