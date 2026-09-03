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
view. Sub-pixel, so the pop is invisible; but note what it forfeited, and why it is gone
for the bodies that matter most: **the cull is angular, and brightness at the cull is
not.** The cull distance scales with radius, so a small body culls when it is very close,
where it is blazing — every named body in the tables is bright at the moment it
disappears, from Venus at V −9.1 down to Charon at +0.3, with Bennu (a 242 m rock) at
−5.1. Bodies that draw a PSF quad (below) therefore opt out of the cull entirely and hand
off to that quad instead; everything else still takes it, having nothing to hand off to.
A packed-scene model that authors its own `visibility_range_end` keeps it; only the
engine's "unset" 0.0 is filled in.

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
- **Per-body PSF quads** (`IVBodyPSF`, next section): not point sprites, but the same
  law on the same shared settings — spatially each is just another farwarp item whose
  AABB always contains the camera.
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

## Point sources: one PSF quad per bright body

`IVBodyPSF` draws the camera's point-spread response to one body's flux on a
camera-facing quad — the Gaussian PSF core plus the `1/r²` glare wing, summed in linear
in one fragment and crossing into the renderer's colour space through one
`display_write()` (`body_psf.gdshader`). It replaced the sun's former `sun_point` +
`sun_glare` pair and extends the mechanism to reflecting bodies, closing three defects
with one thing: the sun reading as an ordinary star at distance, bodies vanishing at the
cull, and crescent glow. The photometric half — the glare law, its anchoring, and why the
wings are not the engine glow pass's job — is in the sibling document.

**Two regimes, and only one of them is a crossfade.** Unresolved, the quad *is* the body:
the core takes the disc handoff, so a body shrinking past its disc becomes a photometric
point instead of disappearing. Resolved, the **wing persists** — glare belongs to the
camera, not to the subject, so it takes no crossfade — and that persisting wing is
crescent glow.

**The rim's sky side is drawn here too, because nothing else can.** A body's surface images
each rim pixel through the camera's PSF (`limb_mean_incidence()`, and *Imaging a pixel* in
the sibling document), but it can only put that light on fragments it has: its rim ends at
the rasterized silhouette, and the outward half of a rim pixel's spread belongs beyond it.
Undrawn, a rim compressed to a line keeps a knife edge, which on a shallow curve is a
staircase. This quad already covers the sky beside the limb, so `limb_sky_side_incidence()`
draws the missing half there — the same closed-form chord integral under the same Gaussian,
evaluated outward, so the two halves partition one convolution rather than overlapping. Its
cells are spaced uniformly in `sqrt(depth)` rather than in depth: seen from outside, the whole
lit sliver sits *at* the limb, and a uniform grid's first sample lands past it and weights it
as if it were that much deeper — 40 % low at three pixels out. And the sun angles it
integrates are the limb point's for the camera where it is (`limb_sun_angles()`), not the
phase at the body's centre: a camera at finite distance sees the tangent circle, whose points
see the sun lower than the centre does by the body's angular radius — 18° from three radii
out. Lit from the centre's phase, the rim stood as if the sun were that far above a limb it
was sitting on, stayed lit after the sun had set behind the disc, and went out only at phase
180°, while the surface beneath it, which has the real normal, had gone dark with the sun.

**What scales it is the body's own flux**, spread over a Lambert sphere's disc, rather than
anything sampled from the surface — which this quad cannot read. The total is therefore the
body's true flux through its true phase law while the distribution across the crescent is
Lambert's, and the seam is where that shows: a body whose rim albedo differs from its disc
average meets its own spread at a slightly different level.

**The silhouette it measures from is the exact conic**, not an angular radius
(`IVBodyPSF.get_limb_conic()`, the tangent cone of the body's own spheroid, handed over in
tangent units and solved per fragment along its own direction). Both of the obvious
approximations fail here by tens of pixels against a spread that is a few pixels wide: a
perspective projection draws the tangent cone, 8 % wider than `r / d` at 2.6 radii out, and an
oblate body's outline is an ellipse whose flattening is not the body's own. Either error puts
the whole of the spread inside the silhouette, where the depth test drops it. The conic is
normalized before it is sent — built from `1/radius^2` terms, Jupiter's raw entries are 1e-15
and their 3x3 determinant underflows float32.

