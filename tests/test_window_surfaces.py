"""Local-only geometry inspector checks; native test uses its own Tk window."""
from __future__ import annotations

from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from window_surfaces import candidates, inspect


def test_filter() -> None:
    result = candidates({'rect': [100, 200, 600, 400], 'visited': 10,
                         'elements': [
                             {'kind': 'Button', 'rect': [120, 280, 180, 30]},
                             {'kind': 'Button', 'rect': [120, 280, 180, 30], 'name': 'private'},
                             {'kind': 'Text', 'rect': [130, 300, 400, 30], 'name': 'private'},
                             {'kind': 'Pane', 'rect': [90, 500, 220, 40]},
                         ]})
    assert result['visible_count'] == 2, result
    assert result['source'] == 'structure', result
    assert result['candidates'][0] == {'x': 20, 'y': 80, 'width': 180, 'kind': 'Button'}
    assert 'private' not in str(result)


def test_display_covers_full_list() -> None:
    result = candidates({'rect': [0, 0, 600, 1200], 'elements': [
        {'kind': 'ListItem', 'rect': [80, 30 + index * 24, 180, 20]}
        for index in range(40)
    ]})
    assert result['visible_count'] == 40, result
    assert len(result['candidates']) == 24, result
    assert result['candidates'][0]['y'] == 30, result
    assert result['candidates'][-1]['y'] == 30 + 39 * 24, result


def test_ledge_mode_frame_and_bars() -> None:
    """Seat search keeps full-width bars and reports lines relative to the visible frame."""
    payload = {'rect': [93, 193, 614, 414], 'frame': [100, 200, 600, 400], 'elements': [
        {'kind': 'ToolBar', 'rect': [100, 260, 600, 44]},
        {'kind': 'Pane', 'rect': [100, 200, 600, 400]},
    ] + [{'kind': 'ListItem', 'rect': [120, 320 + index * 2, 200, 16]} for index in range(40)]}
    diagnostic = candidates(payload)
    assert all(line['kind'] != 'ToolBar' for line in diagnostic['candidates'])
    seat = candidates(payload, ledge_mode=True)
    bar = [line for line in seat['candidates'] if line['kind'] == 'ToolBar']
    assert bar and bar[0]['x'] == 2 and bar[0]['y'] == 60, bar
    assert seat['window'] == [600, 400]
    assert all(line['kind'] != 'Pane' for line in seat['candidates'])


def test_process_name_is_file_name_only() -> None:
    from window_identity import clean_name
    assert clean_name(r'C:\Program Files\Blender Foundation\Blender 4.5\blender.exe') == 'blender.exe'
    assert clean_name('Discord.exe') == 'discord.exe'
    assert len(clean_name('x' * 300)) == 64


def test_native_fixture() -> None:
    if sys.platform != 'win32':
        return
    script = '''import ctypes as C, tkinter as tk
from ctypes import wintypes as W
root = tk.Tk()
root.title("Hoshi surface inspection fixture")
root.geometry("650x420+120+120")
tk.Button(root, text="Wide test button", width=28).pack(pady=36)
tk.Frame(root, width=360, height=42, bg="#ddd8ee").pack()
root.update()
u = C.WinDLL("user32")
u.GetAncestor.argtypes = [W.HWND, W.UINT]
u.GetAncestor.restype = W.HWND
print(int(u.GetAncestor(root.winfo_id(), 2)), flush=True)
root.after(12000, root.destroy)
root.mainloop()
'''
    fixture = subprocess.Popen([sys.executable, '-u', '-c', script],
                               stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    try:
        hwnd = int(fixture.stdout.readline().strip())
        result = inspect(hwnd)
        assert result['ok'] and result['window'][0] >= 600, result
        assert result['visited'] >= 1, result
        assert result['visible_count'] >= 1, result
    finally:
        if fixture.poll() is None:
            fixture.terminate()
        fixture.communicate(timeout=5)


if __name__ == '__main__':
    test_filter()
    test_display_covers_full_list()
    test_ledge_mode_frame_and_bars()
    test_process_name_is_file_name_only()
    test_native_fixture()
    print('HOSHI_WINDOW_SURFACES_RESULT checks=5 failures=0')
