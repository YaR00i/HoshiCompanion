# Hoshi Companion

A small local 3D desktop companion for Windows, built with Godot and VRM 1.0.

Current development version: **0.6**.

Hoshi can idle, blink, follow attention, walk, sit on the floor or an edge, wave,
doze, dangle her legs, lean back on her hands, and look down. She can sit on an
app-owned shelf, a compact cozy corner, or a normal window selected manually.

Version 0.6 adds opt-in autonomous resting places. In “Windows → cozy corner” mode
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

External-window features read geometry/state only. Autonomous discovery is enabled
only by its explicit setting and is bounded; neither mode reads window titles,
page text, screenshots, microphone, camera or network content.

Russian documentation: [README_RU.md](README_RU.md).
Source license: [LICENSE.txt](LICENSE.txt). Model notice: [MODEL_NOTICE.txt](MODEL_NOTICE.txt).
