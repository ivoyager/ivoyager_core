# The Visual Model

This document describes how I, Voyager places, scales, culls, shadows and picks what the
camera sees: the machinery that turns a double-precision simulation spanning some fifteen
orders of magnitude into a scene a float32 render pipeline can draw without shakes,
missing geometry or absurd shadows. It is about the logic and the invariants;
implementation detail lives in the class and shader docs. Its sibling
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) covers how bright each pixel is; this one
covers where everything is, how big it renders, what stands between it and the light, and
how the mouse finds it. A system that has both a photometric and a spatial face (rings,
the sun, the star field) appears in both documents, split by concern and cross-referenced.

## Overview: two number systems

The simulation's truth is double precision; the render pipeline is not. A GDScript
`float` is 64-bit, and every scale-sensitive computation — orbital state, trajectory
paths, time — runs in it (state paths and rebase anchors are `PackedFloat64Array`s
precisely so they stay in it). But Godot's `Vector3`, every `Node3D` transform, and
everything on the GPU is float32 in a standard engine build. Float32 carries a relative
step of about 1.2e-7 (one ULP), which is a property of *magnitude*: a position at 1 au
quantizes at ~18 km, at 40 au at ~700 km. Against that, one screen pixel at the reference
view (50° fov, 1080 lines) subtends ~8e-4 rad — so a naive f32 scene shows kilometer-scale
shakes at planet range and loses distant content entirely to the depth buffer's limits.

Four mechanisms bridge the gap, and the rest of this document is mostly their contracts:

- **Parenting, so imprecision cancels.** Bodies are scene-tree children of what they
  orbit, and the camera is a child of its target body. The f32 rounding of a long
  global-transform chain is large, but it is *shared* by everything under the same
  ancestors — the camera and its target carry the same error, so their relative geometry
  is precise. Several systems exploit this deliberately (the orbit line's rebased tier
  reparents *in order to* share the camera-body's error; spacecraft survive high time
  speed for the same reason — see TODO).
- **Origin shifting.** `IVCamera` re-translates the Universe root every frame to hold
  itself at the world origin, so world-space magnitudes near the camera — where precision
  is visible — stay small.
- **Farwarp compression.** Content beyond a camera-relative start distance is re-rendered
  along its true view ray at logarithmically compressed distance, angular size exactly
  preserved, so the whole universe fits inside a camera far plane that float32 limits cap
  at 6 decades past the near plane (`IVFarwarpManager`).
- **Per-frame f64 residual feeds.** Where a drawn f32 curve must agree with an f64
  position — the orbit line under a zoomed camera — the CPU computes the residual in
  doubles each frame and the shader applies it (the render-frame pin, the rebased line).

One consequence is worth stating as a principle, because it decides what a second camera
may do: **the whole per-frame render state is conditioned for exactly one viewpoint.**
The origin shift, the `iv_farwarp_start` global, every farwarp-remapped vertex, the HUD
symbol placements and the mouse-probe globals all assume the live `IVCamera`'s position.
A secondary camera (the hi-res screenshot rig) must copy that camera's global transform
exactly and may differ only in render size; a camera placed anywhere else sees geometry
warped for someone else. For the same reason a secondary camera must be a plain
`Camera3D`, never an `IVCamera` — announcing itself on `IVGlobal.current_camera_changed`
would hand the farwarp, occlusion, picking and world-controller systems to a throwaway.

## Origin shifting and the frame order

Each frame `IVCamera` processes its own motion, then subtracts its global position from
the Universe root's translation — camera at origin, to the f32 rounding of its ancestor
chain. Ordinary tree children ride the shift automatically (their locals are untouched;
the world moves under them). Two kinds of code do not, and both are ordered explicitly:

| Process priority | Who | What it does / reads |
|---|---|---|
| 0 (tree order) | `IVBody` instances, `IVDynamicLight`, `IVCamera` | Bodies set their local positions from f64 orbital math; the camera moves and applies the shift. Tree order means the star's subtree (its top light included) processes *before* the camera's parent chain. |
| +100 | `IVFarwarpManager`, `IVSunOcclusionManager` | Read the settled, post-shift camera and body globals; publish this frame's `iv_farwarp_start`, per-body `farwarp_position`, occluder uniforms and ambient feed. |
| +101 | `IVBodyPositionVisual` | The one `top_level` node in the stock tree places itself from `farwarp_position` set at +100. |

A `top_level` node opts out of transform inheritance, so it does *not* ride the shift: it
must be placed after the shift settles, from post-shift values. Placing it from pre-shift
state leaves it one frame of camera world-motion behind — the camera's parent moves
kilometers per frame — which reads as violent shake on fast nearby orbiters. That failure
mode is why the +100/+101 ordering exists and must be respected by anything added to it.

A few reads are deliberately one frame behind, all smooth quantities where a frame is
harmless: every occlusion-dimmed light reads last frame's `camera_sun_visible_fraction`
and last frame's `farwarp_start` for its shadow-reach clamp (the manager that writes both
runs at +100, after lights — both lags documented at the site); `sun_light_energy` fed to
compositing shaders is likewise one frame of exposure ramp behind, far under a display
code; and the top light's aim reads whatever the camera's global position was when the
star's subtree processed, typically the previous frame's.

Distance computations are shift-invariant (both endpoints carry the same Universe
translation), so code at priority 0 may difference two same-frame globals freely; what it
may not do is place a world-space node from them before the shift settles.

## The depth range

`IVCamera` sets `near = 0.1 ×` and `far = 1e6 ×` its distance to its parent each frame —
a constant near:far ratio of 1e7. The ratio is hard-capped at ~2^24 (~1.7e7) by float32
*CPU* math in the engine: `Projection::get_projection_planes()` extracts the far plane as
(w row − z row), which catastrophically cancels once far/near exceeds the float32
mantissa. The first loud failure (at a ratio of 1e8) is `RenderingLightCuller` erroring
every frame with garbage frustum points feeding directional shadow-caster culling;
verified in Godot 4.7-stable and 4.8-dev (2026-07). The GPU depth buffer is *not* the
limit — reversed-Z with float depth since Godot 4.3 — and the historical ceilings (1e9 in
Godot 3.2, then 1e6) were earlier symptoms of the same wall. Do not push the ratio past
~1e7.

