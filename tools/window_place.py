"""Put the window of an app launched from the phone on the chosen screen.

"Мои действия": each action may say on which screen and how its window should
appear — centred, left half, right half or maximized (user decision
2026-09-27: Hoshi may move the window that appeared because of the user's own
press, once, right after the launch).

    python tools/window_place.py monitors
        -> {"ok": true, "monitors": [{"index": 1, "primary": true, "width", "height", "x", "y"}]}
           (x, y — where the screen is in the Windows layout, for the screen map)
    python tools/window_place.py list <owner_pid>
        -> {"ok": true, "windows": [{"hwnd", "app", "monitor", "state"}]} — open app
           windows (user decision 2026-09-27: move already open windows too)
    python tools/window_place.py move <owner_pid> <hwnd> <monitor> <mode> [front]
        Places that one window (it must still be an ordinary visible app window);
        "front" also brings it over the other windows.
    python tools/window_place.py front <owner_pid> <hwnd>
        Only brings that window over the other windows (restores it if minimized).
    python tools/window_place.py place <owner_pid> <monitor> <mode> <exe|->
        Takes a snapshot of the windows that exist now, prints {"ready": true}
        (Hoshi launches the app only after that), then waits up to 10 s for a
        NEW top-level window (preferably of <exe>) and places it. If none
        appears but <exe> was given (single-instance apps show their old
        window), the foreground window of that program is placed instead.
        -> {"ok": true, "app": "mpc-be64.exe"} or {"ok": false, "error": "..."}

Like the other window helpers it never reads titles, text or pixels: only
geometry, visibility and the executable FILE NAME (window_identity.py).
"""
from __future__ import annotations

import ctypes as C
from ctypes import wintypes as W
import json
import sys
import time

from window_identity import process_name

MODES = ('center', 'left', 'right', 'max')
WAIT_NEW = 10.0
WAIT_BEFORE_FALLBACK = 4.0
SYSTEM_CLASSES = {'Progman', 'WorkerW', 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd', '#32768',
                  'Windows.UI.Core.CoreWindow', 'ForegroundStaging', 'XamlExplorerHostIslandWindow',
                  'NotifyIconOverflowWindow', 'TopLevelWindowForOverflowXamlIsland'}
GW_OWNER = 4
GWL_EXSTYLE = -20
WS_EX_TOOLWINDOW = 0x00000080
DWMWA_EXTENDED_FRAME_BOUNDS = 9
DWMWA_CLOAKED = 14
SW_MAXIMIZE = 3
SW_RESTORE = 9
SWP_NOZORDER = 0x0004
SWP_NOACTIVATE = 0x0010
SWP_NOSIZE = 0x0001
SWP_NOMOVE = 0x0002
SWP_SHOWWINDOW = 0x0040
HWND_TOPMOST = -1
HWND_NOTOPMOST = -2
MONITORINFOF_PRIMARY = 1


class MONITORINFO(C.Structure):
    _fields_ = [('cbSize', W.DWORD), ('rcMonitor', W.RECT), ('rcWork', W.RECT), ('dwFlags', W.DWORD)]


