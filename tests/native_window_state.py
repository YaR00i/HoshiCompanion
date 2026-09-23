"""Read only visibility of a verified window owned by the calling Hoshi process."""
from __future__ import annotations

import ctypes
import json
import sys
from ctypes import wintypes


def main() -> int:
    hwnd = int(sys.argv[1])
    expected_pid = int(sys.argv[2])
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    user32.IsWindow.argtypes = [wintypes.HWND]
    user32.IsWindow.restype = wintypes.BOOL
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.IsWindowVisible.restype = wintypes.BOOL
    owner = wintypes.DWORD()
    valid = bool(user32.IsWindow(hwnd))
    if valid:
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
    result = {"valid": valid, "owned": valid and owner.value == expected_pid,
              "visible": valid and owner.value == expected_pid and bool(user32.IsWindowVisible(hwnd))}
    print(json.dumps(result))
    return 0 if result["owned"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
