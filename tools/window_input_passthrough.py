"""Own-HWND Windows click-through helper for Hoshi Companion.

The process accepts only the HWND of its direct parent Godot process, never
enumerates windows and never installs hooks. stdin controls WS_EX_TRANSPARENT;
EOF or "stop" restores the two style bits changed by this helper.
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
STYLE_BITS = WS_EX_TRANSPARENT | WS_EX_LAYERED
SWP_NOSIZE = 0x0001
SWP_NOMOVE = 0x0002
SWP_NOZORDER = 0x0004
SWP_NOACTIVATE = 0x0010
SWP_FRAMECHANGED = 0x0020

u = C.WinDLL("user32", use_last_error=True)
u.IsWindow.argtypes = [W.HWND]
u.IsWindow.restype = W.BOOL
u.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
u.GetWindowThreadProcessId.restype = W.DWORD
u.GetWindowLongPtrW.argtypes = [W.HWND, C.c_int]
u.GetWindowLongPtrW.restype = C.c_ssize_t
u.SetWindowLongPtrW.argtypes = [W.HWND, C.c_int, C.c_ssize_t]
u.SetWindowLongPtrW.restype = C.c_ssize_t
u.SetWindowPos.argtypes = [W.HWND, W.HWND, C.c_int, C.c_int, C.c_int, C.c_int, W.UINT]
u.SetWindowPos.restype = W.BOOL

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

def apply_style(style: int) -> None:
    u.SetWindowLongPtrW(hwnd, GWL_EXSTYLE, C.c_ssize_t(style))
    u.SetWindowPos(
        hwnd, W.HWND(0), 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
    )

def set_passthrough(active: bool) -> None:
    current = int(u.GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
    if active:
        wanted = current | WS_EX_LAYERED | WS_EX_TRANSPARENT
    else:
        # Keep WS_EX_LAYERED while Hoshi is alive; toggling only TRANSPARENT is
        # both cheaper and avoids disturbing Godot's transparent composition.
        wanted = current & ~WS_EX_TRANSPARENT
        wanted |= WS_EX_LAYERED
    if wanted != current:
        apply_style(wanted)

def restore() -> None:
    if not u.IsWindow(hwnd):
        return
    current = int(u.GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
    wanted = (current & ~STYLE_BITS) | (original_style & STYLE_BITS)
    if wanted != current:
        apply_style(wanted)

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
