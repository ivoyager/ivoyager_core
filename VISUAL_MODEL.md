# The Visual Model

This document describes how I, Voyager places, scales, culls, shadows and picks what the
camera sees: the machinery that turns a double-precision simulation that spans fifteen
orders of magnitude into a scene a float32 render pipeline can draw without shakes,
missing geometry or absurd shadows. It is about the logic and architecture;
implementation detail lives in the class and shader file docs. It has two siblings.
[PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) is the objective simulation underneath — bodies,
orbits, rotation, time and scale, the 64-bit "truth" for astronomical scales that
everything here renders and never modifies. [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)
covers how bright each pixel is when physical light is enabled. This document covers where
everything is, how big it renders, what stands between it and the light, and how the mouse
identifies items on the screen. A system that has both a photometric and a spatial face
(rings, the sun, the star field) appears in both this document and the photometric one,
split by concern and cross-referenced. A fourth document is not a sibling but a plan:
[IVBody_REDESIGN_v0.3.md](IVBody_REDESIGN_v0.3.md) is the v0.3 rework of `IVBody`, and it
reaches as far into this model as into the physical one — its §2.4 replaces the first two of
the four bridging mechanisms the next section names, and its §2.5 is what lets a project hang
a scene of its own inside the simulation. Where a section below describes a v0.2 mechanism
that plan replaces, it says so.

## Overview: two number systems

The simulation's truth is double precision; the render pipeline is not. A GDScript
`float` is 64-bit, and every scale-sensitive computation — orbital state, trajectory
paths, time — runs in it; state paths and rebase anchors are `PackedFloat64Array`s
precisely so they stay in it. But Godot's `Vector3` and every `Node3D` transform (in a
standard engine build) and everything on the GPU is float32. Float32 carries a relative
step of about 1.2e-7 (one ULP), which is a property of *magnitude*: a position at 1 au
quantizes at ~18 km, at 40 au at ~700 km. A naive f32 scene shows kilometer-scale
shakes at planet range and loses distant content entirely to the depth buffer's limits.

Four mechanisms bridge the gap, and the rest of this document is mostly about them:

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

In upcoming v0.3, the first two items will become unecessary: every astronomical body
in v0.3 is `top_level` and places itself from f64 against a **frame anchor** (a local
non-astronomical scene, which is simply the camera in the case of the Planetarium). The
frame anchor is the origin by definition rather than by subtraction. This will allow a
project to simply "add on" I, Voyager's solar system to a standard Godot scene; see *The
render frame anchor and local scenes*.

One consequence is that **the whole per-frame render state is conditioned for exactly
one astronomical viewpoint.** The origin shift, the `iv_farwarp_start` global, every
farwarp-remapped vertex,
the HUD symbol placements and the mouse-probe globals all assume a single view position.
A secondary camera (e.g., our screenshot rig) must copy that camera's global transform;
a camera placed anywhere else in the solar system sees geometry warped for someone else.
This does not prevent multiplayer games because only the physical state of astronomical
objects needs to be shared, and it does not prevent multiple cameras in a local scene as
long as they share the same astronomical view. The visual state is a player's subjective
*astronomical* view rendered on a single machine, derived entirely from the objective
physical state.

### Why not compile Godot in 64-bit?

Godot builds with `scons precision=double`, which makes `real_t` a double and takes with it
every built-in type that can hold a world coordinate — `Vector3`, `Transform3D`, `Basis`,
`Plane`, `AABB`, `Projection`, and therefore `Node3D.position` and `global_position`. The
arguments for it are strong:

- **The f32 problems would be fixed on the CPU.** A GDScript `float` is already 64-bit; making
  all engine types 64-bit would enable us to use them for astronomical calculations. The main
  advantage is that `Node3D.position` and `global_position` could be treated as "truth" rather
  than as a strongly compressed (lossy) value assigned from the true f64 value. We could also
  remove workarounds like our use of `PackedFloat64Array` in place of `Vector`, `Basis`,
  etc. 
- **Origin shifting would resolve to millimetres** rather than onto a ~16 km lattice, which is
  the direct cause of the shadow boil in *The limits of origin shifting*.
- **The near:far ceiling would move.** The ~2^24 cap is a float32 *CPU* cancellation in
  `Projection::get_projection_planes()` (*The depth range*), computed in `real_t`.
- **Godot physics and collisions could work at astronomical magnitudes**, where today they are
  confined to a local scene.

Against that stands one counterpoint and one blocker. The counterpoint is that **it does not
reach the GPU.** A double build keeps vertex attributes, varyings, uniforms and the depth
buffer in float32 (what it buys on the render side is a double-precision *transform*, carried
to the shader in split-float form). The pipeline this document is about is still a float32
pipeline, geometry spanning many orders of magnitude is still interpolated in f32, and the
systems built for that (farwarp above all) would still be needed.

The blocker is distribution. A double-precision Godot is not the binary anyone downloads from
godotengine.org, and its export templates are not the ones the editor fetches: a project would
have to build, maintain and ship an engine and a template set for every target it exports to
(web included) and redo it at every engine version. I, Voyager is an addon whose value is that
it drops into a standard Godot project.

**Therefore, we don't use it, and everything here assumes a standard build.** However, a
project might want it for other reasons (astronomical collisions is the main one). This may
simplify some of what follows but the GPU limit is still very real.

## Origin shifting and the frame order

*(Becomes obsolete in v0.3.)*

Each frame `IVCamera` processes its own motion, then subtracts its global position from
the Universe root's translation — camera at origin, to the f32 rounding of its ancestor
chain, which at planetary distances is kilometres (*The limits of origin shifting*, below).
Ordinary tree children ride the shift automatically (their locals are untouched; the world
moves under them). Two kinds of code do not, and both are ordered explicitly:

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

### The limits of origin shifting

The shift buys smallness, and smallness is most of what the render needs. Near-camera world
magnitudes drop from ~1e11 units to a few kilometres, where one f32 ULP is half a millimetre
against 16 km at 1 au, and relative geometry stays exact on top of that because the error is
shared (*Overview*).

What it does not buy is a *stationary* world frame, and some things need one. The subtraction
runs in float32 on a number holding the camera's distance from the Universe origin, where one
ULP at 1 au is ~16 km, so the camera comes to rest *within* ~8 km of the origin rather than
*on* it, and that residual is free to drift. Measured on the ISS: `Universe.x` unchanged across
109 consecutive frames, the camera 1.1–6.6 km out, and the whole near-camera scene translating
**129 m per frame** — the ISS's orbital speed over the frame rate — with jumps to ~4 km on the
frames where the lattice does move.

The consumer that needs a stationary frame is Godot's directional shadow, which anchors its
texel lattice in absolute world space: a near scene sliding through that lattice re-rolls its
sub-texel phase every frame, **and a spacecraft self-shadow appears to "boil"** (*Local shadow
maps*, and the TODO entry).

Two things generalize from that, and both matter to anyone re-opening it. The quantum is
*relative*, so it is ~16 km at 1 au whatever `IVUnits.METER` is — a project cannot tune its
way out by changing sim scale, and a scale-sensitivity hunt is the wrong investigation. And
the frame is anchored at the **Universe root**, so a body sweeps through it at its *absolute*
speed rather than at its speed relative to the camera; anything reading a world-space position
rather than a difference between two of them sees that sweep.

