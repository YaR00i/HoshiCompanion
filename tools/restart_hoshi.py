"""Restart Hoshi with the current project files (button «Перезапустить Хоши»).

Two steps, so a broken new version never leaves the user without Hoshi:

    python tools/restart_hoshi.py check <engine> <project> <log>
        Headless import of the project, exactly like tools/launch.cmd does
        before a start. Prints one JSON line {"ok": bool, "error": "..."}.
        The running Hoshi stays untouched; if scripts do not parse, she does
        not close.

    python tools/restart_hoshi.py relaunch <pid> <engine> <project> -- <args...>
        Waits until process <pid> (the old Hoshi) exits, at most 120 s, then
        starts <engine> <args...> in <project> as a detached process. If the
        old Hoshi does not exit in time, nothing is started.

Only the Godot executable Hoshi itself runs from is started, with the same
arguments it was started with; nothing is downloaded.
"""
from __future__ import annotations

import ctypes as C
from ctypes import wintypes as W
import json
import subprocess
import sys
from pathlib import Path

IMPORT_TIMEOUT = 180
EXIT_TIMEOUT_MS = 120_000
ERROR_MARKERS = ('SCRIPT ERROR:', 'Parse Error:', 'Failed to load script')
SYNCHRONIZE = 0x00100000
WAIT_OBJECT_0 = 0
DETACHED_PROCESS = 0x00000008
CREATE_NEW_PROCESS_GROUP = 0x00000200


def check(engine: str, project: str, log: str) -> dict:
    if not Path(engine).is_file():
        return {'ok': False, 'error': 'no_engine'}
    Path(log).parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run([engine, '--headless', '--editor', '--path', project, '--import', '--log-file', log],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=IMPORT_TIMEOUT,
                       creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    except subprocess.TimeoutExpired:
        return {'ok': False, 'error': 'import_timeout'}
    except OSError:
        return {'ok': False, 'error': 'import_failed'}
    try:
        text = Path(log).read_text(encoding='utf-8', errors='replace')
    except OSError:
        return {'ok': False, 'error': 'no_log'}
    if any(marker in text for marker in ERROR_MARKERS):
        return {'ok': False, 'error': 'script_errors'}
    return {'ok': True}


def wait_for_exit(pid: int) -> bool:
    kernel = C.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
    kernel.OpenProcess.restype = W.HANDLE
    kernel.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
    kernel.WaitForSingleObject.restype = W.DWORD
    kernel.CloseHandle.argtypes = [W.HANDLE]
    handle = kernel.OpenProcess(SYNCHRONIZE, False, pid)
    if not handle:
        return True  # already gone
    try:
        return kernel.WaitForSingleObject(handle, EXIT_TIMEOUT_MS) == WAIT_OBJECT_0
    finally:
        kernel.CloseHandle(handle)


def relaunch(pid: int, engine: str, project: str, args: list[str]) -> int:
    if not wait_for_exit(pid):
        return 1
    subprocess.Popen([engine, *args], cwd=project, close_fds=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     creationflags=DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP)
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 5 and argv[1] == 'check':
        result = check(argv[2], argv[3], argv[4])
        print(json.dumps(result), flush=True)
        return 0 if result['ok'] else 1
    if len(argv) >= 6 and argv[1] == 'relaunch' and argv[5] == '--' and argv[2].isdigit():
        return relaunch(int(argv[2]), argv[3], argv[4], argv[6:])
    print('usage: restart_hoshi.py check <engine> <project> <log> | '
          'relaunch <pid> <engine> <project> -- <args...>', file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
