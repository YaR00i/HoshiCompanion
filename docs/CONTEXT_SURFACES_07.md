# Hoshi 0.7 — context motion and desktop surfaces

## Ownership

- `air_motion.gd` owns only screen-space jump/fall/landing routes.
- `context_pose.gd` adds temporary rig rotations for carry/jump/fall/land/portal
  and left/right side leaning. It must never mutate REST transforms or skin binds.
- `idle_life.gd` adds rare standing weight shifts, hand fidgets and shoulder settling.
  It owns no routes, foot targets or support placement and yields to user/context actions.
- `magic_door.gd` is app-owned procedural 3D geometry/shader; no image/network source.
- `surface_controller.gd` maps walking/leaning to the active support's local geometry.
- `shelf_playground.gd` still owns support lifecycle and external HWND tracking.
- `desktop_host.gd` remains the only owner of native companion-window placement and input pass-through.
- On Windows, `tools/window_input_passthrough.py` may change only `WS_EX_TRANSPARENT` on Hoshi's own HWND;
  Godot keeps ownership of layered/composition styles. The helper must not force `WS_EX_LAYERED` or
  `SWP_FRAMECHANGED` during hover transitions, because rebuilding transparent composition can flash the HWND.
  It verifies the HWND belongs to its parent Godot process, installs no hooks and enumerates no windows.
- Precise desktop hit testing samples alpha only from Hoshi's own 3D SubViewport. It never reads
  desktop/application pixels. Transparent window space passes input through; visible Hoshi captures it.

## Surface rules

- A top-edge walking route is local to the support, not the virtual desktop.
- Autonomous support motion must preflight a real route/contact before changing posture; an invalid
  route must remain seated instead of producing a visible stand-then-immediate-resit no-op.
- On external supports, normal/playful autonomy may briefly visit a valid side frame and return;
  it may also rarely choose to leave the support and continue life on the floor.
- If the support moves while walking, placement is recomputed from the current support rect.
- Side leaning is allowed only when the complete companion window fits in the usable area
  and the vertical frame crosses the configured body contact height.
- App-owned and external supports keep their existing close/minimize/unsafe-geometry exits.
- Manual user actions override autonomous surface actions.
- `SurfaceController` must keep reverse references through `WeakRef`; do not create
  app → playground → surface → app reference cycles.
- When walking on a support, the normal floor host-walk mapping must not also move the window.

## Cinematic rules

- Door rendering stays inside Hoshi's own 3D viewport, behind the avatar.
- Startup/outro keeps pointer input pass-through while the cinematic runs. If the native helper
  is unavailable, the old expanded polygon is used only as a compatibility fallback.
- Normal close waits for support return/standing and portal outro before quitting.
- Forced OS process termination is not expected to play an outro.

## Acceptance

Run:
- `python tools/dev.py check`
- `python tools/dev.py shelf_windows`
- `python tools/dev.py external_windows`
- `python tools/dev.py cozy_windows`
- `python tools/dev.py context_views`
- `python tools/dev.py edge_views`

External-window tests operate only on the dedicated Tk fixture process and never capture
pixels from pre-existing user applications.