**And it is the table figure's conic, which two of the bodies with a quad do not have.** The
shared sphere a body scales to its own radii *is* that ellipse to within the tessellation
`RIM_SEAM_PX` absorbs — measured against the projected vertices at three radii out, the two
edges agree to 0.3 px of a 393 px disc. A body carrying its own mesh does not: Ceres and
Charon are drawn from a displaced sphere whose outline stands wherever their terrain does,
1.9 % of the radius inside the figure on Charon, and the rim drew there as a smooth arc of
open sky detached from the limb it belonged to — 16 px off it on a 785 px disc, over a fifth
of the azimuths, at every phase that lights the limb at all. No constant can absorb an error
in percents of a radius, and nothing on this quad can find that outline, so `IVBodyPSF` sends
those bodies a zero `limb_semi_axes` and they get the inward half of the spread only.

**Scope is a flag, but the mechanism is a magnitude.** A quad is built for an in-scene
star and for every body carrying `BODYFLAGS_PLANETARY_MASS_OBJECT` with a geometric
albedo — 26 bodies: eight planets, Ceres and Pluto, and the sixteen planetary-mass moons.
Nothing thresholds on brightness anywhere, because the size law in
`_point_spread_function.gdshaderinc` already shrinks a source to nothing exactly where it drops below
one 8-bit step, and it runs in the shader because it is viewport-dependent. The flag is
the shipped scope only; widening it is one line in `IVBodyPSF.is_applicable()` plus the
table data a new body would need.

**A sunlit body's magnitude** is its whole disc's reflected flux, expressed as the
magnitude an unresolved source of that flux would have: geometric albedo × phase ×
eclipse × the star's illuminance at the body × (radius / camera distance)²
(`IVPhotometry.get_reflected_apparent_magnitude`). It rides `iv_exposure` and the field's
whole chain exactly as a star's does. The albedo is the table's `albedo` and **not**
`meter_albedo` — metering wants the reflectance the camera sees, which a body's shells add
to, while this wants the geometric albedo, which is *defined* by the zero-phase form of
that relation. Two albedos, two jobs.

**The phase function comes from the body's own BRDF**, not from a catalog fit: the
disc-integrated law of the Lunar-Lambert surface the body's shader already renders with
(`shells.tsv` `lunar_lambert`, or `minnaert_k` mapped onto it at its two exact endpoints —
k = 1 is Lambert, k = 0.5 *is* Lommel-Seeliger). Both integrals are closed form, so the
point dims through phase exactly as the disc it hands off to, and the trade is
flux-continuous by construction. **Its cost is stated rather than hidden:** a smooth
BRDF's disc integral is shallower than a real regolith's, whose shadow-hiding takes far
more light out at moderate phase — the quarter Moon comes out about 1.6 mag bright. That
error is the rendered *disc's* already; taking the point's law from anywhere else would
buy catalog accuracy at the price of a step through the handoff, and a Hapke treatment
would fix both halves at once.

**The handoff is solved once and published.** `IVBodyPSF.solve_handoff()` finds the
on-screen pixel radius where the quad's saturated core matches the disc's diameter — where
the two can trade places without stepping in size, which is what the eye actually has to
go on, both being orders of magnitude above saturation throughout. The answer goes on
`IVBody.psf_handoff`, and every shell of the body reads it to leave at exactly the radius
the quad's core arrives at (`IVShellsModel`'s disc LOD; the surface, cloud and limb shaders
all carry it). One producer, one answer: solving it on both sides is how the two would come
to disagree.

