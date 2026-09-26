"""Own-HWND Windows click-through helper for Hoshi Companion.

The process accepts only the HWND of its direct parent Godot process, never
enumerates windows and never installs hooks. It enables WS_EX_LAYERED once for
cross-process hit testing; pointer transitions change only WS_EX_TRANSPARENT.
EOF or "stop" restores both original bits.
"""
from __future__ import annotations
import ctypes as C
from ctypes import wintypes as W
import json
import os
import sys

GWL_EXSTYLE = -20
WS_EX_TRANSPARENT = 0x00000020
WS_EX_LAYERED = 0x00080000

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
original_layered = bool(original_style & WS_EX_LAYERED)

def prepare() -> None:
    """Enable layered hit testing once after Godot creates or restyles the HWND."""
    if not u.IsWindow(hwnd):
        return
    current = int(u.GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
    if not current & WS_EX_LAYERED:
        u.SetWindowLongPtrW(hwnd, GWL_EXSTYLE, C.c_ssize_t(current | WS_EX_LAYERED))

prepare()

def set_passthrough(active: bool) -> None:
    """Toggle only input transparency.

    Do not rebuild WS_EX_LAYERED or send SWP_FRAMECHANGED here. Rebuilding
    composition on every pointer boundary can flash the whole HWND.
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
    if original_layered:
        wanted |= WS_EX_LAYERED
    else:
        wanted &= ~WS_EX_LAYERED
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
        elif op == "prepare":
            prepare()
            set_passthrough(bool(message.get("active", False)))
        elif op == "stop":
            break
finally:
    restore()
