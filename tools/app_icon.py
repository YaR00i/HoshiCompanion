"""Icon of a program for the phone remote (instead of 🚀 on «Мои действия»).

    python tools/app_icon.py <path-or-AppID> <out.png> [size]

<path> — a program, shortcut, file or folder; an AppID from the Start menu is
given as "shell:AppsFolder\\<AppID>" (Store apps like Claude, Chrome apps like
YouTube). Uses the same picture Windows shows (IShellItemImageFactory), writes
a PNG with transparency. Only the icon picture is read — nothing else.
Prints {"ok": true} or {"ok": false, "error": "..."}.
"""
from __future__ import annotations

import ctypes as C
from ctypes import wintypes as W
import json
import struct
import sys
import uuid
import zlib

SIIGBF_BIGGERSIZEOK = 0x1
SIIGBF_ICONONLY = 0x4
IID_IShellItemImageFactory = '{BCC18B79-BA16-442F-80C4-8A59C30C463B}'


class GUID(C.Structure):
    _fields_ = [('d1', W.DWORD), ('d2', W.WORD), ('d3', W.WORD), ('d4', C.c_ubyte * 8)]

    @classmethod
    def parse(cls, text: str) -> 'GUID':
        return cls.from_buffer_copy(uuid.UUID(text).bytes_le)


class SIZE(C.Structure):
    _fields_ = [('cx', C.c_long), ('cy', C.c_long)]


class BITMAP(C.Structure):
    _fields_ = [('bmType', C.c_long), ('bmWidth', C.c_long), ('bmHeight', C.c_long), ('bmWidthBytes', C.c_long),
                ('bmPlanes', W.WORD), ('bmBitsPixel', W.WORD), ('bmBits', C.c_void_p)]


class BITMAPINFOHEADER(C.Structure):
    _fields_ = [('biSize', W.DWORD), ('biWidth', C.c_long), ('biHeight', C.c_long), ('biPlanes', W.WORD),
                ('biBitCount', W.WORD), ('biCompression', W.DWORD), ('biSizeImage', W.DWORD),
                ('biXPelsPerMeter', C.c_long), ('biYPelsPerMeter', C.c_long), ('biClrUsed', W.DWORD), ('biClrImportant', W.DWORD)]


def png(width: int, height: int, rgba: bytes) -> bytes:
    """Pure: RGBA pixels (top row first) -> PNG bytes."""
    rows = b''.join(b'\x00' + rgba[y * width * 4:(y + 1) * width * 4] for y in range(height))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))


def icon_png(target: str, size: int) -> bytes:
    ole32, shell32, gdi32, user32 = C.WinDLL('ole32'), C.WinDLL('shell32'), C.WinDLL('gdi32'), C.WinDLL('user32')
    ole32.CoInitializeEx(None, 0x2)
    if not target.lower().startswith('shell:'):
        target = target.replace('/', '\\')  # Windows wants backslashes here
    shell32.SHCreateItemFromParsingName.argtypes = [W.LPCWSTR, C.c_void_p, C.POINTER(GUID), C.POINTER(C.c_void_p)]
    shell32.SHCreateItemFromParsingName.restype = C.c_long
    factory = C.c_void_p()
    hr = shell32.SHCreateItemFromParsingName(target, None, C.byref(GUID.parse(IID_IShellItemImageFactory)), C.byref(factory))
    if hr < 0 or not factory:
        raise OSError('not found (0x%08X)' % (hr & 0xFFFFFFFF))
    vtable = C.cast(factory, C.POINTER(C.POINTER(C.c_void_p)))[0]
    get_image = C.WINFUNCTYPE(C.c_long, C.c_void_p, SIZE, C.c_int, C.POINTER(W.HBITMAP))(vtable[3])
    release = C.WINFUNCTYPE(C.c_ulong, C.c_void_p)(vtable[2])
    bitmap = W.HBITMAP()
    try:
        hr = get_image(factory, SIZE(size, size), SIIGBF_ICONONLY | SIIGBF_BIGGERSIZEOK, C.byref(bitmap))
        if hr < 0 or not bitmap:
            raise OSError('no image (0x%08X)' % (hr & 0xFFFFFFFF))
    finally:
        release(factory)
    try:
        info = BITMAP()
        gdi32.GetObjectW.argtypes = [W.HANDLE, C.c_int, C.c_void_p]
        gdi32.GetObjectW(bitmap, C.sizeof(info), C.byref(info))
        width, height = info.bmWidth, abs(info.bmHeight)
        header = BITMAPINFOHEADER(C.sizeof(BITMAPINFOHEADER), width, -height, 1, 32, 0, 0, 0, 0, 0, 0)
        pixels = (C.c_ubyte * (width * height * 4))()
        user32.GetDC.restype = W.HDC
        user32.GetDC.argtypes = [W.HWND]
        user32.ReleaseDC.argtypes = [W.HWND, W.HDC]
        gdi32.DeleteObject.argtypes = [W.HANDLE]
        dc = user32.GetDC(None)
        gdi32.GetDIBits.argtypes = [W.HDC, W.HBITMAP, W.UINT, W.UINT, C.c_void_p, C.c_void_p, W.UINT]
        gdi32.GetDIBits(dc, bitmap, 0, height, pixels, C.byref(header), 0)
        user32.ReleaseDC(None, dc)
    finally:
        gdi32.DeleteObject(bitmap)
    raw = bytes(pixels)
    out = bytearray(len(raw))
    has_alpha = any(raw[i] for i in range(3, len(raw), 4))
    for i in range(0, len(raw), 4):
        b, g, r, a = raw[i], raw[i + 1], raw[i + 2], raw[i + 3] if has_alpha else 255
        if 0 < a < 255:  # the picture comes premultiplied by alpha
            r, g, b = min(255, r * 255 // a), min(255, g * 255 // a), min(255, b * 255 // a)
        out[i:i + 4] = bytes((r, g, b, a))
    return png(width, height, bytes(out))


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4) or not hasattr(C, 'WinDLL'):
        print(json.dumps({'ok': False, 'error': 'usage: app_icon.py <path-or-shell:AppsFolder\\\\AppID> <out.png> [size]'}))
        return 2
    try:
        data = icon_png(argv[1], int(argv[3]) if len(argv) == 4 and argv[3].isdigit() else 96)
        with open(argv[2], 'wb') as handle:
            handle.write(data)
    except OSError as error:
        print(json.dumps({'ok': False, 'error': str(error)[:120]}))
        return 1
    print(json.dumps({'ok': True}))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
