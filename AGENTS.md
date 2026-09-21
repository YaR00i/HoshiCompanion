# Hoshi Companion — development handoff

## Safety and repository rules
- This repository is public source code. Never commit VRM files, user avatars, textures,
  local logs, .workspace, godot_path.txt, python_path.txt or machine-specific data.
- assets/*.vrm and docs/MODEL_METADATA.json are intentionally ignored.
- Do not change global Git configuration, PATH, registry, security settings or autostart.
- Never publish a build containing a local avatar unless its separate license allows it.
- Work only on processes/files belonging to this project; never kill unrelated Godot/Python processes.

## Engine and checks
- Read godot_path.txt when present; otherwise use a user-selected Godot executable.
- Development is tested on Godot 4.7.2; project baseline is Godot 4.5.1+.
- Use `python tools/dev.py check` after code changes.
- A successful runtime suite must emit its HOSHI_*_RESULT marker with failures=0.
- Headless success does not prove Windows transparency, native-window composition or visual quality.
- Use bounded app-owned captures; never capture unrelated desktop windows for tests.

## Architecture
- companion.gd coordinates state, behavior, UI and desktop-window actions.
- avatar_stage.gd owns the 3D viewport and drivers.
- vrm_source.gd / expression_driver.gd own the working VRM/morph binding.
- locomotion.gd + gait_driver.gd own horizontal routes and lower-body walking IK.
- posture_controller.gd + posture_driver.gd own floor sit/stand transitions.
- edge_pose.gd + edge_life.gd own seated-on-edge pose and small activities.
- shelf_playground.gd owns support lifecycle for the app shelf and manual selected window.
- desktop_host.gd is the only owner of native companion-window positioning.
- tools/window_geometry.py is opt-in and read-only: one selected HWND, geometry/state only.

## Invariants
- Keep the current development model local at assets/Hoshi_v1.vrm; never add it to Git.
- Never rewrite source VRM bytes, REST transforms, skin binds or morph data as an animation fix.
- Walking and seated lower-body ownership must never overlap.
- Manual user actions override autonomy; canceled routes must never resume unexpectedly.
- Closing/minimizing an active support returns the companion to a safe floor state.
- Manual external-window selection must not read titles, pixels, page content, microphone or network data.
- Current full regression suite is calibrated to the local development Hoshi model.
