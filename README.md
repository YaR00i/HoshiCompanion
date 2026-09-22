# Hoshi Companion

A small local 3D desktop companion for Windows, built with Godot and VRM 1.0.

Current development version: **0.7**.

Hoshi can idle, blink, follow attention, walk, sit on the floor or on application
edges, wave, doze, dangle her legs, lean back on her hands, and look down. She can
sit on an app-owned shelf, a compact cozy corner, or an ordinary selected window.

Version 0.7 adds a context-motion layer: pickup/carry pose, falling and landing,
jumping to supports instead of teleporting, a procedural magical star-door for
arrival/departure, walking along a support edge, and contextual leaning against
left/right vertical window frames when the geometry safely permits it.

Version 0.6 autonomous resting places are retained. In “Windows → cozy corner” mode
Hoshi performs one bounded geometry-only search when she decides to rest, chooses
a safe nearby top edge on her current monitor, and falls back to her own cozy
corner when no suitable edge exists. This is not continuous monitoring.

The repository contains **source code only**. The development VRM is intentionally
not public. See [assets/README.md](assets/README.md) for local setup.

## Quick start

1. Install Godot 4.5.1+ (development is tested on Godot 4.7.2).
2. Put your local compatible VRM at `assets/Hoshi_v1.vrm`.
3. Open `project.godot`, or on Windows run `PREVIEW_WINDOWS.bat`.
4. Use `START_WINDOWS.bat` for the transparent desktop companion.

External-window features use geometry/state only. Autonomous discovery is explicit
and bounded; neither mode reads window titles, page text, screenshots, microphone,
camera or network content.

Russian documentation: [README_RU.md](README_RU.md).
Manual 0.7 acceptance: [docs/ACCEPTANCE_07_RU.md](docs/ACCEPTANCE_07_RU.md).
Source license: [LICENSE.txt](LICENSE.txt). Model notice: [MODEL_NOTICE.txt](MODEL_NOTICE.txt).