Both follow from where the frame is anchored, which is what the designed answer changes: place
every body from f64 against a frame anchor that is the origin by definition, and the frame stops
moving under the near scene at all ([IVBody_REDESIGN_v0.3.md](IVBody_REDESIGN_v0.3.md) §2.4).
That is the next section.

## The render frame anchor and local scenes

*Planned for v0.3, not shipped in v0.2. The mechanism is
[IVBody_REDESIGN_v0.3.md](IVBody_REDESIGN_v0.3.md) §2.4; this section is the contract it
establishes and what it means for a project that is not a planetarium.*

I, Voyager is an addon, and the projects it serves are not all planetaria. A first-person game
set in a base on the Moon, a lander sim, a ship whose interior you walk around: each has complex
local scenes, its own camera, Godot collision shapes and Godot physics, and wants all of it to
sit inside a real solar system under a real sky.

**The two-number-systems split is about astronomical scale.** A body's rendered `position` is
derived and disposable because at 1e11 units an f32 coordinate quantizes at kilometres; at 1e2
units it quantizes below a micron, so a local scene is under no such constraint. Inside one,
`position` can be the truth exactly as in any other Godot project — Godot physics moving a
`CharacterBody3D`, Godot collision, the project's own camera, its own gravity — and nothing
here asks otherwise. What has to meet our systems is a project's astronomical-scale content,
if it has any. The two regimes and what each owns are tabulated in
[PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *A game whose action is local*. What falls to this
document is the frame they meet in.

**The seam is one node: the frame anchor.** Under §2.4 every `IVBody` is `top_level` and places
itself at `f64(absolute − anchor_absolute)`. The anchor is placed by that same rule, so it lands
at exactly zero, and whatever hangs below it is therefore at ordinary local coordinates in a
world frame that does not move — which is the condition Godot physics, Godot collision and
Godot's directional-shadow lattice all want, and the condition *The limits of origin shifting*
says v0.2 cannot deliver. **What I, Voyager needs from a project's scene is its root.** We place
that node; everything under it is the project's and is never touched.

The anchor must be **the thing the camera stays near**, and that is the whole of the contract:
the f32 rounding of `body − anchor` is proportional to distance from the *anchor*, so it reads
as a constant ~1.2e-7 rad of angular error only while the camera sits close to it. The
Planetarium meets that by anchoring on its own `IVCamera` (distance zero, and the degenerate
case of the same formula); a project meets it because a viewer inside a level cannot leave it.

Five consequences worth stating, because each is a thing a project would otherwise have to
discover:

- **Local content needs no farwarp work.** A local scene lives at distances far under T, where
  `g(d)` is the exact identity (*Farwarp*), so ordinary Godot materials render correctly with no
  shader changes and none of the three farwarp obligations apply to them. Only content that can
  be astronomically distant needs the always-pass `custom_aabb` and the rest. This holds as long
  as T is set from the camera's own near scale, which `IVCamera` gets from its parent distance;
  a foreign camera has no parent in our sense and would have to supply it (TODO).
- **The camera's depth range is the one thing a local scene must change.** Godot's `Camera3D`
  ships `near = 0.05` and `far = 4000`, and 4000 units does not reach the farwarp'd sky: at a
  metre-scale near distance T is ~1e4 units, which puts the Moon at ~1.2e5, the sun at ~1.8e5
  and the catalog stars at ~3e5 (*Farwarp*), so a default far plane clips every astronomical
  thing away. A project's camera takes `IVCamera`'s rule instead — `near = 0.1 ×` and
  `far = 1e6 ×` the same near scale that sets T — which lands the compressed universe at ~30 %
  of the far plane and holds the near:far ratio at the 1e7 the engine caps (*The depth
  range*); a default `near` of 0.05 under a 1e6 far plane would exceed that cap on its own.
  Nothing else about the scene changes.
- **Local content is near-domain for lighting.** `IVCoreSettings.size_layers` sorts by radius
  into far / middle / near, and a project's scene belongs with the near light (*Local shadow
  maps*), which carries shadow maps and scales its energy by the camera-point occlusion
  fraction — so a lunar base goes dark in an eclipse with nothing written for it.
- **Picking coexists.** Ours targets astronomical content: bodies by CPU screen-space
  unprojection, lines and points by fragment id (*Mouse picking*). A project picks its own local
  objects with ordinary physics raycasting, which works because local content is at true
  positions in a stationary frame. What is *not* settled is how mouse input is shared between
  `IVWorldController` and a project's own controls (TODO).
- **One anchor is live at a time.** The whole per-frame render state is conditioned for exactly
  one viewpoint (*Overview*), so a second live frame does not exist. Other anchors — a second
  base, a ship the viewer is not in — are placed by the same rule as any body and render at
  astronomical distance with the same angular error as anything else out there. Moving between
  them re-places everything by one constant vector, including the departing scene and the camera
  riding in it, so nothing moves on screen; it is the same class of event as the camera's parent
  handoff mid-transfer, which *Farwarp* already tolerates for the same reason.

Orientation is not the anchor's job: `IVBody` is never rotated, so a surface scene's root is a
child carrying the body's ground basis — the same relationship `IVBody` has with `IVBodyVisual`,
with the project's scene standing where the visual would.

**What v0.2 offers today.** Under our `IVCamera`, a scene parented to an `IVBody` does ride the
origin shift, and its f32 error is largely shared with the camera's and cancels, so it renders.
But it is exactly the case *The limits of origin shifting* describes: its world position is
composed in f32 from astronomical terms, and it sweeps through the world frame at its body's
**absolute** speed — which is what makes craft self-shadowing boil, and it would do the same to
a base's. Under a project's own camera there is no origin shift at all, since `IVCamera` is what
performs it, and the scene sits at raw astronomical world coordinates rounding at kilometres.
Neither is a frame to build a game in. The anchor is, and it arrives with
[IVBody_REDESIGN_v0.3.md](IVBody_REDESIGN_v0.3.md) §2.4.

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

Three obligations fall on every farwarp consumer:

