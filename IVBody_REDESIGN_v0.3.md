# IVBody Redesign — v0.3 Planning Document

Living design document for the ivoyager_core v0.3 `IVBody` rework. Updated as decisions are
made; see the Decision Log at the end. This is a from-scratch redesign — nothing here is
obligated to preserve the v0.2 API. Existing call sites are used only as evidence of what the
new API must be *able* to express (Appendices A & B).

The three model documents written since this plan's first draft state the architecture it has
to land inside. §2 introduces them and draws the line they share through `IVBody`; the
sections after it cite them rather than restate them.

**Ground rules (from project owner):**

- Composition over inheritance. No duck-typing *inside* `IVBody`.
- External systems that duck-type *into* `IVBody` (GUI widgets, `IVSelectionManager`,
  `IVCamera`, string-path data display) keep working; their entry points are contracts (§11).
- Associated classes keep their identity and are edited to the new API. `IVBodyVisual` is
  explicitly in scope for redesign; `IVOrbit`/`IVTrajectory` gain a base class but keep their
  content.
- `IVBody` carries no HUD state and no HUD policy — the same separation it already keeps from
  GUI widgets. *Knowing* what HUDs and GUI need is expected and is how the signals and the
  facade get designed; *changing when they change* is what must not happen. Body-side names
  stay in the body's own vocabulary (no `hud_` member, signal or method), and a passive
  `display_nodes: Array[Node3D]` container holds whatever external code attaches.
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
The parent defines the *frame*, which is a physical fact; it no longer composes the body's
*transform*, which is a rendering job the tree cannot do at astronomical magnitudes
(§§2.3–2.5).

Invariants that carry over unchanged:

