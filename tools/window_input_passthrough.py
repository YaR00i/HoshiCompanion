"""Own-HWND Windows click-through helper for Hoshi Companion.

The process accepts only the HWND of its direct parent Godot process, never
enumerates windows and never installs hooks. It changes only WS_EX_TRANSPARENT;
Godot remains the sole owner of layered/transparent composition.
EOF or "stop" restores the original WS_EX_TRANSPARENT bit.
"""
from __future__ import annotations
import ctypes as C
from ctypes import wintypes as W
import json
import os
import sys

GWL_EXSTYLE = -20
WS_EX_TRANSPARENT = 0x00000020

u = C.WinDLL("user32", use_last_error=True)
u.IsWindow.argtypes = [W.HWND]
u.IsWindow.restype = W.BOOL
u.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
u.GetWindowThreadProcessId.restype = W.DWORD
u.GetWindowLongPtrW.argtypes = [W.HWND, C.c_int]
u.GetWindowLongPtrW.restype = C.c_ssize_t
u.SetWindowLongPtrW.argtypes = [W.HWND, C.c_int, C.c_ssize_t]
u.SetWindowLongPtrW.restype = C.c_ssize_t

if len(sys.argv) != 2:
    raise SystemExit("usage: window_input_passthrough.py HWND")

hwnd = W.HWND(int(sys.argv[1]))
if not u.IsWindow(hwnd):
    raise SystemExit("invalid Hoshi HWND")

owner_pid = W.DWORD()
u.GetWindowThreadProcessId(hwnd, C.byref(owner_pid))
if int(owner_pid.value) != int(os.getppid()):
    raise SystemExit("refusing HWND not owned by parent Godot process")

original_style = int(u.GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
original_passthrough = bool(original_style & WS_EX_TRANSPARENT)

def set_passthrough(active: bool) -> None:
    """Toggle only input transparency.

    Do not touch WS_EX_LAYERED and do not send SWP_FRAMECHANGED: both are owned
    by Godot's transparent-window compositor. Rebuilding those styles on every
    pointer boundary can flash the whole HWND for a frame.
    """
    if not u.IsWindow(hwnd):
        return
    current = int(u.GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
    wanted = (
        current | WS_EX_TRANSPARENT
        if active
        else current & ~WS_EX_TRANSPARENT
    )
    if wanted != current:
        u.SetWindowLongPtrW(hwnd, GWL_EXSTYLE, C.c_ssize_t(wanted))

def restore() -> None:
    if not u.IsWindow(hwnd):
        return
    current = int(u.GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
    if original_passthrough:
        wanted = current | WS_EX_TRANSPARENT
    else:
        wanted = current & ~WS_EX_TRANSPARENT
    if wanted != current:
        u.SetWindowLongPtrW(hwnd, GWL_EXSTYLE, C.c_ssize_t(wanted))

try:
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        message = json.loads(raw)
        op = message.get("op")
        if op == "passthrough":
            set_passthrough(bool(message.get("active", False)))
        elif op == "stop":
            break
finally:
    restore()