- **Defeat frustum culling.** Culling tests the true-scale AABB against the far plane,
  and the true positions fail that test exactly when farwarp is doing its job. Every
  consumer sets a `custom_aabb` sized to always contain the camera
  (`max_camera_distance`, or the star field's own extent if larger): shells models, rings,
  path visuals, SBG points and orbit lines, the star field, the sun point. A new farwarp
  consumer that forgets this renders correctly until the camera zooms in somewhere, then
  vanishes.

  The box costs everything else the engine does with an instance's bounds. A boxed
  instance is never culled, so off screen or behind the camera it still submits every
  vertex. **Its mesh LOD never engages**: every renderer measures LOD distance to the AABB,
  and one that contains the camera measures zero, so a mesh imported with LODs draws its
  finest at any range. And **its `visibility_range_end` never fires**, since Godot measures
  that from the transformed AABB's centre, which f32 collapses (next obligation): Saturn's
  rings, measured before they had a gate of their own, drew from the Moon at three times
  their range.

  So **a shells model holds the box only while it needs it.** While its body may reach past
  `IVFarwarpManager.true_bounds_distance`, a quarter of the camera's far plane, it takes the
  box; inside that it culls on its own bounds, the mesh's or, for a shader that places its
  own vertices, its unit sphere (`IVShellsModel.shader_meshes`). There true bounds give the
  drawn geometry's answer: farwarp scales positions along camera rays and only beyond T, so
  nothing crosses a side or the near plane, and the true distance is the right one for LOD
  because the remap preserves angular size. A body's own mesh then takes the engine's LODs,
  held by `lod_bias` to the sphere ladder's 0.15 px silhouette budget (*The sphere LOD
  ladder*) rather than the viewport's coarser pixel threshold. The quarter keeps clear of the
  far plane itself, which the engine extracts in float32 and which at a 1e7 ratio can sit
  tens of percent off (derived, not measured). `IVBody.update_farwarp()` decides at +100, per body and
  change-gated, beside the local shadow grant (`IVBodyVisual.set_farwarp_box()`); a shell
  built later adopts its visual's current state. Rings keep the box always, their shader
  tilting and widening the plane past any bounds its mesh has, and their handoff gate retires
  them instead (*Culling, visibility and lifecycle*). Measured in *Level of detail, and shells
  nobody can see* ([GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)).
- **Opt out of AABB-centre sorting.** Godot takes an instance's sort depth from the centre
  of its *transformed* AABB, which for the box above is not where the object is: at
  `max_camera_distance` a f32 coordinate quantizes at ~6.7e7 m, and the model scale a
  shell or a ring rides multiplies that further, so the centre collapses to a constant and
  every such instance reports one identical depth — an arbitrary blend order for the
  transparent ones, a lost front-to-back pass for the opaque ones. Each consumer therefore
  pairs its `custom_aabb` with `sorting_use_aabb_center = false`, which takes the node's own
  origin — the true position the AABB was never describing — as the pivot instead.
- **Keep enough vertices to follow the curve.** A surface far beyond T is compressed
  near-uniformly, but geometry that *spans* decades of distance bends along g(). The
  shared ring `PlaneMesh` is subdivided (`plane_mesh_subdivisions` = 64) for exactly
  this; line meshes carry hundreds of vertices per orbit anyway. The atmosphere's limb
  annulus is cut into rows (`limb_annulus_rows`) for a variant of the same problem: its
  fragment stage reads the view ray from an interpolated true position, which drifts off
  the pixel's ray across a triangle whose corners are compressed by different factors.
  The sphere's LOD ladder below does not fight this obligation: a body only takes a
  coarser rung once it subtends little, and a body that subtends little spans a small
  fraction of its own distance, which is where g() is closest to linear across it.

What deliberately does **not** ride farwarp: anything that computes from true positions.
Occlusion (below), exposure metering, and mouse targeting all read true geometry — which
is consistent *because* the remap preserves screen direction, so a true-position
unprojection lands on the same pixel as the remapped rendering. This invariant — true
math, warped drawing, same pixels — is load-bearing across the model; the picking and
orbit-line sections both depend on it.

Disable the whole system with `IVCoreSettings.apply_farwarp = false` (the global goes to
0.0, every shader takes the identity branch, the HUD symbol becomes an ordinary child).

### The sphere LOD ladder

A body with no mesh of its own draws the shared sphere. One sphere at the finest resolution
(256 radial segments by default) serves the whole range correctly but isn't cheap, since
a body a few pixels across still draws every triangle a screen-filling disc needs. The
ladder is a rendering optimization: `IVShellsModel` picks a rung per frame from meshes built
by `IVResourceInitializer` — `max_sphere_resolution` halved down to a floor of 16, with
rings always half the segments.

The rule is one number. A facet's chord sags inside the true sphere by
`radius x (1 - cos(PI / segments))`, fixed in world units, so a rung serves every body whose
on-screen radius keeps that sag within a budget of 0.15 px — the error the finest rung gives a
screen-filling disc, where it measured indistinguishable. Each rung therefore covers a 4x range
of on-screen size (1992, 498, 125, 31 and 7.8 px), and a body crossing back to a coarser rung
must fall 20 % inside it, which is slack against jitter rather than a tuned crossover. Below
that the `IVBodyPSF` handoff has already taken over at 1-2.5 px.

What it optimizes are visible "spheroid" bodies that aren't extremely close to the camera: before
the ladder a body drew 65,536 triangles down to a 2.5-pixel radius, which might be many moon bodies
in a gas giant system. What it protects is the near end — a view of Earth's rim from the ISS
(*Level of detail, and shells nobody can see* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)).

Two obligations fall on it, both discharged rather than assumed:

- **A mesh swap must not drop the farwarp obligations above.** Verified on Godot 4.7.2: an
  instance keeps its `custom_aabb`, its `sorting_use_aabb_center` and its surface override
  material across an assignment to `mesh`.
- **The rung is decided in pixels, on the CPU, and one `MeshInstance3D` has one mesh for
  every viewport it draws into.** `IVScreenshotManager` renders these same nodes at a size of
  its own, so the ladder takes the greater of the live viewport's render height and the height
  a capture has registered (`IVShellsModel.capture_render_height`) — the same handshake
  `IVStarsVisual` uses for its bin cull, `IVRings` for its plane/point crossfade and
  `IVWorldEnvironment` for glow. Rungs are monotone in that height, so the answer can be too
  fine but never too coarse.

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

**The model presently assumes one star (TODO: support multiple stars).** The manager feeds
a single sun direction and one occluder set, and one AO value scales all direct light
uniformly — a fragment eclipsed from star A but lit by star B cannot be expressed in it.
The occlusion math itself is already sun-parameterized and reusable per star; only the
application is single-sun (per-light attenuation in a custom `light()`, viable now that
the METER scale-sensitivity that once ruled it out is resolved, or additive per-star
passes). See the shaderinc header and the multistar entry in the TODO.

## Local shadow maps

What shadow maps *are* for is the local, true-position scene: a lander in a crater, a
craft's dish shadowing its own bus. `IVDynamicLight` builds a per-star light stack from
`dynamic_lights.tsv`, each row lighting one **size domain** via `light_cull_mask` against
the layer bits `IVCoreSettings``.size_layers` assigns by body radius (≥ 100 km → far
domain 0b0001, 0.1–100 km → middle 0b0010, < 0.1 km → near 0b0100). Only the near and
middle lights carry shadow maps; the far light never does. Shadow reach follows the
camera (`floor`, `+ target distance`, `+ star-orbiter distance`, capped by `ceiling` —
100 km near, 1e5 km middle), and the near/middle energies carry the camera-point
occlusion fraction above. Reach is the whole of the texel budget: a split's texel is its
share of the reach over its share of the atlas, so every metre of reach past the target is
resolution thrown away. It cannot simply be minimised, though — Godot fades a directional
shadow out from `directional_shadow_fade_start` (0.8) of the reach, so the reach must stay
above ~1.25× the camera-to-target distance or the target itself fades. With an additive
`+ target distance` that ratio decays with distance, which is what bounds how far out a
craft keeps its self-shadows (~1 km at the shipped 0.25 km `target_plus`).

