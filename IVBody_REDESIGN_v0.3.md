# IVBody Redesign — v0.3 Planning Document

Living design document for the ivoyager_core v0.3 `IVBody` rework. Updated as decisions are
made; see the Decision Log at the end. This is a from-scratch redesign — nothing here is
obligated to preserve the v0.2 API. Existing call sites are used only as evidence of what the
new API must be *able* to express (Appendices A & B).

**Ground rules (from project owner):**

- Composition over inheritance. No duck-typing *inside* `IVBody`.
- External systems that duck-type *into* `IVBody` (GUI widgets, `IVSelectionManager`,
  `IVCamera`, string-path data display) keep working; their entry points are contracts (§10).
- Associated classes keep their identity and are edited to the new API. `IVBodyVisual` is
  explicitly in scope for redesign; `IVOrbit`/`IVTrajectory` gain a base class but keep their
  content.
- `IVBody` must be ignorant of its HUD elements. At most a passive
  `hud_elements: Array[Node3D]` container for external convenience.
- `characteristics` is renamed `attributes`.
- The body must be able to answer its own surface geometry (radius at any coordinate) without
  reaching into its visual representation.
- The sleep system will be rebuilt on proximity detection (separate effort); this design must
  not bake camera-parenting assumptions into `IVBody`.


## 1. What a "body" is in v0.3

**v0.2 definition:** a free body in space that orbits or is orbited (even the Sun conceptually
orbited the galaxy).

**v0.3 definition:** a named, persistent, selectable object in the simulation scene tree.
Its scene-tree parent defines its reference frame; its translation within that frame over time
is supplied by an optional *positioner*; its orientation over time by an optional *rotator*;
its physical figure by an optional *geometry*; its 3D representation by an optional *visual*.
What kind of thing a body *is* falls out of which parts it carries — not out of a subclass.

Invariants that carry over unchanged:

- `IVBody` extends `Node3D` and is **never rotated or scaled**. Local translations at every
  tree level are in the ecliptic basis. (Also load-bearing for external contracts:
  `IVSelectionManager` falls back on `selection is Node3D` / `is IVBody`, and `IVCamera`
  parents to targets as plain `Node3D`.)
- `Node.name` is the table row name (`PLANET_VENUS`, `SPACECRAFT_JUNO`, ...) and the registry
  key.
- Position math is 64-bit (`PackedFloat64Array` "translation"/"state"); `Vector3` outputs are
  the 32-bit graphics idiom (unchanged from `IVOrbit` conventions).

### Capability matrix

| Body | positioner | rotator | geometry | visual | can be orbited |
|---|---|---|---|---|---|
| Sun (top of tree) | null (galactic drift possible later) | uniform | spheroid | star shells | yes |
| Planet | `IVOrbit` | uniform | spheroid | shells | yes |
| Tidally locked moon | `IVOrbit` | locked (slaved to orbit) | spheroid | shells | yes |
| Irregular small moon | `IVOrbit` | uniform (tumbler later) | triaxial / mesh | shells+mesh | yes |
| Spacecraft (Juno) | `IVTrajectory` | pointing law (sun-spin) | mesh or none | packed model | no (GM 0) |
| **Barycenter** | `IVOrbit` | null | **null** | **null** | **yes** |
| **Rocket on launch pad** | `IVSurfaceAnchor` | grounded | mesh | packed model | no |
| **Rover (Curiosity)** | `IVSurfaceAnchor` (optionally moving) | grounded | mesh | packed model | no |
| **Space elevator** | `IVSurfaceAnchor` | grounded | tall mesh | packed model | no |
| **Gravity-ignoring object** | `IVFixedPositioner` or project subclass | any | any | any | no |

Notes:

- "Can be orbited" needs only `gravitational_parameter > 0` and tree membership — which is why
  a geometry-less, visual-less barycenter works with no special code path.
- A launch becomes a *component swap*: at ignition, replace `IVSurfaceAnchor` with an
  `IVOrbit`/`IVTrajectory` and the grounded rotator with a pointing rotator. No class change,
  no reparent gymnastics beyond what trajectory handoff already does.
- The extension point for exotic motion is **subclassing `IVPositioner`**, not subclassing
  `IVBody`. (`IVBody.replacement_subclass` remains for projects that need a fatter body, but
  the positioner strategy should make that rare.)


## 2. The bloat audit — where every current responsibility goes

Current `body.gd` is 2,134 lines. Disposition of each responsibility:

