"""Which window is active right now — for the "Моё окно → уголок" rest mode.

Runs only while that mode is on, as a child of Hoshi. About once a second it
looks at the foreground top-level window and reports, only when something
changes (plus a slow heartbeat):
  {"hwnd": "...", "app": "chrome.exe", "state": "normal|maximized|fullscreen|minimized|system"}
or {"own": true} when Hoshi herself is active.

It never reads window titles, text, pixels, other windows or anything inside a
process; the program name is the executable file name only (window_identity.py).
No hooks. EOF on stdin (Hoshi closed) or "quit" ends the process.
"""
from __future__ import annotations

import ctypes as C
from ctypes import wintypes as W
import json
import sys
import threading
import time

from window_identity import process_name

SYSTEM_CLASSES = {'Progman', 'WorkerW', 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd',
                  '#32768', 'Windows.UI.Core.CoreWindow', 'ForegroundStaging', 'XamlExplorerHostIslandWindow'}


def classify(identity: dict) -> dict:
    """Pure: turn raw facts about the foreground window into a report."""
    if identity.get('own'):
        return {'own': True}
    if not identity.get('hwnd'):
        return {'hwnd': '0', 'app': '', 'state': 'none'}
    state = 'normal'
    if identity.get('class') in SYSTEM_CLASSES or identity.get('tool'):
        state = 'system'
    elif identity.get('iconic'):
        state = 'minimized'
    elif identity.get('fullscreen'):
        state = 'fullscreen'
    elif identity.get('zoomed'):
        state = 'maximized'
    return {'hwnd': str(identity['hwnd']), 'app': identity.get('app', ''), 'state': state}


class Focus:
    def __init__(self, owner_pid: int):
        self.owner = owner_pid
        u = C.WinDLL('user32', use_last_error=True)
        self.u = u
        u.GetForegroundWindow.restype = W.HWND
        u.GetAncestor.argtypes = [W.HWND, W.UINT]
        u.GetAncestor.restype = W.HWND
        u.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
        u.GetWindowThreadProcessId.restype = W.DWORD
        u.GetClassNameW.argtypes = [W.HWND, W.LPWSTR, C.c_int]
        u.GetClassNameW.restype = C.c_int
        u.IsIconic.argtypes = [W.HWND]
        u.IsIconic.restype = W.BOOL
        u.IsZoomed.argtypes = [W.HWND]
        u.IsZoomed.restype = W.BOOL
        u.GetWindowRect.argtypes = [W.HWND, C.POINTER(W.RECT)]
        u.GetWindowRect.restype = W.BOOL
        u.MonitorFromWindow.argtypes = [W.HWND, W.DWORD]
        u.MonitorFromWindow.restype = W.HANDLE
        u.GetMonitorInfoW.argtypes = [W.HANDLE, C.c_void_p]
        u.GetMonitorInfoW.restype = W.BOOL
        name = 'GetWindowLongPtrW' if C.sizeof(C.c_void_p) == 8 else 'GetWindowLongW'
        self.style = getattr(u, name)
        self.style.argtypes = [W.HWND, C.c_int]
        self.style.restype = C.c_ssize_t
        self._names: dict[int, str] = {}

    def identity(self) -> dict:
        u = self.u
        hwnd = u.GetForegroundWindow()
        if not hwnd:
            return {}
        hwnd = u.GetAncestor(hwnd, 2) or hwnd
        pid = W.DWORD()
        u.GetWindowThreadProcessId(hwnd, C.byref(pid))
        if pid.value == self.owner:
            return {'own': True}
        cls = C.create_unicode_buffer(256)
        u.GetClassNameW(hwnd, cls, 256)
        if pid.value not in self._names:
            self._names[pid.value] = process_name(pid.value)
        return {'hwnd': int(hwnd), 'app': self._names[pid.value], 'class': cls.value,
                'tool': bool(self.style(hwnd, -20) & 0x80), 'iconic': bool(u.IsIconic(hwnd)),
                'zoomed': bool(u.IsZoomed(hwnd)), 'fullscreen': self.fullscreen(hwnd)}

    def fullscreen(self, hwnd) -> bool:
        class Info(C.Structure):
            _fields_ = [('cbSize', W.DWORD), ('monitor', W.RECT), ('work', W.RECT), ('flags', W.DWORD)]
        rect, info = W.RECT(), Info()
        info.cbSize = C.sizeof(info)
        if not self.u.GetWindowRect(hwnd, C.byref(rect)) or not self.u.GetMonitorInfoW(self.u.MonitorFromWindow(hwnd, 2), C.byref(info)):
            return False
        m = info.monitor
        return rect.left <= m.left and rect.top <= m.top and rect.right >= m.right and rect.bottom >= m.bottom


def main() -> int:
    if sys.platform != 'win32' or len(sys.argv) != 2:
        print(json.dumps({'ok': False, 'reason': 'platform'}), flush=True)
        return 1
    focus = Focus(int(sys.argv[1]))
    stop = threading.Event()

    def watch_stdin() -> None:
        for line in sys.stdin:
            if line.strip() == 'quit':
                break
        stop.set()

    threading.Thread(target=watch_stdin, daemon=True).start()
    print(json.dumps({'ready': True}), flush=True)
    last, last_sent = None, 0.0
    while not stop.wait(1.0):
        try:
            report = classify(focus.identity())
        except OSError:
            continue
        now = time.monotonic()
        if report != last or now - last_sent > 30.0:
            print(json.dumps(report, separators=(',', ':')), flush=True)
            last, last_sent = report, now
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