One thing reach cannot buy back is steadiness. Godot stabilises a directional shadow by
snapping the ortho bounds to a texel lattice anchored in **absolute world space**
(`renderer_scene_cull.cpp`, `_light_instance_setup_directional_shadow`), which holds static
world geometry on the same texels every frame. Our near scene is not static in world space —
see *The limits of origin shifting* — so its sub-texel phase re-randomises every frame and craft
self-shadowing boils. Reach and atlas size set the amplitude of that boil, not its existence.
An anchored frame makes the near scene stationary by construction, which is the fix and is also
the condition a project's own level needs (*The render frame anchor and local scenes*).

Two rules keep the maps honest across the warp boundary:

- **No map shadow may cross the farwarp boundary.** Everything remapped renders at
  distance > T while every true-position receiver sits inside it; without the clamp
  (`directional_shadow_max_distance` ≤ last frame's `farwarp_start`), near casters stamp
  oversized shadows on warp-compressed bodies, and a warped body's own light-space
  imprint false-shadows its camera-space self. The room that leaves is worth stating in
  metres, because a local scene has to fit inside it: T is 1e4 × the camera's distance to
  its target, so a camera 2 m from a lander has 20 km of shadow room and one 100 m out has
  1000 km. Against that the near light asks for at most `target_plus` (250 m) plus the
  camera distance, so the clamp overrides it only inside ~2.5 cm of the target — no
  ordinary local scene comes near the boundary. What the clamp does govern is the middle
  light, whose 1000 km floor exceeds T whenever the camera is within 100 m of its target.
- **Only true-position "terrain" casts.** Casters carry the
  `IVGlobal.LOCAL_SHADOW_CASTER` layer bit (0b1_0000_0000, the near/middle rows'
  `shadow_caster_mask`). Craft-scale bodies hold it statically; larger bodies are granted
  it per frame only while closer than both `farwarp_start` and
  `IVCoreSettings.local_shadow_caster_ceiling` (1e5 km). The ceiling keeps sunward planets
  at astronomical distances from being extruded into the maps. A shell that builds after a
  dynamic grant adopts its ancestor visual's current state, since the grant recursion is
  change-gated.

The ceiling and the largest shadowed `shadow_max_ceiling` are equal today, and the
guarantee that buys is that **anything a shadowed light can reach is already granted**:
every reach is clamped by both its own ceiling and `farwarp_start`, and the grant by
`local_shadow_caster_ceiling` and that same `farwarp_start`. The empty-pass skip below
rests on it, so `IVDynamicLight` now asserts it at construction rather than leaving it to
convention. What equality does not quite buy is exactness, because the grant compares a
body's **centre** distance where a reach bounds a **view** distance; the residual is a
receiver whose centre sits just past the grant while its surface is just inside reach,
bounded by that body's own radius (≤ 100 km for the only domain it can happen in, against
reaches of 1e3–1e5 km) and so landing inside the outer fifth that
`directional_shadow_fade_start` has already faded away.

**A map with no work is switched off.** Under
`IVCoreSettings.apply_empty_shadow_pass_skip` (opt-in) a shadowed light clears
`shadow_enabled` while, within its reach, either nothing holds `LOCAL_SHADOW_CASTER` — so
nothing would be drawn into the map — or nothing sits in a size domain its
`light_cull_mask` selects, so nothing would read it. Both halves are needed: at an Earth
close-up the planet holds the caster bit, and only the receiver half retires the middle
light. Eight atlas splits are otherwise set up and cleared every frame regardless; removing
them is worth 7–22 % of an integrated-GPU Forward+ frame
([GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md), *Empty shadow passes*).
Four properties make it safe:

- **What can take part is registered, not searched for.** An `IVBodyVisual` declares itself
  to `IVDynamicLight` whenever it holds the caster bit and drops out when it loses it —
  which the grant already change-gates, so the registry costs nothing per frame and a light
  reads a set of at most a handful rather than sweeping every body. A project's own level
  scene joins the same registry through `IVDynamicLight.add_local_shadow_geometry()`,
  declaring the `layers` it carries so the receiver half is exact for it too. Nothing about
  this lives outside the lighting classes.
- **Distances are measured to the near surface**, not the centre. On the lunar surface the
  Moon's centre is 1737 km away where the near light's whole reach is under a kilometre, so
  a centre test would switch off the very map this section exists for.
- **On is immediate, off waits** `IVDynamicLight.SHADOW_DISABLE_DELAY_FRAMES`: a missing
  shadow is a defect where an idle pass is only a cost, and every flip changes the frame's
  shadowed-light count, which is a shader specialization input for every lit instance
  ([GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md), *The light configuration*) —
  the reason this is opt-in rather than automatic. The transition itself is free, because
  Godot's `directional_shadow_fade_start` (0.8) has already faded to nothing whatever is
  crossing the boundary.
- **A hidden participant is skipped.** A body the distance cull or `IVSleepManager` has
  hidden draws into no map and reads none, and `is_visible_in_tree()` says so at the moment
  the light asks — so a slept spacecraft cannot hold the near light open.

**The user can switch every map off.** `IVDynamicLight.shadow_maps_enabled` false clears
`shadow_enabled` on every shadowed light whatever the skip would decide. `IVGraphicsManager` sets
it from the Shadow Resolution option's Off and shrinks the atlas with it, since Godot frees an
allocated atlas only on a size change (*`directional_shadow_count` stops being a constant* in
[GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)). The lights go on lighting their
domains, and the analytic shadows are untouched. A change moves the shadowed-light count exactly
as a flip does, but only when the user makes one.

