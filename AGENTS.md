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
- companion.gd coordinates state, behavior, UI and desktop-window actions. It owns the frame
  loop and planner orchestration; focused helpers (WeakRef back to the app) own the rest:
  - desktop_input.gd — mouse/keyboard gestures (touch, pet, carry, cursor hang, wheel, menu, hotkeys);
  - companion_settings.gd — user://companion.cfg read/save and light/shading values;
  - session_lifecycle.gd — portal intro, return-then-outro close sequence, cinematic mask;
  - command_runner.gd — starting commands and planner-step completion (see Skeleton below).
  - support_port.gd — the only requests shelf_playground.gd / surface_controller.gd may make to the app
    (say, stop walking, switch to desktop, save settings, user_busy...). Supports may read shared body
    services (host, state, stage, air, walker) directly but must not call app private members, ui,
    director, places, planner or runner; test_commands.gd enforces this boundary.
  Keep thin compatibility wrappers (_press_active, _open_menu, _save_settings, _quit) for supports/tests.
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
- Exception approved by the user (2026-09-27): the owning executable FILE NAME only (tools/window_identity.py)
  for the selected/occupied window. Never paths, command lines, titles or element names/text.
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

## Skeleton: commands -> runner -> motions (read docs/SKELETON_RU.md)
- scripts/hoshi_commands.gd is the only list of commands. Menus, hotkeys, cozy/shelf windows,
  IntentPlanner steps and tests refer to commands by NAME ("wave", "edge_sway"), never by number.
- Each command declares `sources`: "user" (menu/keys, later phone/voice) and/or "auto" (Hoshi herself).
  Every IntentPlanner step must be a registered command with "auto"; test_commands.gd enforces it.
- scripts/command_runner.gd is the only place that starts a command and decides when a planner
  step is finished, for both sources. It asks owners (edge_life, idle_life, gait/posture,
  SurfaceController) and never rotates bones or moves windows itself.
- scripts/motion_library.gd lists every motion: "clip" (res://animations/, editable in
  scenes/animation_authoring_3d.tscn) or "code" (procedural for now). Commands link motions by id;
  the runner takes gesture names from the library instead of hard-coding them.
- menu_id is an internal PopupMenu detail kept equal to the historical numbers; -1 means no menu item.
  Legacy integers are still accepted by _on_action for compatibility only.
- Manual-command rules live in registry flags (pauses_places / keeps_intent / keeps_walk).
- New sources (phone remote, voice, AI, app adapters) must call companion.run_command(name) and
  must not invent new command paths or bypass the runner.

## Supports inside windows (read docs/SUPPORTS_RU.md)
- All support sources produce one candidate format {source, kind, x, y, width, confidence} in Hoshi
  pixels relative to the window; scripts/support_judge.gd is the single judge (width, room below,
  not the top edge, inside the window, confidence level auto/manual/show).
- An inner ledge is represented as a smaller support rect whose top is the line (Judge.ledge_rect);
  keep SurfaceController/solve_placement unaware of the source. Side leaning is only for the window top.
- Structure (UIA) ledges are "manual" level: used only when the user pointed at them. Do not let
  autonomy choose inner ledges before adapters and occlusion checks exist.
- test_supports.gd covers the judge, ledge geometry and the no-titles/no-text rule for window helpers.
- Rest mode "focus" (Моё окно → уголок): home is the cozy corner; FocusTracker + tools/window_focus.py
  report only the foreground HWND, executable file name and normal/maximized/fullscreen state, once a
  second, and only while this mode is on (user-approved 2026-09-27). All thresholds and go/stay
  decisions live in place_director.gd; companion.gd only executes them. Never add titles or hooks.

## Phone remote and app add-ons (read docs/REMOTE_RU.md)
- scripts/remote_bus.gd serves remote/remote.html (port 18770) and WebSocket (18771). Off by default;
  home-network peers only; phones must pair with a one-time 6-digit code; tokens live in companion.cfg.
- Phones may run only commands whose sources include "remote" (always a subset of "user") plus commands
  of connected add-ons ("app:<id>:<name>"). Hoshi commands go through app.run_command(), never around it.
- Add-ons connect only from 127.0.0.1 at /hoshi-adapter-v1 and declare commands/state (app_adapters.gd).
  Add-on commands run only on an explicit human press; autonomy must never trigger them.