| # | Current responsibility (v0.2 body.gd) | v0.3 home |
|---|---|---|
| 1 | Identity: `name`, `flags` | **stays** (core) |
| 2 | Static registry `bodies`, `top_bodies` | **stays** (core statics) |
| 3 | Selection-order cache + 14 `get_selection_*` traversal methods (~500 lines) | thin protocol delegates on body → **new static traversal helper** (§8) |
| 4 | Tree indexing: `parent`, `star`, `star_orbiter`, `satellites`, `ordered_satellites`, `index_satellite` etc. | **stays** (core); ordering key generalized (§4.4) |
| 5 | `_orbit` + ~10 `get_orbit_*` passthroughs, each with the sleep/time-projection pattern | **`IVPositioner`** slot; passthroughs mostly dropped (§4.3, §5) |
| 6 | `_trajectory` special-casing: `_clamp_trajectory_time`, `_get_orbit_at_time`, per-frame segment swap, `set_orbit_and_parent` | **`IVTrajectory` becomes a positioner**; body handles one generic transition protocol (§5.3) |
| 7 | Rotation state: `orientation_at_epoch`, `rotation_axis`, `rotation_rate`, `rotation_at_epoch`, `get_orientation`, north/positive axis policy, tilts, `get_rotation_period` | **`IVRotator`** slot (§6) |
| 8 | Tidal/axis locking (`_update_rotations`, `locked_rotation_at_epoch` stash) | **`IVLockedRotator`** (§6) |
| 9 | Spacecraft pointing: static `process_methods` registry + `_earth_pointing`, `_sun_pointing`, `_process_iss`, `_process_hubble`, `_resolve_process`, `_process_callable` | **pointing `IVRotator` subclasses** (§6) |
| 10 | Stroboscope effect (3 cached settings + ~25 lines of `_process`) | **`IVBodyVisual`** (§7) |
| 11 | Visual management: `body_visual`, lazy init, `make_body_visual`, `add_child_to_body_visual`, `remove_and_disable_body_visual` | **stays** (visual is the body's own representation, not a HUD) — but visual self-drives its rotation (§7) |
| 12 | Figure: `mean_radius`, equatorial/polar radius, `triaxial_size`, `perspective_radius`, `_resolve_triaxial_size` (surface-class fallback) | **`IVBodyGeometry`** slot (§4.2, §7) |
| 13 | `_system_radius`, `_hill_sphere` | **stays** (derived, body-graph domain) |
| 14 | `characteristics` dict + typed accessors + `get_characteristic` mega-switch | **`attributes`** dict; switch dropped — GUI paths address components directly (§9) |
| 15 | `components: Dictionary[StringName, RefCounted]` (e.g. `IVComposition`) | **stays** (open-ended object extensions) |
| 16 | Lifespan: `begin`, `end`, `within_lifespan`, selection invalidation | **stays** (core) |
| 17 | HUD visibility policy: `huds_visible`, `huds_visibility_changed`, `_min_hud_dist`, `hide_hud_when_close` listener, static HUD-dist multipliers | **removed from body** → HUD side (§8.2) |
| 18 | `farwarp_position`, `update_farwarp()`, LOCAL_SHADOW_CASTER grant | **removed from body** → `IVBodyPositionVisual` / `IVBodyVisual` self-compute (§8.3) |
| 19 | Mouse-target push (`_world_controller.update_world_target` each frame, visual-separation test) | **removed from body** → camera-distance service (§8.4) |
| 20 | `get_fragment_data` / `get_fragment_text` (orbit-visual mouse-over) | **`IVPathVisual`** owns its own fragment identity (§8.5) |
| 21 | Camera duck protocol: `get_camera_radius/ground_basis/orbit_basis/lat_lon_type` | **stays** as thin delegates (contract, §10.2) |
| 22 | Selection duck protocol: 14 `get_selection_*` | **stays** as thin delegates (contract, §10.1) |
| 23 | `get_periapsis_label` / `get_apoapsis_label` (STAR_SUN / PLANET_EARTH hardcode) | GUI side (`selection_data.gd` computes from `body.parent.name`) |
| 24 | `texture_2d`, `texture_slice_2d` cached from `IVAssetPreloader` | storage dropped; **method delegates** `get_selection_texture_2d()` etc. → AssetPreloader (§10.1) |
| 25 | `get_float_precision(path)` | **stays** (reads `attributes`; Planetarium contract) |
| 26 | Two static `create*` factories + `replacement_subclass` | one `create()` taking composed parts; astronomy-specs logic → rotator/builder factories (§11) |
| 27 | Position/state API: `get_position_vector`, `get_translation`, `get_state_vectors`, `get_translation_to_ancestor` | **stays** (core facade over positioner; heavily used) |
| 28 | `get_latitude_longitude(vector)` | rotator domain (no known external consumer — candidate to drop) |
| 29 | `get_orbit_tracking_basis` (LVLH) | positioner-domain helper; consumed by camera delegate + LVLH rotator |
| 30 | Paused-game-load process hack (`_on_simulator_started`) | keep for now; revisit with proximity/sleep rebuild |

Rough expectation: new `body.gd` lands at ~500–650 lines, with removed weight going to
`IVPositioner` family (mostly existing `IVOrbit`/`IVTrajectory` content), `IVRotator` family
(~250 lines), `IVBodyGeometry` (~150), and deletions (HUD/screen logic reimplemented at its
consumers, traversal boilerplate collapsed).


## 3. Architecture overview

```
IVBody (Node3D, never rotated/scaled)
 ├── positioner: IVPositioner        # translation vs parent over time (nullable)
 │     IVOrbit | IVTrajectory | IVSurfaceAnchor | IVFixedPositioner | project subclass
 ├── rotator: IVRotator              # orientation over time (nullable)
 │     IVUniformRotator | IVLockedRotator | pointing rotators | IVGroundedRotator | ...
 ├── geometry: IVBodyGeometry        # figure; radius at coordinates (nullable)
 │     IVBodyGeometry (spheroid/triaxial) | IVMeshGeometry
 ├── attributes: Dictionary[StringName, Variant]   # optional scalar data (was characteristics)
 ├── components: Dictionary[StringName, RefCounted] # open-ended object extensions (IVComposition...)
 ├── body_visual: IVBodyVisual       # child Node3D, optional/lazy; self-drives rotation
 └── hud_elements: Array[Node3D]     # passive container; body never touches contents
```

- The three typed slots are RefCounted strategy components. Each family is **one abstract base
  plus concrete subclasses** (`@abstract`, Godot 4.5+). This is typed polymorphism, not
  duck-typing, and not deep inheritance — exactly the pattern the codebase already uses for
  orbits (`IVRealPlanetOrbit extends IVOrbit`, `IVOrbit.replacement_subclass`).
- Cross-component needs (a locked rotator needs the orbit; a surface anchor needs the parent
  body's rotator and geometry) are met by components holding object references — the precedent
  is `IVTrajectory`, which already holds `IVBody` refs and cleans them up on
  `about_to_free_procedural_nodes`.
- A uniform component lifecycle handles wiring and teardown:

```gdscript
# On every slot component (positioner / rotator / geometry):
func _attached(body: IVBody) -> void   # cache refs, connect signals (e.g. locked rotator → positioner.changed)
func _detached(body: IVBody) -> void   # disconnect, null refs, break cycles
```

`IVBody` calls these on slot assignment, on load reconstruction, and from
`_clear_procedural()`. This generalizes the ad-hoc teardown that `IVTrajectory` and the
graphic nodes each implement today.


## 4. The new IVBody core

### 4.1 Members (sketch)

```gdscript
class_name IVBody
extends Node3D

signal positioner_changed(positioner: IVPositioner, is_intrinsic: bool, precession_only: bool)
signal parent_changed(new_parent: IVBody)
signal rotation_changed(is_intrinsic: bool)          # typo `rotation_chaged` fixed
signal sleep_changed(is_sleeping: bool)
signal within_lifespan_changed(is_within_lifespan: bool)
# REMOVED: huds_visibility_changed (HUD policy leaves the body; §8.2)

enum BodyFlags { ... }        # identity / GUI / program bits; see §4.5

static var replacement_subclass: Script
static var bodies: Dictionary[StringName, IVBody] = {}       # main thread only
static var top_bodies: Dictionary[StringName, IVBody] = {}

# persisted
var flags := 0
var gravitational_parameter := 0.0   # what satellites orbit; stays core (barycenters need it)
var begin := NAN                     # lifespan (mainly table-driven spacecraft)
var end := NAN
var attributes: Dictionary[StringName, Variant] = {}
var components: Dictionary[StringName, RefCounted] = {}
var positioner: IVPositioner         # nullable; persisted as nested object (as _orbit is today)
var rotator: IVRotator               # nullable; persisted
var geometry: IVBodyGeometry         # nullable; persisted

# read-only, derived on _enter_tree()
var parent: IVBody
var star: IVBody
var star_orbiter: IVBody
var satellites: Dictionary[StringName, IVBody]
var ordered_satellites: Array[IVBody]
var within_lifespan := true

# unpersisted conveniences
var body_visual: IVBodyVisual        # null until built (lazy)
var hud_elements: Array[Node3D] = [] # filled by IVBodyFinisher; body never reads or iterates it
```

Dropped vs v0.2: `mean_radius` (→ geometry), all four rotation vars (→ rotator), `_orbit`,
`_trajectory` (→ positioner), `huds_visible`, `farwarp_position`, `_min_hud_dist`,
`texture_2d`, `texture_slice_2d`, stroboscope caches, `_world_controller`,
`_process_callable`.

### 4.2 Facade methods that remain on the body

`IVBody` keeps a *small* facade where a query is cross-component, null-safe, or a published
contract. Everything else is reached through the typed slots (`body.positioner`,
`body.rotator`, `body.geometry`) — including by GUI string paths (§9).

```gdscript
# position/state (delegate to positioner; sensible defaults when null)
func get_position_vector(time := NAN) -> Vector3
func get_translation(time := NAN) -> PackedFloat64Array
func get_state_vectors(time := NAN) -> PackedVector3Array
func get_state(time := NAN) -> PackedFloat64Array
func get_translation_to_ancestor(ancestor: IVBody, time := NAN) -> PackedFloat64Array

# component conveniences
func get_orbit() -> IVOrbit            # the governing 2-body orbit now, if any:
                                       # positioner if it IS an IVOrbit; a trajectory's active
                                       # segment; null for anchors/fixed/null
func get_orientation(time := NAN) -> Basis    # rotator basis; IDENTITY if null
func get_north_axis(time := NAN) -> Vector3   # rotator; ecliptic north if null
func get_mean_radius() -> float               # geometry; 0.0 if null (barycenter)
func get_mass() -> float                      # attributes mass, else GM/G

# attributes / GUI contracts (§9, §10)
func get_hud_name() -> String
func get_float_precision(path: String) -> int
func get_selection_texture_2d() -> Texture2D          # delegates to IVAssetPreloader
func get_selection_texture_slice_2d() -> Texture2D

# duck-type protocol delegates (contracts; §10) — all one-liners
func get_camera_radius() -> float
func get_camera_ground_basis() -> Basis
func get_camera_orbit_basis() -> Basis
func get_camera_lat_lon_type() -> IVQFormat.LatitudeLongitudeType
func get_selection_up() -> IVBody     # ... and the other 13, delegating to traversal helper

# tree / registry
func get_system_radius() -> float
func get_hill_sphere() -> float
func remove() -> void
func set_positioner(new_positioner: IVPositioner) -> void
func set_positioner_and_parent(new_positioner: IVPositioner, new_parent: IVBody) -> void
func set_rotator(new_rotator: IVRotator) -> void
func set_sleeping(sleeping: bool, show_hide := true) -> void
func is_sleeping() -> bool
```

The v0.2 long tail of `get_orbit_semi_parameter/eccentricity/inclination/...` passthroughs is
**dropped**. Callers do `var orbit := body.get_orbit(); if orbit: orbit.get_eccentricity()`.
The handful of program-side users (timekeeper, SBG Lagrange code, orbit builder) get edited
accordingly (§12). The sleep/time-projection guard that was copy-pasted into every passthrough
is implemented once, in the position/state facade.

### 4.3 `_process()` in v0.3

```gdscript
func _process(_delta: float) -> void:
	var time := _times[0]
	# 1. lifespan gate (unchanged behavior; emits within_lifespan_changed,
	#    IVGlobal.selection_invalidated)
	# 2. if positioner: position = positioner.update(time)
	# 3. if positioner.has_pending_transition(): _apply_transition()  # §5.3
```

That is the whole loop. Gone from `_process`: mouse-target push, HUD visibility, visual
rotation, stroboscope, pointing callables, trajectory segment comparison. The visual and HUD
elements process themselves (§7, §8); a body with no positioner and no lifespan bounds can run
with processing disabled entirely.

**Under Consideration: camera-relative placement (the world frame follows `IVCamera`).** Step 2
writes a parent-relative translation into a transform chain carrying astronomical magnitudes.
The alternative is for the body to be `top_level` and place itself relative to the camera:

```gdscript
	# 2'. top_level == true; position = absolute_f64(time) - camera_anchor_f64
```

The scene tree stays the *logical* hierarchy — orbital math, lifecycle, selection, satellite
indexing, visual children — and stops being the *transform* hierarchy for bodies.

*Why consider anything this drastic.* Opting bodies out of transform inheritance is abnormal
for Godot and abnormal for us: the hierarchy is load-bearing here, and the f32 error it shares
down the chain is exactly what makes a close-up precise today. The case for it is that the tree
is being asked to do two jobs that have quietly diverged. It expresses **what orbits what**,
which is correct and is not in question. It also **constructs the render frame**, by composing
those parent-relative locals — and that job it cannot do well, because the composition is f32
and the locals are astronomical. Two consequences follow that nothing local can undo, because
the information is gone before it reaches the camera's neighbourhood: the frame is anchored at
the barycentre, so a body sweeps through world space at its *absolute* speed rather than its
speed relative to the camera; and the quantum near the top of the chain is ~16 km at 1 au.

Both of VISUAL_MODEL.md's standing defects are that same root. Craft self-shadowing boils
because Godot anchors its directional-shadow texel lattice in absolute world space while our
near scene translates 129 m per frame through it (ISS orbital speed over the frame rate; the
origin shift resolves onto the 16 km lattice and so holds the camera *near* the origin rather
than *on* it). High-speed render registration loss is the same f32 chain rounding differently
as huge per-frame motion churns the magnitudes, with only common-mode error cancelling. A
single f64 subtraction rounded once has no chain to churn and no lattice to sit on, so it
plausibly subsumes both — worth testing against the second before claiming it.

What makes it *thinkable* rather than merely appealing is that the change surface is one line.
v0.2 `IVBody` writes its own transform in exactly one place (`body.gd:687`, `position =
_orbit.update(time)`) and never writes its own basis — every rotation goes to
`body_visual.basis`. A body is already a pure translation node, which is the condition that
makes `top_level` structurally free: nothing inherits orientation through it, and visual
children keep inheriting normally. And the pattern is not new to the codebase —
`IVBodyPositionVisual` is already `top_level` and placed camera-relatively, and farwarp already
re-places everything beyond T camera-relatively. This unifies an answer we have twice reached
for at other ranges.

*What it buys.* Rounding `f64(body − camera)` to f32 leaves an absolute error proportional to
distance *from the camera* — a constant angular error of ~1.2e-7 rad (0.025") for every object
at every distance, about 1/6500 of a pixel at the reference view. That is what the
parenting/shared-error scheme achieves locally, made global and automatic. Note what this does
to the apparent conflict with parenting: shared error only matters because there *is* large
error to share, and here there is not, so the mechanism this seems to violate is the one it
makes unnecessary.

*It is mostly a deletion.* Origin shifting is subsumed — `Universe.position` stays zero and
`IVCamera.origin_shifting` with its `-=` line is removed. Farwarp improves with it:
`body.gd:1848` already assembles `farwarp_position` camera-relatively, and VISUAL_MODEL.md
carries a standing warning never to derive it by differencing large true-scale positions. Here
`position` *is* the camera-relative vector, so farwarp reduces to scaling it by `g(d)/d` and
that hazard becomes unrepresentable. The added cost is one top-down f64 pass per frame, keeping
the sum that is currently discarded at the f32 write.

*`IVPositioner` does not change.* It stays parent-relative (§5) — that is the physical
abstraction and should not absorb a rendering concern. Only what the body does with the result
changes.

To resolve before this could be adopted:

- **It sits against a ground rule.** "This design must not bake camera-parenting assumptions
  into `IVBody`" was written for the sleep rebuild. Camera-relative *placement* is a different
  coupling from camera *parenting*, but it is still a camera dependency inside `_process`, and
  the project owner should rule on it explicitly.
- **Sleep.** A sleeping body's stale placement stays valid today because the tree carries it;
  camera-relative, stale means visibly lagging a moving camera. Ties directly to the proximity
  sleep rebuild (§14).
- **Anchor ordering.** `camera_anchor_f64` must exist before any body is placed. §5's "valid at
  any [param time]" positioner contract makes that a query at the top of the frame rather than
  a one-frame lag.
- **Small-body groups.** GPU-placed by their own scheme; they would need the anchor as a
  uniform. Unexamined.
- **`global_position` changes meaning** to camera-relative for every consumer (§10). Most
  already want that — farwarp, sun occlusion, mouse picking, HUD placement — and several
  simplify; a consumer wanting absolute ecliptic coordinates queries the f64 state, which is
  the correct source anyway.


*The lesser alternative: walk the camera's ancestor chain.* If the tree structure is to be left
alone, the flaw can be patched rather than removed. Each frame, walk up from the camera's target
and re-translate that chain — target, its parent, and so on — from f64, leaving every other body
on the ordinary path. Depth is the knob, and it decides where the leftover 16 km lattice error
lands. One node (the target alone) holds the camera at the world origin — measured, the
per-frame slide goes to exactly 0.000 m and it converges to a fixed point — but puts up to ~8 km
between craft and planet, about 1.5 px of parallax, and fixes only the camera's own parent:
every other local caster keeps sliding, and a sibling craft (Hubble is a sibling of ISS under
Earth) is displaced against it. Two nodes makes craft↔planet exact again and pushes the error
out to planet↔star, where 16 km is 1e-7 rad and farwarp is remapping anyway. Depth 2 covers the
general case, and rebasing a node fixes everything below it for free, since `top_level` severs
only the link to the parent.

It is a patch and should be judged as one. It writes into body positions from outside the
positioner, it is a special case that helps only the camera's own chain, and it leaves the frame
anchored at the barycentre — so the high-speed registration defect is untouched. Its virtue is
that it is small, testable against the same acceptance check, and does not require this
section's decision to be made first.

### 4.4 Registry, indexing, ordering

- `bodies` / `top_bodies` statics stay: they are the system-wide lookup used by builders,
  managers, GUI, tools, and the assistant (Appendices). Main-thread-only rule stays.
- `_index()` / `_clear_indexing()` / `index_satellite()` / `parent`-`star`-`star_orbiter`
  resolution stay as-is (cheap, correct, widely consumed).
- Satellite ordering generalizes: the sort key changes from `get_orbit_semi_parameter()` to
  `positioner.get_ordering_distance()` (base returns 0.0; orbit returns semi-parameter; anchor
  returns anchor radius). Surface objects therefore sort inside the lowest orbits, which is
  the natural GUI traversal order, and bodies with null positioners sort first.

### 4.5 BodyFlags

Flags remain the cheap identity/role bitmask (`flags & BODYFLAGS_STAR` in per-frame manager
loops, HUD group keying in `IVBodyHUDsState`, GUI filters).

- **Bit values of the identity flags are frozen.** `huds_box.tscn` bakes raw integers
  (16/64/128/512/1024/2048/8192) into exported `body_flags` scene properties; renumbering
  breaks scenes silently.
- Rotation-mechanics flags (`BODYFLAGS_TIDALLY_LOCKED`, `BODYFLAGS_AXIS_LOCKED`, the three
  tumbler placeholders) are **retired**: that information now lives in the rotator's type.
  `selection_data.gd` (the only GUI consumer of `AXIS_LOCKED`/`CHAOTIC_TUMBLER`) reads the
  rotator instead. Table columns (`tidally_locked`, `axis_locked`) become rotator-construction
  directives in the builder rather than flag bits. *(Open question Q3.)*
- Program-mechanics flags (`BODYFLAGS_LAZY_MODEL`, `BODYFLAGS_CAN_SLEEP`,
  `BODYFLAGS_DISABLE_MODEL_SPACE`) stay — the proximity sleep rebuild still needs a cheap
  eligibility bit.
- New-kind flags (e.g. a `BODYFLAGS_SURFACE_OBJECT`) can be added later in reserved bits if
  GUI grouping needs them; nothing in the core requires them.


## 5. IVPositioner — the generic positioning object

### 5.1 The problem it solves

In v0.2, "where is this body" is answered by a nullable `IVOrbit` plus a nullable
`IVTrajectory` that shadows it, with the multiplexing (`_get_orbit_at_time`,
`_clamp_trajectory_time`, per-frame segment swap) copy-pasted through ~15 body methods. The
new body kinds (pad, rover, elevator, no-gravity object) don't fit either. The requested
"generic positioning object" is a single strategy interface:

```gdscript
@abstract
class_name IVPositioner
extends RefCounted

## Supplies a body's translation (and translational state) relative to its scene-tree
## parent over time. All get methods are threadsafe and valid at any [param time]
## (the basis of sleep-safe queries). update() and setters are main-thread only.

signal changed(is_intrinsic: bool, precession_only: bool)   # relayed by IVBody

@abstract func get_translation(time: float) -> PackedFloat64Array   # 64-bit [x,y,z]
@abstract func get_state(time: float) -> PackedFloat64Array         # 64-bit [x,y,z,vx,vy,vz]
func get_position_vector(time: float) -> Vector3   # 32-bit graphics idiom; default impl
func get_state_vectors(time: float) -> PackedVector3Array           # default impl
func update(time: float) -> Vector3    # cached fast path for IVBody._process; default impl

func get_ordering_distance() -> float  # §4.4; base 0.0
func has_pending_transition() -> bool  # §5.3; base false
func get_transition() -> IVPositionerTransition  # base null

func _attached(body: IVBody) -> void
func _detached(body: IVBody) -> void
```

This is not duck-typing (every call is statically dispatched through the declared base type)
and not "over-complex inheritance" (one abstract layer; concrete classes are siblings). It is
the same shape the camera problem was *not* given in v0.2 — and it is the designated project
extension point: a developer with exotic motion subclasses `IVPositioner`, not `IVBody`.

### 5.2 The concrete family

- **`IVOrbit extends IVPositioner`** — unchanged content (Keplerian elements, precessions,
  64/32-bit getters, `changed` signal, state paths, Lambert, serialize). Its existing
  `update(time)`, `get_translation(time)`, `get_state(time)` already satisfy the interface.
  Keeps `replacement_subclass` and `IVRealPlanetOrbit`.
- **`IVTrajectory extends IVPositioner`** — the composite: maps time → active `IVOrbit`
  segment and forwards all state queries (absorbing v0.2 body's `_clamp_trajectory_time` /
  `_get_orbit_at_time`). Continues to hold segment-parent `IVBody` refs and its LCA/path
  machinery. Exposes the active orbit for `IVBody.get_orbit()`.
- **`IVSurfaceAnchor`** — fixed (or slowly moving) attachment to the parent body's surface:
  `latitude`, `longitude`, `altitude` (+ optional motion model later, for a driving rover).
  `get_translation(time)` = parent rotator basis(time) × parent geometry surface point,
  radially offset by altitude. Velocity is analytic (ω × r). Requires the parent body to have
  a rotator and geometry; asserts at `_attached()`.
- **`IVFixedPositioner`** — constant translation (optionally constant velocity drift) in the
  parent frame. Serves gravity-ignoring objects and gives "top" bodies a future galactic-drift
  option without a new mechanism.
- **null** — body stays wherever it was placed (today's top-body behavior).

### 5.3 Transitions (trajectory handoffs, launches)

v0.2 detects segment changes by comparing the trajectory's current orbit against `_orbit`
every frame inside `IVBody._process`, then calls `set_orbit_and_parent()`. Generalized:

- `positioner.update(time)` may set a pending transition. `IVBody._process` polls
  `has_pending_transition()` (one cheap virtual per frame) and applies it:

```gdscript
class_name IVPositionerTransition   # plain data
var new_parent: IVBody              # null = no reparent
var replacement: IVPositioner       # null = keep current positioner (internal segment swap)
var is_intrinsic: bool
```

- Reparenting stays the body's job (scene ops). After applying: emit `positioner_changed`
  (and `parent_changed` if reparented) — the stable connection points for `IVPathVisual`,
  which survive positioner replacement (listeners never connect to the positioner directly
  across a swap).
- `IVTrajectory.end_remove` becomes a transition with `replacement = final IVOrbit`.
- A scripted launch is the same mechanism driven by project code:
  `body.set_positioner_and_parent(ascent_trajectory, planet)`.

### 5.4 What the body-side orbit API reduces to

- `get_orbit()` (typed, null when not orbit-governed) is the single orbit access point.
- The path-display facade that migrated *into* `IVBody` during v0.2 (`is_showing_orbit`,
  `get_path_frame`, `get_orbit_display`, `get_display_state_paths`, `is_camera_focused`)
  **moves to `IVPositioner`** (with `get_orbit_display`'s mesh lookup moving all the way out
  into `IVPathVisual` — meshes are display resources and don't belong below the visual layer).
  `IVPathVisual` talks to `body.positioner`, typed; the body stays out of it (§8.5).


## 6. IVRotator — orientation over time

One strategy family absorbs three v0.2 mechanisms: the four rotation vars + uniform axial
spin, tidal/axis locking (`_update_rotations`), and the spacecraft pointing-law registry
(`process_methods` + four static methods).

```gdscript
@abstract
class_name IVRotator
extends RefCounted

## Supplies a body's orientation (the "ground"/model basis in ecliptic space) over time.
## Get methods are threadsafe and valid at any time.

signal changed(is_intrinsic: bool)    # relayed by IVBody as rotation_changed

@abstract func get_basis(time: float) -> Basis
func get_axis(time: float) -> Vector3          # north axis (policy per v0.2 get_north_axis docs)
func get_positive_axis(time: float) -> Vector3
func get_rotation_rate(time: float) -> float   # 0.0 where meaningless (pointing laws)
func get_rotation_period() -> float
func is_retrograde(time: float) -> bool
func get_axial_tilt_to_ecliptic(time: float) -> float
func get_axial_tilt_to_orbit(time: float) -> float    # NAN if body has no orbit

func _attached(body: IVBody) -> void
func _detached(body: IVBody) -> void
```

Concrete family:

- **`IVUniformRotator`** — `orientation_at_epoch`, `rotation_axis`, `rotation_rate`,
  `rotation_at_epoch`; the v0.2 default behavior, including the astronomy-specs construction
  (`create_from_astronomy_specs(right_ascension, declination, rotation_period, ...)` moves
  here from `IVBody`).
- **`IVLockedRotator`** — tidal lock, optional axis lock; connects to the body's
  `positioner_changed` in `_attached()` and re-derives rate/axis/phase from the orbit
  (v0.2 `_update_rotations`, including the Triton polarity flip and the
  vernal-referenced anchor). Holds the lock offset that v0.2 stashed as
  `characteristics.locked_rotation_at_epoch`.
- **Pointing rotators** — `IVEarthPointingRotator`, `IVSunSpinRotator`, `IVLVLHRotator`,
  `IVSlewRotator` (Pioneer/Voyager, Juno, ISS, Hubble). Each holds what it needs (body ref for
  global positions; the LVLH one uses the positioner's tracking basis). A static registry maps
  the spacecrafts.tsv `process` column to a rotator factory, replacing
  `IVBody.process_methods` — projects register new pointing laws without subclassing anything
  but `IVRotator`.
- **`IVGroundedRotator`** — orientation slaved to the parent's ground frame at an anchor point
  (surface normal up, fixed heading): pads, rovers, elevators.
- **Future**: `IVWobbleRotator` / tumblers slot in as siblings (the v0.2 roadmap's four
  rotation classes become subclasses instead of flags + special cases).

Division of labor with the visual: the rotator answers "what is the body's orientation at
time t" — a simulation fact, queryable while sleeping. The *stroboscope* effect is a display
distortion of that fact and moves to `IVBodyVisual` (§7).


## 7. Geometry and visuals

### 7.1 IVBodyGeometry

New component; the body answers surface questions itself, without touching its visual:

```gdscript
class_name IVBodyGeometry
extends RefCounted

## A body's physical figure. Base class handles point (all radii equal), oblate spheroid,
## and triaxial ellipsoid. Get methods are threadsafe.

var mean_radius: float            # volumetric mean; > 0.0 required if geometry exists
var triaxial_size: Vector3        # IAU order (a, b, c); ZERO = spheroid via e/p radii
var equatorial_radius: float
var polar_radius: float
var extent_radius: float          # was perspective_radius: visible extent (Titan haze) for
                                  # camera framing/near-plane; defaults to mean_radius

func get_surface_radius(latitude: float, longitude: float) -> float   # ellipsoid math
func get_surface_point(latitude: float, longitude: float) -> Vector3  # body frame
func get_surface_normal(latitude: float, longitude: float) -> Vector3
```

- **`IVMeshGeometry extends IVBodyGeometry`** — for a body with a single mesh figure
  (Arrokoth, Eros, spacecraft if wanted): overrides `get_surface_radius` from a lat/lon radius
  table sampled once from the mesh arrays (same source asset the visual uses, but owned here —
  the visual is never queried). Sampling resolution is a construction parameter.
- The surface-class fallback figure (v0.2 `_resolve_triaxial_size` + AssetPreloader lookup)
  moves into the builder: geometry components are constructed already-resolved, and the body's
  AssetPreloader dependency disappears.
- Consumers served: `IVSurfaceAnchor` (§5.2), camera radius, `IVSunOcclusionManager`
  (`get_equatorial_radius`/`get_polar_radius`/`get_north_axis` per frame),
  exposure metering (`mean_radius`), GUI radii display, the 2D icon rig.
- `geometry == null` is the barycenter case: `get_mean_radius()` returns 0.0 and camera
  framing falls back (Q6).

### 7.2 IVBodyVisual (in redesign scope)

Keeps its identity (model instantiation, shells vs packed model, scale/reference basis,
layers, preview staging) with these changes:

- **Self-driving rotation.** The visual connects to the frame loop itself and sets
  `basis = rotator.get_basis(time)`, applying the stroboscope effect (settings and logic move
  here from `IVBody._process`) on top when active. Pointing laws are just rotators, so the
  `process_methods` attitude branch disappears from the loop.
- **Constructor takes components, not a body:** `IVBodyVisual.new(name, geometry, rotator)` —
  it needs assets (by name), figure (scale), and orientation; it does not need the whole body.
- **Local-shadow-caster self-management.** The camera-distance check that
  `IVBody.update_farwarp()` performed moves into the visual's own per-frame update.
- Lazy init flow is unchanged in shape (`body.body_visual` null until needed;
  `IVLazyModelInitializer` or successor triggers creation) but the trigger will be revisited
  with the proximity rebuild, since "camera visits" is currently defined by camera parenting.
- `add_child_to_body_visual()` (rings attachment) and `make_body_visual()` (icon/preview
  staging) remain body methods.

### 7.3 GUI textures

`texture_2d` / `texture_slice_2d` storage leaves the body. The selection protocol's method
hooks (`get_selection_texture_2d()`, checked *before* the property fallback by
`IVSelectionManager`) delegate to `IVAssetPreloader` by name. `nav_button.gd` (typed consumer
of both) is edited to the methods.


## 8. HUD ignorance, restored

Principle: `IVBody` holds no HUD state, computes no HUD policy, and emits no HUD-specific
signals. HUD elements hold a body reference, query body/components, and connect to the body's
*simulation* signals. `hud_elements: Array[Node3D]` exists purely so external code can find a
body's HUD nodes without scene-tree spelunking; `IVBodyFinisher` appends to it; the body never
reads it.

What moves, and where:

### 8.1 Inventory of the v0.2 leakage

`huds_visible` + `huds_visibility_changed` + `_min_hud_dist` + `hide_hud_when_close`
settings listener + `min_hud_dist_*` statics; `farwarp_position` + `update_farwarp()`;
`min_visual_separation_multiplier` + world-target push; `get_fragment_data/text`;
`get_orbit_display()` returning display meshes. All of it leaves.

### 8.2 HUD visibility policy

The show/hide-by-distance recommendation ("hide when too close", "hide when not visually
separate from parent") becomes a HUD-side policy helper — proposed home: a static on
`IVBodyHUDsState` (already the per-group HUD visibility authority), taking the body and a
camera distance. `IVBodyPositionVisual` and `IVPathVisual` apply it in their own frame
updates. If the camera-distance service (§8.4) exists, they read the distance from it;
otherwise each computes it (trivial math).

### 8.3 Farwarp

`IVBodyPositionVisual` computes its own farwarp position per frame (it already runs at
process priority 101, after the origin shift) from `body.global_position`, the camera global
position, and the static `IVFarwarpManager.get_farwarp_factor()`. `IVFarwarpManager` keeps
the global parameters and shader globals but stops pushing per-body state into `IVBody`.

### 8.4 Mouse targets and the camera-distance service

Someone must still feed `IVWorldController.update_world_target()` per body per frame. Rather
than each body pushing (v0.2), a single per-frame service iterates live bodies and computes
camera distance, visual separation, mouse-target registration — and this is the same loop the
**proximity-based sleep rebuild** needs. Proposal: one new program node (working name
`IVBodyProximityMonitor`) that owns the camera↔body distance sweep and serves:

1. proximity sleep decisions (replacing `IVSleepManager`'s camera-parenting trigger),
2. mouse-target push to `IVWorldController`,
3. cached per-body camera distance for HUD policy (§8.2) and lazy-visual triggering (§7.2).

Its design belongs to the sleep-rebuild effort; for this redesign the only requirement is that
`IVBody` exposes what it needs (position queries valid while sleeping — already guaranteed by
positioner semantics — plus `set_sleeping()` / `sleep_changed`).

### 8.5 Orbit-line fragments and display facade

`IVPathVisual` becomes self-sufficient: it owns its fragment identity
(`get_fragment_data/get_fragment_text` move to it; the mouse-over label duck-calls whatever
object the fragment resolves to, so nothing upstream changes), selects its own conic display
mesh from `IVGlobal.resources` using `IVOrbit`'s unit-transform getters, and reads path frames
and state paths from `body.positioner` (typed). If orbit-line click-to-select is ever wanted,
`IVPathVisual` implements `get_selection_body()` — a hook `IVSelectionManager` already probes
first.


## 9. Attributes (was characteristics)

- Renamed `attributes`; still `Dictionary[StringName, Variant]`, non-Object values only,
  persisted, populated by the builder from ~57 table columns.
- The `get_characteristic()` mega-switch (which virtualized `mass`, radii, `hud_name`, ...)
  is dropped. Radii live in `geometry`; the few surviving virtual accessors are plain methods
  (`get_mass`, `get_hud_name`, `get_body_class`, `get_surface_class`, `get_file_prefix`,
  `has_light`, `has_rings` — the last five read by `IVBodyFinisher`, on worker threads, so the
  dict must remain effectively frozen during build; unchanged constraint from v0.2).
- **The string-path display contract** (Planetarium `selection_data.gd` +
  `IVTree.get_path_variant` + `float_precisions` keys) is preserved as a *mechanism* but its
  path data changes with the structure — e.g. `characteristics/mass` → `attributes/mass`,
  `orbit/get_eccentricity` → resolvable as `get_orbit/get_eccentricity` (method-step) or via a
  kept `orbit` read-only property alias (Q7), new `geometry/equatorial_radius`,
  `rotator/get_rotation_period`. `IVTableBodyBuilder`'s precision-path tables and
  `selection_data.gd`'s row definitions are updated in lockstep — they are data, and both are
  ours to edit. `get_float_precision(path)` stays on the body with paths matching the new
  layout.


## 10. External duck-type contracts (must keep working)

`IVBody` performs no duck-typed calls itself. These are the entry points *others* use on it.

### 10.1 IVSelectionManager protocol (deliberately duck-typed on its side)

| Probe | v0.3 answer |
|---|---|
| property `name` | Node name (unchanged) |
| method `get_selection_gui_name()` / property `gui_name` | not implemented → falls back to `tr(name)` (unchanged) |
| method `get_selection_texture_2d()` | **new method** (was property `texture_2d`) |
| method `get_selection_camera_target()` | not implemented → `selection is Node3D` fallback (unchanged) |
| method `get_selection_body()` | not implemented → `selection is IVBody` fallback (unchanged) |
| property `flags` | kept |
| method `get_float_precision(path)` | kept (paths updated per §9) |
| methods `get_selection_up/down/next/last` + `_star/_planet/_major_moon/_moon/_spacecraft` ×2 | kept as one-line delegates to the traversal helper |

The 14 traversal bodies collapse into a parameterized helper (working name
`IVBodyTraversal`, static utility owning the selection-order cache + dirty flag that are
static vars on `IVBody` today): `next_in_order(from: IVBody, flags_all: int) -> IVBody` etc.
~500 lines become ~80.

### 10.2 IVCamera protocol

`get_camera_radius()` (→ `geometry.extent_radius`, meter-scale fallback when geometry null),
`get_camera_ground_basis()` (→ rotator), `get_camera_orbit_basis()` (→ positioner tracking
basis + star-orbiter flip), `get_camera_lat_lon_type()` (→ flags). All kept as thin
delegates; the camera continues to accept any `Node3D` and probe with `has_method`.

### 10.3 Other hard contracts

- `IVBody` remains `Node3D` (camera parenting, selection fallbacks, world targets).
- `IVGlobal.selection_invalidated(name)` still emitted on lifespan exit;
  `within_lifespan_changed` kept (nav buttons connect to it — the only GUI-connected body
  signal today).
- `IVGlobal.camera_tree_changed(camera, body, star_orbiter, star)` remains the hub signal (its
  consumers — sleep, lazy models, exposure, occlusion, dynamic light, path visual — are
  edited, not broken; the proximity rebuild may later replace some uses).
- Identity `BodyFlags` bit values frozen (scene-baked ints, §4.5).
- Mouse-over label duck-reads `object.name` on world targets and duck-calls
  `get_fragment_text()` on fragment sources (now `IVPathVisual`).


## 11. Creation and the build pipeline

```gdscript
static func create(
		name: StringName,
		flags: int,
		gravitational_parameter: float,
		geometry: IVBodyGeometry,      # nullable (barycenter)
		positioner: IVPositioner,      # nullable (top body)
		rotator: IVRotator,            # nullable
		attributes: Dictionary[StringName, Variant],
		components: Dictionary[StringName, RefCounted],
		existing_body: IVBody = null,  # for replacement_subclass chaining
	) -> IVBody
```

- `create_from_astronomy_specs()` disappears from `IVBody`; its RA/dec/period math becomes
  `IVUniformRotator.create_from_astronomy_specs(...)`, and the tidal-lock anchor logic becomes
  `IVLockedRotator` construction. `IVTableBodyBuilder` becomes a component assembler: flags →
  bits; orbit/trajectory rows → positioner; rotation columns + lock columns → rotator; radii
  columns + surface-class fallback → geometry; the rest → attributes/components. Asserts that
  guarded `create()` move to the components that own the data (geometry asserts
  `mean_radius > 0`, etc.).
- Table-driven trajectory construction (`attributes.trajectory` at `system_tree_built`) moves
  into the builder path with the rest of positioner construction; the body no longer
  constructs its own trajectory.
- `IVBodyFinisher` is unchanged in role (adds position visual, path visual, lights, rings,
  reads `has_orbit`→`get_orbit`, `has_light`, `has_rings` on worker threads) and additionally
  appends what it adds to `body.hud_elements`.
- Persistence: same `PERSIST_PROCEDURAL` pattern; the three slots persist as nested objects
  exactly as `_orbit`/`_trajectory` do today. On load, `IVBody` re-runs `_attached()` wiring
  in `_enter_tree()`/`_ready()` (replacing today's ad-hoc orbit-signal reconnect).
- Teardown: `_clear_procedural()` detaches components (breaking the trajectory↔body style
  reference cycles uniformly) and clears statics, as today.


## 12. Migration map (associated classes)

| Class | Change |
|---|---|
| `IVOrbit` | `extends IVPositioner`; content unchanged; already satisfies the interface |
| `IVTrajectory` | `extends IVPositioner`; absorbs body's segment multiplexing; emits transitions (§5.3) |
| `IVBodyVisual` | in scope: self-driving rotation + stroboscope; constructor takes (name, geometry, rotator); shadow-caster self-management |
| `IVBodyPositionVisual` | computes own farwarp position + HUD visibility (was `_body.farwarp_position`, `huds_visible`, signal) |
| `IVPathVisual` | reads `body.positioner` (typed) for frames/paths; owns fragment identity; picks display meshes itself; own HUD visibility |
| `IVBodyFinisher` | same role; appends to `hud_elements`; `has_orbit()` → positioner check |
| `IVSelectionManager` | unchanged (its duck protocol is the contract; body keeps the entry points) |
| `IVCamera` | unchanged (probes kept methods) |
| `IVSleepManager` | replaced by proximity monitor (separate effort, §8.4); interim: works via `top_bodies`/`satellites`/`set_sleeping` unchanged |
| `IVLazyModelInitializer` | unchanged short-term; trigger revisited with proximity rebuild |
| `IVFarwarpManager` | stops per-body pushes; keeps globals/shader params + factor statics |
| `IVWorldController` | unchanged; fed by the proximity monitor instead of by bodies |
| `IVTableBodyBuilder` | becomes component assembler (§11); precision-path tables updated |
| `IVTableOrbitBuilder` | `parent.get_positive_axis()` → `parent.rotator`; `get_gravitational_parameter()` unchanged |
| `IVTableSystemBuilder` | unchanged in shape |
| `IVTimekeeper` | `get_rotation_rate/at_epoch` → `body.rotator`; `get_orbit_mean_*` → `body.get_orbit()` |
| `IVSunOcclusionManager` / `IVExposureManager` | per-frame reads move to `body.geometry` / `body.rotator` / `attributes` |
| `IVSmallBodiesGroup` / `IVSBGPositionsVisual` | `secondary_body.get_orbit_semi_major_axis()` etc. → `secondary_body.get_orbit().…` |
| `IVShellsModel` (sun mode) / `IVDynamicLight` / `IVRings` | `characteristics` → `attributes` key reads; otherwise unchanged |
| `selection_data.gd` (+ Planetarium info panel) | path data updated (§9); periapsis/apoapsis label logic moves here |
| `nav_button.gd` / `nav_buttons_system.gd` | texture methods; `get_mean_radius()` unchanged (facade) |
| `body_2d_capture` rig / tool suites | `make_body_visual()` / `get_camera_radius()` unchanged; `get_triaxial_size()` → geometry |
| `ivoyager_assistant` suites | typed reads updated (`mean_radius`, `get_orbit()`, positioner state queries) |

External projects (e.g. Astropolis) migrate on the same map; API breakage is accepted for
v0.3 per the ground rules.


## 13. Open questions

- **Q1 — Naming.** `IVPositioner` vs `IVLocator`/`IVEphemeris`; `IVSurfaceAnchor` vs
  `IVGroundAnchor`; `IVRotator` vs `IVRotationState`; `IVBodyGeometry` vs `IVFigure` (the
  astronomy term); does the open-ended `components` dict keep its name now that the typed
  slots are also informally "components"?
- **Q2 — Slot granularity.** Is geometry a strategy family (base + `IVMeshGeometry`) as
  proposed, or one class with an optional mesh sampler? Proposed: family, for symmetry.
- **Q3 — Flags pruning.** Retire `BODYFLAGS_TIDALLY_LOCKED`/`AXIS_LOCKED`/tumbler bits in
  favor of rotator typing (proposed), or keep them as cheap informational mirrors?
- **Q4 — Proximity monitor scope.** Accept the combined camera-distance service (sleep +
  mouse targets + HUD-distance cache) or keep those three consumers independent? This design
  only requires that they live outside `IVBody`.
- **Q5 — Barycenter orbit linkage.** True binary support needs phase-linked partner orbits
  (same period, opposite longitude, amplitude by mass ratio). Mechanism (an `IVOrbit`
  feature? builder convention? deferred past v0.3?) is undecided; the body model itself is
  ready either way.
- **Q6 — Camera at geometry-less bodies.** `get_camera_radius()` fallback for barycenters:
  fixed meter-scale (v0.2 default), or derived from system radius?
- **Q7 — `orbit` property alias.** Keep a read-only `orbit` property (`get = get_orbit`) so
  existing GUI paths and muscle memory survive, or force `get_orbit()` everywhere?
- **Q8 — Resource-based components.** Making positioner/rotator/geometry extend `Resource`
  would enable `@export` editor construction (a long-standing roadmap TODO) at some cost in
  save-system and threading review. Decide before implementation; RefCounted is the default.
- **Q9 — `begin`/`end` lifespan.** Stay as core floats (proposed — per-frame gate) or move
  into attributes?
- **Q10 — system_radius / hill_sphere.** Keep as body-cached derived values (proposed) or
  recompute on demand?

## 14. Deferred / out of scope for v0.3

- Proximity-based sleep + lazy-visual triggering (separate effort; §8.4 defines the seam).
- Network sync (component `changed(is_intrinsic=false)` signals + `IVOrbit.serialize()` are
  the intended hooks; rotators will need the same).
- Wobble/tumble rotators; `IVResonantOrbit` / `IVManeuveringOrbit` (slot in as subclasses).
- Multi-star scene loading; galactic-frame top-body motion (`IVFixedPositioner` covers the
  first step).
- Collisions (still out of scope for ivoyager_core; geometry's surface queries are a
  prerequisite a project could build on).


## Appendix A — Required API surface, GUI consumers (evidence)

Compiled from exhaustive sweep of `ui_widgets/`, `ui_components/`, `ui/`,
`planetarium/gui/`, assistant GUI suites. Tags: [typed] static typing, [duck] dynamic.

- `IVBody.bodies` [typed] — selection dictionaries, nav buttons/system, views, capture dialog.
- `BodyFlags` enum + identity bits [typed] — nav system, HUDs state, selection_data;
  **raw ints baked in `huds_box.tscn`** (16, 64, 128, 512, 1024, 2048, 8192).
- `name` [both], `flags` [both], `satellites` [typed], `within_lifespan` +
  `within_lifespan_changed` [typed], `get_mean_radius()` [typed].
- `texture_2d` [both → becomes `get_selection_texture_2d()`], `texture_slice_2d` [typed →
  method].
- Selection protocol: 14 `get_selection_*` [duck], `get_float_precision(path)` [duck].
- String paths via `IVTree.get_path_variant` [duck]: `mean_radius`,
  `characteristics/<38 keys>`, `components/atmosphere|trace_atmosphere|photosphere`,
  `orbit/get_periapsis|get_apoapsis|get_semi_major_axis|get_eccentricity|get_period|get_inclination`,
  `get_rotation_period`, `get_axial_tilt_to_orbit`, `get_axial_tilt_to_ecliptic` — all
  become path *data* updates per §9.
- `get_periapsis_label()` / `get_apoapsis_label()` [duck, probed with `has_method`] — moving
  to GUI side is graceful (probe simply fails over).
- Camera protocol [duck]: `get_camera_radius`, `get_camera_ground_basis`,
  `get_camera_orbit_basis`, `get_camera_lat_lon_type`.
- Mouse-over: `object.name` on world targets; `get_fragment_text(data)` on fragment source
  (moves to `IVPathVisual`).
- Node-ness: `selection is Node3D` / `is IVBody` fallbacks.

## Appendix B — Required API surface, program consumers (evidence)

- Builders: `IVBody.bodies`, `create_from_astronomy_specs` (→ new `create`), `flags`,
  `add_child` tree ops, `begin`/`end` writes (only external writes in v0.2);
  orbit builder reads `parent.name`, `parent.get_positive_axis()`,
  `parent.get_gravitational_parameter()`.
- `IVBodyFinisher` (worker threads): `has_orbit()`, `has_light()`, `has_rings()`, `name`,
  `add_child_to_body_visual()`; constructor injection of body ref into position/path/rings
  visuals.
- Managers iterating `bodies` per frame: `IVFarwarpManager` (`visible`, `update_farwarp` —
  removed), `IVSunOcclusionManager` (`visible`, `flags`, `global_position`, `mean_radius`,
  `get_north_axis`, `get_equatorial_radius`, `get_polar_radius`, `star`, `star_orbiter`,
  `parent`, `satellites`, `body_visual`), `IVExposureManager` (`visible`, `mean_radius`,
  `global_position`, `flags`, `rotation_axis`, `characteristics.albedo/absolute_magnitude`).
- `IVTimekeeper`: `get_rotation_rate/at_epoch`, `get_orbit_mean_motion/mean_longitude`
  (universal-time body).
- Sleep/lazy: `top_bodies`, `satellites`, `set_sleeping()`, `is_lazy_model_uninited()` /
  `lazy_model_init()`; both driven by `IVGlobal.camera_tree_changed`.
- HUD/graphic nodes: position visual (`huds_visible`*, `farwarp_position`*, `flags`,
  `get_hud_name`, `huds_visibility_changed`*), path visual (`orbit_changed`,
  `huds_visibility_changed`*, `get_path_frame`*, `is_showing_orbit`*, `get_orbit_display`*,
  `get_display_state_paths`*, `is_camera_focused`*, `get_fragment_data`*,
  `get_translation_to_ancestor`), rings (`name`, star lookup), shells sun-mode
  (`characteristics.color_b_v/absolute_magnitude`, `global_position`, `add_child`),
  dynamic light (`characteristics.absolute_magnitude`). Starred items are removed/relocated
  by §8.
- SBG: persisted `secondary_body: IVBody`, `get_orbit_semi_major_axis()`,
  `get_orbit_mean_longitude()` (Lagrange).
- `IVTrajectory` (as consumer): `bodies`, `parent` chain walk,
  `get_translation_to_ancestor()`; holds body refs (cycle broken on clear).
- Assistant/tools: `bodies`, `flags`, `parent`, `satellites`, `mean_radius`,
  `gravitational_parameter`, `has_orbit()`, `get_orbit()`, `get_position_vector()`,
  `get_state_vectors()`, `make_body_visual()`, `get_camera_radius()`, `get_triaxial_size()`.
- Long-lived body refs held externally (teardown discipline via
  `about_to_free_procedural_nodes` must survive): sleep manager, occlusion manager
  (+ per-name candidate lists), exposure manager, timekeeper, position/path/rings visuals,
  shells sun-mode, SBG (persisted!), trajectory, selection manager (as `Object`).


## Decision Log

- 2026-08-29 — Initial draft from full body.gd read + exhaustive consumer inventories (GUI
  and program sweeps). All sections open for review; recommendations marked "proposed";
  unresolved items in §13.
- 2026-09-04 — Added "Under Consideration: camera-relative placement" to §4.3, out of the ISS
  shadow-shake investigation. Not a decision; the ground-rule tension noted there needs an
  owner ruling before it goes further.