Under the Compatibility renderer the stack degrades to a single unshadowed light unless
`IVCoreSettings.apply_gl_compatibility_shadows` (default true) re-enables the multi-light
path; the historical defects that once forced the fallback — cull masks not respected,
wrong energy with multiple lights, color shifts once any light casts (godotengine/godot
#90259) — should be re-tested on a given target before relying on it. The analytic
astronomical shadows are independent of all of this and work either way.

The fallback is also much the cheaper configuration to compile, taking a lit shader from four
GL programs to one — a large part of a Compatibility cold start, and the only configuration
the shader warm-up covers completely at its default radii
([GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md), *The light configuration*). The
[Planetarium](https://github.com/ivoyager/planetarium) ships with it off, trading spacecraft
self-shadowing for that.

## Culling, visibility and lifecycle

**Distance culling is angular-size culling in disguise.** Bodies set
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
engine's "unset" 0.0 is filled in. A shell takes the cull only while it holds no farwarp box
(*Farwarp*); rings, which always hold one, are retired by their handoff instead (below).

**A handed-off body stops drawing its shells** (`IVShellsModel.cull_handed_off`). At or under
the handoff's low edge every fragment they draw discards, so all that was left of them was
vertex work — a body's own mesh, Ceres's 65,000 triangles, in every view in the system. The
gate measures the on-screen radius at the greater of the live and the capture render height,
the handshake the sphere ladder takes, so no viewport drawing the node could have drawn a
fragment of it. A local shadow caster is exempt: its shadow pass resolves the handoff against
the shadow map rather than a viewport. **Rings stop drawing at their own handoff**
(`IVRings.cull_handed_off`), once the body's point has all of their light: `IVRings` decides
that fraction at the same greatest render height and hands it to the shader, which discards
every fragment at zero. Their gate hides the instance through the rendering server, the node's
own `visible` being a project's switch for the ring and its light together.

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

- **The catalog star field** (`IVStarsVisual`): one `PRIMITIVE_POINTS` child per
  magnitude-binned star binary, vertices at true ecliptic positions, `CUSTOM0`
  carrying (V, B−V) for the photometric chain (sibling document). A fixed node under
  Universe, so it rides the origin shift, builds once and survives system rebuilds; the
  parent holds no mesh of its own. The split is per BIN and not per region because its
  purpose is the exposure cull, which drops a magnitude suffix and nothing else
  (*Skipping what the camera has metered away*, sibling document) — there is no distance
  or direction culling here, and could not be, farwarp having put every star inside the
  camera's range. Each child repeats the farwarp obligations below for itself: its own
  always-pass `custom_aabb`, its own `sorting_use_aabb_center = false`, and the parent's
  `layers`, which a child does not inherit.
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

`IVBodyPSF` draws one body's flux through the camera's point-spread function (PSF) on a
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
crescent glow. With physical light off a sunlit body's wing retires as its disc resolves and
the rim below is not drawn; the sibling document's *Glow: the bloom pass* says why.

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

## Pixel spaces

Three kinds of pixel meet on the screen, and every size in the Core is stated in one of them.

- **Logical pixels** are the GUI's: the root viewport's 2D space, which `get_visible_rect()`,
  `unproject_position()` and every mouse position are in. HUD sizes are stated here too — a
  body's name and symbol, an asteroid's symbol, the click radius, the hover probe — because they
  are sizes on the screen, and like the GUI's text they must not shrink when a screen's pixels
  do.
- **Window pixels** are the display's own. `display/window/dpi/allow_hidpi` is on by default:
  Godot declares itself DPI-aware on Windows and sizes the web canvas at its CSS size times
  devicePixelRatio, so both builds draw into physical pixels. A screenshot is in these.
- **Render pixels** are the 3D buffer's: window pixels times the 3D render scale, what a
  shader reads as `VIEWPORT_SIZE` and `IVGraphicsManager.get_render_size()` returns. Every
  decision about what the render can resolve is made in them (*Settings summary*), and the
  finest marks the HUD draws are stated in them: an orbit line and a plain asteroid point.

**The display scale maps logical pixels onto window pixels.** `IVGraphicsManager` reads it from
the screen and sets it as the root window's `content_scale_factor`
(`IVCoreSettings.apply_display_scale`). On Windows it is the primary screen's
`screen_get_dpi() / 96`: Godot is only system-DPI-aware there and reports no scale, and a
system-aware window is drawn at the system DPI on every screen. On the web it is
devicePixelRatio, re-read every frame, because browser zoom changes it and raises no event —
the canvas keeps its pixel count, so there is not even a resize to catch. macOS and Wayland
report a change through the window's `dpi_changed`. With the project's stretch mode disabled
the scale acts on 2D alone: Godot lays the GUI out in logical pixels and rasterizes its fonts
and vector icons at the scale, sharp at any factor, while the 3D view goes on rendering at
window pixels. A window still at the project's size at startup is enlarged by the scale and
fitted to the screen, since that size is the room the GUI was laid out for; a size from the
command line is left alone. The GUI Size option multiplies on top.

**The 3D pass draws the HUD, so the HUD is converted.** Every name and symbol in the 3D view
is in logical pixels. A body's name and symbol are billboards sized against the logical
viewport height, which puts them in logical pixels at any 3D render scale, and the name's
glyphs and outline are rasterized at the display scale so they are not magnified to a blur. An
asteroid's shaped symbol is a `POINT_SIZE` in render pixels, so `IVSBGPositionsVisual`
multiplies it by the display scale and the 3D render scale, and `IVFragmentIdentifier` widens
its probe by the display scale so the hover tolerance is the same distance on any screen. A
display scale change always arrives as a root `size_changed` — it moves either the logical
size or the window's — and a viewport raises no signal for a render scale change, so
`IVGraphicsManager` emits `IVGlobal.viewport_size_changed` itself; each of these re-reads its
scale there. What does not follow is a line or a plain point: an orbit line is one render pixel wide on any screen, and the Small Bodies Point
Size option (`small_bodies_point_size`) counts render pixels, which are the screen's own at a
3D render scale of 100%.

**`get_visible_rect()` is not the render size.** Under a display scale it is the window's size
divided by that scale. Code that mirrors a shader's `VIEWPORT_SIZE`, or maps a mouse position
to a buffer pixel, takes `get_render_size()`: the ring crossfade, the sphere LOD rung, the
star-bin cull, the glow levels and the picking probe all do.

Until 2026-09-22 neither build applied a scale. The GUI was laid out in window pixels, so a
250 % Windows laptop drew it at 40 % of its designed size, which no GUI Size setting could
make up. Verified on that laptop (3840×2400): the GUI and its popups lay out at 2.5, names
rasterize at 2.5 times their logical size, a changed scale re-sizes names, points and the
probe live, hover picking of bodies, orbit lines and asteroids passes at 2.5 and at 1.5, and
with the HUD and GUI hidden the 3D render in a 1920×1080 window is bit-identical to the
unscaled build's at four poses.

## Mouse picking

Picking has two halves, split by what is being picked.

**Bodies: CPU screen-space targeting.** Every in-lifespan body pushes itself to
`IVWorldController` each frame (`update_world_target`) with its camera distance; the
controller unprojects the *true* global position and keeps the target whose screen
distance to the mouse is least, within a click radius (`min_click_radius` = 20 logical px,
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
dispatches a tiny compute probe at `PRE_TRANSPARENT`, reads the HDR buffer over the same
grid — the unresolved multisample buffer under MSAA, since a resolve would average the
encoding away — returns the id nearest the mouse asynchronously, and the identifier holds
it against dropout (40 frames or 20 px of mouse travel) so a thin line does not flicker
its label.

**The probe reads the opaque pass, before anything is added over it.** A stamp decodes
only if it survives exactly, and about 1/4096 added to it breaks it. Between the opaque
pass, where every id shader draws, and the probe nothing changes a stamp: the sky draws
only where no geometry wrote depth, and glow and tonemapping come later still.
`PRE_TRANSPARENT` is also the only such point the Mobile renderer runs (`POST_OPAQUE` and
`POST_SKY` fire on Forward+ alone), and the probe asks for no resolve, which under MSAA
would add one it never reads. Two rules follow. An id shader must stay in the opaque pass
(`_fragment_id.gdshaderinc` lists what moves one out). And transparent geometry does not
hide an id: an opaque body hides a line behind it by depth, as on screen, but a line or
point seen through an atmosphere limb or a ring is picked through it — even behind a ring
dense enough to hide it from the eye. The one transparent surface that is opaque to the
eye, the sun's photosphere, lies under CPU body targeting, which `IVMouseTargetLabel`
prefers. Fog is the same case. The engine blends fog into a fragment after the shader
writes it, which with its default fog lost every orbit and point target, so every id
shader renders `fog_disabled`: a line fogged from sight is still picked, and the SBG
points, which share their shader with the id, render unfogged.

That trade is deliberate. Until 2026-09-22 the probe ran after the transparent pass, where
additive draws — which by design hide nothing — lifted the stamps beneath them off their
encoding, and `IVBodyPSF`'s glare wing made that visible. From 4.7 AU on Forward+, 19 of
125 orbit targets were lost with glare on, all within 190 px of the Sun, at 100 % render
scale, and 37 within about 300 px at 50 %, the glare law being written per render pixel;
every one returned with `glare_scale` at 0. After the move no target's result depends on
glare, at either scale, with or without MSAA, and what was found without glare is
unchanged. Phobos' orbit measures the semantic change: behind Mars' disc it is hidden both
ways, and behind Mars' limb shell it was hidden and is now picked.

Three id spaces serve three producer shapes: a per-body orbit line stamps one uniform id
(`path_id.gdshader`, a `material_overlay` above the base pass — pin and farwarp applied
identically so overlay and base occupy the same pixels); an SBG orbit line carries its
id per instance (`instance_id.gdshader`, `INSTANCE_CUSTOM`); an SBG point carries it per
vertex (`VERTEX` *is* the id). The id overlay pattern keeps identification orthogonal to
appearance — the base material knows nothing about picking.

Both halves serve *astronomical* content. A project's own local objects are picked with
ordinary physics raycasting against their true positions, which coexists with this and needs
nothing from it (*The render frame anchor and local scenes*); how the two share mouse input is
not settled (TODO).

The system requires a `RenderingDevice`: on the Compatibility renderer the identifier
removes itself and every producer's `if _fragment_identifier:` guard falls back to the
plain materials — no line/point mouse-over on the web export, while body picking (pure
CPU) is unaffected.

The stamp and the probe both live in the 3D render buffer, whose pixels are not the
mouse's: the mouse moves in logical pixels, which a display scale makes coarser than the
window's, and 3D render scale makes the buffer coarser than the window (*Pixel spaces*).
The identifier maps the mouse to the buffer pixel under it and hands that one whole pixel
to both. The two sparse grids must coincide exactly, and a scaled mouse position is
fractional: rounded separately, the stamp and the probe land on different pixels and find
nothing, silently. `fragment_range` therefore counts buffer pixels, times the display
scale to the nearest multiple of 3: at 50 % render scale the probe reaches twice as far
across the screen, each stamped pixel magnified with the rest of the image, while on a
2.5× screen it reaches as far as on a 1× one.

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

## The cloud deck's phase

A cloud deck drifts over the surface beneath it: a `shells.tsv` `process` of `_rotate`, at the
rate in `process_args` — 0.0003 deg/s on Earth's, which is 26 deg of sim day and nothing a
real second shows. It is the only shipped shell that moves relative to its body, and the phase
it moves to is a **closed form in the clock**: `IVShellsModel.get_spin()` returns
`fposmod(times[0] x rate, TAU)` and `_rotate` writes the basis from it every frame, pause
included.

**It accumulated per-frame deltas until 2026-09-19, and the defect is worth recording because
the obvious test could not see it.** The deck's phase was a function of the session's frame
history rather than of the clock, which cost three things:

- **One date did not render one Earth.** Paused at a fixed instant and posed identically, two
  processes differed across the whole lit disc by however much unpaused sim time each had run
  first. Measured at 1.6 radii, 1920x1080: 61.8 s of elapsed sim time (0.019 deg of deck)
  moves mean 1.08 codes, 16.6 % of pixels past 2, maximum 79; 240 s (0.072 deg) moves 4.19,
  40.2 % and 127. Within a run it reproduced exactly, because a paused deck stops — which is
  what made it read as a property of the process instead of a bug.
- **A clock that moved took the deck nowhere.** `IVTimekeeper.set_time` jumped the date and
  left the deck at the phase its frames had built; an excursion out and back returned
  everything except the deck.
- **The shadow the deck casts walked away from the deck.** The surface samples the deck's map
  in its OWN frame (*Cloud shells* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)), so the
  shadow fell behind by the accumulated phase — unbounded, and 26 deg per *second* at 1 day/s.
  At 195 deg the Sahara renders under grey cloud-shaped darkening with no cloud above it. The
  rule this broke was already on the record: *Renderer parity* in that document had found that
  a cross-shell sample misregisters unless the consumer tracks the drifting frame, and that a
  harness which pauses to be deterministic freezes the deck at zero drift — the one state in
  which it looks right.

The closed form settles the first two and makes the third solvable, which is why they were one
change: `clouds_shadow_spin` carries the phase to the surface shader as (cos, sin), and the
lookup turns the crossing direction back into the deck's frame before it reads the map. Both
sides resolve the phase through the one `get_spin()` from the deck's own table rate — not from
the deck NODE's basis, which shell 0 would read a frame stale, a whole revolution of error at
the top time speeds.

**What no phase rule can keep is the map's registration to the geography.** Measured from the
epoch, Earth's deck is 689 turns round by 2026, so the composite sits at an arbitrary
longitude for any date but J2000. That is inherent to a deck that drifts at all — the
accumulation held registration only until the clock first ran, then lost it at 26 deg per sim
day — and a cloud composite is weather, not a dated observation.

Verified in the app, 1920x1080, HUDs hidden, sim paused: an excursion of 426,672 sim s and
back to the same instant, 128 deg of deck under the old rule, renders **0 of 2,073,600
pixels** changed, as do two separate processes over all six poses of the cross-run A/B recipe.
Where the spin is exactly zero (`times[0] = 0`) the new surface shader is bit-identical to the
one it replaces, and the four bodies with no deck are bit-identical at every pose.

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
- **A shell's own spin** is a closed form in the clock rather than an integral of frames,
  which is what keeps it correct at any speed and across a time jump (*The cloud deck's
  phase*, above).
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
| Empty-pass skip | renderer-neutral: it keys on whether a light has a map, not on the renderer | same — but here the flip recompiles, which is why it is opt-in (*Local shadow maps*) |
| Body mouse targeting | CPU, identical | identical |
| Line/point picking | compute probe at `PRE_TRANSPARENT` | **absent** (no RenderingDevice); producers fall back to plain materials |
| 3D render scale upscale | FSR 1 (Forward+); bilinear (Mobile) | bilinear |
| GPU Kepler points | identical | identical (solver unrolled for old GL compilers) |

## Settings summary

| Where | Setting | What it does |
|---|---|---|
| `IVCamera` | `NEAR_MULTIPLIER` / `FAR_MULTIPLIER` (constants, 0.1 / 1e6) | Depth planes as multiples of camera-to-parent distance. Ratio hard-capped ~1e7 (float32 plane extraction); do not raise. |
| `IVCoreSettings` | `apply_farwarp` | Enables the compression system (manager, shader global, HUD symbol placement). |
| | `farwarp_start_ratio` | T as a multiple of camera-to-parent distance (1e4). Must stay well under `FAR_MULTIPLIER`; 1e4 leaves 100× headroom while the compressed universe spans < ~29× T. |
| | `apply_body_psf` | Enables the per-body PSF quad ([IVBodyPSF]). Off, those bodies take the fixed distance cull like any other and their discs do not fade. |
| | `apply_analytic_shadows` | Enables the analytic shadow terms and the camera-fraction light dimming. Off, astronomical shadows are absent entirely (maps don't serve them); the ambient feed continues regardless. |
| | `apply_gl_compatibility_shadows` | Shadowed multi-light stack on the Compatibility renderer (vs. one unshadowed light). Off, a lit shader compiles one GL program instead of four; see *The light configuration* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md). |
| | `apply_size_layers` / `size_layers` | Layer bits by body radius — the lighting size domains ([100 km, 0.1 km] → three domains). |
| | `local_shadow_caster_ceiling` | Dynamic `LOCAL_SHADOW_CASTER` grant range (1e5 km; must cover the largest shadowed `shadow_max_ceiling` in `dynamic_lights.tsv`). |
| | `apply_empty_shadow_pass_skip` | Opt-in: a shadowed light clears `shadow_enabled` while nothing in reach would draw into its map or read it (*Local shadow maps*). |
| | `apply_display_scale` | The screen's own scale as the root window's content scale, so GUI and HUD sizes are logical pixels (*Pixel spaces*). Off, a logical pixel is a window pixel. |
| | `radius_multiplier_visibility_range_end` | Distance cull in body radii (4000 ≈ 0.6 px angular diameter). |
| | `max_camera_distance` | Camera range limit; also sizes every always-pass `custom_aabb`. |
| | `plane_mesh_subdivisions` | Ring mesh subdivision, enough for per-vertex farwarp across the ring span. |
| | `max_sphere_resolution` | Radial segments of the finest shared sphere (256) — the top of the LOD ladder, and the annulus's azimuth steps. Rings are half it at every rung. |
| | `vertecies_per_orbit` / `vertecies_per_trajectory_segment` | State-path knots (500): smoothness base for the rebased line; the pin owns trueness. |
| | `vertecies_per_conic_mesh` / `vertecies_per_orbit_low_res` | Shared unit conic (4096) for coarse body orbits; low-res loop (100) for SBG orbit lines. |
| | `stroboscope_frames_per_second` (+ blur settings) | Artificial stable stroboscope for fast rotators at high time speed (0 = off). |
| user options | `render_scale` | The 3D render buffer as a share of the window (100, 85, 70 or 50 %), set by `IVGraphicsManager`. Every decision about what the buffer can resolve is made in its pixels: the sphere LOD rung, the star-bin cull, the disc, ring and point-source handoffs, and picking. HUD sizes stay in logical pixels, being sizes on the screen, except a line's width and a plain asteroid point's, which are render pixels and so coarsen with the buffer; glow halos keep their share of the frame (*Glow: the bloom pass* in the sibling document). |
| `IVDynamicLight` | `SHADOW_ENABLE_REACH_RATIO` / `SHADOW_DISABLE_REACH_RATIO` / `SHADOW_DISABLE_DELAY_FRAMES` (constants, 1.25 / 2.0 / 120) | Flip suppression for the empty-pass skip. Asymmetric on purpose: on is immediate, off waits. |
| | `shadow_maps_enabled` (static) | False clears every shadow map, whatever the skip decides. `IVGraphicsManager` sets it from the user's Shadow Resolution option (Off). |
| `dynamic_lights.tsv` | per-row masks, shadow distances, `apply_sun_occlusion` | The light stack: domains, shadow reach, which rows dim by the camera-point sun fraction. |
| `IVSunOcclusionManager` | `MAX_OCCLUDERS` / `MIN_OCCLUDER_RADIUS` (constants) | Occluder slots (6, matching the shader array) and the sub-km candidate cutoff. |
| `IVWorldController` | `min_click_radius` | Body-picking screen radius floor (20 logical px). |
| `IVFragmentIdentifier` | `fragment_range`, `drop_id_frames`, `drop_id_mouse_movement` | Probe grid half-extent in buffer pixels, times the display scale (9 → 49 sampled pixels at 1×); id retention against flicker. |
| `IVPathVisual` | `REBASE_*`, `PIN_*` (constants) | Rebase trigger (500 → ~0.3 px), rebake policy, tessellation bounds, pin window sizing. |
| `IVBodyPositionVisual` | `HUD_RENDER_PRIORITY` (constant) | HUD symbol/name above the shell transparency range. |
| `IVBodyPSF` | `HANDOFF_*` (constants) | Disc/point crossfade: fade span, the fallback for a source with no saturated core, and the exposure/magnitude shift that re-solves it. |
| `IVFarwarpManager` | `true_bounds_far_fraction` | Share of the camera's far plane inside which a body's shells drop the farwarp box and cull on their own bounds (0.25; *Farwarp*). 0.0 keeps the box everywhere, the un-culled render an A/B measures against. |
| `IVShellsModel` | `cull_handed_off` (static) | A body handed off to its PSF point stops drawing its shells (*Culling, visibility and lifecycle*). False draws them regardless. |
| `IVRings` | `cull_handed_off` (static) | The same for a ring whose light the point has all of; this is what retires a distant ring. False draws the plane regardless. |

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
- **Craft self-shadowing boils: the world frame is small but not stationary.** The
  near-camera scene translates through world space at the camera target's orbital speed
  (129 m/frame on the ISS, with ~4 km lattice snaps), because the origin shift resolves
  onto a ~16 km f32 lattice at 1 au and so holds the camera *near* the origin rather than
  *on* it (*The limits of origin shifting*). Godot's directional-shadow texel lattice is
  anchored in absolute world space, so the sub-texel phase re-rolls every frame.
  Established 2026-09 by the decisive experiment: pause, translate the scene rigidly by
  one frame's worth of real motion, and ~25k pixels change — every one of them on the
  craft's self-shadowing, against 250 with shadows off; a **5 cm** translation already
  changes the image. Established what it is *not*: a light-rig defect (light direction and
  `directional_shadow_max_distance` both measured perfectly constant); not `IVUnits.METER`
  sensitivity (the f32 quantum is relative); and not a defect in origin shifting, which
  delivers the smallness it was designed for — stationarity is a requirement this
  investigation discovered, not one the mechanism ever failed. ISS is the worst case,
  being the fastest-moving thing the camera can be parented to and in the only size domain
  that gets small shadow-map texels. No fix in v0.2 — the shipped near-light reach cuts
  the amplitude, not the cause. Candidate directions, in ascending order of scope:
  re-translate the camera's ancestor chain from f64 each frame (fixes it, and the depth of
  the walk decides where the residual parallax lands — one node puts it between craft and
  planet at ~1.5 px, two nodes puts it between planet and star where it is invisible);
  make every body `top_level` and place it from f64 against a frame anchor, which subsumes
  origin shifting entirely, gives a constant ~1.2e-7 rad angular error at every distance, and
  holds the near scene still under camera motion as well as under the target's orbital motion
  (planned for v0.3, §§2.4–2.5 of
  [IVBody_REDESIGN_v0.3.md](IVBody_REDESIGN_v0.3.md));
  or a `precision=double` engine build, which would let the existing shift resolve to
  millimetres but would not retire farwarp, and which we have ruled out because it requires
  custom engine and export-template builds for every target including web (*Why not compile
  Godot in 64-bit?*).
- **A project's own scene: the anchor exists, the plumbing around it does not.** *The render
  frame anchor and local scenes* states the contract v0.3's placement rule establishes; three
  things it needs are unbuilt and undesigned. A project cannot **announce its own camera** —
  `IVGlobal.current_camera_changed(camera: Camera3D)` and `camera_tree_changed(camera:
  Camera3D, parent: Node3D, …)` are already typed to the engine's classes and their consumers
  (farwarp, occlusion, exposure, body picking) would take a foreign camera today, but nothing
  lets a project emit them or supply the tree context the second one carries. Nothing **owns
  the active anchor** or sequences a handoff between two of them. And **mouse input is not
  shared**: `IVWorldController` assumes the pointer is its own, which an FPS controller also
  assumes. None of the three is hard; all three are unspecified, and a project hitting them
  would each solve them differently.
- **A shell past the true-bounds distance is still never culled.** In a close-up of something
  small the far plane shrinks, and a body beyond a quarter of it keeps the farwarp box: drawn
  off screen, a body's own mesh at its finest LOD. The handoff gate retires such a body once it
  is a point, but only a body with a quad. A box that followed the drawn geometry — the
  compressed sphere, placed camera-relative each frame — would close it, for an AABB write per
  shell per frame.
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
- **An atmosphere limb is not eclipsed.** The planet's own shadow is in the limb model
  but an eclipse by another body is not; `sun_occlusion_visible_fraction` at the
  tangent point would add it (also listed in the sibling document's atmosphere TODO —
  it is this system's one missing consumer).
- **Multiple stars: the light rig, the engine budget, and per-star occlusion.** Audited
  2026-09-05 for 3–6 light sources at a location and more than one system running at once.
  The occlusion math is per-star already; every *application* is single-sun, and the engine
  sets the hard limits. Metering, star colour and the star field seen from another system
  are the sibling document's entry.
  - **The engine budget is the wall, and per-star light stacks hit it first.** Every renderer
    caps directional lights at 8 (`RendererSceneRender::MAX_DIRECTIONAL_LIGHTS`); the one
    directional shadow atlas splits among all shadowed directional lights in powers of two
    (`_get_directional_shadow_rect`); and Compatibility draws each *shadowed* directional
    light as one more full additive geometry pass per lit instance, where unshadowed ones
    ride the base pass for ALU only. A star's `IVDynamicLight` stack is three lights, two
    shadowed: two stars take six of the eight slots and a third overflows. Decouple the jobs —
    shadow maps only for the one or two stars dominant at the camera by illuminance, the rest
    an unshadowed light or no engine light at all (next entry). `dynamic_lights.tsv` keys its
    rows to `STAR_SUN` by name, and its `apply_sun_occlusion` rows read the one
    `camera_sun_visible_fraction`, which must become per-star.
  - **Two routes to per-star occlusion, each with a trap.** (a) Attenuate per light in a
    custom `light()`. Godot's `light()` has no light index, so a star is identified by
    matching `LIGHT` to the fed directions (or `LIGHT_COLOR` to the fed energies) — and the
    top light is aimed star→*camera* while the fed direction is body→star, so they differ by
    the body's parallax seen from the star: nil in the camera's own system, tens of degrees
    across it, where a close pair of stars can be confused. (That parallax already lights
    every body with the *camera's* sun direction; a far planet under a zoomed camera renders
    the wrong phase today.) (b) Make the shell shaders self-lit from a fed star array: they
    already carry the whole per-sun interface and rebuild ambient, and the rings and the limb
    already re-apply `sun_light_energy` by hand. That takes the astronomical domain out of
    the engine's light count, aims every body's light exactly, and — `unshaded` — compiles
    ONE GL program per shell shader under any local light configuration, the trade
    `apply_gl_compatibility_shadows` makes today. It costs re-implementing the engine's
    diffuse, GGX specular and normal-map application, re-verifying `_display.gdshaderinc` on
    a lit path the renderer no longer multiplies for us, and map self-shadowing for
    middle-domain shells (Phobos), which would keep the engine path or forgo it.
  - **Either way the single-sun coupling lives in the ALBEDO-riding terms.** Lunar-Lambert,
    Minnaert, the atmosphere's sun transmittance, the rim ratio and the compat albedo/specular shadow
    all multiply ALBEDO to divide out the engine's ONE µ₀; two stars sum two µ₀ and no ALBEDO
    factor separates them, so each becomes a per-star weight on that star's diffuse, and the
    twilight and limb-remainder EMISSION terms become per-star sums. `atmosphere_limb`'s
    `light()` ignores `LIGHT` and would scale one star's integral by the sum of every light.
    `rings.gdshader` takes a second sun channel (`illumination_position`) and one phase
    angle, and `IVRings` flips its mesh sunward — with two stars there is no sunward side.
    `body_psf` folds one phase into `apparent_magnitude` and offsets one glare wing toward
    one lit limb.
  - **Per-body star selection replaces `body.star`.** `star` is one ancestor (`_index()`
    stops at the first star up the tree): a circumbinary body has none, and a planet of the
    secondary never sees the primary. Rank every star by illuminance at the receiver and feed
    the top `MAX_STARS` (6) above a floor — most bodies get one or two, which keeps
    per-fragment cost linear in the *fed* count rather than the cap — as arrays of direction,
    angular radius, energy, colour and `MAX_STARS × MAX_OCCLUDERS` occluders with a count per
    star. Loop bounds must be uniforms (*What drives the cost* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)): a
    constant six-way loop around the atmosphere quadrature is exactly the unrolling that cost
    24 s. Candidate lists stay star-independent but the sunward filter and ranking run per
    star, so CPU cost goes as stars × receivers × candidates; stars must be admitted as
    occluders of *other* stars' light; and the same selection serves concurrent systems,
    since a star 4 ly away never qualifies. The opt-in (`occluder_data_a` by name) and every
    feeder of the old uniforms (`IVBody2DCapturer`, `IVShaderWarmup`, the probe suites)
    follow the interface.
  - **Concurrent systems, the spatial part.** Every always-pass `custom_aabb` is sized to
    `max_camera_distance` about its own body, so a star's PSF quad — what would show the Sun
    from α Cen — frustum-culls from the next system; the catalog field must drop in-scene
    stars (build-time, by a catalog id column in `stars.tsv`) or the visited star draws
    twice; `camera_tree_changed` carries one star and is the funnel every consumer subscribes
    to; and `IVSleepManager` sleeps and hides the sleepable bodies outside the camera's
    planetary system, so a second system's planets stay awake while its moons do not.
- **The display scale is unverified in a browser.** *Pixel spaces* was verified on Windows
  only; the web path (devicePixelRatio, re-read every frame for zoom) has not been run in an
  export, and neither has the macOS and Wayland `dpi_changed` path.
