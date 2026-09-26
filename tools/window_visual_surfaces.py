"""One-frame visual edge probe of one manually selected HWND.

Windows Graphics Capture sees GPU-rendered application content. The frame stays
in this short-lived process; only horizontal coordinates are returned to Godot.
No OCR, image files, hooks, enumeration, or network requests.
"""
from __future__ import annotations

import ctypes as C
from ctypes import wintypes as W
import json
from pathlib import Path
import sys

LOCAL_DEPS = Path(__file__).resolve().parents[1] / '.workspace' / 'surface-deps'
if LOCAL_DEPS.is_dir():
    sys.path.insert(0, str(LOCAL_DEPS))


def capture(hwnd: int):
    from windows_capture import WindowsCapture, Frame, InternalCaptureControl

    user = C.WinDLL('user32')
    user.IsWindow.argtypes = [W.HWND]
    user.IsWindow.restype = W.BOOL
    user.IsIconic.argtypes = [W.HWND]
    user.IsIconic.restype = W.BOOL
    if not user.IsWindow(W.HWND(hwnd)) or user.IsIconic(W.HWND(hwnd)):
        raise ValueError('window_unavailable')

    frames = []
    session = WindowsCapture(window_hwnd=hwnd, cursor_capture=False)

    @session.event
    def on_frame_arrived(frame: Frame, control: InternalCaptureControl):
        frames.append(frame.frame_buffer.copy())
        control.stop()

    @session.event
    def on_closed():
        pass

    session.start()
    if not frames:
        raise ValueError('capture_unavailable')
    return frames[0]


def spread_over_height(items: list[dict], budget: int, height: int) -> list[dict]:
    """Keep bottom content visible even when chrome produces many top edges."""
    if len(items) <= budget:
        return items
    buckets = [[] for _ in range(min(6, budget))]
    for item in items:
        index = min(len(buckets) - 1, int(item['y'] * len(buckets) / height))
        buckets[index].append(item)
    for bucket in buckets:
        bucket.sort(key=lambda item: (-item['width'], item['y']))
    chosen = []
    while len(chosen) < budget and any(buckets):
        for bucket in buckets:
            if bucket and len(chosen) < budget:
                chosen.append(bucket.pop(0))
    return sorted(chosen, key=lambda item: (item['y'], item['x']))


def visual_rows(gray, scale: float) -> list[dict]:
    """Find repeated aligned UI rows without reading their text."""
    import cv2

    edges = cv2.Canny(gray.astype('uint8'), 45, 110)
    joined = cv2.morphologyEx(edges, cv2.MORPH_CLOSE,
                              cv2.getStructuringElement(cv2.MORPH_RECT, (11, 3)))
    height, width = gray.shape
    groups = []
    for contour in cv2.findContours(joined, cv2.RETR_EXTERNAL,
                                     cv2.CHAIN_APPROX_SIMPLE)[0]:
        x, y, w, h = cv2.boundingRect(contour)
        if not (45 <= w <= width * .62 and 5 <= h <= 22 and y > height * .19):
            continue
        group = next((group for group in groups if abs(group[0] - x) <= 6), None)
        if group is None:
            group = [x, []]
            groups.append(group)
        group[1].append((x, y, w, h))

    repeated = []
    for _, rects in groups:
        rects.sort(key=lambda rect: rect[1])
        run = []
        for rect in rects:
            if run and not 10 <= rect[1] - run[-1][1] <= 40:
                if len(run) >= 4:
                    repeated.extend(run)
                run = []
            run.append(rect)
        if len(run) >= 4:
            repeated.extend(run)

    # Several list columns can describe the same row. Prefer the first content
    # column over metadata columns and the navigation sidebar.
    rows = []
    for x, y, w, h in sorted(repeated, key=lambda rect: (rect[1], rect[0])):
        item = {'x': round(x / scale), 'y': round((y + h) / scale),
                'width': round(w / scale), 'kind': 'VisualItem'}
        near = next((old for old in rows if abs(old['y'] - item['y']) <= 3), None)
        if near is None:
            rows.append(item)
        elif (item['x'] >= width * .12 / scale and
              (near['x'] < width * .12 / scale or item['x'] < near['x'])):
            near.update(item)
    return rows


def lines_from_frame(frame) -> dict:
    import cv2
    import numpy as np

    height, width = frame.shape[:2]
    if width < 120 or height < 80 or width * height > 12000000:
        raise ValueError('bounds')
    scale = min(1.0, 900.0 / max(width, height))
    if scale < 1.0:
        frame = cv2.resize(frame, (round(width * scale), round(height * scale)),
                           interpolation=cv2.INTER_AREA)
    rgb = frame[:, :, :3].astype(np.int32)
    if float(rgb.std()) < 3.0:
        raise ValueError('blank_capture')
    gray = (rgb[:, :, 2] * 77 + rgb[:, :, 1] * 150 + rgb[:, :, 0] * 29) // 256
    hit = np.abs(gray[1:] - gray[:-1]) >= 12
    min_width = max(70, int(frame.shape[1] * .13))
    found = []
    for y in range(max(10, int(24 * scale)), frame.shape[0] - 4):
        row = hit[y]
        if int(row.sum()) < min_width:
            continue
        delta = np.diff(np.pad(row.astype(np.int8), (1, 1)))
        starts = np.flatnonzero(delta == 1)
        ends = np.flatnonzero(delta == -1)
        for left, right in zip(starts, ends):
            if right - left < min_width:
                continue
            item = {'x': round(left / scale), 'y': round((y + 1) / scale),
                    'width': round((right - left) / scale), 'kind': 'Visual'}
            if any(abs(old['y'] - item['y']) <= 4 and
                   abs(old['x'] - item['x']) < 12 and
                   abs(old['width'] - item['width']) < 16 for old in found):
                continue
            found.append(item)
    rows = visual_rows(gray, scale)
    if rows:
        selected = spread_over_height(found, 12, height) + spread_over_height(rows, 12, height)
    else:
        selected = spread_over_height(found, 24, height)
    selected.sort(key=lambda item: (item['y'], item['x']))
    return {'ok': True, 'window': [width, height], 'candidates': selected,
            'visible_count': len(found) + len(rows), 'edge_count': len(found),
            'row_count': len(rows), 'source': 'visual'}


if __name__ == '__main__':
    try:
        if sys.platform != 'win32' or len(sys.argv) != 2:
            raise ValueError('platform')
        result = lines_from_frame(capture(int(sys.argv[1])))
    except ImportError:
        result = {'ok': False, 'reason': 'visual_dependency'}
    except (OSError, ValueError, RuntimeError) as exc:
        result = {'ok': False, 'reason': str(exc) if isinstance(exc, ValueError) else 'capture_unavailable'}
    print(json.dumps(result, separators=(',', ':')), flush=True)
