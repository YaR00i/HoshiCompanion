"""Which program owns a window: executable file name only (e.g. "explorer.exe").

Allowed by the user on 2026-09-27 so Hoshi can choose how to look into a window
(structure, browser extension, Blender add-on) and later remember taught ledges
per program. Never reads window titles, command lines, paths beyond the file
name, text, pixels or anything inside the process.
"""
from __future__ import annotations

import ctypes as C
from ctypes import wintypes as W
import ntpath

PROCESS_QUERY_LIMITED_INFORMATION = 0x1000


def process_name(pid: int) -> str:
    if not pid or not hasattr(C, 'WinDLL'):
        return ''
    kernel = C.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
    kernel.OpenProcess.restype = W.HANDLE
    kernel.QueryFullProcessImageNameW.argtypes = [W.HANDLE, W.DWORD, W.LPWSTR, C.POINTER(W.DWORD)]
    kernel.QueryFullProcessImageNameW.restype = W.BOOL
    kernel.CloseHandle.argtypes = [W.HANDLE]
    kernel.CloseHandle.restype = W.BOOL
    handle = kernel.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return ''
    try:
        size = W.DWORD(1024)
        buffer = C.create_unicode_buffer(1024)
        if not kernel.QueryFullProcessImageNameW(handle, 0, buffer, C.byref(size)):
            return ''
        return clean_name(buffer.value)
    finally:
        kernel.CloseHandle(handle)


def clean_name(path: str) -> str:
    """Keep only a short lowercase executable name; drop folders."""
    name = ntpath.basename(str(path)).strip().lower()
    return ''.join(ch for ch in name if ch.isalnum() or ch in '._- ')[:64]