Six decades cannot span a spacecraft strut and Neptune, so distant content necessarily
falls beyond the far plane whenever the camera is zoomed to something small. Nothing is
allowed to vanish for it: everything beyond a start distance is farwarp-compressed back
inside.

## Farwarp

Farwarp is a view-layer remap, published once per frame by `IVFarwarpManager`. With
`T = camera-to-parent distance × IVCoreSettings.farwarp_start_ratio` (1e4):

```
g(d) = d                      for d <= T     (exact identity)
g(d) = T * (1 + ln(d / T))    beyond         (C1-continuous at T)
```

A position beyond T is pulled inward *along its own view ray* to distance g(d), uniformly
scaled by g(d)/d — screen direction and angular size are therefore **exactly** preserved,
not approximately. True `IVBody` positions are never modified; only rendering moves.

Its invariants carry the whole system:

- **Monotonic, so occlusion order is preserved**, including a transit across T: whatever
  was in front stays in front, at compressed depth separations.
- **T tracks the far plane by construction.** T and `far` use the same distance
  expression, so T/far is the constant `farwarp_start_ratio / FAR_MULTIPLIER` = 1e-2, and
  the compressed universe spans less than ~29× T (the log of the maximum camera distance
  over the smallest T) — everything lands within ~30 % of the far plane at any zoom.
- **T may change arbitrarily per frame with no visual consequence.** Angular size and
  direction are preserved at any T, so the camera's parent handoff mid-transfer — which
  steps the parent distance, and with it T and the far plane, discontinuously — moves
  nothing on screen; only depth precision redistributes.
- **The remap is a render-depth remap, not a deformation.** The lit-surface variants keep
  the normal frame at its true (un-remapped) view orientation, so PBR shading and the
  day/night terminator are unchanged, and `VIEW` survives unchanged because a position
  scaled along its own ray keeps its screen direction (which is what lets disc photometry
  ride it untouched — see the sibling document).

A worked example, camera 100 m from the ISS (T = 1000 km, far = 1e5 km, near = 10 m):

| object | true distance | rendered distance g(d) |
|---|---|---|
| Moon | 3.84e5 km | 6,950 km |
| Sun | 1.496e8 km | 12,920 km |
| Neptune (near conjunction) | ~4.5e9 km | ~16,300 km |
| α Centauri | 4.1e13 km | 25,400 km |

Every angular size is exact, every occlusion correct, and the whole sky sits a quarter of
the way to the far plane. Zoomed to a planet instead, T already exceeds the solar system
and the remap is identity everywhere — farwarp engages only when the camera closes on
something small.

**Almost every consumer applies g() per-vertex on the GPU, in view space** — the geometry
sits at its true position and the shader compresses it (`shaders/_farwarp.gdshaderinc`,
driven by the `iv_farwarp_start` global; ≤ 0.0 disables). Body surfaces and shells take
the lit variants under `skip_vertex_transform`; orbit and trajectory lines, small-body
points, the catalog star field and the sun's far point take the plain remap. The star
field is the extreme case that proves the design: its vertices are true ecliptic star
positions, parsecs out in internal units, and the same per-vertex remap that saves the
Moon from the far plane puts every star behind every simulation visual at any zoom.

**The one CPU-placed consumer is the HUD position symbol** (`IVBodyPositionVisual`, a
single `top_level` point that cannot ride a vertex shader). Its compressed position,
`IVBody.farwarp_position`, is assembled camera-relatively —
`camera_global + (body_global − camera_global) × g/d` — because origin shifting keeps
`camera_global` small, so the f32 rounding stays proportional to the *compressed*
distance. Never derive it by differencing large true-scale positions; the rounding of the
large terms swamps the small result.

Two obligations fall on every farwarp consumer:

