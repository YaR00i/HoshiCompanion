"""Native regression: local browser page content must yield a candidate line."""
from __future__ import annotations

import ctypes as C
from ctypes import wintypes as W
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from window_surfaces import inspect

CHROME = Path(r'C:\Program Files\Google\Chrome\Application\chrome.exe')
PAGE = '''<!doctype html><html><head><meta charset="utf-8"><title>Hoshi fixture</title>
<style>body{margin:0;font:20px Arial}header{height:90px;background:#d8cce9}
main{padding:32px}button{display:block;width:340px;height:48px;margin:22px;background:#f3e9b2}</style></head>
<body><header></header><main><button>Content control</button></main></body></html>'''


def window_for_pid(pid: int) -> int:
    user = C.WinDLL('user32')
    user.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
    user.GetWindowThreadProcessId.restype = W.DWORD
    user.IsWindowVisible.argtypes = [W.HWND]
    user.IsWindowVisible.restype = W.BOOL
    found = []
    callback_type = C.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)

    @callback_type
    def callback(hwnd, _data):
        owner = W.DWORD()
        user.GetWindowThreadProcessId(hwnd, C.byref(owner))
        if owner.value == pid and user.IsWindowVisible(hwnd):
            found.append(int(hwnd))
        return True

    user.EnumWindows.argtypes = [callback_type, W.LPARAM]
    user.EnumWindows(callback, 0)
    return found[0] if found else 0


def main() -> None:
    if sys.platform != 'win32' or not CHROME.is_file():
        print('SKIP: isolated Chrome fixture unavailable')
        return
    with tempfile.TemporaryDirectory(prefix='hoshi_surface_', dir=ROOT / '.workspace') as folder:
        page = Path(folder) / 'fixture.html'
        page.write_text(PAGE, encoding='utf-8')
        args = [str(CHROME), '--user-data-dir=' + str(Path(folder) / 'profile'),
                '--no-first-run', '--no-default-browser-check', '--disable-sync',
                '--force-renderer-accessibility',
                '--disable-backgrounding-occluded-windows',
                '--disable-renderer-backgrounding',
                '--window-size=900,680', page.as_uri()]
        proc = subprocess.Popen(args, stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            hwnd = 0
            for _ in range(50):
                hwnd = window_for_pid(proc.pid)
                if hwnd:
                    break
                time.sleep(.1)
            assert hwnd, 'fixture window did not appear'

            # A top-chrome-only scan is the original browser failure.
            structure = None
            for _ in range(15):
                structure = inspect(hwnd)
                if any(item['kind'] == 'Button' and 250 <= item['y'] <= 400
                       for item in structure['candidates']):
                    break
                time.sleep(.2)
            assert structure is not None and any(
                item['kind'] == 'Button' and 250 <= item['y'] <= 400
                for item in structure['candidates']), structure

            # Capture only the fixture HWND. The worker returns coordinates, no frame.
            child = subprocess.run([sys.executable, str(ROOT / 'tools' / 'window_visual_surfaces.py'),
                                    str(hwnd)], stdin=subprocess.DEVNULL,
                                   capture_output=True, timeout=6,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
            visual = json.loads(child.stdout)
            if visual.get('reason') == 'visual_dependency':
                print('HOSHI_WINDOW_SURFACES_BROWSER_RESULT checks=1 failures=0 visual=skipped_dependency')
                return
            assert visual['ok'], visual
            assert any(item['kind'] == 'Visual' and 250 <= item['y'] <= 400
                       for item in visual['candidates']), visual
            print('HOSHI_WINDOW_SURFACES_BROWSER_RESULT checks=2 failures=0')
        finally:
            proc.terminate()
            proc.wait(timeout=5)


if __name__ == '__main__':
    main()
