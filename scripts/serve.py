#!/usr/bin/env python3
"""Serve only the checkout's application files on localhost, without a database."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit
import argparse

class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parts = Path(unquote(urlsplit(self.path).path)).parts
        if any(part.startswith('.') for part in parts if part not in ('/', '.')) or any(part in ('tests', 'node_modules') for part in parts):
            self.send_error(404)
            return
        super().do_GET()
    def list_directory(self, path):
        self.send_error(404)
        return None
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8765)
    args=parser.parse_args()
    root=Path(__file__).resolve().parent.parent
    def handler(*a, **kw): return Handler(*a, directory=str(root), **kw)
    print(f'Plate Setup: http://127.0.0.1:{args.port}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), handler).serve_forever()
