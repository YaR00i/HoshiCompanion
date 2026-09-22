"""Isolated native test window in a separate process; moves only itself.
No user documents/apps are opened or modified. stdin EOF or 60s destroys it.
The fixture places itself on the same monitor as Hoshi by native HWND, avoiding
Tk/Godot virtual-desktop coordinate assumptions.
"""
import ctypes as C
from ctypes import wintypes as W
import json
import queue
import sys
import threading
import tkinter as tk

u = C.WinDLL("user32")
u.SetThreadDpiAwarenessContext.argtypes = [W.HANDLE]
u.SetThreadDpiAwarenessContext.restype = W.HANDLE
u.SetThreadDpiAwarenessContext(C.c_void_p(-2))
u.GetAncestor.argtypes = [W.HWND, W.UINT]
u.GetAncestor.restype = W.HWND
u.MonitorFromWindow.argtypes = [W.HWND, W.DWORD]
u.MonitorFromWindow.restype = W.HANDLE
u.SetWindowPos.argtypes = [W.HWND, W.HWND, C.c_int, C.c_int, C.c_int, C.c_int, W.UINT]
u.SetWindowPos.restype = W.BOOL
u.GetWindowRect.argtypes = [W.HWND, C.POINTER(W.RECT)]
u.GetWindowRect.restype = W.BOOL
u.IsIconic.argtypes = [W.HWND]
u.IsIconic.restype = W.BOOL
u.IsWindowVisible.argtypes = [W.HWND]
u.IsWindowVisible.restype = W.BOOL
u.ShowWindow.argtypes = [W.HWND, C.c_int]
u.ShowWindow.restype = W.BOOL
u.IsWindowEnabled.argtypes = [W.HWND]
u.IsWindowEnabled.restype = W.BOOL
u.IsZoomed.argtypes = [W.HWND]
u.IsZoomed.restype = W.BOOL
d = C.WinDLL("dwmapi")
d.DwmGetWindowAttribute.argtypes = [W.HWND, W.DWORD, C.c_void_p, W.DWORD]
d.DwmGetWindowAttribute.restype = C.c_long

class MONITORINFO(C.Structure):
    _fields_ = [("cbSize", W.DWORD), ("rcMonitor", W.RECT),
                ("rcWork", W.RECT), ("dwFlags", W.DWORD)]

u.GetMonitorInfoW.argtypes = [W.HANDLE, C.POINTER(MONITORINFO)]
u.GetMonitorInfoW.restype = W.BOOL

owner_hwnd = int(sys.argv[1])
window_height = int(sys.argv[2]) if len(sys.argv) > 2 else 560
window_width = 640

root = tk.Tk()
root.title("Hoshi - isolated external window test")
root.geometry(f"{window_width}x{window_height}+0+0")
root.configure(bg="#eee5f1")
tk.Label(root, text="HOSHI / EXTERNAL WINDOW TEST", bg="#eee5f1",
         font=("Segoe UI", 18)).pack(pady=45)
tk.Label(root, text="Separate process. No personal content.", bg="#eee5f1",
         font=("Segoe UI", 12)).pack()
root.update()

hwnd = u.GetAncestor(root.winfo_id(), 2)
monitor = u.MonitorFromWindow(W.HWND(owner_hwnd), 2)
info = MONITORINFO()
info.cbSize = C.sizeof(MONITORINFO)
if not monitor or not u.GetMonitorInfoW(monitor, C.byref(info)):
    raise RuntimeError("could not resolve Hoshi monitor")
work = info.rcWork
work_w = int(work.right - work.left)
work_h = int(work.bottom - work.top)
x = int(work.left + work_w * 0.25)
y = int(work.top + work_h * 0.48)
u.SetWindowPos(hwnd, W.HWND(0), x, y, window_width, window_height, 0x0004 | 0x0010)
root.update()
print(json.dumps({"hwnd": str(hwnd)}), flush=True)

inbox = queue.Queue(maxsize=20)
def read():
    for line in sys.stdin:
        inbox.put(line)
    inbox.put(None)

def move_by(message):
    rect = W.RECT()
    if not u.GetWindowRect(hwnd, C.byref(rect)):
        return
    dx = int(message.get("dx", 0))
    dy = int(message.get("dy", 0))
    dw = int(message.get("dw", 0))
    dh = int(message.get("dh", 0))
    width = max(220, int(rect.right - rect.left) + dw)
    height = max(180, int(rect.bottom - rect.top) + dh)
    u.SetWindowPos(hwnd, W.HWND(0), int(rect.left) + dx, int(rect.top) + dy,
                   width, height, 0x0004 | 0x0010)

def ack(op, **extra):
    payload = {"ack": op}
    payload.update(extra)
    print(json.dumps(payload), flush=True)

_restore_last_rect = None
_restore_stable = 0

def ack_when_restored(attempt=0):
    global _restore_last_rect, _restore_stable
    iconic = bool(u.IsIconic(hwnd))
    visible = bool(u.IsWindowVisible(hwnd))
    enabled = bool(u.IsWindowEnabled(hwnd))
    zoomed = bool(u.IsZoomed(hwnd))
    cloaked = W.DWORD()
    cloak_ok = d.DwmGetWindowAttribute(hwnd, 14, C.byref(cloaked), C.sizeof(cloaked)) == 0
    frame = W.RECT()
    frame_ok = d.DwmGetWindowAttribute(hwnd, 9, C.byref(frame), C.sizeof(frame)) == 0
    rect = (int(frame.left), int(frame.top), int(frame.right), int(frame.bottom)) if frame_ok else None
    size_ok = rect is not None and rect[2] - rect[0] >= 180 and rect[3] - rect[1] >= 80
    ready = not iconic and visible and enabled and not zoomed and (not cloak_ok or not cloaked.value) and size_ok
    if ready and rect == _restore_last_rect:
        _restore_stable += 1
    else:
        _restore_stable = 0
    _restore_last_rect = rect
    if (ready and _restore_stable >= 3) or attempt >= 100:
        ack("restore", iconic=iconic, visible=visible, enabled=enabled,
            zoomed=zoomed, cloaked=bool(cloaked.value) if cloak_ok else False,
            stable=_restore_stable, frame=list(rect) if rect is not None else [])
        return
    root.after(15, lambda: ack_when_restored(attempt + 1))

def tick():
    while not inbox.empty():
        line = inbox.get_nowait()
        if line is None:
            root.destroy()
            return
        message = json.loads(line)
        op = message.get("op")
        if op == "move_by":
            move_by(message)
        elif op == "minimize":
            root.iconify()
        elif op == "restore":
            root.deiconify()
            root.state("normal")
            root.update_idletasks()
            u.ShowWindow(hwnd, 9)  # SW_RESTORE
            root.after(15, ack_when_restored)
            continue
        elif op == "maximize":
            root.state("zoomed")
        elif op == "close":
            root.destroy()
            return
        ack(op)
    root.after(15, tick)

threading.Thread(target=read, daemon=True).start()
root.after(15, tick)
root.after(60000, root.destroy)
root.mainloop()