- `IVBody` extends `Node3D` and is **never rotated or scaled**. Translations at every tree
  level are in the ecliptic basis — which is why the frame change between any two bodies is
  vector addition up the parent chain and never a walk through frames
  ([PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *Frames, units and constants*). (Also load-bearing
  for external contracts: `IVSelectionManager` falls back on `selection is Node3D` /
  `is IVBody`, and `IVCamera` parents to targets as plain `Node3D`.)
- `Node.name` is the table row name (`PLANET_VENUS`, `SPACECRAFT_JUNO`, ...) and the registry
  key.
- Position math is 64-bit (`PackedFloat64Array` "translation"/"state"); `Vector3` outputs are
  the 32-bit graphics idiom (unchanged from `IVOrbit` conventions;
  [PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *Frames, units and constants* → "Two number widths,
  one idiom"). What changes in v0.3 is which side of that line the body's own `position`
  falls on (§2.4).

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
| **Project scene anchor** | `IVSurfaceAnchor` / `IVOrbit` / `IVTrajectory` / `IVFixedPositioner` | grounded or any | **null** | the project's own scene (§2.5) | no |

Notes:

- "Can be orbited" needs only `gravitational_parameter > 0` and tree membership — which is why
  a geometry-less, visual-less barycenter works with no special code path.
- A launch becomes a *component swap*: at ignition, replace `IVSurfaceAnchor` with an
  `IVOrbit`/`IVTrajectory` and the grounded rotator with a pointing rotator. No class change,
  no reparent gymnastics beyond what trajectory handoff already does.
- A **project scene anchor** is what a game hangs its own local scene from, and under §2.4 it is
  also the node the render frame is built around. It is an ordinary body with nothing in the
  geometry slot; what would be its visual is the project's scene. §2.5 is the whole of it.
- The extension point for exotic motion is **subclassing `IVPositioner`**, not subclassing
  `IVBody`. (`IVBody.replacement_subclass` remains for projects that need a fatter body, but
  the positioner strategy should make that rare.)


## 2. Where this sits in the larger architecture

Three documents describe the simulation this redesign has to land inside, and all three were
written after this plan's first draft. [PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) is the objective
simulation — bodies, orbits as an element coordinate system, trajectories, rotation, time,
units and scale, the persisted state. [VISUAL_MODEL.md](VISUAL_MODEL.md) is how that truth
reaches a float32 pipeline for one camera — parenting, origin shifting, farwarp, shadows,
culling, lines, picking. [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) is how bright each pixel
is. They draw one division between them, and this redesign is that division drawn through a
single class. §2.5 draws the same line the other way, at the other end of the scale: what a
project's own scene owns, what we owe it, and why "derived, disposable `position`" was never
a rule about Godot.

### 2.1 The one-way rule

[PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *Physical state versus visual state* names the two. The
**physical state** is 64-bit, authored rather than derived, and the same for every observer:
every body's identity, mass, figure, rotation parameters and attributes, every orbit's elements
and epoch, every trajectory's segments, and simulator time. The **visual state** is what a
frame computes from it for one viewpoint: `Node3D` transforms, farwarp positions, orbit lines
and their pins, HUD visibility, lazy models, sleep, the camera. The visual state is subjective
by construction — every mechanism in VISUAL_MODEL.md conditions the frame for exactly one
camera.

The load-bearing part is the *direction*. Visual derives from physical every frame; physical
never reads back. Three properties the project already depends on are consequences of that rule
and of nothing else:

- **Multiplayer needs only the physical state** ([PHYSICAL_MODEL.md](PHYSICAL_MODEL.md)
  *Persistence, determinism and sync*). Two clients holding the same elements and the same time
  compute the same position; what they render is each one's own business.
- **The whole visual state is disposable.** It can be rebuilt from the physical state at any
  time, which is why a sleeping body loses nothing, why the Planetarium rebuilds its world from
  tables at every launch, and why a rendering change is never a simulation change.
- **Nothing accumulates.** A frame's rounding is a frame's rounding; it does not become next
  frame's input.

The corollary for this redesign is a typing rule for §4's composition. `positioner`, `rotator`,
`geometry` and `attributes` are physical: 64-bit, authored, queryable at any time, persisted.
`body_visual` and `display_nodes` are visual: derived, unpersisted, disposable. Nothing in the
first group may be computed from anything in the second — which is the real content of the
ground rule that a body answers its own surface geometry without reaching into its visual
(§8.1), and of the rule that HUD policy is not body state (§9).

### 2.2 The precedent: `IVOrbit`'s 64/32 API (v0.2)

The v0.2 orbit work is the same rule applied to the class below this one, and it is the model
to follow:

> [API breaking] Fully support 64-bit in `IVOrbit` and formalize a new 64-/32-bit API idiom.
> New idiom: "Vector" = 32-bit = "for graphics use". New methods `get_translation()` and
> `get_state()` return `PackedFloat64Array`. Old methods renamed `get_position_vector()` and
> `get_state_vectors()` return `Vector3` and `PackedVector3Array`. New static utility
> `IVMath64` supports 64-bit rotations, etc.

What that bought is not precision — the math was already double, GDScript's `float` is 64-bit
in any Godot build, and none of it needs a double-precision engine. It bought **a boundary
visible in the type system.** A return type now declares which model its value belongs to, so a
caller cannot silently take the graphics answer for the physical one, and a computation that
must stay in doubles — the trajectory joins, the Lambert solver, the builders — is legible as
such end to end ([PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *Frames, units and constants* → "Two
number widths, one idiom"). `IVMath64` exists because `Vector3` and `Basis` cannot hold the
physical side of that boundary at all.

Two places in this redesign inherit the idiom directly:

- **`IVPositioner` (§6) encodes the direction in its abstract interface.** The two `@abstract`
  methods are the f64 ones, `get_translation(time)` and `get_state(time)`;
  `get_position_vector` and `get_state_vectors` are *default implementations that derive from
  them*. A subclass must supply physical truth and gets the visual output for free, and it has
  no way to supply the latter without the former. The designated project extension point is
  shaped by the rule rather than merely documented with it.
- **`IVRotator` (§7) returns a 32-bit `Basis`, and that is correct.** The idiom is not "f64
  everywhere"; it is that a quantity whose error scales with its magnitude must be f64. A
  direction-cosine matrix is unit-magnitude, so float32's relative step is an absolute
  ~1.2e-7 rad wherever the body is — below anything the frame can show. Positions are the
  opposite case, which is the whole of §2.3.

### 2.3 `IVBody.position` is on the wrong side of the line

**The prohibited 32-bit → 64-bit direction is live, in `position` and `global_position`.**
v0.2's `_process` writes `position = _orbit.update(time)`
(`tree/body.gd`, the body's only write to its own transform) — the f32 return of an f64
computation — into a transform chain carrying astronomical magnitudes. The body's 32-bit
`position` is where the simulation's spatial relationships actually live as far as
everything downstream is concerned, and `global_position` is the number most consumers reach
for. Every cost below follows from it.

The scene tree is being asked to do two jobs that have quietly diverged. It expresses **what
orbits what** — correct, load-bearing, and not in question. It also **constructs the render
frame**, and that job it cannot do, because the composition is f32 and the locals are
astronomical.

#### Two requirements on the render frame

Rendering through f32 makes two demands on the world frame — one about where the camera *is* in
it, one about how it *moves* through it. Neither is an issue in a normal Godot scene tree. Both
become a problem when they are **astronomical** in size.

1. **Location — the camera's world-space magnitude stays small.** Float32's step is relative,
   so how precisely anything near the camera can be placed is set by how far the camera is from
   the world origin. A game camera wandering kilometres from it rounds at sub-millimetres; a
   camera at 1 au rounds at ~16 km.
2. **Motion — the camera's per-frame travel through the frame stays small.** The engine anchors
   things in absolute world space, Godot's directional-shadow texel lattice above all, and
   those re-roll as the scene slides through them. Every game camera moves through its world,
   and that re-roll is the ordinary shadow crawl, motivated by motion the viewer can see. What
   must stay small is the part of the travel that is *not* real motion relative to what is
   being drawn.

Both say "camera" because in the Planetarium the camera is the only thing in the near scene.
The general subject of both is the **near scene** — whatever is being drawn at close range,
which in a project might be a whole level with the camera inside it.

Neither is a requirement of the simulation; both are artifacts of rendering it, which is why
they sit on the visual side of §2.1 — and why they are hard to meet while the body's `position`
is carrying physical state. Where v0.2 stands on each:

- **Requirement 1 is met, by a patch.** Origin shifting hauls the Universe root back under the
  camera every frame (below). It is approximate and it is awkward, but the magnitude it has to
  deliver is the magnitude it delivers.
- **Requirement 2 is not met at all, and you can watch it fail.** Parked alongside the ISS, the
  camera is stationary relative to a station that is not moving relative to it — and the frame
  still sweeps ~129 m per frame underneath them both, a hundred-odd metres against a
  hundred-metre subject. Godot's shadow lattice re-rolls on every one of those frames, and the
  **station's self-shadowing visibly boils**. Godot's world frame is anchored at the Sun;
  a body travels through it at its **absolute** speed rather than its speed
  relative to the camera, and nothing on the shading side can see that, let alone undo it.

The ~16 km quantum behind both is *relative*, so it is ~16 km at 1 au whatever `IVUnits.METER`
is; changing sim scale is not a way out ([VISUAL_MODEL.md](VISUAL_MODEL.md) *The limits of
origin shifting*).

#### What holds it together, and why that is the problem

Close-up geometry is precise anyway, and the reason is the **shared-error effect**: a body and
the camera inherit the *same* upstream rounding, so it cancels in their difference.
[VISUAL_MODEL.md](VISUAL_MODEL.md) lists it first among the four mechanisms bridging the two
number systems, and several systems reach for it deliberately. It works. What it is not is
something anyone can rely on without thinking about it, and that is the objection:

- **It is fragile: it stops working, and nothing warns you.** The cancellation holds only while
  two nodes share enough of the parent chain *and* the magnitudes running through that chain
  are not churning. Turn the time speed up and watch from far out, and the second condition
  fails: the things drawn for a body — its orbit line, its HUD symbol, its model — come off the
  body and float beside it. Nothing moved in the simulation and no code changed; two error
  terms that had been matching simply stopped matching, and only spacecraft, which share the
  camera's whole chain, stayed put. There is no warning because there is nothing to warn
  about — a compensation that is not written down anywhere cannot be checked. (The falsification
  work and the mechanism are in [VISUAL_MODEL.md](VISUAL_MODEL.md)'s TODO, "high-speed render
  registration loss"; it is one of two standing defects there with no designed fix.)
- **It is non-local, so it cannot be reasoned about where the code is.** Whether a given piece
  of geometry is precise depends on where two nodes sit relative to their common ancestor and
  how large the ancestors' translations are — facts nowhere near the line that draws it. No
  type, assertion or test catches a violation. You find out from a screenshot, at one zoom, on
  one body.
- **It has to be patched by hand, over and over.** The inventory below is real engineering that
  exists for no other reason.

#### The patches

- **Origin shifting — the patch for requirement 1, and only requirement 1.**
  `IVCamera.origin_shifting` re-translates the Universe root every frame so the camera comes to
  rest near the world origin. It is a patch in shape as well as in effect: having the camera
  move the universe inverts the obvious relationship, and the subtraction is itself f32 on a
  number holding the camera's distance from the Universe origin, so it lands the camera
  *within* ~8 km of the origin rather than *on* it. It delivers the smallness it was built for.
  What it leaves behind — a camera that is near the origin but still traveling through the
  frame — is requirement 2, untouched.
- **`IVPathVisual`'s rebased tier** (`tree/path_visual.gd` — read it as the evidence).
  One graphic has to be correct in the local render frame, against nearby
  objects, while its total extent is astronomical, and a large part of the class is machinery
  for inheriting the right rounding in the right places and not in the wrong ones. The code
  comments are nearly incomprehensible: one of them warns against setting `global_position`
  because that "would re-do the large-magnitude float32 cancellation." To understand the code
  or even the comments requires you to hold the whole error chain in your head. (Caveat: the
  change below removes most of this difficulty but not all of it. The level-of-detail mechanics
  are still needed after the 32-bit issues are removed.)
- **Farwarp's assembly rule.** `update_farwarp()` must build its result camera-relatively and
  carries a standing warning never to derive it by offsetting true-scale positions — the
  rounding of the large terms swamps the small result.
- **`IVBodyPositionVisual` has already made this change, for one node.** It is `top_level` and
  placed camera-relatively, for exactly the reason given here — and the +100/+101
  process-priority ladder in [VISUAL_MODEL.md](VISUAL_MODEL.md) *Origin shifting and the frame
  order* exists because a node that opts out of the frame must be placed after the shift
  settles. `IVSunOcclusionManager` sits in the same ladder so its `global_position` reads land
  post-shift. The precedent cuts both ways: it shows the pattern works, and it shows what one
  exception costs in ordering discipline.

A neighbouring family — the `custom_aabb` / `sorting_use_aabb_center` pairs, `farwarp_length()`,
the ~2^24 near:far ceiling — is also float32 damage, but from different roots (AABB-centre
quantization, the engine's own projection math). This change does not touch them.

#### Requirement 2 has no patch at all: local shadows boil

The decisive experiment on the ISS sweep named above: pause, translate the scene rigidly by one
frame's worth of that motion, and ~25k pixels change — every one of them on the craft's
self-shadowing, against 250 with shadows off. **Five centimetres of translation already changes
the image**, and the sweep delivers 129 m of it per frame, with ~4 km jumps on the frames where
the lattice itself moves.

This is the difference between a fragile mechanism and an absent one. No `IVPathVisual` move is
available here, because the consumer is inside the engine and takes its input from world space:
there is nothing to reparent, no anchor to rebase to, and no residual to feed a shader. It is
not a light-rig defect, not `IVUnits.METER` sensitivity, and not a failure of origin shifting,
which delivers the requirement it was built for. The shift simply has no bearing on the other
one, and could not acquire it: subtracting an f32 number at 1 au magnitude cannot make the
result hold still. Residual velocity is the direct signature of a render frame anchored
somewhere other than the scene being drawn.

### 2.4 The change: anchor-relative placement

§2.3 is the case that something has to change. This is what changes: **the body becomes
`top_level` and places itself relative to a frame anchor, from f64.**

```gdscript
top_level = true
position = absolute_f64(time) - anchor_absolute_f64(time)
```

The **frame anchor** is the one node whose absolute position the render frame is built around.
It is placed by the same rule as every body, so it lands at exactly zero and costs the formula
no special case. All it must supply is an f64 absolute translation valid at any `time` — which
is a positioner and a parent chain (§6), so an anchor is an ordinary `IVBody` carrying no
geometry, no visual and no GM. The Planetarium's anchor is its `IVCamera`; a project's is the
root of whatever local scene the viewer is standing in, and §2.5 is that case.

The scene tree stays the *logical* hierarchy — orbital math, lifecycle, selection, satellite
indexing, visual children — and stops being the *transform* hierarchy for bodies. `position`
becomes what it should always have been: a render coordinate in the visual model, derived from
the physical state each frame, with no physical relationship riding on it.

**Both requirements are then met by construction rather than approximated.** The anchor
*defines* the origin, so whatever stands with it is at zero exactly with no residual to drift
(requirement 1), and the frame is the anchor's own, so nothing translates through it except by
real motion relative to the anchor (requirement 2, which no patch was reaching). The two
requirements stop being things the code achieves and become things the frame *is* — which is
why this is worth more than the sum of the patches it deletes.

*Why an anchor and not the camera itself.* Subtracting the camera writes `position = B − C`,
which a viewer at world coordinate `C` sees at `(B − C) − C` — correct only where `C` is zero.
The Planetarium can pin its camera at the origin because nothing else is in its scene, and for
one draft that made the two formulations look like the same change. They are not. With the
anchor at `A` and the camera at its true offset `C = camera − A`, a body draws at `(B − A) − C`,
which is `B − (A + C)`: the camera's true offset from the body, at any camera position and
without the camera having to be anywhere in particular. That is what lets a viewpoint move
inside a scene of its own, and §2.5 is what the freedom is for.

Requirement 1 then survives as one contract on the anchor rather than as a property of the
whole scene: **the camera stays near its anchor**, "near" meaning small against what it is
looking at. The Planetarium meets it identically (distance zero); a project meets it because a
viewer inside a scene cannot leave it. A camera that does leave — walking out of a base and
flying away — hands the anchor off, which is continuous on screen (§2.5).

*What it buys.* Rounding `f64(body − anchor)` to f32 leaves an absolute error proportional to
distance *from the anchor* — a constant angular error of ~1.2e-7 rad (0.025") for every object
at every distance, about 1/6500 of a pixel at the reference view, so long as the camera sits
near the anchor. That is what the parenting/shared-error scheme achieves locally, made global,
automatic, and local to reason about. Note what this does to the apparent conflict with
parenting: shared error only matters because there *is* large error to share, and here there is
not, so the mechanism this seems to violate is the one it makes unnecessary. Both standing
defects in [VISUAL_MODEL.md](VISUAL_MODEL.md)'s TODO share this root: a single f64 subtraction
rounded once has no chain to churn and no lattice to sit on, so it plausibly subsumes both —
worth testing against high-speed registration before claiming it.

*And the anchor form is the better fix for the defect that motivated it.* Anchored at the
camera, orbiting the camera around the ISS drags the station through Godot's world-anchored
shadow lattice at the camera's own rate, and the boil returns whenever the viewer moves;
anchored at the station, the station is stationary in world space by construction and only the
camera moves, which is the case the lattice was built for. Camera-anchoring fixes the reported
symptom (a camera at rest beside a craft whose shadows boil anyway) and leaves ordinary shadow
crawl; anchoring on the thing being drawn makes even that unrepresentable.

*The change surface is one line.* v0.2 `IVBody` writes its own transform in exactly one place
and never writes its own basis — every rotation goes to `body_visual.basis`. A body is already a
pure translation node, which is the condition that makes `top_level` structurally free: nothing
inherits orientation through it, and visual children keep inheriting normally.

*It is mostly a deletion.* Origin shifting is subsumed — `Universe.position` stays zero and
`IVCamera.origin_shifting` with its `-=` line is removed. Farwarp improves with it: since
`position` *is* the anchor-relative vector and the camera sits at a local-scene offset from the
anchor, farwarp reduces to scaling the camera-to-body vector by `g(d)/d` and the hazard its
assembly rule guards against becomes unrepresentable. The added cost is one top-down f64 pass
per frame, keeping the sum that is currently discarded at the f32 write.

*`IVPositioner` does not change.* It stays parent-relative (§6) — that is the physical
abstraction and must not absorb a rendering concern. Only what the body does with the result
changes, which is the §2.1 rule working as intended: the visual layer is where a viewpoint
enters, and it enters nowhere else.

*It sits inside the ground rules, not against them.* "This design must not bake camera-parenting
assumptions into `IVBody`" was written for the sleep rebuild, and is about *parenting* — the
v0.2 mechanism by which camera tree position stands in for proximity. Anchor-relative
*placement* is a different coupling: it reads one anchor vector per frame and assumes nothing
about what the camera is attached to — or, under §2.5, whether the camera is one of ours at
all — which is exactly what the sleep rebuild needs to be free to change (§9.4).

#### To settle during implementation

- **Sleep.** A sleeping body's stale placement stays valid today because the tree carries it;
  anchor-relative, stale means visibly lagging whenever the anchor moves. Placement is cheap
  (one subtraction from a positioner query valid at any time), so the likely answer is that
  sleep stops gating placement and gates only the expensive work. Ties to the proximity rebuild
  (§15). An anchor itself must never sleep: it is the frame.
- **Anchor ordering.** `anchor_absolute_f64` must exist before any body is placed. §6's "valid
  at any `time`" positioner contract makes that a query at the top of the frame rather than a
  one-frame lag — one more consumer of *Any time is as cheap as now*.
- **Small-body groups.** GPU-placed by their own scheme
  ([PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *Small-body groups*); they would need the anchor as a
  uniform. Unexamined, and the one item here that could turn out to be real work.
- **`global_position` changes meaning** to anchor-relative for every consumer (§11). Most
  already want that — farwarp, sun occlusion, mouse picking, HUD placement — and several
  simplify; a consumer wanting absolute ecliptic coordinates queries the f64 state, which is the
  correct source anyway. This is the change's main review surface.
- **The model documents change with it**, and per project convention the prose is what gets
  missed: [PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *The body tree* credits parenting with letting
  "float32 imprecision cancel in the render", which stops being true; and
  [VISUAL_MODEL.md](VISUAL_MODEL.md)'s *Overview* (four mechanisms, parenting first), *Origin
  shifting and the frame order*, *The limits of origin shifting* and both TODO entries are all
  rewritten by this.

*The fallback, if v0.3 slips.* The flaw can be patched instead of removed: each frame, walk up
from the camera's target and re-translate that chain from f64, leaving every other body on the
ordinary path. Depth decides where the leftover 16 km lattice error lands — one node holds the
camera at the world origin (measured: the per-frame slide goes to exactly 0.000 m) but puts up
to ~8 km between craft and planet, ~1.5 px of parallax, and fixes only the camera's own parent;
two nodes makes craft↔planet exact and pushes the error out to planet↔star, where 16 km is
1e-7 rad and farwarp is remapping anyway. It is a patch and should be judged as one: it writes
body positions from outside the positioner, helps only the camera's own chain, and leaves the
frame barycentre-anchored, so high-speed registration is untouched. It also offers §2.5 nothing
at all, having no anchor to hand a project. Its virtue is that it is small and testable against
the same acceptance check.

### 2.5 Where a project's own scene fits

I, Voyager is an addon, and the projects it is for are not all planetaria. A first-person game
whose action happens in a base on the Moon, a lander sim, a colony builder, a ship whose
interior you walk around — each has complex local scenes, its own camera, Godot collision shapes
and Godot physics, and wants all of it to sit inside a real solar system under a real sky. That
is not a concession the architecture has to make room for. It is what the architecture is
already shaped for, and §2.4 is the piece that finishes it.

**The physical/visual split is about *astronomical* scale, and about nothing else.** §2.1's
one-way rule makes a body's rendered `position` derived and disposable because at 1e11 m an f32
coordinate quantizes at kilometres and an integrator would accumulate. Neither is true at 1e2 m.
Inside a local scene, `position` **is** the truth, exactly as in any other Godot game: a
`CharacterBody3D` moves by it, collision resolves against it, a project's own gravity integrates
it, and f32 at metre magnitudes rounds below a micron. Nothing in this document forbids that or
ever meant to. What the two states separate is the astronomical domain from its rendering — not
Godot from itself.

So there are two regimes, and the frame anchor is the seam between them.
[PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *A game whose action is local* tabulates what each owns;
what follows is the `IVBody` side of the seam.

**What I, Voyager needs from the project's scene is its root.** One `Node3D`, which becomes the
frame anchor: we place it, and everything below it is the project's business and is never
touched. Because §2.4 places it by the same rule as everything else it sits at world zero, so
the project's scene is at ordinary local coordinates in a stationary world frame — the condition
Godot physics, Godot collision and Godot's shadow lattice all want, and the one v0.2 could not
offer at all.

**The anchor is an `IVBody`, and the redesign already builds every part of it.** Its positioner
says where the scene is: `IVSurfaceAnchor` for a base or a pad (§6.2), `IVOrbit` or
`IVTrajectory` for a station or a craft in flight, `IVFixedPositioner` for something
station-kept. It carries no geometry, no visual and GM 0, which the §1 capability matrix already
admits as a row. Being a body, it is selectable, camera-targetable, indexed among its primary's
satellites, and swappable: **a launch is the component swap §1 already describes**, and the
local scene never learns that anything happened.

**Orientation comes from a rotated child, exactly as a body's visual does.** `IVBody` is never
rotated (§1), so the project's scene root is a child whose basis is `rotator.get_basis(time)` —
`IVGroundedRotator` (§7) for a surface scene, so "up" is the local vertical and the sky turns
overhead at the body's true rate. This is the same relationship `IVBody` already has with
`IVBodyVisual`; the invariant survives untouched, and the project's scene is simply the visual
that a project authored instead of us.

**More than one world, and moving between them.** One anchor is active at a time — the render
state is conditioned for exactly one viewpoint ([VISUAL_MODEL.md](VISUAL_MODEL.md) *Overview*),
so a second live frame is not a thing that exists. Every *other* anchor is placed by the same
rule as every body, `A′ − A`, so its scene renders at astronomical distance carrying the same
~1.2e-7 rad angular error as anything else out there. Handoff — the viewer boards the ship and
the ship leaves — re-places everything by one constant vector, including the departing scene and
the camera riding inside it, so nothing moves on screen. It is the same class of event as the
camera's parent handoff mid-transfer, which farwarp already tolerates for the same reason
([VISUAL_MODEL.md](VISUAL_MODEL.md) *Farwarp*).

**What a project must not do:**

- Write an `IVBody`'s `position`, or read `global_position` as an ecliptic coordinate. It is
  anchor-relative and it is a render value; the f64 state queries are the source (§5.2).
- Run Godot physics on `IVBody` nodes, or at astronomical magnitudes at all.
- Put local content outside the anchor's subtree, where it inherits no frame.
- Add a second `IVCamera` ([VISUAL_MODEL.md](VISUAL_MODEL.md) *Overview*).

**What already works, and what is still a seam.** `IVGlobal.current_camera_changed(camera:
Camera3D)` and `camera_tree_changed(camera: Camera3D, parent: Node3D, …)` are typed to the
engine's classes rather than to `IVCamera` and `IVBody`, so farwarp, sun occlusion, exposure
metering and body picking will already take a project's own camera. What a project cannot do yet
is *announce* one, or supply the tree context those signals carry. That, the choice of active
anchor, and how mouse input is shared between `IVWorldController` and a project's own controls
are open work, named in §14 and §15 rather than designed here. The photometric half of the
story — what a project's own lights and its own exposure may and may not do alongside ours — is
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) *A project's own lighting*.


## 3. The bloat audit — where every current responsibility goes

Current `body.gd` is 2,134 lines. Disposition of each responsibility:

| # | Current responsibility (v0.2 body.gd) | v0.3 home |
|---|---|---|
| 1 | Identity: `name`, `flags` | **stays** (core) |
| 2 | Static registry `bodies`, `top_bodies` | **stays** (core statics) |
| 3 | Selection-order cache + 14 `get_selection_*` traversal methods (~500 lines) | thin protocol delegates on body → **new static traversal helper** (§9) |
| 4 | Tree indexing: `parent`, `star`, `star_orbiter`, `satellites`, `ordered_satellites`, `index_satellite` etc. | **stays** (core); ordering key generalized (§5.4) |
| 5 | `_orbit` + ~10 `get_orbit_*` passthroughs, each with the sleep/time-projection pattern | **`IVPositioner`** slot; passthroughs mostly dropped (§5.3, §6) |
| 6 | `_trajectory` special-casing: `_clamp_trajectory_time`, `_get_orbit_at_time`, per-frame segment swap, `set_orbit_and_parent` | **`IVTrajectory` becomes a positioner**; body handles one generic transition protocol (§6.3) |
| 7 | Rotation state: `orientation_at_epoch`, `rotation_axis`, `rotation_rate`, `rotation_at_epoch`, `get_orientation`, north/positive axis policy, tilts, `get_rotation_period` | **`IVRotator`** slot (§7) |
| 8 | Tidal/axis locking (`_update_rotations`, `locked_rotation_at_epoch` stash) | **`IVLockedRotator`** (§7) |
| 9 | Spacecraft pointing: static `process_methods` registry + `_earth_pointing`, `_sun_pointing`, `_process_iss`, `_process_hubble`, `_resolve_process`, `_process_callable` | **pointing `IVRotator` subclasses** (§7) |
| 10 | Stroboscope effect (3 cached settings + ~25 lines of `_process`) | **`IVBodyVisual`** (§8) |
| 11 | Visual management: `body_visual`, lazy init, `make_body_visual`, `add_child_to_body_visual`, `remove_and_disable_body_visual` | **stays** (visual is the body's own representation, not a HUD) — but visual self-drives its rotation (§8) |
| 12 | Figure: `mean_radius`, equatorial/polar radius, `triaxial_size`, `perspective_radius`, `_resolve_triaxial_size` (surface-class fallback) | **`IVBodyGeometry`** slot (§5.2, §8) |
| 13 | `_system_radius`, `_hill_sphere` | **stays** (derived, body-graph domain) |
| 14 | `characteristics` dict + typed accessors + `get_characteristic` mega-switch | **`attributes`** dict; switch dropped — GUI paths address components directly (§10) |
| 15 | `components: Dictionary[StringName, RefCounted]` (e.g. `IVComposition`) | **stays** (open-ended object extensions) |
| 16 | Lifespan: `begin`, `end`, `within_lifespan`, selection invalidation | **stays** (core) |
| 17 | HUD visibility policy: `huds_visible`, `huds_visibility_changed`, `_min_hud_dist`, `hide_hud_when_close` listener, static HUD-dist multipliers | **removed from body** → HUD side (§9.2) |
| 18 | `farwarp_position`, `update_farwarp()`, LOCAL_SHADOW_CASTER grant | **removed from body** → `IVBodyPositionVisual` / `IVBodyVisual` self-compute (§9.3) |
| 19 | Mouse-target push (`_world_controller.update_world_target` each frame, visual-separation test) | **removed from body** → camera-distance service (§9.4) |
| 20 | `get_fragment_data` / `get_fragment_text` (orbit-visual mouse-over) | **`IVPathVisual`** owns its own fragment identity (§9.5) |
| 21 | Camera duck protocol: `get_camera_radius/ground_basis/orbit_basis/lat_lon_type` | **stays** as thin delegates (contract, §11.2) |
| 22 | Selection duck protocol: 14 `get_selection_*` | **stays** as thin delegates (contract, §11.1) |
| 23 | `get_periapsis_label` / `get_apoapsis_label` (STAR_SUN / PLANET_EARTH hardcode) | GUI side (`selection_data.gd` computes from `body.parent.name`) |
| 24 | `texture_2d`, `texture_slice_2d` cached from `IVAssetPreloader` | storage dropped; **method delegates** `get_selection_texture_2d()` etc. → AssetPreloader (§11.1) |
| 25 | `get_float_precision(path)` | **stays** (reads `attributes`; Planetarium contract) |
| 26 | Two static `create*` factories + `replacement_subclass` | one `create()` taking composed parts; astronomy-specs logic → rotator/builder factories (§12) |
| 27 | Position/state API: `get_position_vector`, `get_translation`, `get_state_vectors`, `get_translation_to_ancestor` | **stays** (core facade over positioner; heavily used) |
| 28 | `get_latitude_longitude(vector)` | rotator domain (no known external consumer — candidate to drop) |
| 29 | `get_orbit_tracking_basis` (LVLH) | positioner-domain helper; consumed by camera delegate + LVLH rotator |
| 30 | Paused-game-load process hack (`_on_simulator_started`) | keep for now; revisit with proximity/sleep rebuild |

Rough expectation: new `body.gd` lands at ~500–650 lines, with removed weight going to
`IVPositioner` family (mostly existing `IVOrbit`/`IVTrajectory` content), `IVRotator` family
(~250 lines), `IVBodyGeometry` (~150), and deletions (HUD/screen logic reimplemented at its
consumers, traversal boilerplate collapsed).


## 4. Architecture overview

```
IVBody (Node3D, never rotated/scaled; top_level, placed anchor-relatively — §2.4)
 ├── positioner: IVPositioner        # translation vs parent over time (nullable)
 │     IVOrbit | IVTrajectory | IVSurfaceAnchor | IVFixedPositioner | project subclass
 ├── rotator: IVRotator              # orientation over time (nullable)
 │     IVUniformRotator | IVLockedRotator | pointing rotators | IVGroundedRotator | ...
 ├── geometry: IVBodyGeometry        # figure; radius at coordinates (nullable)
 │     IVBodyGeometry (spheroid/triaxial) | IVMeshGeometry
 ├── attributes: Dictionary[StringName, Variant]   # optional scalar data (was characteristics)
 ├── components: Dictionary[StringName, RefCounted] # open-ended object extensions (IVComposition...)
 ├── body_visual: IVBodyVisual       # child Node3D, optional/lazy; self-drives rotation
 └── display_nodes: Array[Node3D]     # passive container; body never touches contents
```

The first four entries are physical state and the last two visual; §2.1 is the rule that
separates them and §2.3 is why the body's own transform now sits on the visual side.


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


## 5. The new IVBody core

### 5.1 Members (sketch)

```gdscript
class_name IVBody
extends Node3D

# Every signal states a simulation fact. Listeners named for orientation (§9): HUD and GUI
# consumers are what most of these exist to serve, and saying so is not coupling — emitting a
# display decision would be.
signal positioner_changed(positioner: IVPositioner, is_intrinsic: bool, precession_only: bool)
		# → IVPathVisual (rebuild the line); survives positioner replacement, which is why
		#   listeners connect here and never to the positioner itself
signal parent_changed(new_parent: IVBody)            # → IVPathVisual; selection/nav GUI
signal rotation_changed(is_intrinsic: bool)          # typo `rotation_chaged` fixed;
		# no listener in v0.2 — kept for network sync (§15) and for GUI reading tilts/period
signal sleep_changed(is_sleeping: bool)              # → proximity monitor, lazy visuals (§9.4)
signal within_lifespan_changed(is_within_lifespan: bool)  # → nav_button.gd; the only GUI-
		# connected body signal in v0.2, and it stays
# REMOVED: huds_visibility_changed — a display decision, and the one signal that was
#   (§9.2 rehomes the policy on the HUD side)

enum BodyFlags { ... }        # identity / GUI / program bits; see §5.5

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
var display_nodes: Array[Node3D] = [] # filled by IVBodyFinisher; body never reads or iterates it

# top_level is set true at build; `position` is an anchor-relative render coordinate (§2.4)
```

Dropped vs v0.2: `mean_radius` (→ geometry), all four rotation vars (→ rotator), `_orbit`,
`_trajectory` (→ positioner), `huds_visible`, `farwarp_position`, `_min_hud_dist`,
`texture_2d`, `texture_slice_2d`, stroboscope caches, `_world_controller`,
`_process_callable`.

### 5.2 Facade methods that remain on the body

`IVBody` keeps a *small* facade where a query is cross-component, null-safe, or a published
contract. Everything else is reached through the typed slots (`body.positioner`,
`body.rotator`, `body.geometry`) — including by GUI string paths (§10).

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

# attributes / GUI contracts (§10, §11)
func get_display_name() -> String
func get_float_precision(path: String) -> int
func get_selection_texture_2d() -> Texture2D          # delegates to IVAssetPreloader
func get_selection_texture_slice_2d() -> Texture2D

# duck-type protocol delegates (contracts; §11) — all one-liners
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
accordingly (§13). The sleep/time-projection guard that was copy-pasted into every passthrough
is implemented once, in the position/state facade.

### 5.3 `_process()` in v0.3

```gdscript
func _process(_delta: float) -> void:
	var time := _times[0]
	# 1. lifespan gate (unchanged behavior; emits within_lifespan_changed,
	#    IVGlobal.selection_invalidated)
	# 2. top_level == true; _absolute = parent._absolute + positioner.get_translation(time)
	#    position = _absolute - _anchor_absolute         # both f64, one f32 round (§2.4)
	# 3. if positioner and positioner.has_pending_transition(): _apply_transition()  # §6.3
```

That is the whole loop. Gone from `_process`: mouse-target push, HUD visibility, visual
rotation, stroboscope, pointing callables, trajectory segment comparison. The visual and HUD
elements process themselves (§8, §9); a body with no positioner and no lifespan bounds can run
with processing disabled entirely.

Step 2 is the one line that changes meaning in this redesign rather than merely moving. v0.2
writes `position = _orbit.update(time)` — a parent-relative f32 translation that the scene tree
then composes into the render frame. v0.3 sums the same parent-relative answers in f64 and
writes an anchor-relative render coordinate, rounded once; the tree stops carrying body
transforms at all. §2.3 is why. Two notes on the sketch:

- **The f64 sum replaces the tree's f32 composition, so it must run in the same top-down
  order** — a body reads its parent's already-updated absolute translation rather than walking
  the chain itself, which keeps the per-frame cost one pass over the tree rather than O(depth)
  per body. Scene-tree process order gives that for free today; making it a requirement rather
  than an accident is an implementation item (§2.4, *Anchor ordering*).
- **`IVPositioner` is unaffected either way** (§6). It answers the same parent-relative
  question; the body does the summing and the differencing, because the camera is a visual
  concern and must not reach below this line.

### 5.4 Registry, indexing, ordering

- `bodies` / `top_bodies` statics stay: they are the system-wide lookup used by builders,
  managers, GUI, tools, and the assistant (Appendices). Main-thread-only rule stays.
- `_index()` / `_clear_indexing()` / `index_satellite()` / `parent`-`star`-`star_orbiter`
  resolution stay as-is (cheap, correct, widely consumed).
- Satellite ordering generalizes: the sort key changes from `get_orbit_semi_parameter()` to
  `positioner.get_ordering_distance()` (base returns 0.0; orbit returns semi-parameter; anchor
  returns anchor radius). Surface objects therefore sort inside the lowest orbits, which is
  the natural GUI traversal order, and bodies with null positioners sort first.

### 5.5 BodyFlags

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


## 6. IVPositioner — the generic positioning object

### 6.1 The problem it solves

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

func get_ordering_distance() -> float  # §5.4; base 0.0
func has_pending_transition() -> bool  # §6.3; base false
func get_transition() -> IVPositionerTransition  # base null

func _attached(body: IVBody) -> void
func _detached(body: IVBody) -> void
```

This is not duck-typing (every call is statically dispatched through the declared base type)
and not "over-complex inheritance" (one abstract layer; concrete classes are siblings). It is
the same shape the camera problem was *not* given in v0.2 — and it is the designated project
extension point: a developer with exotic motion subclasses `IVPositioner`, not `IVBody`.

The "valid at any `time`" clause is the base class inheriting a property the model already
has and depends on — [PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *Overview* → "Any time is as cheap
as now". It is what makes a sleeping body's position queryable, orbit-line sampling and the
trajectory joins ordinary calls, and §2.4's anchor-relative placement a same-frame query
rather than a one-frame lag. A subclass that can only answer "now" breaks all four.

### 6.2 The concrete family

- **`IVOrbit extends IVPositioner`** — unchanged content (Keplerian elements, precessions,
  64/32-bit getters, `changed` signal, state paths, Lambert, serialize). Its existing
  `update(time)`, `get_translation(time)`, `get_state(time)` already satisfy the interface.
  Keeps `replacement_subclass` and `IVRealPlanetOrbit`.
- **`IVTrajectory extends IVPositioner`** — the composite: maps time → active `IVOrbit`
  segment and forwards all state queries (absorbing v0.2 body's `_clamp_trajectory_time` /
  `_get_orbit_at_time`). Continues to hold segment-parent `IVBody` refs and its LCA/path
  machinery. Exposes the active orbit for `IVBody.get_orbit()`. The patched-conic model it
  implements — what a segment is, why the joins close in doubles, the handoff rule — is
  [PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *Trajectories: patched conics*.
- **`IVSurfaceAnchor`** — fixed (or slowly moving) attachment to the parent body's surface:
  `latitude`, `longitude`, `altitude` (+ optional motion model later, for a driving rover).
  `get_translation(time)` = parent rotator basis(time) × parent geometry surface point,
  radially offset by altitude. Velocity is analytic (ω × r). Requires the parent body to have
  a rotator and geometry; asserts at `_attached()`.
- **`IVFixedPositioner`** — constant translation (optionally constant velocity drift) in the
  parent frame. Serves gravity-ignoring objects and gives "top" bodies a future galactic-drift
  option without a new mechanism.
- **null** — body stays wherever it was placed (today's top-body behavior).

### 6.3 Transitions (trajectory handoffs, launches)

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

### 6.4 What the body-side orbit API reduces to

- `get_orbit()` (typed, null when not orbit-governed) is the single orbit access point.
- The path-display facade that migrated *into* `IVBody` during v0.2 (`is_showing_orbit`,
  `get_path_frame`, `get_orbit_display`, `get_display_state_paths`, `is_camera_focused`)
  **moves to `IVPositioner`** (with `get_orbit_display`'s mesh lookup moving all the way out
  into `IVPathVisual` — meshes are display resources and don't belong below the visual layer).
  `IVPathVisual` talks to `body.positioner`, typed; the body stays out of it (§9.5).


## 7. IVRotator — orientation over time

One strategy family absorbs three v0.2 mechanisms: the four rotation vars + uniform axial
spin, tidal/axis locking (`_update_rotations`), and the spacecraft pointing-law registry
(`process_methods` + four static methods). [PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *Rotation*
states the model this family must express — the pole convention, the retrograde rule, what
tidal lock means against a precessing orbit — and its TODO names the four seams v0.2 leaves
open (no precession in the axis getters; attitude written per-frame to the visual rather than
held as state) as the ones a rotator family closes.

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
distortion of that fact and moves to `IVBodyVisual` (§8).


## 8. Geometry and visuals

### 8.1 IVBodyGeometry

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
- Consumers served: `IVSurfaceAnchor` (§6.2), camera radius, `IVSunOcclusionManager`
  (`get_equatorial_radius`/`get_polar_radius`/`get_north_axis` per frame —
  [VISUAL_MODEL.md](VISUAL_MODEL.md) *Sun occlusion: analytic shadows*), exposure metering
  (`mean_radius` — [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)), GUI radii display, the 2D
  icon rig. That list is why the figure must be a physical component and not a property of
  the visual: two of those consumers read it every frame for bodies that have no visual
  built.
- `geometry == null` is the barycenter case: `get_mean_radius()` returns 0.0 and camera
  framing falls back (Q6).

### 8.2 IVBodyVisual (in redesign scope)

Keeps its identity (model instantiation, shells vs packed model, scale/reference basis,
layers, preview staging) with these changes:

- **Self-driving rotation.** The visual connects to the frame loop itself and sets
  `basis = rotator.get_basis(time)`, applying the stroboscope effect (settings and logic move
  here from `IVBody._process`) on top when active. Pointing laws are just rotators, so the
  `process_methods` attitude branch disappears from the loop. The split is §2.1 exactly: the
  rotator answers what the orientation *is* at time t, and the stroboscope is a deliberate
  display distortion of that answer ([VISUAL_MODEL.md](VISUAL_MODEL.md) *Time compression and
  the render*), so it belongs on the visual side and must not be visible to a rotator query.
- **Constructor takes components, not a body:** `IVBodyVisual.new(name, geometry, rotator)` —
  it needs assets (by name), figure (scale), and orientation; it does not need the whole body.
- **Local-shadow-caster self-management.** The camera-distance check that
  `IVBody.update_farwarp()` performed moves into the visual's own per-frame update.
- Lazy init flow is unchanged in shape (`body.body_visual` null until needed;
  `IVLazyModelInitializer` or successor triggers creation) but the trigger will be revisited
  with the proximity rebuild, since "camera visits" is currently defined by camera parenting.
- `add_child_to_body_visual()` (rings attachment) and `make_body_visual()` (icon/preview
  staging) remain body methods.

### 8.3 GUI textures

`texture_2d` / `texture_slice_2d` storage leaves the body. The selection protocol's method
hooks (`get_selection_texture_2d()`, checked *before* the property fallback by
`IVSelectionManager`) delegate to `IVAssetPreloader` by name. `nav_button.gd` (typed consumer
of both) is edited to the methods.


## 9. HUDs and GUI on the outside of the body

**The relationship to aim for is the one `IVBody` already has with GUI widgets.** Nav buttons,
the selection panel and the info panel read the body every frame and connect to its signals;
the body has never held a widget reference, a panel's visibility rule or a button's label
policy, and a GUI redesign has never required editing `body.gd`. HUD elements — the position
symbol, the name label, the orbit line — are the same kind of consumer drawn in 3D instead of
2D, and in v0.2 they are the ones that got inside.

So the principle is a coupling rule, not a pretence of ignorance:

- The body holds no HUD state, computes no HUD policy, and emits no signal whose *meaning* is
  a display decision. `huds_visible` is a display decision; `parent_changed` is a fact about
  the simulation that happens to be what a path visual needs to hear.
- Designing that signal set and the §5.2 facade *with the HUD and GUI consumers in front of
  us* is the point of Appendices A and B — they are the inventory of what those consumers
  need, and a query they need and the body can answer cheaply belongs on the body. What the
  body must not acquire is a reason to change when they change.
- Body-side names stay in the body's own vocabulary. No member, signal or method on `IVBody`
  spells `hud`, because the body is not the thing with a heads-up display — but the doc says
  plainly, at each one, which consumers it is there for.

`display_nodes: Array[Node3D]` (this doc's earlier `hud_elements`) exists purely so external
code can find the nodes drawn for a body — position visual, path visual, lights, rings —
without scene-tree spelunking. `IVBodyFinisher` appends to it; the body never reads or iterates
it. `get_hud_name()` becomes `get_display_name()` and the table column `hud_name` follows it
[Table breaking]: the value is the body's display name, read by the HUD name label today and
by any GUI that wants a presentation name (Q1).

What moves, and where:

### 9.1 Inventory of the v0.2 leakage

`huds_visible` + `huds_visibility_changed` + `_min_hud_dist` + `hide_hud_when_close`
settings listener + `min_hud_dist_*` statics; `farwarp_position` + `update_farwarp()`;
`min_visual_separation_multiplier` + world-target push; `get_fragment_data/text`;
`get_orbit_display()` returning display meshes. All of it leaves.

### 9.2 HUD visibility policy

The show/hide-by-distance policy — hide when too close, hide when not visually separate from
the parent, the rule and its rationale in [VISUAL_MODEL.md](VISUAL_MODEL.md) *Culling,
visibility and lifecycle* → "HUD visibility policy" — becomes a HUD-side helper. Proposed home:
a static on `IVBodyHUDsState` (already the per-group HUD visibility authority), taking the body
and a camera distance. `IVBodyPositionVisual` and `IVPathVisual` apply it in their own frame
updates. If the camera-distance service (§9.4) exists, they read the distance from it;
otherwise each computes it (trivial math).

### 9.3 Farwarp

`IVBodyPositionVisual` computes its own farwarp position per frame from `body.global_position`,
the camera global position, and the static `IVFarwarpManager.get_farwarp_factor()`.
`IVFarwarpManager` keeps the global parameters and shader globals
([VISUAL_MODEL.md](VISUAL_MODEL.md) *Farwarp*) but stops pushing per-body state into `IVBody`.

Two things simplify under §2.4 and should land together. The +100/+101 priority ladder exists
because a `top_level` node cannot ride the origin shift and must be placed after it settles
([VISUAL_MODEL.md](VISUAL_MODEL.md) *Origin shifting and the frame order*); with no origin
shift there is nothing to wait for. And `body.position` *is* the anchor-relative vector, so the
farwarp position reduces to scaling the camera-to-body difference of two such vectors by
`g(d)/d` — the "never derive this by offsetting true-scale positions" hazard becomes
unrepresentable rather than merely documented.

### 9.4 Mouse targets and the camera-distance service

Someone must still feed `IVWorldController.update_world_target()` per body per frame. Rather
than each body pushing (v0.2), a single per-frame service iterates live bodies and computes
camera distance, visual separation, mouse-target registration — and this is the same loop the
**proximity-based sleep rebuild** needs. Proposal: one new program node (working name
`IVBodyProximityMonitor`) that owns the camera↔body distance sweep and serves:

1. proximity sleep decisions (replacing `IVSleepManager`'s camera-parenting trigger),
2. mouse-target push to `IVWorldController`,
3. cached per-body camera distance for HUD policy (§9.2) and lazy-visual triggering (§8.2).

Its design belongs to the sleep-rebuild effort; for this redesign the only requirement is that
`IVBody` exposes what it needs (position queries valid while sleeping — already guaranteed by
positioner semantics — plus `set_sleeping()` / `sleep_changed`).

### 9.5 Orbit-line fragments and display facade

`IVPathVisual` becomes self-sufficient: it owns its fragment identity
(`get_fragment_data/get_fragment_text` move to it; the mouse-over label duck-calls whatever
object the fragment resolves to, so nothing upstream changes), selects its own conic display
mesh from `IVGlobal.resources` using `IVOrbit`'s unit-transform getters, and reads path frames
and state paths from `body.positioner` (typed). Its three drawing tiers are
[VISUAL_MODEL.md](VISUAL_MODEL.md) *Orbit and trajectory lines*; §2.4 retires the rebased tier's
reason for existing but not the Hermite tier or the render-frame pin, and that removal is its
own effort, not a prerequisite here. If orbit-line click-to-select is ever wanted,
`IVPathVisual` implements `get_selection_body()` — a hook `IVSelectionManager` already probes
first.


## 10. Attributes (was characteristics)

- Renamed `attributes`; still `Dictionary[StringName, Variant]`, non-Object values only,
  persisted, populated by the builder from ~57 table columns.
- The `get_characteristic()` mega-switch (which virtualized `mass`, radii, `display_name`, ...)
  is dropped. Radii live in `geometry`; the few surviving virtual accessors are plain methods
  (`get_mass`, `get_display_name`, `get_body_class`, `get_surface_class`, `get_file_prefix`,
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


## 11. External duck-type contracts (must keep working)

`IVBody` performs no duck-typed calls itself. These are the entry points *others* use on it.

### 11.1 IVSelectionManager protocol (deliberately duck-typed on its side)

| Probe | v0.3 answer |
|---|---|
| property `name` | Node name (unchanged) |
| method `get_selection_gui_name()` / property `gui_name` | not implemented → falls back to `tr(name)` (unchanged) |
| method `get_selection_texture_2d()` | **new method** (was property `texture_2d`) |
| method `get_selection_camera_target()` | not implemented → `selection is Node3D` fallback (unchanged) |
| method `get_selection_body()` | not implemented → `selection is IVBody` fallback (unchanged) |
| property `flags` | kept |
| method `get_float_precision(path)` | kept (paths updated per §10) |
| methods `get_selection_up/down/next/last` + `_star/_planet/_major_moon/_moon/_spacecraft` ×2 | kept as one-line delegates to the traversal helper |

The 14 traversal bodies collapse into a parameterized helper (working name
`IVBodyTraversal`, static utility owning the selection-order cache + dirty flag that are
static vars on `IVBody` today): `next_in_order(from: IVBody, flags_all: int) -> IVBody` etc.
~500 lines become ~80.

### 11.2 IVCamera protocol

`get_camera_radius()` (→ `geometry.extent_radius`, meter-scale fallback when geometry null),
`get_camera_ground_basis()` (→ rotator), `get_camera_orbit_basis()` (→ positioner tracking
basis + star-orbiter flip), `get_camera_lat_lon_type()` (→ flags). All kept as thin
delegates; the camera continues to accept any `Node3D` and probe with `has_method`.

### 11.3 Other hard contracts

- `IVBody` remains `Node3D` (camera parenting, selection fallbacks, world targets).
- `IVGlobal.selection_invalidated(name)` still emitted on lifespan exit;
  `within_lifespan_changed` kept (nav buttons connect to it — the only GUI-connected body
  signal today).
- `IVGlobal.camera_tree_changed(camera, body, star_orbiter, star)` remains the hub signal (its
  consumers — sleep, lazy models, exposure, occlusion, dynamic light, path visual — are
  edited, not broken; the proximity rebuild may later replace some uses).
- `global_position` is **anchor-relative**, not ecliptic (§2.4). Every consumer inside Core wants
  that; a project reading it must know it, and read the f64 state instead when it wants an
  ecliptic coordinate (§2.5).
- Identity `BodyFlags` bit values frozen (scene-baked ints, §5.5).
- Mouse-over label duck-reads `object.name` on world targets and duck-calls
  `get_fragment_text()` on fragment sources (now `IVPathVisual`).


## 12. Creation and the build pipeline

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
  appends what it adds to `body.display_nodes`.
- Persistence: same `PERSIST_PROCEDURAL` pattern; the three slots persist as nested objects
  exactly as `_orbit`/`_trajectory` do today. On load, `IVBody` re-runs `_attached()` wiring
  in `_enter_tree()`/`_ready()` (replacing today's ad-hoc orbit-signal reconnect).
- Teardown: `_clear_procedural()` detaches components (breaking the trajectory↔body style
  reference cycles uniformly) and clears statics, as today.


## 13. Migration map (associated classes)

| Class | Change |
|---|---|
| `IVOrbit` | `extends IVPositioner`; content unchanged; already satisfies the interface |
| `IVTrajectory` | `extends IVPositioner`; absorbs body's segment multiplexing; emits transitions (§6.3) |
| `IVBodyVisual` | in scope: self-driving rotation + stroboscope; constructor takes (name, geometry, rotator); shadow-caster self-management |
| `IVBodyPositionVisual` | computes own farwarp position + HUD visibility (was `_body.farwarp_position`, `huds_visible`, signal); already `top_level` — §2.4 makes it the ordinary case rather than the exception |
| `IVPathVisual` | reads `body.positioner` (typed) for frames/paths; owns fragment identity; picks display meshes itself; own HUD visibility. §2.4 retires its rebased tier's reason for existing (separate effort; Hermite tier and pin stay) |
| `IVBodyFinisher` | same role; appends to `display_nodes`; `has_orbit()` → positioner check |
| `IVSelectionManager` | unchanged (its duck protocol is the contract; body keeps the entry points) |
| `IVCamera` | probes unchanged; `origin_shifting` and its `-=` line are deleted by §2.4; it serves as the Planetarium's frame anchor, publishing its own per-frame f64 absolute translation (§2.5: a project supplies one instead) |
| `IVSleepManager` | replaced by proximity monitor (separate effort, §9.4); interim: works via `top_bodies`/`satellites`/`set_sleeping` unchanged |
| `IVLazyModelInitializer` | unchanged short-term; trigger revisited with proximity rebuild |
| `IVFarwarpManager` | stops per-body pushes; keeps globals/shader params + factor statics; §2.4 drops the +100/+101 ordering it exists to anchor |
| `IVWorldController` | unchanged; fed by the proximity monitor instead of by bodies |
| `IVTableBodyBuilder` | becomes component assembler (§12); precision-path tables updated |
| `IVTableOrbitBuilder` | `parent.get_positive_axis()` → `parent.rotator`; `get_gravitational_parameter()` unchanged |
| `IVTableSystemBuilder` | unchanged in shape |
| `IVTimekeeper` | `get_rotation_rate/at_epoch` → `body.rotator`; `get_orbit_mean_*` → `body.get_orbit()` |
| `IVSunOcclusionManager` / `IVExposureManager` | per-frame reads move to `body.geometry` / `body.rotator` / `attributes` |
| `IVSmallBodiesGroup` / `IVSBGPositionsVisual` | `secondary_body.get_orbit_semi_major_axis()` etc. → `secondary_body.get_orbit().…`; GPU placement needs the §2.4 frame anchor as a uniform (unexamined) |
| `IVShellsModel` (sun mode) / `IVDynamicLight` / `IVRings` | `characteristics` → `attributes` key reads; otherwise unchanged |
| `selection_data.gd` (+ Planetarium info panel) | path data updated (§10); periapsis/apoapsis label logic moves here |
| `nav_button.gd` / `nav_buttons_system.gd` | texture methods; `get_mean_radius()` unchanged (facade) |
| `body_2d_capture` rig / tool suites | `make_body_visual()` / `get_camera_radius()` unchanged; `get_triaxial_size()` → geometry |
| `ivoyager_assistant` suites | typed reads updated (`mean_radius`, `get_orbit()`, positioner state queries) |

External projects (e.g. Astropolis) migrate on the same map; API breakage is accepted for
v0.3 per the ground rules.


## 14. Open questions

- **Q1 — Naming.** `IVPositioner` vs `IVLocator`/`IVEphemeris`; `IVSurfaceAnchor` vs
  `IVGroundAnchor`; `IVRotator` vs `IVRotationState`; `IVBodyGeometry` vs `IVFigure` (the
  astronomy term); does the open-ended `components` dict keep its name now that the typed
  slots are also informally "components"? And on the de-`hud`-ing (§9): `display_nodes` vs
  `attached_visuals` for the passive container ("elements" is spoken for by orbital elements
  and should not be reused); `get_display_name()` + table column `display_name` for v0.2's
  `get_hud_name()` + `hud_name`, which touches five body tables. And §2.5's role: "frame
  anchor" reads well in prose but sits one letter from `IVSurfaceAnchor`, which is a
  positioner and a different thing.
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
- **Q11 — Who owns the frame anchor (§§2.4–2.5).** A flag bit and a static on `IVBody`, a
  property on a new program node, or the camera's own business as today? Whatever holds it
  must be queryable before the first body is placed each frame, must survive a handoff
  without a frame of lag, and must let a project name a node we did not create. Related: does
  an anchor body appear in selection traversal and in the nav GUI (a reserved
  `BODYFLAGS_` bit would exclude it), and does it need `gravitational_parameter` semantics
  at all.
- **Q12 — Should the Planetarium anchor at the camera or at the camera's target?** Target-
  anchoring would hold a craft stationary in world space under camera motion too (§2.4), but
  `max_camera_distance` lets the camera sit 5e3 au from its target, where requirement 1 fails
  badly. A distance-gated hybrid is the obvious third answer and the obvious new complexity.
  Camera-anchoring is proposed for v0.3; §2.5 is unaffected either way, since a project
  anchors at its own scene.

## 15. Deferred / out of scope for v0.3

- Proximity-based sleep + lazy-visual triggering (separate effort; §9.4 defines the seam).
- Network sync (component `changed(is_intrinsic=false)` signals + `IVOrbit.serialize()` are
  the intended hooks; rotators will need the same). The composition of §4 is what makes this
  tractable — the physical slots are exactly the state that must be shared
  ([PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) *Persistence, determinism and sync*), and §2.4
  removes the last spatial quantity that was neither shared nor derivable.
- Wobble/tumble rotators; `IVResonantOrbit` / `IVManeuveringOrbit` (slot in as subclasses).
- Multi-star scene loading; galactic-frame top-body motion (`IVFixedPositioner` covers the
  first step). [VISUAL_MODEL.md](VISUAL_MODEL.md) and
  [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) both carry multi-star audits whose body-side
  ask is per-body star ranking in place of `body.star`; this redesign neither provides nor
  blocks it.
- Removing `IVPathVisual`'s rebased tier and `IVCamera.origin_shifting` once §2.4 ships and is
  verified against the two [VISUAL_MODEL.md](VISUAL_MODEL.md) TODO defects. The deletions are
  the payoff, but they are separate work with their own acceptance checks, and nothing in this
  redesign requires them to happen first.
- Collisions at astronomical scale (still out of scope for ivoyager_core; geometry's surface
  queries are a prerequisite a project could build on). A project's *local* collisions are
  Godot's own and need nothing from us — §2.5.
- The rest of §2.5's project-scene seam: a way for a project to announce its own camera and
  supply the tree context `camera_tree_changed` carries; selection of the active anchor and
  the handoff between anchors; sharing mouse input between `IVWorldController` and a project's
  own controls. §2.4's placement rule is what makes all three expressible; none of them is
  designed, and none blocks v0.3.


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
  become path *data* updates per §10.
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
  `get_hud_name`†, `huds_visibility_changed`*), path visual (`orbit_changed`,
  `huds_visibility_changed`*, `get_path_frame`*, `is_showing_orbit`*, `get_orbit_display`*,
  `get_display_state_paths`*, `is_camera_focused`*, `get_fragment_data`*,
  `get_translation_to_ancestor`), rings (`name`, star lookup), shells sun-mode
  (`characteristics.color_b_v/absolute_magnitude`, `global_position`, `add_child`),
  dynamic light (`characteristics.absolute_magnitude`). Starred items are removed/relocated
  by §9; † is kept but renamed (`get_display_name`).
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
  unresolved items in §14.
- 2026-09-04 — Added "Under Consideration: camera-relative placement" to what was then §4.3,
  out of the ISS shadow-shake investigation. Not a decision; the ground-rule tension noted
  there needed an owner ruling before it went further.
- 2026-09-12 — **Camera-relative placement adopted**, and the doc re-seated against the three
  model documents written since the first draft. New §2 states the physical/visual split the
  redesign realizes, with v0.2's `IVOrbit` 64/32 API as its precedent; camera-relative
  placement moves there from the old §4.3 as planned work, on the ruling that it is a different
  coupling from the camera *parenting* the ground rule forbids. §2.3 argues the need — from the
  two magnitude requirements a render frame must meet and the cost of the shared-error effect,
  rather than from the ISS symptom alone — and §2.4 states the change. All sections renumbered
  (+1 from §2 on). HUD ground rule relaxed: the body stays uncoupled from
  HUD and GUI change, but the doc stops pretending not to know who its consumers are —
  `hud_elements` → `display_nodes`, `get_hud_name()` → `get_display_name()` (Q1), §9 rewritten
  around the GUI-widget analogy.
- 2026-09-12 — **§2.4 amended from camera-relative to anchor-relative placement, and §2.5
  added**, on the owner's ruling that what the render frame needs at the origin is not the
  camera but a non-astronomical anchor the camera shares — which is what an ordinary game
  scene's root already is. The amendment is a generalization, not a retreat: camera-anchoring
  is its degenerate case (a scene of one node), and subtracting the camera is only correct
  where the camera's world position is zero, which a project with a scene of its own can
  never arrange. §2.5 states the two regimes the split actually separates — astronomical
  (ours, derived `position`) and local (the project's, `position` as truth, Godot physics and
  collisions unchanged) — and the anchor as the seam; the capability matrix gains the anchor
  row, and Q11/Q12 carry what is undecided. The three model documents were edited in the
  same pass (PHYSICAL_MODEL *Three kinds of project*, VISUAL_MODEL *The render frame anchor
  and local scenes*, PHOTOMETRIC_MODEL *A project's own lighting*).
