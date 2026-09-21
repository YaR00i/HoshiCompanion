# Hoshi Companion 0.3

Posture layer and current validation: see POSTURE_03.md.
The 0.2 movement/import architecture below is preserved.

## Ownership

`companion.gd` is the composition root and arbitrates user actions. Only
`desktop_host.gd` touches native screen geometry/cursor/window coordinates.
`vrm_source.gd` and `expression_driver.gd` are unchanged from the working 0.1.1.

`locomotion.gd` is pure data. It owns one bounded horizontal route and the states
idle / turn_out / walk / settle / turn_in. Its x is absolute in preview-lane pixels
or native-window pixels, depending on the caller; never silently mix the spaces.
Walk scalar distance is always positive, direction is separate (+/-1). The model
faces its own +Z, turned +/-90 degrees about Y during the translating portion.

During a step the stance target's `world_z` is constant. Its skeleton-space offset
is `world_z - travelled_m`. Both translation and targets come from the same scalar
route progress, not two clocks. Last two step targets are the route endpoint.
Stops snapshot current offsets, sequentially put feet down, then face the user.
Native x is rounded once, with the residual applied to `AvatarPivot.position.x`.
Consequently window rounding does not intentionally become separate foot drift.

`gait_driver.gd` solves hips-knee-ankle chains in SKELETON space. It caches original
RESTs and measures segment lengths from the supplied rig. It never edits rest
transforms, binds, source GLB bytes or blendshapes. Parent CURRENT global rotation
is used to convert desired global rotations back to local bone poses. Knees use
the avatar +Z pole. Feet preserve authored global orientation. Forcing a constant
hip drop was rejected after the CPU pose sanity check; reach-based lowering avoids
the obvious squat. A new avatar with differently oriented roots may need calibration.

`rig_driver.gd` still controls the upper body/expressions' gesture motion. It adds
small contralateral arm swing; lower-body IK executes AFTER those offsets so feet
remain planted. `behavior_director.gd` decides when to look, wave or request a
route. It does not move the window, touch the skeleton or emit autonomous speech.

`avatar_stage.gd` owns the SubViewport, camera, pivot, importer and drivers. The
stage framing's meters_per_pixel is the single source of scale conversion. Host
movement, gait and preview movement all use it. Resize/mode switch/pickup cancel
the old route; never reuse a previous route scale on a differently sized avatar.

## Important invariants

- Keep 0.1.1 final-mesh morph resolution intact; no stale GLTF scene-node pointers.
- A walk is an optional capability. Missing leg mappings must not break rendering.
- Autonomous walking only on the current monitor's usable bottom; no window-title
  inspection, screen capture, or hidden traversal to another monitor.
- Explicit stop, pet, menu, sleep cancel a route; dragging fully replaces navigation.
- Quiet disables autonomous walks/waves, not manual tests. Disabling all motion
  stops navigation immediately. A new explicit walk can wake the dozing avatar.
- Camera offset is preview travel OR native subpixel residual, never both at once.
- The static native hit polygon is not per-pixel picking. Do not claim otherwise.

## Validation boundaries

Actual Windows Godot 4.7.2 import, runtime and posture checks pass (79 + 39).
Run `python tools/dev.py check`; view app-only renders with `poses`.
Outputs live in .workspace/checks. Numerical tests use live Skeleton3D bones.
Renderer captures and native-mask anchor checks are not a full desktop usability
or animation-quality certification. Human visual acceptance remains necessary.

Primary API references used in this iteration:
- https://docs.godotengine.org/en/4.5/classes/class_skeleton3d.html
- https://docs.godotengine.org/en/4.5/classes/class_quaternion.html
- https://docs.godotengine.org/en/4.5/classes/class_displayserver.html

Next likely work: actual Windows footage -> calibrate stride/ground/shoe contact;
then authored turn/idle/sit clips with an explicit animation mixer. Do not replace
the rest pose with identity, animate native-window x independently of gait, or add
automatic screen/notification capture as part of an animation fix.


## 0.4 own-window support

shelf_playground owns the explicitly opened shelf_window. No external-window APIs.
edge_pose is a separate lower-body layer selected by posture.kind.
Preparing -> boarding -> attached -> returning -> settling -> off.
The coordinator blocks autonomous routes while this layer owns support.
Window anchoring runs after pose evaluation, using the projected seat contact.
Temporary support position must not overwrite the persisted floor position.
See docs/SHELF_04.md for validation commands and rendering limitations.
