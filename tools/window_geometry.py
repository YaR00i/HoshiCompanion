"""Opt-in, read-only geometry of ONE selected window; JSON lines over stdio.
No window titles, screen pixels, hooks, networking, writes or global settings.
The caller asks to pick once, then probe the same HWND. EOF/5s idle exits.
"""
from __future__ import annotations
import ctypes as C
from ctypes import wintypes as W
import json
import queue
import sys
import threading


def winapi(dll, name, result, *args):
    fn = getattr(dll, name)
    fn.restype, fn.argtypes = result, list(args)
    return fn


class Geometry:
    def __init__(self, owner_pid: int, owner_hwnd: int, host_x: int, host_y: int):
        self.owner = owner_pid
        self.hwnd = 0
        self.identity = None
        self.u = C.WinDLL('user32', use_last_error=True)
        self.d = C.WinDLL('dwmapi', use_last_error=True)
        self.dpi = winapi(self.u, 'SetThreadDpiAwarenessContext', W.HANDLE, W.HANDLE)
        get_context = winapi(self.u, 'GetWindowDpiAwarenessContext', W.HANDLE, W.HWND)
        owner_context = get_context(owner_hwnd)
        if not owner_context or not self.dpi(owner_context):
            raise OSError('Cannot match host DPI coordinate space')
        self.valid = winapi(self.u, 'IsWindow', W.BOOL, W.HWND)
        self.visible = winapi(self.u, 'IsWindowVisible', W.BOOL, W.HWND)
        self.enabled = winapi(self.u, 'IsWindowEnabled', W.BOOL, W.HWND)
        self.iconic = winapi(self.u, 'IsIconic', W.BOOL, W.HWND)
        self.zoomed = winapi(self.u, 'IsZoomed', W.BOOL, W.HWND)
        self.cursor = winapi(self.u, 'GetPhysicalCursorPos', W.BOOL, C.POINTER(W.POINT))
        self.at = winapi(self.u, 'WindowFromPhysicalPoint', W.HWND, W.POINT)
        self.root = winapi(self.u, 'GetAncestor', W.HWND, W.HWND, W.UINT)
        self.pid = winapi(self.u, 'GetWindowThreadProcessId', W.DWORD, W.HWND, C.POINTER(W.DWORD))
        self.cls = winapi(self.u, 'GetClassNameW', C.c_int, W.HWND, W.LPWSTR, C.c_int)
        self.rect = winapi(self.u, 'GetWindowRect', W.BOOL, W.HWND, C.POINTER(W.RECT))
        self.attr = winapi(self.d, 'DwmGetWindowAttribute', C.c_long, W.HWND, W.DWORD, C.c_void_p, W.DWORD)
        name = 'GetWindowLongPtrW' if C.sizeof(C.c_void_p) == 8 else 'GetWindowLongW'
        self.style = winapi(self.u, name, C.c_ssize_t, W.HWND, C.c_int)
        self.monitor = winapi(self.u, 'MonitorFromWindow', W.HANDLE, W.HWND, W.DWORD)
        self.monitor_info = winapi(self.u, 'GetMonitorInfoW', W.BOOL, W.HANDLE, C.c_void_p)
        self.client_point = winapi(self.u, 'ClientToScreen', W.BOOL, W.HWND, C.POINTER(W.POINT))
        if self.identify(owner_hwnd)[0] != self.owner:
            raise OSError('Invalid host window')
        # Match Godot's own client coordinates, including system-DPI-aware hosts.
        point = W.POINT(0, 0)
        if not self.client_point(owner_hwnd, C.byref(point)):
            raise OSError('Cannot calibrate host coordinates')
        self.shift = (host_x - point.x, host_y - point.y)
        self.owner_hwnd = owner_hwnd

    def visible_bounds(self, hwnd, result):
        # GetWindowRect follows caller DPI, DWM never does. Map only the small
        # frame insets between physical and host-logical outer rectangles.
        logical, physical, visible = W.RECT(), W.RECT(), W.RECT()
        if not self.rect(hwnd, C.byref(logical)):
            return False
        old = self.dpi(C.c_void_p(-4))
        if not old:
            return False
        try:
            if not self.rect(hwnd, C.byref(physical)):
                return False
            if self.attr(hwnd, 9, C.byref(visible), C.sizeof(visible)) != 0:
                visible = physical
        finally:
            self.dpi(old)
        pw, ph = physical.right - physical.left, physical.bottom - physical.top
        if pw <= 0 or ph <= 0:
            return False
        sx = (logical.right - logical.left) / pw
        sy = (logical.bottom - logical.top) / ph
        result.left = logical.left + round((visible.left - physical.left) * sx)
        result.top = logical.top + round((visible.top - physical.top) * sy)
        result.right = logical.right + round((visible.right - physical.right) * sx)
        result.bottom = logical.bottom + round((visible.bottom - physical.bottom) * sy)
        return True

    def identify(self, hwnd):
        pid = W.DWORD()
        tid = self.pid(hwnd, C.byref(pid))
        name = C.create_unicode_buffer(256)
        self.cls(hwnd, name, 256)
        return (pid.value, tid, name.value)

    def pick(self):
        point = W.POINT()
        if not self.cursor(C.byref(point)):
            return {'ok': False, 'reason': 'cursor'}
        hwnd = self.root(self.at(point), 2)
        result = self.bind(int(hwnd or 0))
        if result['ok']:
            old = self.dpi(C.c_void_p(-4))
            bounds = W.RECT()
            try:
                if self.attr(hwnd, 9, C.byref(bounds), C.sizeof(bounds)) != 0:
                    self.rect(hwnd, C.byref(bounds))
            finally:
                self.dpi(old)
            result['fraction'] = min(.95, max(.05, (point.x - bounds.left - 24) / max(1, bounds.right - bounds.left - 48)))
        return result

    def bind(self, hwnd: int):
        self.hwnd = hwnd
        self.identity = self.identify(hwnd) if self.valid(hwnd) else None
        reply = self.probe()
        return reply

    def probe(self):
        hwnd = self.hwnd
        bad = lambda reason: {'ok': False, 'reason': reason}
        if not hwnd or not self.valid(hwnd):
            return bad('closed')
        identity = self.identify(hwnd)
        if identity != self.identity or not identity[0]:
            return bad('changed')
        if identity[0] == self.owner:
            return bad('own')
        if identity[2] in {'Progman', 'WorkerW', 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd', '#32770', '#32768'}:
            return bad('system')
        if self.iconic(hwnd):
            return bad('minimized')
        if self.zoomed(hwnd):
            return bad('maximized')
        if not self.visible(hwnd) or not self.enabled(hwnd):
            return bad('hidden')
        if self.style(hwnd, -20) & (0x80 | 0x08000000):
            return bad('tool_window')
        cloaked = W.DWORD()
        if self.attr(hwnd, 14, C.byref(cloaked), C.sizeof(cloaked)) == 0 and cloaked.value:
            return bad('hidden')
        bounds = W.RECT()
        if not self.visible_bounds(hwnd, bounds):
            return bad('unavailable')
        width, height = bounds.right - bounds.left, bounds.bottom - bounds.top
        if width < 180 or height < 80:
            return bad('small')
        class Info(C.Structure):
            _fields_ = [('cbSize', W.DWORD), ('monitor', W.RECT), ('work', W.RECT), ('flags', W.DWORD)]
        info = Info()
        info.cbSize = C.sizeof(info)
        if not self.monitor_info(self.monitor(hwnd, 2), C.byref(info)):
            return bad('monitor')
        m = info.monitor
        if bounds.left <= m.left and bounds.top <= m.top and bounds.right >= m.right and bounds.bottom >= m.bottom:
            return bad('fullscreen')
        w = info.work
        # Host-DPI virtual desktop coordinates, NOT unconditionally physical pixels.
        vx, vy = -self.shift[0], -self.shift[1]
        return {'ok': True, 'hwnd': str(hwnd), 'rect': [bounds.left - vx, bounds.top - vy, width, height],
                'area': [w.left - vx, w.top - vy, w.right - w.left, w.bottom - w.top],
                'space': 'godot_virtual_pixels'}


def read_commands(inbox):
    for line in sys.stdin:
        inbox.put(line)
    inbox.put(None)

def main() -> int:
    geometry = Geometry(*(int(arg) for arg in sys.argv[1:5]))
    inbox = queue.Queue(maxsize=8)
    threading.Thread(target=read_commands, args=(inbox,), daemon=True).start()
    print(json.dumps({'ready': True, 'protocol': 1, 'coordinate_shift': geometry.shift}), flush=True)
    while True:
        try:
            line = inbox.get(timeout=5.0)
        except queue.Empty:
            return 0  # No host heartbeat: do not leave an orphan observer.
        if line is None or len(line) > 2048:
            return 0
        try:
            request = json.loads(line)
            op = request.get('op')
            if op == 'quit':
                return 0
            if op == 'pick':
                result = geometry.pick()
            elif op == 'bind':
                result = geometry.bind(int(request['hwnd']))
            elif op == 'probe':
                result = geometry.probe()
            else:
                result = {'ok': False, 'reason': 'protocol'}
        except (ValueError, KeyError, TypeError, OSError):
            result = {'ok': False, 'reason': 'invalid'}
        print(json.dumps(result, separators=(',', ':')), flush=True)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, AttributeError, IndexError, ValueError):
        print(json.dumps({'ok': False, 'reason': 'startup'}), flush=True)
        raise SystemExit(1)
