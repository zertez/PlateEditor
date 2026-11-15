#!/usr/bin/env python3
"""Double-click launcher: keep a stable origin so the local library persists."""
from pathlib import Path
from threading import Thread
from urllib.request import urlopen
from http.server import ThreadingHTTPServer
import webbrowser
from serve import Handler

ROOT=Path(__file__).resolve().parent.parent
URL='http://127.0.0.1:8765/'

def main():
    try:
        with urlopen(URL+'index.html', timeout=1) as response:
            existing=response.read().decode('utf-8')
        if 'PlateEditor · Plate Setup' in existing:
            webbrowser.open(URL)
            print('Plate Setup is already running. Opened your plate library.')
            return
        raise RuntimeError('Port 8765 is being used by another app. Close that app and try again.')
    except OSError:
        pass
    def handler(*args, **kwargs): return Handler(*args,directory=str(ROOT),**kwargs)
    server=ThreadingHTTPServer(('127.0.0.1',8765),handler)
    Thread(target=lambda:webbrowser.open(URL),daemon=True).start()
    print('Plate Setup is open in your browser. Keep this window open while using it.')
    print('Your plates save in this browser automatically. Press Control-C here to stop.')
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()

if __name__=='__main__': main()
