"""Read input style and hit target for explicitly supplied Hoshi-owned HWNDs."""
import ctypes as c
from ctypes import wintypes as w
import json
import sys

if len(sys.argv) not in (3, 4, 8):
    raise SystemExit("usage: own_window_input_style.py HWND OWNER_PID [UNDERLAY_HWND [LOCAL_X LOCAL_Y WINDOW_W WINDOW_H]]")

hwnd = w.HWND(int(sys.argv[1]))
expected_pid = int(sys.argv[2])
user32 = c.WinDLL("user32", use_last_error=True)
user32.GetWindowThreadProcessId.argtypes = [w.HWND, c.POINTER(w.DWORD)]
user32.GetWindowThreadProcessId.restype = w.DWORD
user32.GetWindowLongPtrW.argtypes = [w.HWND, c.c_int]
user32.GetWindowLongPtrW.restype = c.c_ssize_t
owner = w.DWORD()
if not user32.GetWindowThreadProcessId(hwnd, c.byref(owner)) or owner.value != expected_pid:
    raise SystemExit("refusing HWND outside the supplied Hoshi process")

style = int(user32.GetWindowLongPtrW(hwnd, -20))
result = {"passthrough": bool(style & 0x20), "style": style}
if len(sys.argv) in (4, 8):
    underlay = w.HWND(int(sys.argv[3]))
    user32.GetWindowThreadProcessId(underlay, c.byref(owner))
    if owner.value != expected_pid:
        raise SystemExit("refusing underlay outside the supplied Hoshi process")

    class Point(c.Structure):
        _fields_ = [("x", c.c_long), ("y", c.c_long)]

    class Rect(c.Structure):
        _fields_ = [("left", c.c_long), ("top", c.c_long), ("right", c.c_long), ("bottom", c.c_long)]

    user32.GetWindowRect.argtypes = [w.HWND, c.POINTER(Rect)]
    user32.GetWindowRect.restype = w.BOOL
    user32.WindowFromPoint.argtypes = [Point]
    user32.WindowFromPoint.restype = w.HWND
    overlay_rect, underlay_rect = Rect(), Rect()
    if not user32.GetWindowRect(hwnd, c.byref(overlay_rect)) or not user32.GetWindowRect(underlay, c.byref(underlay_rect)):
        raise SystemExit("own window rect unavailable")
    left = max(overlay_rect.left, underlay_rect.left)
    top = max(overlay_rect.top, underlay_rect.top)
    right = min(overlay_rect.right, underlay_rect.right)
    bottom = min(overlay_rect.bottom, underlay_rect.bottom)
    if left >= right or top >= bottom:
        result["target"] = "no_overlap"
    else:
        if len(sys.argv) == 8:
            local_x, local_y = float(sys.argv[4]), float(sys.argv[5])
            logical_w, logical_h = float(sys.argv[6]), float(sys.argv[7])
            point = Point(round(underlay_rect.left + local_x * (underlay_rect.right - underlay_rect.left) / logical_w),
                          round(underlay_rect.top + local_y * (underlay_rect.bottom - underlay_rect.top) / logical_h))
        else:
            point = Point(left + min(25, (right - left) // 2), top + (bottom - top) // 2)
        if not left <= point.x < right or not top <= point.y < bottom:
            result["target"] = "outside_overlap"
        else:
            target = user32.WindowFromPoint(point)
            result["target"] = "underlay" if target == underlay.value else "overlay" if target == hwnd.value else "other"
        result["point"] = [point.x, point.y]
        result["overlay_rect"] = [overlay_rect.left, overlay_rect.top, overlay_rect.right, overlay_rect.bottom]
print(json.dumps(result))
