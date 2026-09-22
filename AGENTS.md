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
- shelf_playground.gd owns app supports and manual/automatic geometry-only external supports.
- desktop_host.gd is the only owner of native companion-window positioning.
- tools/window_geometry.py is read-only: manual mode probes one selected HWND.
- Smart-rest mode may perform one bounded geometry-only top-level candidate search.

## Invariants
- Keep the current development model local at assets/Hoshi_v1.vrm; never add it to Git.
- Never rewrite source VRM bytes, REST transforms, skin binds or morph data as an animation fix.
- Walking and seated lower-body ownership must never overlap.
- Manual user actions override autonomy; canceled routes must never resume unexpectedly.
- Closing/minimizing an active support returns the companion to a safe floor state.
- Manual external-window selection must not read titles, pixels, page content, microphone or network data.
- A known explicit HWND may retry the same geometry-only bind at most twice for transient restore-state errors; never turn retry into new window discovery.
- Current full regression suite is calibrated to the local development Hoshi model.

## 0.6 living places
- Read docs/LIVING_06.md before changing autonomous support selection.
- place_director.gd requests rare rests; it must never enumerate or inspect windows itself.
- place_mode values: off / cozy / smart. Manual actions always override autonomous rest.
- Smart search is one-shot, current-monitor-only, capped at 256 windows and ~0.45s.
- window_choice.py may use geometry/state/Z-order only; never add titles, text or pixels.
- No suitable external edge must fall back to the app-owned cozy window.
- Closing the cozy window manually pauses autonomous place requests for 180 seconds.
- Existing manual four-second window picker remains independent and must keep working.
- dev.py check includes place-director checks; also run shelf_windows, external_windows,
  cozy_windows and edge_views before merging changes to support/pose arbitration.

## Living roadmap
- Read docs/ROADMAP_LIVING_RU.md before adding new autonomous behavior systems.
- Prefer a small intent planner with short plans over a large generic behavior framework.
- intent_planner.gd is initially shadow-only: it may choose/record intent but must not move windows or bones.
- Intent cooldown/novelty time belongs to intent_planner.gd; keep rejection reasons inspectable for deterministic tests.
- Floor and surface intent execution are coordinated by companion.gd and must wait for real controller completion before advancing a step.
- A controller-busy frame must not erase its own active intent; only explicit interruption/support loss may cancel it.
- SurfaceController owns all support geometry/movement; IntentPlanner may only choose among preflighted surface actions.
- Planner mini-scenes may request existing idle_life/edge_life gestures, but those drivers keep sole ownership of their bone rotations.
- While a planner scene is active, ambient random micro-gestures must yield so two autonomous pose choices do not overlap.
- BehaviorDirector may provide gaze while floor decisions are disabled; do not let it emit a second autonomous floor action in parallel.
- Existing motion/pose controllers keep ownership; planners choose actions but do not animate bones or place windows directly.
- User input always interrupts autonomous intent immediately.

## 0.7 context motion and desktop surfaces
- Read docs/CONTEXT_SURFACES_07.md before changing carry/jump/fall/portal/surface behavior.
- air_motion.gd owns screen-space jump/fall/landing only; it must not edit rig bones. It may expose normalized phase, screen velocity and impact strength as read-only pose inputs.
- context_pose.gd owns temporary carry/jump/fall/land/portal/side-lean overlays and may use AirMotion phase/velocity/impact, but never changes trajectory.
- idle_life.gd owns rare standing micro-gestures only; it must never take foot placement or locomotion ownership.
- magic_door.gd must remain app-owned procedural rendering with no external assets/network.
- surface_controller.gd owns support-local walking and vertical side leaning.
- SurfaceController reverse links to app/playground must remain WeakRef to avoid resource cycles.
- A support-local walk must suppress normal floor host.walk_to mapping.
- Autonomous surface actions must validate geometry before standing; never animate a stand just to
  discover the route is invalid and sit back at the same point.
- Automatic floor walks do not imply automatic sitting; BehaviorDirector owns that choice.
- Side leaning is geometry-gated; never fake contact when the companion window cannot fit.
- Windows precise input uses only Hoshi's own HWND plus alpha from Hoshi's own SubViewport;
  no global hooks, foreign-window enumeration or desktop pixel reads are allowed.
- The Win32 input helper must verify that its target HWND belongs to its parent Godot process.
- Hover click-through may toggle only WS_EX_TRANSPARENT; never rebuild Godot's layered-window composition per pointer transition.
- Startup/outro stays pointer-pass-through; polygon masking is compatibility fallback only.
- Normal close should return from support, stand, play portal outro, then quit.
- Keep the 0.6 privacy contract: geometry/state/Z-order only for external windows.
- Release acceptance: check + shelf_windows + external_windows + cozy_windows +
  context_views + edge_views; external tests must stay fixture-only.
- Native fixture restore tests must wait for fixture acknowledgement of a non-iconic visible HWND; do not use fixed sleeps as restore readiness.
