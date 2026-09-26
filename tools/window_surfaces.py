"""One-shot, opt-in edge preview for a window chosen under the cursor.

Structure mode requests only UIA types and rectangles. The separately chosen
visual mode captures one frame in a bounded child. Neither mode returns titles,
text, pixels, or image files to Godot; only compact coordinates reach it.
"""
from __future__ import annotations

import ctypes as C
from ctypes import wintypes as W
import json
from pathlib import Path
import subprocess
import sys
import time

SCRIPT = Path(__file__).with_suffix('.ps1')
MAX_CANDIDATES = 24
KINDS = {'ToolBar', 'Tab', 'TabItem', 'Header', 'HeaderItem', 'ListItem',
         'Button', 'Group', 'Pane', 'Custom'}


def candidates(payload: dict) -> dict:
    root = payload['rect']
    rx, ry, rw, rh = (int(v) for v in root)
    if rw < 120 or rh < 80 or rw > 20000 or rh > 20000:
        raise ValueError('bounds')
    lines = []
    seen = set()
    for item in payload.get('elements', [])[:240]:
        kind = str(item.get('kind', ''))
        if kind not in KINDS:
            continue
        x, y, w, h = (int(v) for v in item['rect'])
        left, right = max(x, rx + 2), min(x + w, rx + rw - 2)
        top, bottom = max(y, ry + 2), min(y + h, ry + rh - 2)
        width = right - left
        if width < 90 or bottom - top < 15 or top <= ry + 8:
            continue
        if width > rw * .96 or bottom - top > rh * .65:
            continue
        key = (round((left - rx) / 8), round((top - ry) / 8), round(width / 8))
        if key in seen:
            continue
        seen.add(key)
        lines.append({'x': left - rx, 'y': top - ry, 'width': width,
                      'kind': kind})
    lines.sort(key=lambda line: (line['y'], line['x']))
    if len(lines) > MAX_CANDIDATES:
        # A dense toolbar must not consume the whole map before list content.
        shown = [lines[round(index * (len(lines) - 1) / (MAX_CANDIDATES - 1))]
                 for index in range(MAX_CANDIDATES)]
    else:
        shown = lines
    return {'ok': True, 'window': [rw, rh], 'candidates': shown,
            'visible_count': len(lines), 'visited': int(payload.get('visited', 0)),
            'source': 'structure', 'offscreen': int(payload.get('offscreen', 0)),
            'limited': bool(payload.get('limited', False))}


def selected_window(owner_pid: int, owner_hwnd: int) -> int:
    user32 = C.WinDLL('user32', use_last_error=True)
    user32.GetPhysicalCursorPos.argtypes = [C.POINTER(W.POINT)]
    user32.GetPhysicalCursorPos.restype = W.BOOL
    user32.WindowFromPhysicalPoint.argtypes = [W.POINT]
    user32.WindowFromPhysicalPoint.restype = W.HWND
    user32.GetAncestor.argtypes = [W.HWND, W.UINT]
    user32.GetAncestor.restype = W.HWND
    user32.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
    user32.GetWindowThreadProcessId.restype = W.DWORD
    user32.IsWindowVisible.argtypes = [W.HWND]
    user32.IsWindowVisible.restype = W.BOOL
    user32.IsIconic.argtypes = [W.HWND]
    user32.IsIconic.restype = W.BOOL
    user32.GetClassNameW.argtypes = [W.HWND, W.LPWSTR, C.c_int]
    user32.GetClassNameW.restype = C.c_int
    point = W.POINT()
    if not user32.GetPhysicalCursorPos(C.byref(point)):
        raise ValueError('cursor')
    hwnd = int(user32.GetAncestor(user32.WindowFromPhysicalPoint(point), 2) or 0)
    pid = W.DWORD()
    if not hwnd or not user32.GetWindowThreadProcessId(W.HWND(hwnd), C.byref(pid)):
        raise ValueError('window')
    if hwnd == owner_hwnd or pid.value == owner_pid or not user32.IsWindowVisible(W.HWND(hwnd)):
        raise ValueError('own_or_hidden')
    if user32.IsIconic(W.HWND(hwnd)):
        raise ValueError('minimized')
    name = C.create_unicode_buffer(256)
    user32.GetClassNameW(W.HWND(hwnd), name, 256)
    if name.value in {'Progman', 'WorkerW', 'Shell_TrayWnd',
                      'Shell_SecondaryTrayWnd', '#32768'}:
        raise ValueError('system')
    return hwnd


def inspect(hwnd: int, max_depth: int = 12) -> dict:
    args = ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy',
            'Bypass', '-File', str(SCRIPT), '-TargetHandle', str(hwnd),
            '-MaxDepth', str(max_depth)]
    proc = subprocess.run(
        args,
        stdin=subprocess.DEVNULL, capture_output=True, timeout=6,
        creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0,
    )
    if proc.returncode:
        raise ValueError('uia_unavailable')
    return candidates(json.loads(proc.stdout.decode('utf-8-sig')))


def main() -> None:
    if sys.platform != 'win32' or len(sys.argv) not in (3, 4):
        raise ValueError('platform')
    owner_pid, owner_hwnd = int(sys.argv[1]), int(sys.argv[2])
    print(json.dumps({'ready': True}), flush=True)
    time.sleep(4.0)
    hwnd = selected_window(owner_pid, owner_hwnd)
    mode = sys.argv[3] if len(sys.argv) == 4 else 'structure'
    if mode == 'visual':
        helper = Path(__file__).with_name('window_visual_surfaces.py')
        child = subprocess.run([sys.executable, str(helper), str(hwnd)],
                               stdin=subprocess.DEVNULL, capture_output=True, timeout=6,
                               creationflags=subprocess.CREATE_NO_WINDOW)
        if child.returncode:
            raise ValueError('visual_unavailable')
        result = json.loads(child.stdout)
    elif mode == 'structure':
        result = inspect(hwnd)
    else:
        raise ValueError('mode')
    print(json.dumps(result, separators=(',', ':')), flush=True)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.TimeoutExpired,
            json.JSONDecodeError) as exc:
        reason = str(exc) if isinstance(exc, ValueError) else 'uia_unavailable'
        source = sys.argv[3] if len(sys.argv) == 4 and sys.argv[3] in ('structure', 'visual') else 'structure'
        print(json.dumps({'ok': False, 'reason': reason, 'source': source}), flush=True)