def _api():
    u = C.WinDLL('user32', use_last_error=True)
    d = C.WinDLL('dwmapi')
    try:
        u.SetProcessDpiAwarenessContext.argtypes = [C.c_void_p]
        u.SetProcessDpiAwarenessContext(C.c_void_p(-4))  # per-monitor v2: real pixels on every screen
    except (AttributeError, OSError):
        pass
    u.EnumWindows.argtypes = [C.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM), W.LPARAM]
    u.IsWindowVisible.argtypes = [W.HWND]
    u.GetWindow.argtypes = [W.HWND, W.UINT]
    u.GetWindow.restype = W.HWND
    u.GetClassNameW.argtypes = [W.HWND, W.LPWSTR, C.c_int]
    u.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
    u.GetWindowRect.argtypes = [W.HWND, C.POINTER(W.RECT)]
    u.GetForegroundWindow.restype = W.HWND
    u.IsIconic.argtypes = [W.HWND]
    u.IsZoomed.argtypes = [W.HWND]
    u.ShowWindow.argtypes = [W.HWND, C.c_int]
    u.SetWindowPos.argtypes = [W.HWND, W.HWND, C.c_int, C.c_int, C.c_int, C.c_int, W.UINT]
    u.SetForegroundWindow.argtypes = [W.HWND]
    u.BringWindowToTop.argtypes = [W.HWND]
    u.EnumDisplayMonitors.argtypes = [W.HDC, C.c_void_p, C.WINFUNCTYPE(W.BOOL, W.HANDLE, W.HDC, C.POINTER(W.RECT), W.LPARAM), W.LPARAM]
    u.GetMonitorInfoW.argtypes = [W.HANDLE, C.POINTER(MONITORINFO)]
    name = 'GetWindowLongPtrW' if C.sizeof(C.c_void_p) == 8 else 'GetWindowLongW'
    ex_style = getattr(u, name)
    ex_style.argtypes = [W.HWND, C.c_int]
    ex_style.restype = C.c_ssize_t
    d.DwmGetWindowAttribute.argtypes = [W.HWND, W.DWORD, C.c_void_p, W.DWORD]
    return u, d, ex_style


def monitors() -> list[dict]:
    """Screens: primary first, then left to right. Work area = without the taskbar."""
    u, _, _ = _api()
    found = []

    @C.WINFUNCTYPE(W.BOOL, W.HANDLE, W.HDC, C.POINTER(W.RECT), W.LPARAM)
    def each(handle, _dc, _rect, _data):
        info = MONITORINFO()
        info.cbSize = C.sizeof(MONITORINFO)
        if u.GetMonitorInfoW(handle, C.byref(info)):
            m, w = info.rcMonitor, info.rcWork
            found.append({'primary': bool(info.dwFlags & MONITORINFOF_PRIMARY),
                          'width': m.right - m.left, 'height': m.bottom - m.top, 'left': m.left,
                          'x': m.left, 'y': m.top,
                          'work': [w.left, w.top, w.right - w.left, w.bottom - w.top]})
        return True

    u.EnumDisplayMonitors(None, None, each, 0)
    found.sort(key=lambda m: (not m['primary'], m['left']))
    for index, item in enumerate(found, 1):
        item['index'] = index
    return found