- test_remote.gd covers pairing, refusals, routing to a stub add-on and cleanup.
- browser_extension/hoshi_apps: MV3 add-on for www.youtube.com only. youtube.js reads now-playing and
  presses player controls; worker.js keeps the single 127.0.0.1 adapter connection while a YouTube tab
  exists. Never add other sites, history, comments or account data without a new user decision.
  tests/extension/test_youtube_content.py checks youtube.js on a fake page (optional, needs Playwright).
- scripts/pc_actions.gd ("Мои действия", phone tab «Компьютер»): the list is edited only on the PC
  (menu → Пульт с телефона → Мои действия) and stored in user://pc_actions.json. Phones send only
  "pc:<id>" of saved actions and can never supply a path, program or arguments. Shutdown/restart need
  {"confirm": true} and use a 60 s delay with pc:cancel; system buttons are off by default.
  test_pc_actions.gd runs everything in dry_run.
  Kind "startapp" (added on the PC from Get-StartApps): target is a validated AppID, launched only as
  explorer.exe "shell:AppsFolder\<AppID>". pc_actions.app_for() maps actions to remote apps
  (mpc/youtube/claude) so the phone's app bar shows closed apps as launch icons (still "pc:<id>" only).
  Window placement (user-approved 2026-09-27): an action may have place {monitor, mode center|left|
  right|max, ask}. tools/window_place.py snapshots existing top-level windows (geometry/visibility/exe
  file name only, never titles/pixels), prints ready, Hoshi launches, then it moves only the NEW window
  of the expected exe (or that exe's foreground window for single-instance apps) once, re-checking once.
  The phone may pass {monitor, mode} only for actions with ask=true; values are clamped/enumerated.
  "reuse" (default on when window_exe is known): window_place.py place ... reuse first looks for an
  open window of that exe; if found it is brought forward (and placed) and nothing is launched.
  Program icons: tools/app_icon.py (IShellItemImageFactory, icon picture only) -> user://pc_icons/<id>.png,
  served at /pc_icon/<id>.png (id must be a saved action id); catalog items carry icon_url.
  Moving open windows (user-approved 2026-09-27): "pc:windows" refreshes a list via window_place.py
  list (exe file name, monitor, normal/maximized/minimized; never titles), sent to paired phones in
  state.windows; "pc:move" {hwnd, monitor, mode, front} and "pc:front" {hwnd} accept only an hwnd from
  that last list (front = topmost then not-topmost + SetForegroundWindow attempt; no input simulation). Monitors carry
  x/y/width/height for the screen map (monitor_map.gd on the PC, screenMap() on the phone).
  Quick menu has a «Пульт и компьютер» section (remote toggle, QR, my actions, sound, move window, restart).
- scripts/sound_outputs.gd ("Звук на пульте", card «Звук» on the main tab): which output devices the
  phone may switch to is chosen only on the PC (menu → Пульт с телефона → Звук на пульте), stored in
  user://sound_outputs.json. Phones send only "sound:<id>" of saved buttons, never a device id.
  tools/audio_devices.py (list / set) runs as a separate process; it switches only the console +
  multimedia default and never the communications default. Privacy (user-approved 2026-09-27):
  output device friendly names and which one is default only; never playing programs, sessions,
  volume or media. test_sound_outputs.gd runs in dry_run.
- scripts/mpc_adapter.gd: MPC-BE as a built-in add-on (peer -1 in app_adapters, "app:mpc:<name>").
  Talks only to its web interface at 127.0.0.1:13579, only while the remote is on and a phone is
  connected (1 s poll, 3 s probe when closed). Privacy (user-approved 2026-09-27): file NAME,
  position, duration, play state, player volume/mute only; never filepath/filedir. Commands only on a human press.
  test_mpc_adapter.gd and test_remote.gd keep mpc/sound in dry_run — tests never touch real apps.
- scripts/assistant_watch.gd + tools/claude_hook.py: Claude Code async command hooks (user-level
  ~/.claude/settings.json, user-approved 2026-09-27) post notes to 127.0.0.1:18772/assistant; the
  receiver accepts only loopback POST /assistant, keeps sessions in memory only and shows a built-in
  "claude" card (peer -2). Allowed data: event, session id, project FOLDER NAME (never the path),
  notification type/text, last assistant message. Never user prompts, transcripts or files.
  Hoshi closed => the hook silently exits. Tests use port 18872.
  Phone replies (user-approved 2026-09-27, a deliberate exception to "phones press only ready
  buttons"): a second Stop hook `claude_hook.py --wait` with asyncRewake holds POST {"event":"Wait"}
  open; "app:claude:reply" {text<=2000, session} releases it with the text, the hook exits 2 and
  Claude Code wakes Claude with it. UserPromptSubmit/SessionEnd/Hoshi exit release it empty.
  Media (user request 2026-09-27): claude_hook.media_in() lists existing media files (png/jpg/gif/
  webp/mp4/webm <=16 MB, max 8) that the answer itself names, never UNC/network paths; Hoshi maps them
  to random 32-hex ids served at GET /media/<id> on the remote HTTP port (streamed in chunks). The
  phone gets id/name/kind only, never paths; a new answer invalidates old ids.
  Permissions/questions (user-approved 2026-09-27): sync hooks `claude_hook.py --ask` on PermissionRequest
  and PreToolUse(AskUserQuestion) POST Permission/Question; Hoshi answers 204 at once unless a phone is
  connected (bus sets assistants.phones), otherwise holds one request up to 30 s with a random 5-letter
  code. "app:claude:permit" {id, behavior allow|deny} / "app:claude:answer" {id, answers for exactly
  those questions} release it; timeout/close => 204 => the normal dialog on the PC.
  History (user-approved on the PC 2026-09-27): phone op "history" {kind read|sessions, session} ->
  tools/claude_history.py (read-only, ~/.claude/projects/*/<id>.jsonl, message texts only: user/phone/
  assistant; never tool calls/results, file contents, thinking) -> {op:"history"} sent ONLY to the
  requesting phone (never in broadcast state). Session ids are validated (hex/-).
  Clouds over Hoshi: assistant_watch.clouds() -> companion_ui -> assistant_clouds.gd (draw only,
  mouse-transparent, menu toggle "toggle_assistant_clouds", saved in companion.cfg); petting marks seen.
  The --wait hooks need "timeout": 43200 in settings (Claude Code otherwise kills background hooks after
  10 min); the waiter re-knocks every 5 min (HEARTBEAT) and logs to %LOCALAPPDATA%/HoshiCompanion/
  claude_hook.log (time, event, 8-char session, outcome; never text). StopFailure is reported too.
  Phone packets may be up to 8 KB for this. Never change Claude's permission mode from the phone.
- Codex uses the same assistant_watch receiver with a separate `codex` card/cloud and
  `tools/codex_hook.py` in user-level `~/.codex/hooks.json` (user-approved 2026-09-28).
  The paired phone may see status, project folder name, last final answer, answer-named media,
  and text-only session history (`tools/codex_history.py`), and may send a reply during the
  one-minute synchronous Stop hook. Never send paths, tool calls/results or reasoning to the
  phone. Keep the existing Codex `notify` setting untouched. PermissionRequest may use the
  same 30-second phone decision; do not change Codex approval policy from the phone.
  Interrupt clears the working state; the Android foreground service uses the same
  notification path for Claude and Codex with independent status and alert IDs.
- android/ (Kotlin app «Хоши», see docs/ANDROID_APP_RU.md): WebView of the live remote page, a
  foreground service (same phone protocol: hello/ping/state, never sends commands) for assistant
  notifications while the page is hidden, self-update from GET /app/version.json + /app/hoshi.apk
  (remote_bus serves only these two files from .workspace/android/, built by `dev.py android`).
  Quick buttons (0.6): the page (only inside the app, window.HoshiApp) lets the user pick up to 3
  notification buttons and 6 quick-settings tiles from the existing catalog (never "confirm" items);
  the app stores them and sends the same {"op":"run"} commands. The page reports {sound, selected} to
  the app via HoshiApp.onState so tiles light up.
  android/.gdignore keeps Godot from importing it; build outputs and local.properties are ignored.
- Command "restart" (menu + phone, flag "confirm"): scripts/hoshi_restart.gd runs
  tools/restart_hoshi.py check (headless import like launch.cmd); only on success it starts the
  detached "relaunch" helper (waits for this PID, max 120 s, then starts the same Godot executable
  with --path/--log-file and this run's arguments) and closes through the normal portal outro.
  A new version with script errors never closes Hoshi. Tests use dry_run.
