# Hoshi Companion

A small local 3D desktop companion for Windows, built with Godot and VRM 1.0.

Current development version: **0.5.1**.

Hoshi can idle, blink, look at the cursor, walk along the usable screen edge,
sit on the floor, sit on the app-owned test shelf, attach manually to a selected
ordinary window, wave, doze, and use small seated activities such as dangling
her legs, leaning back on her hands, and looking down.

The repository contains **source code only**. The development VRM is intentionally
not public. See [assets/README.md](assets/README.md) for local setup.

## Quick start

1. Install Godot 4.5.1+ (development is tested on Godot 4.7.2).
2. Put your local compatible VRM at `assets/Hoshi_v1.vrm`.
3. Open `project.godot`, or on Windows run `PREVIEW_WINDOWS.bat`.
4. Use `START_WINDOWS.bat` for the transparent desktop companion.

The selected-window feature uses a short-lived local Python helper and reads only
window geometry/state for one explicitly selected window. It does not read window
titles, page text, screenshots, microphone, camera or network content.

Russian documentation: [README_RU.md](README_RU.md).
Source license: [LICENSE.txt](LICENSE.txt). Model notice: [MODEL_NOTICE.txt](MODEL_NOTICE.txt).