def target_rect(work: list[int], mode: str, size: tuple[int, int]) -> list[int]:
    """Pure: where the visible window frame goes inside a work area [x, y, w, h]."""
    x, y, w, h = work
    if mode == 'left':
        return [x, y, w // 2, h]
    if mode == 'right':
        return [x + w - w // 2, y, w // 2, h]
    width = max(320, min(size[0], int(w * 0.9)))
    height = max(240, min(size[1], int(h * 0.9)))
    return [x + (w - width) // 2, y + (h - height) // 2, width, height]


class Windows:
    def __init__(self, owner_pid: int):
        self.u, self.d, self.ex_style = _api()
        self.owner = owner_pid

    def top_level(self) -> list[int]:
        u = self.u
        result = []

        @C.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
        def each(hwnd, _data):
            if self.usable(hwnd):
                result.append(int(hwnd))
            return True

        u.EnumWindows(each, 0)
        return result

    def usable(self, hwnd) -> bool:
        u = self.u
        if not u.IsWindowVisible(hwnd) or u.GetWindow(hwnd, GW_OWNER):
            return False
        if self.ex_style(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW:
            return False
        cloaked = W.DWORD()
        if self.d.DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, C.byref(cloaked), C.sizeof(cloaked)) == 0 and cloaked.value:
            return False
        buffer = C.create_unicode_buffer(128)
        u.GetClassNameW(hwnd, buffer, 128)
        if buffer.value in SYSTEM_CLASSES:
            return False
        rect = W.RECT()
        u.GetWindowRect(hwnd, C.byref(rect))
        if rect.right - rect.left < 120 or rect.bottom - rect.top < 80:
            return False
        return self.pid(hwnd) != self.owner

    def pid(self, hwnd) -> int:
        pid = W.DWORD()
        self.u.GetWindowThreadProcessId(hwnd, C.byref(pid))
        return pid.value

    def app(self, hwnd) -> str:
        return process_name(self.pid(hwnd))

    def frame(self, hwnd) -> tuple[W.RECT, W.RECT]:
        outer, visible = W.RECT(), W.RECT()
        self.u.GetWindowRect(hwnd, C.byref(outer))
        if self.d.DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, C.byref(visible), C.sizeof(visible)) != 0:
            visible = outer
        return outer, visible

    def place(self, hwnd, work: list[int], mode: str) -> None:
        u = self.u
        if u.IsIconic(hwnd) or u.IsZoomed(hwnd):
            u.ShowWindow(hwnd, SW_RESTORE)
        for _ in range(2):  # the second pass fixes the size after a jump to a screen with another scale
            outer, visible = self.frame(hwnd)
            size = (visible.right - visible.left, visible.bottom - visible.top)
            x, y, w, h = target_rect(work, 'center' if mode == 'max' else mode, size)
            # The visible frame is smaller than the window rect (invisible resize borders).
            left, top = visible.left - outer.left, visible.top - outer.top
            right, bottom = outer.right - visible.right, outer.bottom - visible.bottom
            u.SetWindowPos(hwnd, None, x - left, y - top, w + left + right, h + top + bottom, SWP_NOZORDER | SWP_NOACTIVATE)
            time.sleep(0.25)
        if mode == 'max':
            u.ShowWindow(hwnd, SW_MAXIMIZE)

    def front(self, hwnd) -> None:
        """Over the other windows: briefly "always on top", then back to normal
        (works even when Windows refuses to hand over the keyboard focus)."""
        u = self.u
        if u.IsIconic(hwnd):
            u.ShowWindow(hwnd, SW_RESTORE)
        flags = SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW
        u.SetWindowPos(hwnd, W.HWND(HWND_TOPMOST), 0, 0, 0, 0, flags)
        u.SetWindowPos(hwnd, W.HWND(HWND_NOTOPMOST), 0, 0, 0, 0, flags)
        u.BringWindowToTop(hwnd)
        u.SetForegroundWindow(hwnd)  # may be refused by Windows; the window is on top anyway


def monitor_of(rect: W.RECT, screens: list[dict]) -> int:
    """Pure-ish: the screen that holds the window's centre (nearest if none)."""
    cx, cy = (rect.left + rect.right) // 2, (rect.top + rect.bottom) // 2
    best, distance = 0, None
    for m in screens:
        x, y, w, h = m['x'], m['y'], m['width'], m['height']
        if x <= cx < x + w and y <= cy < y + h:
            return m['index']
        d = abs(cx - (x + w // 2)) + abs(cy - (y + h // 2))
        if distance is None or d < distance:
            best, distance = m['index'], d
    return best


def list_windows(owner_pid: int) -> list[dict]:
    """Open app windows: program file name, screen, state. Never titles."""
    windows = Windows(owner_pid)
    screens = monitors()
    result = []
    for hwnd in windows.top_level()[:60]:
        _, visible = windows.frame(hwnd)
        state = 'minimized' if windows.u.IsIconic(hwnd) else ('maximized' if windows.u.IsZoomed(hwnd) else 'normal')
        result.append({'hwnd': str(hwnd), 'app': windows.app(hwnd), 'monitor': monitor_of(visible, screens), 'state': state})
    return result


def move(owner_pid: int, hwnd: int, monitor: int, mode: str, on_top: bool = False) -> dict:
    screen = next((m for m in monitors() if m['index'] == monitor), None)
    windows = Windows(owner_pid)
    if mode not in MODES or screen is None or hwnd not in windows.top_level():
        return {'ok': False, 'error': 'bad_target'}
    windows.place(hwnd, screen['work'], mode)
    if on_top:
        windows.front(hwnd)
    return {'ok': True, 'app': windows.app(hwnd)}


def front(owner_pid: int, hwnd: int) -> dict:
    windows = Windows(owner_pid)
    if hwnd not in windows.top_level():
        return {'ok': False, 'error': 'bad_target'}
    windows.front(hwnd)
    return {'ok': True, 'app': windows.app(hwnd)}


def place(owner_pid: int, monitor: int, mode: str, exe: str) -> dict:
    screens = monitors()
    screen = next((m for m in screens if m['index'] == monitor), None)
    if mode not in MODES or screen is None:
        print(json.dumps({'ready': True}), flush=True)
        return {'ok': False, 'error': 'bad_target'}
    windows = Windows(owner_pid)
    before = set(windows.top_level())
    print(json.dumps({'ready': True}), flush=True)
    start = time.monotonic()
    chosen = 0
    while time.monotonic() - start < WAIT_NEW and not chosen:
        time.sleep(0.2)
        fresh = [h for h in windows.top_level() if h not in before]
        matching = [h for h in fresh if exe and windows.app(h) == exe]
        chosen = (matching or ([] if exe else fresh) or [0])[0]
        if not chosen and exe and fresh and time.monotonic() - start > WAIT_BEFORE_FALLBACK:
            chosen = fresh[0]  # a helper process of another name opened the window
        if not chosen and exe and time.monotonic() - start > WAIT_BEFORE_FALLBACK:
            front = windows.u.GetForegroundWindow()
            if front and windows.usable(front) and windows.app(front) == exe:
                chosen = int(front)  # single-instance app brought its old window forward
    if not chosen:
        return {'ok': False, 'error': 'no_window'}
    windows.place(chosen, screen['work'], mode)
    time.sleep(1.2)
    if mode != 'max':
        _, visible = windows.frame(chosen)
        expected = target_rect(screen['work'], mode, (visible.right - visible.left, visible.bottom - visible.top))
        if abs(visible.left - expected[0]) > 24 or abs(visible.top - expected[1]) > 24:
            windows.place(chosen, screen['work'], mode)  # the app restored its own position — once more
    return {'ok': True, 'app': windows.app(chosen)}


def main(argv: list[str]) -> int:
    if not hasattr(C, 'WinDLL'):
        print(json.dumps({'ok': False, 'error': 'windows_only'}))
        return 1
    if argv[1:] == ['monitors']:
        print(json.dumps({'ok': True, 'monitors': [{k: m[k] for k in ('index', 'primary', 'width', 'height', 'x', 'y')} for m in monitors()]}))
        return 0
    if len(argv) == 3 and argv[1] == 'list' and argv[2].isdigit():
        print(json.dumps({'ok': True, 'windows': list_windows(int(argv[2]))}))
        return 0
    if len(argv) in (6, 7) and argv[1] == 'move' and argv[2].isdigit() and argv[3].isdigit() and argv[4].isdigit():
        print(json.dumps(move(int(argv[2]), int(argv[3]), int(argv[4]), argv[5], argv[6:] == ['front'])), flush=True)
        return 0
    if len(argv) == 4 and argv[1] == 'front' and argv[2].isdigit() and argv[3].isdigit():
        print(json.dumps(front(int(argv[2]), int(argv[3]))), flush=True)
        return 0
    if len(argv) == 6 and argv[1] == 'place' and argv[2].isdigit() and argv[3].isdigit():
        exe = '' if argv[5] == '-' else argv[5].lower()
        print(json.dumps(place(int(argv[2]), int(argv[3]), argv[4], exe)), flush=True)
        return 0
    print('usage: window_place.py monitors | list <owner_pid> | move <owner_pid> <hwnd> <monitor> <mode> [front]'
          ' | front <owner_pid> <hwnd> | place <owner_pid> <monitor> <mode> <exe|->', file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
