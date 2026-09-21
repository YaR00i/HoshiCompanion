"""Bounded opt-in candidate selection. Geometry only; never reads window text."""
from __future__ import annotations
import ctypes as C
from ctypes import wintypes as W
import math
import time


def overlaps(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def placement(rect, fraction, seat, size, area):
    x, y, w, h = rect
    if w < 180 or h < 80 or min(size) <= 0:
        return None
    anchor = (x + 24 + (w - 48) * fraction, y + 2)
    pos = (round(anchor[0] - seat[0]), round(anchor[1] - seat[1]))
    ax, ay, aw, ah = area
    if pos[0] < ax or pos[1] < ay or pos[0] + size[0] > ax + aw or pos[1] + size[1] > ay + ah:
        return None
    return pos, anchor


def covered(g, hwnd, strip, fixture_pid=0):
    """Conservative rectangular edge occlusion; bounded Z-order traversal."""
    get_window = g.u.GetWindow
    get_window.argtypes, get_window.restype = [W.HWND, W.UINT], W.HWND
    seen = set()
    for _ in range(128):
        hwnd = get_window(hwnd, 3)  # GW_HWNDPREV; do not loop indefinitely.
        if not hwnd:
            return False
        key = int(hwnd)
        if key in seen:
            return True
        seen.add(key)
        if fixture_pid and g.identify(hwnd)[0] != fixture_pid:
            continue
        if not g.visible(hwnd) or g.iconic(hwnd) or g.identify(hwnd)[0] == g.owner:
            continue
        cloaked = W.DWORD()
        if g.attr(hwnd, 14, C.byref(cloaked), C.sizeof(cloaked)) == 0 and cloaked.value:
            continue
        rect = W.RECT()
        if g.visible_bounds(hwnd, rect):
            box = [rect.left + g.shift[0], rect.top + g.shift[1], rect.right - rect.left, rect.bottom - rect.top]
            if overlaps(box, strip):
                return True
    return True


def choose(g, options):
    seat, size, area = options['seat'], options['size'], options['area']
    origin = options['origin']
    for values, count in [(seat, 2), (size, 2), (area, 4), (origin, 2)]:
        if len(values) != count or not all(isinstance(n, (int, float)) and math.isfinite(n) and abs(n) < 100000 for n in values):
            return {'ok': False, 'reason': 'invalid'}
    handles = []
    callback_type = C.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
    def collect(hwnd, _param):
        handles.append(int(hwnd))
        return len(handles) < 256
    enum = g.u.EnumWindows
    enum.argtypes, enum.restype = [callback_type, W.LPARAM], W.BOOL
    enum(callback_type(collect), 0)
    best = None
    stats = {'handles': len(handles), 'fixture': 0, 'visible': 0, 'probe_ok': 0, 'area_match': 0, 'placement': 0, 'covered': 0}
    started = time.monotonic()
    # Test fixture restriction is set only by the test-mode caller. It uses the
    # real enumeration but does not inspect unrelated window geometry in tests.
    fixture_pid = int(options.get('fixture_pid', 0))
    for hwnd in handles:
        if time.monotonic() - started > 0.45:
            break
        if not g.visible(hwnd) or g.iconic(hwnd):
            continue
        if fixture_pid and g.identify(hwnd)[0] != fixture_pid:
            continue
        stats['fixture'] += 1
        stats['visible'] += 1
        data = g.bind(hwnd)
        if not data['ok']:
            continue
        stats['probe_ok'] += 1
        if data['area'] != area:
            continue
        stats['area_match'] += 1
        for fraction in (0.28, 0.50, 0.70):
            where = placement(data['rect'], fraction, seat, size, area)
            if where is None:
                continue
            stats['placement'] += 1
            pos, anchor = where
            strip = [anchor[0] - size[0] * .22, anchor[1] - 4, size[0] * .44, 30]
            if covered(g, hwnd, strip, fixture_pid):
                stats['covered'] += 1
                continue
            score = math.hypot(pos[0] - origin[0], pos[1] - origin[1])
            if best is None or score < best[0]:
                best = (score, hwnd, fraction)
    if best is None:
        g.hwnd, g.identity = 0, None
        return {'ok': False, 'reason': 'no_candidate', 'stats': stats}
    data = g.bind(best[1])  # Revalidate chosen identity after enumeration.
    if data['ok']:
        data['fraction'] = best[2]
    return data