**How a shell leaves depends on which pass it is already in, and that is not cosmetic.** A
lit surface is opaque and must stay so: writing `ALPHA` moves a Godot spatial material to
the transparent pass, where `depth_draw_opaque` means *no depth write at all* — and an
opaque body that stops writing depth stops occluding everything, silently. Shipped briefly
and caught in review: the star field rendered through every night side, bodies stopped
sorting against each other, and each body's own quad drew through it. `depth_draw_always`
is no escape either, since it would write depth across the fade and punch the quad's core
out of the middle of its own crossfade. So a **lit disc discards at one threshold**, and
`IVBodyPSF` collapses the ramp (`HANDOFF_STEP_RATIO`) so that threshold and the core's
onset coincide — neither a gap nor a double-count, and the trade happens at a size the
solve has already matched. Only a shell that is *already* transparent — a cloud deck, a
limb, an emissive star disc — can afford to crossfade, and those still do.
Each shader resolves the pixel radius against its **own** `VIEWPORT_SIZE`, so an
off-screen capture fades at its own buffer's scale rather than the main window's — the
same reason nothing viewport-dependent is allowed on the CPU side here.

Four approximations worth carrying:

- **The wing is offset toward the lit limb by a phase-dependent fraction of the
  silhouette's own radius in that direction** (direction the sun's on screen, magnitude
  `(1 − cos phase)/2`), because a crescent's light is not centred on the body and the wing
  used to be. What that cost showed worst with the sun near the limb, where the rim is a
  saturated line and the one thing that could gradate it — the camera's own spill — sat
  half a disc away as an even halo. It takes the silhouette's radius rather than a mean one
  because that is what holds the `1/r²` singularity on the disc, which draws over it: a mean
  lies *between* an oblate body's polar and equatorial extents, and past Saturn's pole the
  centre stood ten pixels out in open sky, where an unoccluded peak is a dot with a glow
  around it. The core keeps the body's own centre, and the silhouette radius retires the
  offset on its own as the disc shrinks toward the unresolved regime. The fraction is by
  eye: a Lambert sphere's lit centroid is at 4/(3π) of the radius at quarter phase
  against this curve's 0.5, and closing that gap would mean carrying the disc integral of
  whichever BRDF the body renders with.
- **The wing carries the flux this camera receives, not a distant observer's.** The
  magnitude driving the quad evaluates the body's phase law at the body's *centre*, which is
  a distant observer's crescent. From close range the camera sees less than a hemisphere, so
  the sun sets behind the disc while that law still reports one: at Saturn from 3.7 radii the
  whole visible face is dark past 164° of phase, where the law still says 4 × 10⁻⁴ of full —
  and the wing glared for a body with no light anywhere on it. Every limb point sees the sun
  at `sin(phase + ρ)` for the silhouette's own angular radius ρ, so a distant observer with
  that much more phase has this camera's geometry; the substitution is exact where the
  crescent dies and where the body is far (ρ → 0), and within a third of a magnitude between,
  which on a glare halo is nothing. Only the wing takes it. The core is a point source only
  where the body is unresolved, and the two fluxes agree exactly there; the rim divides the
  same flux by the same disc integral, so the correction cancels out of it — which is right,
  a crescent's surface brightness being its albedo and its illuminance however little of it
  is left.
- **On Forward+ a resolved bright disc still feeds the engine glow pass**, so the
  resolved-regime wing stacks on that pass's bloom there and the two renderers are close
  rather than identical. Its amplitude in that regime is an in-app anchor to judge,
  possibly renderer-weighted.
- **A ringed planet's quad carries the globe's flux only**; its rings keep their own
  distance cull, at 2.4× the globe's. The regime where that shows is narrow.

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
| | `apply_body_psf` | Enables the per-body PSF quad ([IVBodyPSF]). Off, those bodies take the fixed distance cull like any other and their discs do not fade. |
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
| `IVBodyPSF` | `HANDOFF_*` (constants) | Disc/point crossfade: fade span, the fallback for a source with no saturated core, and the exposure/magnitude shift that re-solves it. |

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
- **Bodies outside the PSF quad's scope still vanish at the cull.** The quad covers the
  sun and the 26 planetary-mass objects; the other ~150 named moons, the named
  asteroids, and every spacecraft still take the 4000-radii cull, at which they are
  often very bright (Bennu culls at V −5.1). The gate is one line, but the data is not:
  104 of 177 moons carry no albedo at all, and the phase law needs the body's surface
  BRDF. The named asteroids are the cheapest next step — all five are non-lazy and carry
  both an albedo and an explicit `magnitude` (H).
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