- **Defeat frustum culling.** Culling tests the true-scale AABB against the far plane,
  and the true positions fail that test exactly when farwarp is doing its job. Every
  consumer sets a `custom_aabb` sized to always contain the camera
  (`max_camera_distance`, or the star field's own extent if larger): shells models, rings,
  path visuals, SBG points and orbit lines, the star field, the sun point. A new farwarp
  consumer that forgets this renders correctly until the camera zooms in somewhere, then
  vanishes.
- **Keep enough vertices to follow the curve.** A surface far beyond T is compressed
  near-uniformly, but geometry that *spans* decades of distance bends along g(). The
  shared ring `PlaneMesh` is subdivided (`plane_mesh_subdivisions` = 64) for exactly
  this; line meshes carry hundreds of vertices per orbit anyway.

What deliberately does **not** ride farwarp: anything that computes from true positions.
Occlusion (below), exposure metering, and mouse targeting all read true geometry — which
is consistent *because* the remap preserves screen direction, so a true-position
unprojection lands on the same pixel as the remapped rendering. This invariant — true
math, warped drawing, same pixels — is load-bearing across the model; the picking and
orbit-line sections both depend on it.

Disable the whole system with `IVCoreSettings.apply_farwarp = false` (the global goes to
0.0, every shader takes the identity branch, the HUD symbol becomes an ordinary child).

## Sun occlusion: analytic shadows

Astronomical-scale shadows — Saturn's rings on the globe and its moons, the planet on the
rings, eclipses, transits, a craft entering its planet's shadow — do not use shadow maps
at all. Shadow maps cannot serve them twice over: a directional map's world-space texel
footprint at these spans is tens to hundreds of kilometers, far coarser than real
occluder structure (a ring shadow's profile, an eclipse penumbra); and under farwarp the
caster geometry warps in light space while the receiver warps in camera space, so a map
shadow across the warp boundary is wrong *by construction*. Instead
`IVSunOcclusionManager` feeds true-space geometry uniforms to receiving materials, whose
fragments compute the visible fraction of the sun's disc analytically
(`shaders/_sun_occlusion.gdshaderinc`) — exact at any zoom, farwarp-immune (fragments
capture the true world position in `vertex()` before the remap overwrites it).

**Receivers opt in by declaring the uniform interface** (detected by the presence of
`occluder_data_a`), and are discovered lazily from each body's visual, rediscovered
whenever the visual instance changes (lazy models build late and can be swapped). Stars
are never receivers. On the Forward+/Mobile renderers the fraction rides `AO` with
`AO_LIGHT_AFFECT = 1.0` — the engine's own PBR and shadow path, no custom `light()`. On
Compatibility, where AO never reaches direct light, the fallback multiplies it into
`ALBEDO` and, as its square root, into `SPECULAR` (see *Renderer parity* in the sibling
document).

**Occluder selection.** A receiver's candidates are its parent, its parent's other
satellites, and its own satellites — stars and sub-kilometer bodies excluded
(`MIN_OCCLUDER_RADIUS` = 1 km) — so a moon takes its planet and sibling moons, a planet
takes its own moons (a solar eclipse shadow crossing Earth), and heliocentric bodies take
nothing. Candidates whose shadow reaches the receiver's disc are ranked by **linear
clearance** — how far the occluder's penumbra reaches past the receiver's limb — and the
best `MAX_OCCLUDERS` (6) fill the uniform slots. Clearance rather than an angular score,
deliberately: an angular score carries a parallax term that blows up as a candidate gets
close, so a nearby moon whose shadow is nowhere near the disc could starve the slot a
genuinely transiting distant occluder needs. Candidate lists are built once per receiver
and cached for the session (see TODO for the constraint this encodes).

**The math, in two regimes plus a stretch.** The visible fraction of the sun's disc past
one occluder is the exact two-circle lens overlap in the planar small-angle
approximation, with exact containment tests, so totality, annularity and partial phases
all behave. When the occluder disc is much larger than the sun's (b > 20a — Saturn from
its rings is ~1700×), the lens formula cancels catastrophically in float32 (an a²-scale
result from b²-scale terms, sparkling along the penumbra), so the edge is treated as
locally straight and the stable chord fraction used instead. Oblateness matters —
Saturn's flattening is visible in its shadow on the rings — so an occluder is an oblate
spheroid, handled by stretching space along the pole so it becomes a sphere and applying
the same affine map to the sun ray. Multiple occluders multiply (independent-occlusion
approximation). A triaxial occluder is approximated by its longest and polar semi-axes;
nothing shadowed by one is small enough to notice.

**Ring shadows** are a separate term: transmission through an annular layer holding a 1D
radial opacity profile (R8, generated with the ring assets), with slant-path optical
depth (`pow(1 − α, 1/cos)`) and a physically sized penumbra — the shader samples the mip
level whose texel footprint matches the sun's angular size times the ray length, floored
at the screen footprint so sub-pixel ringlet shadows filter instead of aliasing into
dashes. That mip trick is how the shadow edge gets its correct softness for free. Ring
uniforms feed every receiver in the ringed body's planetary system, so moons get ring
shadows too; the ringed body itself is fed to its own rings material as their occluder
(the rings' own transmission term stays off — rings do not self-shadow, deliberately).

**Every CPU mirror must stay in exact sync with its GLSL twin** — the manager's statics
are the same math, used for metering and the camera fraction (the ring mirror stands in
for mip sampling with a bounded box average). Both sides carry the same containment
epsilons and the same 20× straight-edge threshold; an edit to either file is an edit to
both.

**The camera-point fraction** (`camera_sun_visible_fraction`) is the same computation run
once at the camera's position — the camera's planetary system's bodies plus ring
transmission — and it scales the energy of the *local* (near/middle) lights. That is how
spacecraft and other shadow-map-scale objects get eclipse and ring shadows without any
shader term: at their scale the occlusion field is uniform, and their culled visibility
ranges keep anything camera-remote off screen (the guarantee is airtight for the craft
domain, whose visibility bubble is kilometers; see TODO for the middle domain, where it
leaks). It also carries eclipse into the photometric chain: the same factor dims
`light_energy`, so an eclipsed moon meters dark and night adaptation opens inside a
totality (sibling document).

**The ambient invariant: occlusion may remove direct sunlight only, never starlight.**
`AO` multiplies engine ambient regardless of `AO_LIGHT_AFFECT`, the compat albedo
multiply darkens everything albedo touches, and engine ambient cannot be compensated
exactly from a shader. So receivers opt out of engine ambient entirely
(`ambient_light_disabled`) and rebuild diffuse ambient as emission from the manager-fed
`ambient_light` uniform — which the occlusion then physically cannot touch: a shadowed
region and the sun-less night side settle at the same ambient level. The feed continues
when `IVCoreSettings.apply_analytic_shadows` is false (that setting disables only the
shadow terms and the light dimming), so night sides never go black.

**The model assumes one star.** The manager feeds a single sun direction and one occluder
set, and one AO value scales all direct light uniformly — a fragment eclipsed from star A
but lit by star B cannot be expressed in it. The occlusion math itself is already
sun-parameterized and reusable per star; only the application is single-sun (per-light
attenuation in a custom `light()`, viable now that the METER scale-sensitivity that once
ruled it out is resolved, or additive per-star passes). See the shaderinc header.

## Local shadow maps

What shadow maps *are* for is the local, true-position scene: a lander in a crater, a
craft's dish shadowing its own bus. `IVDynamicLight` builds a per-star light stack from
`dynamic_lights.tsv`, each row lighting one **size domain** via `light_cull_mask` against
the layer bits `IVCoreSettings``.size_layers` assigns by body radius (≥ 100 km → far
domain 0b0001, 0.1–100 km → middle 0b0010, < 0.1 km → near 0b0100). Only the near and
middle lights carry shadow maps; the far light never does. Shadow reach follows the
camera (`floor`, `+ target distance`, `+ star-orbiter distance`, capped by `ceiling` —
100 km near, 1e5 km middle), and the near/middle energies carry the camera-point
occlusion fraction above.

Two rules keep the maps honest across the warp boundary:

- **No map shadow may cross the farwarp boundary.** Everything remapped renders at
  distance > T while every true-position receiver sits inside it; without the clamp
  (`directional_shadow_max_distance` ≤ last frame's `farwarp_start`), near casters stamp
  oversized shadows on warp-compressed bodies, and a warped body's own light-space
  imprint false-shadows its camera-space self.
- **Only true-position "terrain" casts.** Casters carry the
  `IVGlobal.LOCAL_SHADOW_CASTER` layer bit (0b1_0000_0000, the near/middle rows'
  `shadow_caster_mask`). Craft-scale bodies hold it statically; larger bodies are granted
  it per frame only while closer than both `farwarp_start` and
  `IVCoreSettings.local_shadow_caster_ceiling` (1e5 km — which must cover the largest
  shadowed `shadow_max_ceiling` in the table; they are equal today, a coupling held by
  convention). The ceiling keeps sunward planets at astronomical distances from being
  extruded into the maps. A shell that builds after a dynamic grant adopts its ancestor
  visual's current state, since the grant recursion is change-gated.

Under the Compatibility renderer the stack degrades to a single unshadowed light unless
`IVCoreSettings.apply_gl_compatibility_shadows` (default true) re-enables the multi-light
path; the historical defects that once forced the fallback — cull masks not respected,
wrong energy with multiple lights, color shifts once any light casts (godotengine/godot
#90259) — should be re-tested on a given target before relying on it. The analytic
astronomical shadows are independent of all of this and work either way.

## Culling, visibility and lifecycle

**Distance culling is angular-size culling in disguise.** Bodies (and rings) set
`visibility_range_end` to `radius × radius_multiplier_visibility_range_end` (4000), so a
body culls when its angular diameter falls to ~1/2000 rad — about 0.6 px at the reference
view. Sub-pixel, so the pop is invisible; but note what it forfeits: a real planet at
that size is a naked-eye *point source* (Venus is culled from Earth at 7,000–43,000
radii), which the model currently hands to the HUD symbol instead of to photometry. The
sun opts out (`is_sun` sun-mode manages its own visibility by pixel radius — a fixed
distance cull is zoom-blind and would clip a still-resolved disc when zooming in), and
that machinery is the template for fixing the planet case (see TODO). A packed-scene
model that authors its own `visibility_range_end` keeps it; only the engine's "unset" 0.0
is filled in.

**Layers place a body in a lighting domain, not a visibility class** — `size_layers`
exists so each size scale can be lit (and shadow-mapped) at its own range; see *Local
shadow maps*.

**Lazy models.** Bodies flagged `lazy_model` (spacecraft — small but heavy models — and
the hundreds of small outer moons) build no `IVBodyVisual` until the camera visits them
or a closely associated lazy body (`IVLazyModelInitializer`, on `camera_tree_changed`).
The occlusion manager's lazy material discovery exists for exactly this. Once built, a
visual persists for the session. `IVSleepManager` additionally sleeps far-from-camera
body processing.

**HUD visibility policy.** Each body maintains `huds_visible` for its symbol, label and
orbit line: hidden when too close (`_min_hud_dist`, the `hide_hud_when_close` setting)
and when not **visually separate** — closer than its own orbit size times a multiplier —
so moon HUDs collapse away as the camera pulls back from their system. HUD symbol and
name render at `HUD_RENDER_PRIORITY` (20), above the highest shell priority, because
transparent surfaces sort by priority before depth and a HUD at 0 blends under its
planet's cloud deck.

## Orbit and trajectory lines

`IVPathVisual` renders a body's orbit or trajectory in three tiers, all farwarp-aware
(`path.gdshader`), stepping up as f32 line error would become visible:

- **Tier 1 — coarse.** Camera elsewhere or far: an orbit draws as a shared unit conic
  mesh (`vertecies_per_conic_mesh` = 4096, sized so facet angle at the apsides stays
  under ~0.5° at e = 0.98) plus a transform; a trajectory as a plain polyline. Line
  vertices at au magnitude carry ~magnitude × 1.2e-7 of f32 rounding — invisible from
  far.
- **Tier 2 — rebased.** While the camera is focused on this body and
  (camera-body distance from the line's frame) / (viewing distance) exceeds
  `REBASE_PRECISION_RATIO` (500 — the f32 rounding is then ~0.3 px), the visual
  reparents under the camera-body *so it shares the camera's global-transform
  imprecision, which then cancels*, and rebases the body's 64-bit state path to a
  near-body anchor (small numbers, precise), tracking the body's drift each frame and
  re-anchoring when it outruns the dense core.
- **Tier 3 — Hermite smoothing.** The rebased base vertices are refined by
  time-parameterized cubic Hermite interpolation using the state path's true velocities
  as tangents, tessellated adaptively against view-scaled chord-length, deviation and
  bend bounds — a modest base density smooths to a sub-pixel line at any zoom without
  re-solving Kepler.

**The render-frame pin** closes what no base density can: the drawn curve's deviation
from the true body position is *absolute* (the Hermite bow between knots, or error in
the path data itself), so it can dominate the view at close zoom no matter how dense the
base. Each frame the visual computes the f64 body-minus-curve residual and the shader
shifts a window of the line by it, tapering to zero — the line passes exactly through
the body at any zoom. The window is sized to the *local knot chord* — the residual
field's own correlation length — never to the view: any tighter taper compresses the
field's amplitude into a short stretch of line and paints a breathing S-bend beside the
body; spread over the chord, the taper bend stays sub-pixel at any zoom. Base pass and
id overlay apply pin and farwarp identically, keeping their pixels aligned (the picking
section depends on it). The pin is also what frees knot density to serve smoothness
alone: state paths carry 500 knots per family (per trajectory segment), whose worst
mid-knot Hermite bow (N⁻⁴) shows only mid-field, where there is no reference to see it
against.

Small-body groups draw their orbit lines far more cheaply: one low-res loop
(`vertecies_per_orbit_low_res` = 100) instanced per asteroid in a `MultiMesh`, through
the farwarp-only `farwarp_vertex.gdshader` — no pin, no rebase, no per-frame CPU.

## Point fields

Three point-sprite systems share one pattern — true positions in the mesh, farwarp in
the vertex shader, an always-pass `custom_aabb`:

- **The catalog star field** (`IVStarsVisual`): one `PRIMITIVE_POINTS` surface from the
  magnitude-binned star binaries, vertices at true ecliptic positions, `CUSTOM0`
  carrying (V, B−V) for the photometric chain (sibling document). A fixed node under
  Universe, so it rides the origin shift, builds once and survives system rebuilds.
- **The sun's far point**: a 1-vertex points mesh parented to the star body, crossfaded
  with the resolved disc by pixel radius (sun-mode, sibling document); spatially it is
  just another farwarp point whose AABB always contains the camera.
- **Small-body points** (`IVSBGPositionsVisual`): tens of thousands of asteroids per
  group, each vertex computing its own position *on the GPU* from orbital elements
  packed in `CUSTOM0..2` — Kepler's equation solved per vertex per frame
  (`shaders/_orbit.gdshaderinc`; iteration unrolled because a `while` loop broke WebGL1),
  with nodal/apsidal precession terms, against the `iv_time` global. `VERTEX` carries
  the point's *fragment id*, not a position — `POSITION` is written directly — which is
  why the mesh AABB means nothing and `custom_aabb` spans the group's apoapsis (or the
  camera range under farwarp). Points render as the group's symbol shape masked from
  the atlas in the fragment shader, or as plain points.

The f32 arithmetic here deserves its numbers, because it looks alarming and is not:
`iv_time` (seconds from J2000) is ~8.4e8 in 2026, so it quantizes at 64 s — but a
main-belt asteroid moves ~5e-8 rad/s, so the along-track quantization is ~3e-6 rad ≈
1,200 km, under 2 arcsec from 1 au: two orders below a pixel, for *points*. The same
argument covers the f32 elements and the in-shader trig. (The bodies drawn as real
geometry never touch this path — their positions come from f64 CPU math.) The quantum
doubles at each power-of-two boundary of seconds from J2000 (2034, 2068, 2136), which
still clears the bar by an order of magnitude through the 2090s.

## Mouse picking

Picking has two halves, split by what is being picked.

**Bodies: CPU screen-space targeting.** Every in-lifespan body pushes itself to
`IVWorldController` each frame (`update_world_target`) with its camera distance; the
controller unprojects the *true* global position and keeps the target whose screen
distance to the mouse is least, within a click radius (`min_click_radius` = 20 px,
enlarged for bodies that resolve larger on screen). Unprojecting true positions is
correct *because* farwarp preserves screen direction — the projection of where the body
really is lands on the pixels where it is drawn, beyond the far plane or not. Bodies
that are not visually separate from their parent (see the HUD policy) withdraw
themselves, so a click on a distant planet is never stolen by one of its moons.

**Lines and points: GPU fragment ids.** An orbit line or an asteroid point has no
Node3D position to unproject — the honest answer to "what is under the mouse" is
whatever *fragments* landed there. Producers register a 30-bit id per pickable thing
(`IVFragmentIdentifier`; data keyed by id, target implements `get_fragment_text` for
`IVMouseTargetLabel`), encoded as three channel values in [1, 1024] (offset by +1 so a
zero is a clean reject). Id-bearing shaders write the encoded id into `ALBEDO` — at a
sparse every-3rd-pixel grid within ±`fragment_range` (9) of the mouse, 49 pixels in all,
so the stamp is invisible at a glance — through `id_broadcast()`, which carries each
channel in **[0.5, 1.0]**: topping out exactly at the glow threshold (a raw id bloomed a
blob onto the cursor; sibling document), and confining the accept window to one binade
so content brighter than an id cannot decode as one. The band is one binade of RGBA16F,
whose half-float step is 1/2048 — exactly 1024 representable values per channel, which
is where the 30 bits come from; a broadcast that did not survive storage exactly would
decode as the *wrong* id. An `IVFragmentIDCompositorEffect` on the live camera
dispatches a tiny compute probe at `POST_TRANSPARENT` — pre-tonemap, pre-glow, so the
picture can never perturb picking — reads the resolved HDR buffer over the same grid,
returns the id nearest the mouse asynchronously, and the identifier holds it against
dropout (40 frames or 20 px of mouse travel) so a thin line does not flicker its label.

Three id spaces serve three producer shapes: a per-body orbit line stamps one uniform id
(`path_id.gdshader`, a `material_overlay` above the base pass — pin and farwarp applied
identically so overlay and base occupy the same pixels); an SBG orbit line carries its
id per instance (`instance_id.gdshader`, `INSTANCE_CUSTOM`); an SBG point carries it per
vertex (`VERTEX` *is* the id). The id overlay pattern keeps identification orthogonal to
appearance — the base material knows nothing about picking.

The system requires a `RenderingDevice`: on the Compatibility renderer the identifier
removes itself and every producer's `if _fragment_identifier:` guard falls back to the
plain materials — no line/point mouse-over on the web export, while body picking (pure
CPU) is unaffected. One stated assumption: window pixels equal internal-buffer pixels
(no FSR / resolution scaling) — the broadcast grid and the probe would misalign under
scaling (see TODO).

## Close-range detail

A fixed-resolution map runs out at orbital range — texels are kilometers wide — so the
surface and cloud shaders synthesize what the map lacks (`shaders/_detail.gdshaderinc`):
a C2-continuous bicubic lookup removes the texel squares, and model-space value-noise
FBM supplies sub-texel structure. Two hard-won constants live in that include: the hash
must be axis-asymmetric (a symmetric one correlates the field along the model axes and
prints faint ridgelines crossing in "X" shapes), and the fade must be the C2 quintic
(the standard cubic's discontinuous second derivative at cell boundaries is amplified by
FBM into grid-aligned creases). Pure functions only; each including shader owns its
uniforms and blending, and octave count is a parameter because a textual `#include`
cannot see a caller's later `const`.

## Time compression and the render

The simulator draws at time speeds from pause to ~1e7× and beyond, and three visual
mechanisms answer to that:

- **`iv_time` quantization** is covered under *Point fields*: harmless for points, by
  two orders of magnitude, through this century.
- **The stroboscope** (`stroboscope_frames_per_second`, default 0.0 = off): at high
  speed a fast rotator's per-frame rotation aliases chaotically; the option replaces the
  "natural" stroboscopic effect of process frames with a stable simulated one (a fixed
  simulated frame rate, plus a motion-blur term), which reads better at ~5–10 fps
  simulated.
- **High-speed registration loss** is the one known open defect in this document's
  domain, and it is recorded in the TODO rather than here.

## Renderer / platform matrix

The photometric matrix (color space, glow, exposure parity) is in the sibling document;
this is the spatial one.

| System | Forward+ / Mobile | Compatibility (web export) |
|---|---|---|
| Origin shift, farwarp, depth range | identical | identical |
| Analytic occlusion | `AO` + `AO_LIGHT_AFFECT` on the engine's PBR path | `compat_albedo_shadow`: albedo multiply, √ into SPECULAR |
| Local shadow maps | multi-light stack | same, iff `apply_gl_compatibility_shadows` (default true; re-test the historical defects on a new target) — else one unshadowed light |
| Body mouse targeting | CPU, identical | identical |
| Line/point picking | compute probe at `POST_TRANSPARENT` | **absent** (no RenderingDevice); producers fall back to plain materials |
| GPU Kepler points | identical | identical (solver unrolled for old GL compilers) |

## Settings summary

| Where | Setting | What it does |
|---|---|---|
| `IVCamera` | `NEAR_MULTIPLIER` / `FAR_MULTIPLIER` (constants, 0.1 / 1e6) | Depth planes as multiples of camera-to-parent distance. Ratio hard-capped ~1e7 (float32 plane extraction); do not raise. |
| `IVCoreSettings` | `apply_farwarp` | Enables the compression system (manager, shader global, HUD symbol placement). |
| | `farwarp_start_ratio` | T as a multiple of camera-to-parent distance (1e4). Must stay well under `FAR_MULTIPLIER`; 1e4 leaves 100× headroom while the compressed universe spans < ~29× T. |
| | `apply_analytic_shadows` | Enables the analytic shadow terms and the camera-fraction light dimming. Off, astronomical shadows are absent entirely (maps don't serve them); the ambient feed continues regardless. |
| | `apply_gl_compatibility_shadows` | Shadowed multi-light stack on the Compatibility renderer (vs. one unshadowed light). |
| | `apply_size_layers` / `size_layers` | Layer bits by body radius — the lighting size domains ([100 km, 0.1 km] → three domains). |
| | `local_shadow_caster_ceiling` | Dynamic `LOCAL_SHADOW_CASTER` grant range (1e5 km; must cover the largest shadowed `shadow_max_ceiling` in `dynamic_lights.tsv`). |
| | `radius_multiplier_visibility_range_end` | Distance cull in body radii (4000 ≈ 0.6 px angular diameter). |
| | `max_camera_distance` | Camera range limit; also sizes every always-pass `custom_aabb`. |
| | `plane_mesh_subdivisions` | Ring mesh subdivision, enough for per-vertex farwarp across the ring span. |
| | `vertecies_per_orbit` / `vertecies_per_trajectory_segment` | State-path knots (500): smoothness base for the rebased line; the pin owns trueness. |
| | `vertecies_per_conic_mesh` / `vertecies_per_orbit_low_res` | Shared unit conic (4096) for coarse body orbits; low-res loop (100) for SBG orbit lines. |
| | `stroboscope_frames_per_second` (+ blur settings) | Artificial stable stroboscope for fast rotators at high time speed (0 = off). |
| `dynamic_lights.tsv` | per-row masks, shadow distances, `apply_sun_occlusion` | The light stack: domains, shadow reach, which rows dim by the camera-point sun fraction. |
| `IVSunOcclusionManager` | `MAX_OCCLUDERS` / `MIN_OCCLUDER_RADIUS` (constants) | Occluder slots (6, matching the shader array) and the sub-km candidate cutoff. |
| `IVWorldController` | `min_click_radius` | Body-picking screen radius floor (20 px). |
| `IVFragmentIdentifier` | `fragment_range`, `drop_id_frames`, `drop_id_mouse_movement` | Probe grid half-extent (9 → 49 sampled pixels); id retention against flicker. |
| `IVPathVisual` | `REBASE_*`, `PIN_*` (constants) | Rebase trigger (500 → ~0.3 px), rebake policy, tessellation bounds, pin window sizing. |
| `IVBodyPositionVisual` | `HUD_RENDER_PRIORITY` (constant) | HUD symbol/name above the shell transparency range. |

## TODO

- **High-speed render registration loss** — the one large known defect. At extreme
  time speed viewed from far out (reproduced at ≥ 1e7× at 137 au), every visual
  parented under the camera-body loses registration with it except spacecraft and the
  camera itself: the engine's f32 transform chain rounds differently as huge per-frame
  motion churns the magnitudes, and only nodes whose error is common-mode with the
  camera's (craft, sharing the full parent chain) cancel it. The 2026-08 investigation
  established the mechanism by falsification matrix and witness-marker probe, and
  established what it is *not*: an `IVPathVisual` defect — do not re-chase it there.
  No fix is designed; candidate directions are re-anchoring visuals more aggressively
  at high speed, or accepting and hiding it (HUD-only rendering above a speed × distance
  product).
- **Planets should become point sources, not vanish.** The 4000-radii cull removes a
  body at ~0.6 px, where the real object is often a bright naked-eye point — Venus
  (culled from Earth at 7,000–43,000 radii, magnitude −4) and Jupiter at opposition
  (~9,000 radii, −2.5) simply disappear, leaving the HUD symbol as a non-photometric
  stand-in. The sun already solves exactly this problem: sun-mode crossfades the
  resolved disc to a far point that rides the star field's photometric chain. Planets
  want the same pattern with reflected light: apparent magnitude from the table's
  radius and albedo, the two distances, and a phase term (Mallama's phase functions are
  the reference the albedo column already follows), the point riding `iv_exposure` like
  every star. Interacts with the cull (the crossfade would replace it, as sun-mode's
  pixel-radius fade already does for the sun). Specified — see the ACTION ITEM below,
  which folds this together with crescent glow and the 2026-08-31 star glare.
- **Analytic-shadow receiver gaps.** A body whose material never opts in gets no
  eclipse, transit or ring shading on its surface: the five packed `.glb` bodies and
  every `FALLBACK`-class moon (both on `StandardMaterial3D` — the same two classes the
  sibling document's disc-photometry TODO names). For those in the far lighting domain
  the gap is total — Hyperion in Saturn's shadow stays lit, since only the near/middle
  lights carry the camera-fraction dimming. The sibling TODO's fix (give `FALLBACK` the
  surface shader; touch packed models' materials) brings occlusion along for free.
- **Middle-domain occlusion double-count.** Derived from code, not yet reproduced
  in-app: a 0.1–100 km body with a shells model — Phobos, Pan, Prometheus — is lit by
  the middle light, whose energy scales by the *camera-point* fraction
  (`dynamic_lights.tsv` `apply_sun_occlusion`), and *also* shades itself per-fragment
  through AO from its own fraction. When camera and body share a partial shadow the
  terms multiply (at ring transmission 0.3, three times too dark); when they don't —
  possible inside the middle domain's visibility bubble (4e5 km at 100 km radius),
  which ring-shadow structure is far sharper than — a sunlit moon dims for a shadowed
  camera. The dimming currently earns its keep only for shader-less middle-domain
  receivers (`FALLBACK` small moons, whose eclipses it approximates); once those carry
  the surface shader (previous entry), the middle row's `apply_sun_occlusion` cell
  should go FALSE, leaving camera-fraction dimming to the near (craft) domain where its
  uniform-field assumption is airtight. The near domain also covers the subtle case of
  a camera in a *small heliocentric body's own* shadow cone (standing behind Bennu),
  where the middle light's dimming currently darkens the body's lit crescent wrongly.
- **Occlusion candidate lists assume static parentage.** They are built once per
  receiver and cached for the session; a body added to the tree mid-session never joins
  existing lists, and a receiver that re-parents would keep its old list. Both are
  benign today — the shipped system adds no bodies at runtime, and the bodies that *do*
  re-parent (patched-conic spacecraft) are not shader receivers — but either assumption
  breaking silently mis-shadows. Invalidate the cache on tree change when it matters.
- **Fragment-id picking assumes unscaled rendering.** The broadcast grid and the probe
  both work in internal-buffer pixels assumed equal to window pixels; FSR or 3D
  resolution scaling would misalign them and break line/point picking quietly. Either
  scale `iv_mouse_fragcoord` and the probe origin by the internal/window ratio, or
  assert scaling off.
- **An atmosphere limb is not eclipsed.** The planet's own shadow is in the limb model
  but an eclipse by another body is not; `sun_occlusion_visible_fraction` at the
  tangent point would add it (also listed in the sibling document's atmosphere TODO —
  it is this system's one missing consumer).
- **Multistar occlusion application** — the math is per-star already; the application
  (one sun direction, one AO factor) is not. See the shaderinc header for the two
  viable routes.

## ACTION ITEM: one PSF quad per bright body

The "planets become point sources" TODO above, specified and widened (2026-08-31): it
absorbs crescent glow and the sun's existing point + glare pair, because all three are one
mechanism. Design intent and constraints only — the implementing agent makes the detailed
plan from the code. The photometric half (the glare law, its anchoring, and the glow-pass
measurements that forced it into the shader) is in the sibling document under *Which is why
the wings are no longer the pass's job*; this section is the spatial and architectural half.

**What.** One camera-facing quad per sufficiently bright body — the sun and at least the
eight planets — drawing the camera's point-spread response to the body's flux: the Gaussian
PSF core plus the `1/r²` glare wing, summed in linear in one fragment and crossing into the
renderer's colour space through one `display_write()`. The sun's two current items,
`sun_point.gdshader` (a point sprite) and `sun_glare.gdshader` (a quad), merge into the
first instance. The catalog star field stays on point sprites (`stars.gdshader`) and shares
every line of the law through `_star_point.gdshaderinc` — which is what keeps an in-scene
source photometrically welded to the sky behind it, and must stay true through the merge.

**Why a quad, and why one item rather than two.**

- `POINT_SIZE` has a driver maximum as low as 1 px in the GLES3 spec, and the glare law
  wants ~700 px for the sun seen from Earth. A quad has no cap. (The field keeps sprites
  and accepts the clamp as a risk — it can only truncate a wing's faint outer part.)
- Two draws are two adds in the blend, which on the display-referred renderer runs on
  encoded values, where a sum is not a sum. Core + wing summed in linear before the one
  conversion cross as one value — the field's fragment already does exactly this; the sun's
  split pair does not.
- One farwarped item and one uniform set per body. `sun_point.gdshader`'s "must track
  `stars.gdshader` uniform for uniform" hazard note becomes structure instead of discipline
  (the field–quad half of the hazard remains, and keeps riding `IVStarSettings`).
- It is the unit that multiplies. Sun + planets is nine instances or more, and the design
  questions — crossfade, flux, colour, host — are the same for all of them; decide once.

**The two regimes.** Unresolved, the quad IS the point source: the core takes the existing
disc handoff (`sun_pixel_radius` / `sun_disc_weight`, `handoff_low`/`high`) against the
resolved mesh, replacing the 4000-radii cull's vanish exactly as sun-mode's fade already
does for the sun — the cull interaction the TODO bullet names is real; the quad must remain
where the mesh is culled. Resolved, the WING persists — glare belongs to the camera, not
the subject, so it takes no crossfade — and the persisting wing IS the crescent glow. One
mechanism therefore closes three defects: the sun reading as an ordinary star at distance,
planets vanishing at the cull, and crescent glow (absent on Compatibility since the glow
pass went off there, flux-capped on Forward+).

**Planet photometry.** Apparent magnitude per frame from the table's radius and albedo, the
two distances and a phase term — Mallama's phase functions are the reference the albedo
column already follows — riding `iv_exposure` and the field's whole chain exactly as
sun-mode's `apparent_magnitude` does today. Colour is a design point to settle in the code:
`star_color()` wants a B–V, and a planet wants its disc-mean tint (a fitted B–V equivalent
per body, or a direct tint uniform bypassing the B–V path).

**Stated approximations — carry them as statements.**

- The wing is symmetric about the body's centre while a crescent's light is not. If the eye
  objects, shift the quad centre toward the lit limb by a phase-dependent fraction of the
  disc radius — still analytic, still free. Do not reach for a screen-space convolution:
  that full-screen parallel bloom is the expensive-parity route this design exists to avoid.
  The parallel-system test the analytic shadows passed applies — the native pass is
  structurally unable for POINT sources (its feed is capped, so flux ×1225 across the sun's
  stations rendered as halo radius ×1.34) and healthy for resolved bright regions on
  Forward+, so the replacement is scoped per source and stops there.
- On Forward+ a resolved bright disc still feeds the engine glow pass, so the
  resolved-regime wing stacks on the pass's own bloom there. Its amplitude in that regime
  is an in-app anchor to judge — possibly renderer-weighted — exactly as `glare_scale` was
  anchored against the far-sun halo it replaced.

**For consideration, NOT decided here: the glow pass may come back on under Compatibility.**
It went off 2026-08-31 because for this content it buys nothing — the far sun's halo
measures the same 4 px with the pass on as off, and the halo's integrated light goes DOWN
with it on — while crushing the faint frame: enabling glow moves tonemapping into a post
pass that re-runs the transfer bracket `display_write()` pre-inverts exactly once, and
background content at 6–8 codes renders at 0.041×, the whole frame at 0.84×. But moons,
asteroids and spacecraft parts sit OUTSIDE the quad system, and for those extended sources
the pass does provide at least some glow. Options, in rising order of work: keep it off;
re-enable and accept the crush; re-enable behind a "Compatibility glow" graphics option
(restart-scoped — the transfer path the display compensation calibrates against is decided
at startup); pre-invert the bracket twice in a third display mode, which in principle
recovers much of the crush (not the bottom few codes — each pass's encode has a hard zero
floor); or extend the quad system itself to any body with a computable magnitude, moons
included, which shrinks the pass's remaining role to spacecraft parts. Decide against real
scenes in-app.

**A known artifact the shader should stay structured for.** Over a bright background — the
Milky Way's bulge — the wing over-adds on Compatibility: `blend_add` runs on encoded
values, so the landed increment is `enc(g)` where the linear sum wants
`enc(bg + g) − enc(bg)`, several-fold at the wing's faint end, and the visible halo reads
~2–3× wider over the bulge than over dark sky. (Forward+ adds in linear; its halo over a
bright background is if anything masked.) The exact fix is a screen-texture increment —
sample `hint_screen_texture`, write `enc(dec(S) + g) − S` under the same `blend_add`;
anything drawn after the copy degrades to today's plain add, never to a darkening — at the
cost of one backbuffer copy per frame while a quad is visible, which makes it the first
real candidate for a Compatibility graphics option. Not part of this item; but keep the
fragment's final write in one place so the increment mode can slot in without
restructuring.

**Naming.** The merged system wants one name for the shader, the node and the builder —
`sun_glare` must not survive the merge (it would name a shader whose near-handoff output is
mostly core), and `sun_point` is no longer a point. Suggestions:

- **`source_psf` (recommended)** — `source_psf.gdshader`, node `SourcePsf`, builder
  `_build_source_psf()`. It names the one physical idea every job shares: the camera's
  point-spread function applied to a source's flux — the core is its centre, the glare its
  wings, a "point source" the regime where it is all there is, and crescent glow its wings
  over a resolved source. PSF is already house vocabulary (`stars.gdshader`'s header).
- `psf_quad` — the same idea named by its geometry; fine for the shader file, weaker as a
  node name.
- `point_source` — the TODO's own words and the standard astronomy term; its weakness is
  that half the system's value is delivered exactly when the body is NOT a point source.
- Rejected: `glow`/`bloom` (they name the engine pass this system replaces for point
  sources — actively confusing), `glare`/`halo` (the wing only), `flare` (a lens artifact
  this deliberately is not).

**What exists to build on.** `_star_point.gdshaderinc` (the shared camera: `star_flux`,
`star_visible_size`, `star_psf_falloff`, `star_glare_*`); `stars.gdshader` (the field's
core-plus-wing fragment — the merged quad's fragment should read as its sibling);
`sun_point.gdshader` + `sun_glare.gdshader` (the merge inputs, whose headers carry the
crossfade and quad-geometry reasoning); `IVShellsModel` sun-mode (`_process_sun_lod` and
the two builders — the per-frame driver whose pattern generalizes; where a planet's
instance lives — `IVBodyVisual`, a sibling component, or growth of the shells model — is
the implementing agent's call, made after reading how sun-mode and the cull interact);
`IVStarSettings` (the ONE shared camera — new uniforms join `apply_to()`), with
`IVStarsVisual`'s exports as its inspector face.
