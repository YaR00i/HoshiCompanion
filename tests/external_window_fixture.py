"""Isolated native test window in a separate process; moves only itself.
No user documents/apps are opened or modified. stdin EOF or 45s destroys it.
"""
import ctypes as C
from ctypes import wintypes as W
import json
import queue
import sys
import threading
import tkinter as tk

u = C.WinDLL('user32')
u.SetThreadDpiAwarenessContext.argtypes = [W.HANDLE]
u.SetThreadDpiAwarenessContext.restype = W.HANDLE
u.SetThreadDpiAwarenessContext(C.c_void_p(-2))
u.GetAncestor.argtypes = [W.HWND, W.UINT]
u.GetAncestor.restype = W.HWND
root = tk.Tk()
root.title('Hoshi - isolated external window test')
vx, vy = -int(sys.argv[3]), -int(sys.argv[4])
x, y = int(sys.argv[1]) + vx, int(sys.argv[2]) + vy
window_height = {'value': int(sys.argv[5]) if len(sys.argv) > 5 else 280}
root.geometry(f"640x{window_height['value']}{x:+d}{y:+d}")
root.configure(bg='#eee5f1')
tk.Label(root, text='HOSHI / EXTERNAL WINDOW TEST', bg='#eee5f1', font=('Segoe UI', 18)).pack(pady=45)
tk.Label(root, text='Separate process. No personal content.', bg='#eee5f1', font=('Segoe UI', 12)).pack()
root.update()
print(json.dumps({'hwnd': str(u.GetAncestor(root.winfo_id(), 2))}), flush=True)
inbox = queue.Queue(maxsize=20)
def read():
    for line in sys.stdin:
        inbox.put(line)
    inbox.put(None)

def tick():
    while not inbox.empty():
        line = inbox.get_nowait()
        if line is None:
            root.destroy()
            return
        message = json.loads(line)
        op = message.get('op')
        if op == 'move':
            nx, ny = int(message['x']) + vx, int(message['y']) + vy
            window_height['value'] = int(message.get('h', window_height['value']))
            root.geometry(f"{int(message['w'])}x{window_height['value']}{nx:+d}{ny:+d}")
        elif op == 'minimize':
            root.iconify()
        elif op == 'restore':
            root.deiconify()
            root.state('normal')
        elif op == 'maximize':
            root.state('zoomed')
        elif op == 'close':
            root.destroy()
            return
        print(json.dumps({'ack': op}), flush=True)
    root.after(15, tick)

threading.Thread(target=read, daemon=True).start()
root.after(15, tick)
root.after(45000, root.destroy)
root.mainloop()
