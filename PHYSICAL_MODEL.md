# The Physical Model

This document describes the objective simulation underneath everything I, Voyager draws:
what a body is, how its position and orientation follow from time, what an orbit is made
of and why, how time itself is kept, which numbers are the system's truth and which are
derived from it, and where all of it is authored in the data tables. It is about the logic
and the invariants; implementation detail lives in the class docs. Its two siblings cover
what is deliberately excluded here. [VISUAL_MODEL.md](VISUAL_MODEL.md) is how that truth
reaches a float32 render pipeline from one camera's point of view — parenting, origin
shifting, farwarp, shadows, culling, picking — and [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)
is how bright each pixel is. Light physics belongs to those two entirely, shadows and
eclipses included; this one covers mass, motion, rotation, time and scale. The planned
v0.3 rework of `IVBody` is tracked separately in
[IVBody_REDESIGN_v0.3.md](https://github.com/ivoyager/planetarium/blob/master/IVBody_REDESIGN_v0.3.md);
where a section below describes a v0.2 mechanism that plan replaces, it says so.

## Overview: elements are the state

A body's translation relative to its parent is held as a set of orbital elements rather
than as a position and a velocity. That is a change of coordinates, not a change of kind:
the two representations convert into each other in both directions (`IVOrbit.get_state`,
`IVOrbit.create_from_state_and_precessions`), and either one together with a time is the
same physical fact about the body. What the choice buys is that the closed-form solution
of the two-body problem is written in exactly these variables, so between the events that
change a body's state the simulator evaluates where an integrator would step — no step
size, no accumulated error, and no constraint on the order in which bodies are updated.
Orientation is the same bargain in a single variable, an angle linear in time (the
spacecraft attitude laws being the standing exception; *Rotation*). Two consequences run
through the whole document:

- **Any time is as cheap as now.** Every state query on `IVBody` takes an optional
  `time`, and every `IVOrbit` getter named `_at_time` (and every static) is valid without
  an `update()` call. That is what makes projected positions, orbit-line sampling, the
  trajectory joins, OS-time synchronization and time reversal ordinary calls rather than
  features — and it is why a body whose per-frame processing is switched off loses
  nothing.
- **Nothing accumulates, so nothing drifts.** Two machines holding the same elements and
  the same time compute the same position, to the rounding of identical operations. The
  multiplayer consequences are drawn out under *Persistence, determinism and sync*.

**Elements are live state, not a recorded path.** Nothing here is a keyframed trajectory
or a time-indexed lookup of pre-computed positions: change an orbit's elements and the
body goes somewhere else from that moment on. An impulse is already three lines — read
the state at *t*, add Δv, solve the new orbit — and a rocket under continuous thrust is
that same call repeated as often as the accuracy wants, which is how a project can fly one
today; `IVManeuveringOrbit` is on the roadmap to make impulse and constant thrust a
first-class orbit rather than each project's own loop. What the model does *not* do is
derive such changes for you. There is no N-body force integration, so a third body
perturbs nothing unless something writes the perturbation into the elements — which is why
the slow perturbations of the real solar system arrive as published rates on elements
(*Orbits*), and why the routes to a body that perturbs its neighbors are sketched rather
than built (*Two kinds of project*, TODO). The line worth keeping is between the machinery
and the data: the Planetarium's solar system unfolds the same way in every session because
its tables transcribe a known past, which is a property of that data and not a limit of
what the machinery can be given.

## Physical state versus visual state

Two states coexist. The **physical state** is the objective truth: 64-bit, authored rather
than derived, and the same for every observer. It is simulator time; every `IVBody`'s
identity, flags, mass and figure, rotation parameters, characteristics and components; every
`IVOrbit`'s elements, rates and epoch; every `IVTrajectory`'s segments; and every
`IVSmallBodiesGroup`'s element arrays. The **visual state** is what a frame computes from it
for one viewpoint: `Node3D` transforms (float32, origin-shifted), farwarp positions, orbit
lines and their pins, HUD visibility, lazy model instantiation, sleep, and the camera
itself. The visual state is *subjective* by construction — origin shifting, farwarp and
every other mechanism in the sibling document condition the frame for exactly one camera —
and that is precisely why it is not a constraint on multiplayer: only the physical state
need be shared, and each client derives its own view from it.

The `PERSIST_` constants very nearly draw that same line. The `PERSIST_PROPERTIES` lists in
`IVBody`, `IVOrbit`, `IVRealPlanetOrbit`, `IVTrajectory`, `IVSmallBodiesGroup`,
`IVTimekeeper` and `IVSpeedManager` are the authoritative inventory of the physical state
(*Persistence* below tabulates it); what the constants carry past it is the viewer's own
state — the camera, saved views, HUD visibilities and colors — which is per client and
never the world's. They are also what the optional save plugin reads and writes: with
`ivoyager_save` present, the whole physical state of the simulation saves and loads, which
is what a game needs and what the
[Project Template](https://github.com/ivoyager/project_template) ships working, dialogs and
all. The [Planetarium](https://github.com/ivoyager/planetarium) does not use it. It caches
instead a single hand-picked `IVView` between sessions — camera target, position and
tracking, HUD visibilities and colors, and the time state (speed, pause, clock), which is
the only part of it that is physical at all. Everything else about the world is rebuilt
from the tables at every launch. That shortcut is available only because nothing in the
Planetarium can move the simulation off what its tables imply: no thrust, no player, no
divergence to record. A project that has any of those wants the save plugin.

## Where it lives

| Concern | Classes | Authored in |
|---|---|---|
| Bodies and the tree | `IVBody` (`tree/body.gd`), `BodyFlags`, `characteristics`, `IVComposition` | `stars.tsv`, `planets.tsv`, `moons.tsv`, `asteroids.tsv`, `spacecrafts.tsv` |
| Orbits | `IVOrbit`, `IVRealPlanetOrbit` (`tree_components/`) | `orbits.tsv` |
| Spacecraft trajectories | `IVTrajectory` | `trajectories.tsv` + `orbits.tsv` segment rows |
| Small-body populations | `IVSmallBodiesGroup`; `shaders/_orbit.gdshaderinc`, `orbiting_positions_id.gdshader`, `orbiting_positions_lp_id.gdshader` | `small_bodies_groups.tsv` + `asteroid_binaries/` |
| Time | `IVTimekeeper`, `IVSpeedManager`, `IVScheduler`; `IVGlobal.times` | `IVCoreSettings` start time |
| Frames, constants, scale | `IVAstronomy`, `IVUnits`, `IVMath64` | `ivoyager_override.cfg` (both autoloads are replaceable) |
| Construction | `IVTableSystemBuilder` → `IVTableBodyBuilder` → `IVTableOrbitBuilder`, `IVTableCompositionBuilder`; `IVTableSBGBuilder` + `IVBinaryAsteroidsBuilder`; `IVBodyFinisher`, `IVSBGFinisher` | — |

## The body tree

An `IVBody` is a named, persistent, selectable `Node3D` in the physical tree whose
scene-tree parent is its gravitational primary. `Node.name` is the table row name
(`PLANET_EARTH`, `MOON_EUROPA`), which is also the key in the static registry
`IVBody.bodies`. Parenting *is* the orbital hierarchy: a body is a child of the body it
orbits, and nothing else about the tree's shape is arbitrary (this is also what lets
float32 imprecision cancel in the render — sibling document).

**The frame stays ecliptic all the way down.** Depth in the tree changes what a body's
translation is measured *from*, never what it is measured *in*: no `IVBody` node is ever
rotated, so a translation at any depth is an ecliptic vector. Holding one frame everywhere
is less a convenience than the absence of an alternative, because there is no privileged
local frame to hand a subtree. A planet's rotation, each of its satellites' orbits and the
plane each of those precesses about are naturally stated in different planes, and the
parent's equator is only one candidate among unboundedly many. So each such plane is named
in the data that needs it and rotated into the ecliptic once, at import (*Orbits*,
*Rotation*), and the tree itself carries no orientation — which is what leaves the relation
between any two bodies an addition up the parent chain rather than a walk through frames.

**Identity is a bitmask.** `BodyFlags` carries orbit-context and identity bits (top, star,
star-orbiter, planet, dwarf planet, moon and its planetary-mass split, asteroid,
spacecraft; comet and barycenter reserved and unimplemented), rotation-mechanics bits
(tidally locked, axis locked, the three unimplemented tumbler kinds), program bits (lazy
model, can sleep, model space disabled) and GUI bits. Every per-frame manager and HUD
filter keys on it; the identity bit values are frozen because scenes bake them as integers.

**Indexing.** On entering the tree a body registers itself and resolves three read-only
ancestors: `parent`, `star` (itself if a star, else the star above) and `star_orbiter`
(the planet or equivalent above, if any). Each parent keeps `satellites` and
`ordered_satellites`, the latter sorted by semi-parameter — defined for every conic where
semi-major axis is not — which is the GUI's traversal order. `top_bodies` holds every
root, and the indexing code allows a star to be a star-orbiter, so a hierarchical
multi-star system is expressible in the tables, though untested (*Two kinds of project*).

**A top body has no motion.** A root has no orbit, and today no translation or velocity
either: it sits at the Universe origin and the body never writes its own position.
Galactic-frame drift for a solitary star, and relative placement of several systems, are
on the roadmap (TODO); the star table already carries the galactic numbers as
characteristics.

**Mass and figure.** Core members are `mean_radius` (required, > 0) and
`gravitational_parameter` (0.0 allowed: unknown, or too small to be orbited). Everything
else about the body's substance is in `characteristics`, a persisted dictionary of
non-object values populated from 54 table columns — mass, density, equatorial and polar
radii, a measured `triaxial_size` in IAU (a, b, c) order, surface gravity, escape velocity,
temperatures, pressures, albedos, a `perspective_radius` for camera framing, atmosphere and
hydrostatic-equilibrium facts, stellar parameters — behind typed accessors that fall back
sensibly (`get_equatorial_radius()` tries the spheroid value, then the longest triaxial
axis, then the mean radius). `components` holds object-valued extensions; the stock one is
`IVComposition`, an atmosphere or photosphere composition for display. A body with no
measured figure draws its surface class's generic proportions (`surface_classes.tsv`
`fallback_triaxial_size`, normalized to its mean radius), and a body with a mesh ignores
both. In v0.3 the figure becomes an `IVBodyGeometry` component that answers surface radius
at any coordinate without touching the visual — the prerequisite for surface anchors and
for any project-built collision.

**Derived, cached, persisted.** `_system_radius` and `_hill_sphere` are computed at system
build and again on any non-precession orbit change. The Hill sphere is the textbook
`a(1 − e)(m / 3M)^(1/3)`, INF for a root and 0.0 where a mass is unknown. The system radius
is documented as the largest of the outermost satellite's semi-parameter, a multiple of
the mean radius and a table value, but the code stores only the first (TODO).

**Lifespan.** A body can carry `begin` and `end` times (table-driven, mainly spacecraft).
Outside them the body stays in the tree but is invisible, excluded from selection, and
skips its update. This is a physical fact about the body, yet the two values are not in
`PERSIST_PROPERTIES` (TODO).

**Sleep and lazy models are process economies, not state.** With `IVSleepManager` present,
`can_sleep` bodies process only while the camera is in their star-orbiter's system; with
`IVLazyModelInitializer`, `lazy_model` bodies build no visual until visited. Neither
touches the physical state, and every query stays valid through both, because every
query re-evaluates from time. Both currently key on camera parenting; the redesign
plans a proximity service in their place.

**Statics.** `IVBody.replacement_subclass` and `IVOrbit.replacement_subclass` let a project
substitute a subclass everywhere the builders create one; `IVBody.process_methods` is the
registry of spacecraft attitude laws (*Rotation*).

## Orbits: elements as the coordinate system

`IVOrbit` describes a conic about a parent, valid for e < 1, e = 1 and e > 1 alike. Its
seven defining elements are the ones that stay finite across all three: semi-parameter
*p*, eccentricity *e*, inclination *i*, longitude of the ascending node Ω, argument of
periapsis ω, time of periapsis passage *t₀*, and the gravitational parameter GM — plus a
reference basis. Semi-major axis, mean motion, specific energy and specific angular
momentum are derived and cached. Position at *t* is mean anomaly → Kepler's equation (the
elliptic, hyperbolic or Barker's parabolic form) → true anomaly → the perifocal rotation →
the reference basis.

### Why elements

- **The conic is the exact solution.** Between perturbations, seven numbers and a time
  replace an integrator entirely, with no step size, no error growth and no constraint on
  who is updated first.
- **Real departures from a conic are slow.** For everything the eye can see, the
  perturbations that matter over human spans are secular: the node regresses, the
  periapsis advances, and (for the planets, over millennia) *a*, *e* and *i* creep. Each is
  a rate on an element — the next subsection — exact under the evaluation and costing
  nothing per frame.
- **An orbit is small data.** `serialize()` packs one in 30 floats. That is what makes an
  orbit cheap to persist, to send, and to instantiate speculatively — a trajectory planner
  can hold dozens of candidate `IVOrbit`s without a node among them, which is why the class
  is a `RefCounted` and is meant to stay one.
- **Elements are the published language.** Planetary theories, satellite mean elements,
  asteroid catalogs and spacecraft ephemerides are all delivered as elements of one kind
  or another; the tables transcribe them.
- **They are the field's state variables, not a simplification of them.** Celestial
  mechanics has worked in this representation since Lagrange: variation of parameters
  treats the elements as the state and a perturbing force as rates on them, which is what
  every general-perturbation and mean-element theory propagates — the satellite theories
  behind JPL's published moon elements, SGP4 behind every Earth-satellite two-line element
  set. Mission design is conic-shaped for the same reason: patched conics, Lambert arcs,
  and a burn written as the change it makes to an osculating orbit. Where the profession
  leaves elements is where it wants meter-level accuracy under a full force model — and
  even that arrives back as elements on request (*Approaching the real solar system*).

### Reference planes and the node convention

An orbit's `reference_basis` is the frame its elements are measured in and the plane it
precesses about. Three kinds are supported: **ecliptic** (identity — the model's one frame
is the ecliptic of J2000; planets, asteroids, spacecraft, the Moon), the parent's
**equatorial** plane (built from the parent's positive pole; close-in regular moons), and a
**Laplace** plane given by its own pole RA/dec (most moons — the plane a satellite's node
actually regresses about, between the planet's equator and its orbit). In the shipped
`orbits.tsv`, 162 rows are ecliptic, 25 equatorial and 43 Laplace. For the two body-centric
kinds the basis x-axis — the zero of Ω — is the plane's ascending node on the ICRF equator,
which is the convention of JPL's planetary satellite mean elements and is what makes those
tables transcribable verbatim. The other zero that matters is the projection of the vernal
equinox onto the orbit plane, which is what a body's rotation basis is built against;
`get_vernal_referenced_mean_longitude_at_epoch()` bridges the two (a tidally locked moon
anchored to the wrong zero turns by the angle between them — 131° for Saturn's inner moons).

### Precession for free

Ω and ω are linear in time in the base class: `Ω(t) = Ω₀ + Ω̇·t`, `ω(t) = ω₀ + ω̇·t`.
Whatever produces the rates — the parent's oblateness for a close moon, the Sun for our
Moon, general relativity for Mercury — is outside the model; the rates are data, and the
motion they generate is then exact under the two-body evaluation at no further cost. The
Moon's row carries its 18.6-year nodal regression and 8.85-year apsidal advance in two
numbers, and 186 of the 230 orbit rows carry at least one rate. `IVTableOrbitBuilder`
zeroes a rate whose element is undefined in a body-centric frame (nodal precession below
`min_inclination_for_nodal_precession`, apsidal below
`min_eccentricity_for_apsidal_precession`) and never touches ecliptic rates, because there
ϖ̇ = ω̇ + Ω̇ is a coupled pair that must not be split. Signs follow the astronomical
convention (positive nodal precession is against the orbit's direction; positive apsidal
is with it), and the builder converts a source `mean_motion` given as dL/dt to the true
mean-anomaly rate by subtracting the periapsis drift.

Evolution is slow, so consumers learn of it by threshold rather than by frame: `update()`
emits `changed(is_intrinsic = true, precession_only = true)` when accumulated Ω or ω motion
since the last emit crosses `CHANGED_THRESHOLD` (0.005, which for an angle is 0.005 / 2π
rad ≈ 0.05°). That signal is what re-anchors a tidally locked rotation, rebuilds an orbit's
display path, and would carry an extrinsic change (`is_intrinsic = false`) to a network
layer.

### Real planet orbits

`IVRealPlanetOrbit` adds the JPL *Keplerian elements for approximate positions*
(ssd.jpl.nasa.gov/planets/approx_pos.html): linear rates on *a*, *e* and *i*, and for the
outer planets the *b, c, s, f* corrections, which the class folds into the time of
periapsis rather than into a mean-anomaly correction at evaluation, so the elements alone
still specify position at any time. Validity is the fit's span (3000 BC–3000 AD, or
1800–2050 for the tighter set), clamped outside it; setters are disabled because the class
is a transcription, not a playground. It is opt-in per project
(`IVTableOrbitBuilder.use_real_planet_orbits`; the Planetarium turns it on) and per row
(`real_planet_orbit`), and the nine rows that carry it are the eight planets and Pluto,
whose corrections the JPL page once listed and the table preserves. It is also the worked
example of how a subclass evolves elements the base does not: it overrides the two 64-bit
cores (`_write_translation`, `_write_state`) and the `_at_time` getters, keeps its own
hysteresis detectors for the elements it moves, and inherits everything else.

### Conversion both ways is what keeps elements from limiting

Elements are a coordinate system for state, and the transformation exists in each
direction: `get_state(time)` gives position and velocity;
`create_from_state_and_precessions(x, y, z, vx, vy, vz, GM, time, …)` solves the
osculating elements from them (elliptic and hyperbolic). So an impulse is: read the state,
add Δv, solve a new orbit — one call, no integration. A continuously thrusting or perturbed
arc can be re-osculated as often as its accuracy requires, at any rate from once per burn
to once per frame. A body captured by a new primary is the same conversion in the new
primary's frame — a spacecraft already does exactly this at every trajectory segment
boundary. `solve_lambert` (universal-variable, double precision, zero-revolution) closes
the other classic problem, the conic through two positions in a given time. None of this
requires abandoning elements as the stored truth; it is why the roadmap's
`IVManeuveringOrbit` and `IVResonantOrbit` are subclasses, and why the still-unimplemented
`create_from_state_and_environment` — estimate the precession rates from the parent's J2,
the grandparent and a massive sibling — is an initializer, not a new representation.

### Barycenters, today and tomorrow

Every orbit is about a *body*, and the parent sits at the focus. Where a satellite is
massive enough that this is wrong, the tables compensate: a moon row gives a `mean_motion`,
the builder derives the orbit's GM from `a³n²`, and that GM is the barycentric one —
Charon's works out ~12 % above Pluto's own — so the orbit's period and size are right while
Pluto stays pinned. The builder warns when the derived GM strays past +16 % or −7 % of the
parent's. `BODYFLAGS_BARYCENTER` is reserved for the real fix: a massless orbitable node
that both partners orbit with phase-linked orbits. The redesign's capability matrix shows
the node itself costing no special code path (an orbitable body needs only a GM and tree
membership); the phase linking is still an open question there.

### Epochs

152 of the 230 orbit rows are transcribed at their source epoch rather than J2000
(`epoch_jd`). The builder shifts *t₀*, unwinds Ω and ω by their rates over the epoch
difference, and re-modulos *t₀* into the period nearest J2000, so every live orbit is
J2000-referenced whatever its data's provenance.

## Trajectories: patched conics

A spacecraft that leaves one primary for another is an `IVTrajectory`: an ordered,
time-contiguous array of `IVOrbit` segments, each about its own primary (`parent_name`)
over `[segment_begin, segment_end)`. The body owning one swaps *both* its orbit and its
scene-tree parent at each boundary (`set_orbit_and_parent`), and that reparent is a
physical event — `parent_changed` — not a visual one; position is recomputed from the new
segment in the same frame, so nothing jumps. Outside the trajectory's overall window the
body parks at the nearest endpoint instead of extrapolating a conic off the drawn path,
and `begin` / `end` bound its existence separately. A segment can be flagged a *visual
orbit* (a parking or capture orbit, drawn as an ordinary ellipse in its primary's frame),
and `end_remove` lets the final segment become a plain orbit and the trajectory be
discarded — Juno's capture orbits, the Voyagers' escape legs.

**The data are JPL osculating elements per primary; continuity is a runtime property.**
Each segment is a HORIZONS osculating conic sampled where a single conic best fits — a
flyby at closest approach, a departure at its synthetic perigee — and the heliocentric
cruises between them are flagged `fix_gaps`. At new game `IVTrajectory._fix_gaps` refits
each such cruise as the Lambert conic through its neighbors' boundary positions *as the
running simulation computes them*, so the joins close to float precision under whichever
planet model the project runs (mean elements or `IVRealPlanetOrbit`) and whatever data the
tables carry; the fitted orbits persist, and the flag does not. The shipped 36 segment
rows serve five trajectories (Pioneer 10, Voyagers 1 and 2, Juno, New Horizons), with
eccentricities up to ~3000 at the Pluto flyby — e > 1 is exercised continuously, not as an
edge case. The whole pipeline — sources, the HORIZONS query, the element-to-column mapping,
segmentation rules, the time base and the known imprecisions — is
`addons/tools/TRAJECTORIES.md`. What it does not model is anything *within* a segment:
maneuvers, encounters and the drift between representative orbits are absorbed at
boundaries, where a discontinuity is expected rather than an error.

## Rotation

**One axis, one rate.** A body's orientation at *t* is `orientation_at_epoch` rotated about
`rotation_axis` by `rotation_rate × t`, with `rotation_at_epoch` the phase folded into the
epoch basis. The axis is built from the IAU pole (`right_ascension`, `declination`), the
rate from `rotation_period` (negative for retrograde: Venus), and the phase from
`substellar_longitude_at_epoch`, which the builder anchors so the named longitude faces the
parent at J2000 (Earth's clock runs ~10 minutes off if this sign is wrong; it was, once).
`rotation_axis` is always *north*, under a policy that is messier than it sounds because
the IAU defines north only for planets and their satellites: stars and planets take the
pole in ecliptic north's hemisphere, other star-orbiters take the positive pole (Pluto's
convention), and everything else follows its parent's positive pole — with axis and rate
flipped together at build so the two stay consistent, and `get_positive_axis()`
recovering the right-hand-rule pole when it is the other one.

**Locked rotation is derived from the orbit.** A tidally locked body (60 moons) takes its
rate from the orbit's mean-longitude rate and its phase from the vernal-referenced mean
longitude at epoch plus a table offset, re-derived on every orbit `changed` so a precessing
orbit drags the lock with it; an axis-locked body (59 of those) additionally takes its axis
from the orbit normal, with a polarity flip where that normal points against the parent's
north (Triton). Both are derived once at system build, which is also when the anchor —
stashed as an *offset* in `characteristics`, not a full angle — is applied (applying it
twice was the historical bug).

**Attitude laws are visual, not state.** Spacecraft name a `process` method in
`spacecrafts.tsv` — Earth-pointing with a north-held roll (Pioneer, Voyager, New
Horizons), sun-pointed spin (Juno), nadir-locked LVLH from `get_orbit_tracking_basis()`
(ISS), a slow inertial slew (Hubble) — registered in `IVBody.process_methods` and applied
to `body_visual.basis` each frame. They are not part of the persisted rotation parameters,
and `get_orientation(time)` with an explicit time evaluates the uniform rotation instead,
so a pointing craft's orientation is not queryable at an arbitrary time or while sleeping.
The v0.3 rotator family (uniform, locked, pointing, grounded) makes them state; see the
redesign document.

**What is not modeled.** The 117 moons flagged `tumbles_chaotically` — the outer
irregulars, Pluto's four small moons and Hyperion — get no tumbling: the flag is recorded
and the body falls back to uniform rotation, with ecliptic north for an axis and, wherever
no period is tabulated (every one of them but Hyperion), a zero rate, so they do not rotate
at all. Rotational precession is anticipated by the `time` arguments on the axis getters
and nothing more. The roadmap in `IVBody`'s header grades the missing mechanics:
axisymmetric wobble (tractable, and an aesthetic gain even for bodies that really tumble
chaotically), asymmetric tumbling (Jacobi elliptic functions), chaotic tumbling
(perturbed, and beyond a closed form).

**The stroboscope is display only.** `IVCoreSettings.stroboscope_frames_per_second`
replaces the chaotic per-frame aliasing of a fast rotator at high time speed with a stable
simulated one; it distorts what is drawn and nothing that is queried.

## Small-body groups: seventy thousand orbits on the GPU

Below the threshold where a body earns a node, populations are `IVSmallBodiesGroup`s: one
node per group holding packed float32 element arrays for every member — `e, i, Ω, ω` |
`a, M₀, n` | `s, g, mag, de` | and for Trojans `da, dl, f, θ₀` — plus names. The shipped
eleven groups are the near-Earth objects, Mars-crossers, inner/middle/outer main belt,
Hildas, the two Jupiter Trojan clouds and a "suspect Trojan" catch-all, Centaurs and
trans-Neptunian objects, each loaded from `asteroid_binaries/` by magnitude bin up to the
group's `mag_cutoff` (or `IVCoreSettings.sbg_mag_cutoff_override`). The elements are
AstDyS *proper* elements, and *g* and *s* are the proper frequencies of perihelion and
node — secular precession rates, which is the same "perturbations as rates" idea as
`IVOrbit` applied catalog-wide. The binaries are built externally by `ivbinary_maker`.

**Positions are visual state; elements are physical state.** No CPU code ever computes an
asteroid's position. `IVSBGPositionsVisual` hands the arrays to the GPU as vertex custom
data, and `orbiting_positions_id.gdshader` solves Kepler's equation per vertex per frame
against `iv_time` (Newton steps unrolled, because a `while` broke WebGL1; elliptic only),
applies the precessions, and writes the point. The float32 arithmetic is analyzed in the
sibling document (along-track quantization ~1,200 km, two orders below a pixel). The
element arrays themselves are persisted with the group, and `get_orbit_elements(index)`
exposes a member's elements, so a project can promote one asteroid to a full `IVBody` from
data it already has — the "identity change" the roadmap anticipates for captures and
rendezvous.

**Trojans librate.** L4 and L5 groups use `orbiting_positions_lp_id.gdshader`: each
member's *a* and mean anomaly oscillate about the secondary's (Jupiter's) semi-major axis
and its mean longitude ± 60°, fed per frame from the live `IVBody`, through a harmonic
oscillator with a non-linear tail term that exaggerates the excursion when distal to the
secondary. It is a stated rough approximation — libration about a Lagrange point has no
closed form — and the eccentricity libration amplitude `de` in the arrays is unused. The
proper treatment, an `IVResonantOrbit` whose elements oscillate under the secondary's
influence, is on the roadmap for individual bodies.

**Two known rough edges** are carried in TODO: the group orbit lines are static ellipses at
the epoch elements while the points precess, so line and point separate over centuries;
and a blanket factor of three on every group's *g* and *s*, added to keep the Hildas in
place over ±5,000 years, is marked in code as working for an unknown reason.

## Frames, units and constants

**One frame: the ecliptic of J2000.** Ecliptic north is +z, the vernal equinox is +x, and
every `IVBody` node is *never rotated or scaled*, so a local translation at any depth of
the body tree is already an ecliptic vector and a frame change between two bodies is pure
vector addition up the parent chain (`get_translation_to_ancestor`). `IVAstronomy` holds
the constants that connect this to how astronomers publish — the obliquity (23.4392911°
at J2000), the equatorial↔ecliptic rotations, and the basis constructions that turn a pole
direction into a body or orbit frame. Nothing in the simulator is expressed in equatorial
coordinates except at the table boundary, where a pole's or a Laplace plane's RA/dec is
converted once, and in GUI readouts.

**Two number widths, one idiom.** Real spatial quantities are 64-bit: a "translation" is
a size-3 `PackedFloat64Array`, a "state" size 6, a "basis" size 9 (`IVMath64`). Any method
returning a `Vector3`, `Basis` or `PackedVector3Array` is flagging its result as float32,
for graphics. `IVOrbit` carries both getters side by side (`get_translation` /
`get_state` against `get_position_vector` / `get_state_vectors`), and the builders, the
trajectory joins and the Lambert solver stay in doubles end to end — a near-180° transfer
would lose ~1e4 km at planetary distances through one float32 round trip. GDScript's
`float` is 64-bit in any Godot build; none of this needs a double-precision engine.

**Units are SI internally and scale is one constant.** `IVUnits` defines the internal
units (second, meter, kilogram, …) and every derived unit and constant from them. Table
values are converted at import from the `Unit` row of each `.tsv`, and the asteroid
binaries are rescaled at load, so the whole model follows `IVUnits.METER` if a project
changes it (the Planetarium's `units.gd` keeps the running record of what that constant
has cost the lighting across Godot versions). `IVUnits` is replaced through
`ivoyager_override.cfg`, which is also how a project changes the base units themselves.

**G, GM and mass.** `IVAstronomy.G` is Newton's constant in internal units, and
`IVAstronomy` is an autoload precisely so a fictional universe can replace it. Orbits
never touch G: they take a gravitational parameter (GM), because for real bodies GM is
measured directly and known far better than mass (the Sun's GM to ten significant
figures, its mass to about five). So the tables carry GM where it is known,
`IVBody.get_mass()` divides by G only when no mass was given, and `IVTableBodyBuilder`
multiplies by G only when a body has a mass but no GM. A fictional system authored in
masses therefore picks up the project's G everywhere; a real one is unaffected by it.
Changing a body's GM at runtime does not propagate to its satellites' orbits (see TODO).

## Time

**Simulator time is Terrestrial Time in seconds from J2000**, a 64-bit float that
`IVTimekeeper` advances each frame by `delta × speed_multiplier` and publishes at
`IVGlobal.times[0]` and in the `iv_time` shader global. At present values (~8e8 s) a
float64 resolves ~1e-7 s; the float32 copy the GPU sees resolves 64 s, which the sibling
document shows is harmless for point fields through this century. `IVAstronomy` records
the eventual limit — spans of 10,000+ years want a movable epoch — as a TODO.

**Speed is a multiplier, sign included.** `IVSpeedManager` holds a project-defined ladder
of speeds (`speeds`; the Planetarium's runs to 1e8×), optional eased transitions, and time
reversal when `IVCoreSettings.allow_time_reversal` permits. `Engine.time_scale` follows
the speed only if `manage_engine_time_scale` is set (the Planetarium sets it false; Core
itself almost never uses `delta`). Pause is a tree pause managed by `IVStateManager`, and
the timekeeper is pausable whatever the Universe's own process mode.

**The clock is a second, separate model.** Calendar date, Julian Day Number and the
displayed clock derive from TT but roll over on *clock time*, which by default is a
simulated Universal Time: `IVTimekeeper` counts the synodic days of `universal_time_body`
(Earth) from the sim's own rotation rate and orbital mean motion, offset so that UT1's
present 69.184 s lag behind TT is reproduced. Point it at Mars and the clock runs on sols.
A TT clock is an option; leap seconds are a constant (`utc_leap_seconds`, 37); OS
synchronization (`operating_system_time_sync`, the Planetarium's default) sets TT from the
OS's UTC plus leap seconds plus the 32.184 s TAI offset.

**Sim-time scheduling.** `IVScheduler` emits interval signals in simulator time (capped at
once per frame), for anything that must recur every simulated day or year rather than
every real second.

## Persistence, determinism and sync

**What the truth consists of.** The complete physical state, as the `PERSIST_PROPERTIES`
constants define it:

| Object | Persisted |
|---|---|
| `IVTimekeeper` | `_time` (TT seconds from J2000) |
| `IVSpeedManager` | speed index, time reversal |
| `IVBody` | `name`, `flags`, `mean_radius`, `gravitational_parameter`, the four rotation parameters, `characteristics`, `components`, `_orbit`, `_trajectory`, `_system_radius`, `_hill_sphere` |
| `IVOrbit` | `parent_name`, the segment window, reference plane and basis, the seven defining elements (Ω and ω as epoch value plus rate), the four derived ones, the last-signaled hysteresis values, the last update's anomalies and time |
| `IVRealPlanetOrbit` | additionally the *a / e / i* epoch values and rates, the JPL corrections, the validity span and its own hysteresis values |
| `IVTrajectory` | `orbits`, `visual_orbits`, `end_remove` (everything else — LCA, segment parents, path — is derived) |
| `IVSmallBodiesGroup` | identity, secondary body, `max_apoapsis`, names and all four element arrays |
| `IVComposition` | type and components |

Everything not in that table is derived: every `Node3D.position` and transform, the tree
indexing, paths and LCAs, sleep and lazy state, HUD visibility, farwarp positions, every
visual. The camera *is* persisted (`IVCamera`, `PERSIST_PROCEDURAL`), but as a viewer's
state — target, view position, tracking flags — not the world's; in a multiplayer game it
is per client and never shared. Views, HUD colors and visibility likewise.

**Determinism.** Because nothing accumulates, the persisted state plus a time *is* the
world; a loaded game and a client joining mid-session both reconstruct positions by
evaluation, not replay, and two clients cannot drift apart between syncs. What must be
synchronized is therefore small and event-driven: the time authority (a server's clock and
speed — `IVTimekeeper` and `IVSpeedManager` already refuse time and speed changes on a
client, via `IVStateManager.NetworkState`), and every *extrinsic* change of physical
state — a thrust, a set element, a rotation change, a body added or removed. Intrinsic
evolution (precession, the JPL corrections, tidal re-anchoring) is never sent, since every
client derives it identically. The hooks are in place and marked TODO:
`IVOrbit.changed(is_intrinsic = false)` and `IVBody.orbit_changed` distinguish the cases,
`IVOrbit.serialize()` / `deserialize()` pack an orbit in 30 floats (without `parent_name`,
which would need its own field), and `IVStateManager` carries the network role and
stop-sync enums from the Godot 3 implementation that was never finished for 4. Rotations
would need the same treatment.

**The save plugin** (`ivoyager_save`, absent from the Planetarium) frees and rebuilds every
`PERSIST_PROCEDURAL` object from the table above; `IVTrajectory` rebuilds its derived data
on `game_loaded`, bodies re-sort their children, and the `fix_gaps` refit is not repeated
because the fitted orbits were saved. The persisted set is also what a save must carry
through a table change: elements, not row references (only `IVTrajectory.create_from_table`
and a `characteristics.trajectory` name touch a table after build, and only at new game).

## Two kinds of project

The model, and the code around it, serve two families of project that the Core does not
distinguish; a project can be both.

### Approaching the real solar system

The Planetarium climbs a fidelity ladder that is entirely a matter of *which* elements a
row carries, never a change of machinery: mean elements with precession rates (every
moon) → `IVRealPlanetOrbit` (the JPL Keplerian fits with their millennia of validity) →
HORIZONS osculating segments refit into a continuous path (every spacecraft). The next
rung is conceptual rather than scheduled: an **`IVEphemerisOrbit`** that refreshes its
osculating elements from an integrated ephemeris — HORIZONS on demand, or a local DE/SPK
file — as often as accuracy demands. It is a subclass in the mold of `IVRealPlanetOrbit`
(override the two 64-bit cores and the `_at_time` getters; emit `changed` when it
re-osculates), it slots into the same table row and the same body, and the trajectory
joins would follow it for free because they fit against whatever the primaries actually
do. Nothing in Core has to change for a project to build it; that is the point of elements
as a coordinate system.

**The reference ephemerides are served as elements.** The solar system's reference
solutions — the JPL Development Ephemerides (DE440 and successors) and their satellite and
small-body counterparts — are numerical integrations of the full N-body problem, fit to
decades of radar, spacecraft ranging and VLBI. HORIZONS serves them, and it serves them in
either representation: `EPHEM_TYPE='VECTORS'` returns a Cartesian state,
`EPHEM_TYPE='ELEMENTS'` returns the osculating elements about whatever center you name, at
any time or cadence. Rates are published wherever they are the natural product — JPL's
planetary satellite service gives mean elements with their nodal and apsidal precession
rates and the Laplace plane those precess about (our moons), the *approximate positions*
page gives Keplerian elements with linear rates on *a*, *e* and *i* (our
`IVRealPlanetOrbit`), and AstDyS computes proper elements and their frequencies for the
asteroids (our groups). An element set is therefore not something a project has to derive;
for every class of body it is something to fetch. Each maps onto columns of `orbits.tsv` or
onto `IVOrbit` setters — which is how every spacecraft trajectory in the Planetarium was
authored (`addons/tools/TRAJECTORIES.md`) — and a state vector converts in one call
(`create_from_state_and_precessions`) when elements are not what you have.

That is worth knowing before deciding to write body positions from an ephemeris directly
each frame and step around `IVOrbit`. The two are not equivalent, because the orbit is what
the rest of the simulator asks: orbit lines and projected positions sample it at times that
are not now, the trajectory joins fit against it, tidally locked rotation and the
orbit-tracking bases are derived from it, Hill sphere and satellite ordering are computed
from it, and save, sync and time reversal all carry it as thirty floats. A body whose
position is written from outside answers none of that, and answers nothing at all for a
time it holds no sample for. Refreshing its elements instead — once at build,
once a session, or as often as accuracy demands — keeps all of it working, and is the same
move `IVEphemerisOrbit` would make on the project's behalf. What the simpler function costs
between refreshes is drift away from its epoch: arcminutes over centuries for the planets,
faster for close moons whose mean elements omit the periodic terms — invisible at the
eye's scale, inadequate for navigation, and bounded by how often one chooses to
re-osculate.

### A free-standing physical simulation

A game with an open-ended initial state uses the same machinery with the fidelity knobs
turned wherever it likes. The tables are the universe: any body, any hierarchy, in masses
or GMs; `IVAstronomy.G` is replaceable and every mass-derived value follows; precession is
a rate a row may omit; `use_real_planet_orbits` stays off; the JPL data are just rows to
delete. Time is owned by the project (`allow_time_setting` and `allow_time_reversal` off,
`manage_engine_time_scale` on if the game runs on `delta`).

**Multiple systems and multi-star systems.** The tree, the builders and the sleep manager
handle any number of roots — a body is a root when its row has no orbit — and a star can
orbit a star, so a hierarchical binary or a companion on a wide orbit is a table edit
(untested, per `IVBody`'s own header). Two things are not yet supported: a root has no
position or velocity, so several independent systems would all sit at the Universe origin
until the roadmap's top-body motion lands; and a true binary, where both partners orbit
their common barycenter, needs the barycenter body and the phase-linked orbits that go
with it. Both are in TODO. Each system's light is separate business (the sibling
documents' single-star assumptions).

**Perturbation scenarios.** A rogue planet through the solar system is, as a *body*,
already expressible: a hyperbolic heliocentric `IVOrbit` (e > 1 is a first-class case,
exercised by every flyby segment) with mass and figure. What the codebase does not yet do
is let it perturb anything: the other bodies' elements would have to evolve under its
influence, either through an `IVOrbit` subclass whose rates are driven by the perturber
(the `create_from_state_and_environment` direction, generalized to time-varying rates) or
by periodically re-osculating from a numerically integrated state through
`create_from_state_and_precessions`. Both routes use the conversions that exist; neither
changes what an orbit *is*. Lagrange-point station-keeping is the same story with a
resonant subclass.

**Collisions** are explicitly not a Core feature. A project can build them: positions and
velocities are available in doubles at any time, radii and figures are table data, and
the v0.3 geometry component answers surface radius at a coordinate. The tree gives the
natural broad phase (siblings under one primary), and a merger or fragmentation is a body
added or removed plus new orbits from state — again the same conversion.

## Data tables: where the model is authored

The physical system is built entirely from `.tsv` tables in `tables/`, imported through
the Tables plugin (`IVTableData`), which converts each column from the unit named in its
`Unit` row to internal units at import and, with `IVCoreSettings.enable_precisions`,
records the significant digits of every float for the GUI to reproduce.

- **Body tables** (`stars`, `planets`, `moons`, `asteroids`, `spacecrafts`; the list is
  `IVCoreSettings.body_tables`) hold identity flags as boolean columns, the create
  parameters (`mean_radius`, `gravitational_parameter`, pole RA/dec, `rotation_period`,
  `begin` / `end`), an `orbit` reference, and the characteristics columns. A row with no
  `orbit` is a root and must be flagged `top`. Shipped: the Sun, the eight planets plus
  Ceres and Pluto, 177 moons, five named asteroids and seven spacecraft.
- **`orbits.tsv`** is the consolidated orbit table, 230 rows: `parent` (which is where the
  tree's parentage actually comes from), `epoch_jd`, `reference_plane_type` with the
  Laplace pole for that kind, the elements in either the closed form (`semi_major_axis`,
  `mean_anomaly_at_epoch`, `mean_motion` — 194 rows) or the open-conic form valid at any
  eccentricity (`semi_parameter`, `time_periapsis` — the 36 trajectory segments), an
  optional `orbit_gravitational_parameter`, the two precession rates, the
  `IVRealPlanetOrbit` columns, and the segment columns. The builder rejects the closed form
  for e ≥ 1.
- **`trajectories.tsv`** names an ordered list of orbit rows plus `visual_orbits` and
  `end_remove`; a spacecraft row points at it through `trajectory`.
- **`small_bodies_groups.tsv`** names each group, its binary directory, magnitude cutoff,
  primary and (for Trojans) secondary and Lagrange point; its element-bound columns
  document the group definitions the binary maker applied.
- **`body_classes.tsv`** and **`surface_classes.tsv`** classify bodies for the GUI and for
  the fallback figure.

**Build order.** `IVTableSystemBuilder` walks the body tables, building each body's
ancestors first (`IVTableBodyBuilder`, which calls `IVTableOrbitBuilder` and
`IVTableCompositionBuilder`), then the small-body groups (`IVTableSBGBuilder`, reading
binaries through `IVBinaryAsteroidsBuilder`), then the camera at `home_name`.
`IVBodyFinisher` and `IVSBGFinisher` add the non-persisted adjuncts — HUD symbol, path
visual, PSF quad, lights, rings, group visuals — on `node_added`, mostly on worker threads.
`IVStateManager` then sequences the rest: on `system_tree_built` bodies build their
trajectories, tidal locks, Hill spheres and system radii; `system_tree_ready` lets the
timekeeper set the start time; `simulator_started` releases the clock.

## Settings summary

| Where | Setting | What it does |
|---|---|---|
| `IVUnits` (replaceable autoload) | `METER`, the base units | Simulation scale and internal unit system; tables and binaries convert to it. |
| `IVAstronomy` (replaceable autoload) | `G` | Newton's constant; only mass↔GM conversions use it. |
| `IVCoreSettings` | `start_time_date_clock`, `start_time_is_terrestrial_time` | New-game start time (UT by default). |
| | `allow_time_setting`, `allow_time_reversal` | Arbitrary time setting and OS sync; negative speeds. |
| | `manage_engine_time_scale` | Whether `Engine.time_scale` follows the speed. |
| | `body_tables`, `home_name` | Which tables define bodies; where the camera starts. |
| | `sbg_mag_cutoff_override` | Overrides every group's magnitude cutoff (asteroid count). |
| | `use_threads` | Threaded body finishing and other work. |
| `IVTableOrbitBuilder` | `use_real_planet_orbits` | Enables `IVRealPlanetOrbit` for rows flagged `real_planet_orbit`. |
| | `min_inclination_for_nodal_precession`, `min_eccentricity_for_apsidal_precession` | Zero a body-centric rate whose element is undefined. |
| `IVTimekeeper` | `universal_time_body`, `universal_time_offset`, `recalculate_universal_time_offset` | The simulated UT clock and its TT offset. |
| | `utc_leap_seconds`, `start_real_world_time`, `operating_system_time_sync`, `terrestrial_time_clock` | OS-time conversion and clock display. |
| `IVSpeedManager` | `speeds`, `speed_names`, `start_speed`, `ease_curve`, `ease_seconds` | The speed ladder and its transitions. |
| `IVBody` (statics) | `replacement_subclass`, `process_methods`, `system_mean_radius_multiplier` | Subclass substitution, the attitude-law registry, the system-radius floor. |
| `IVOrbit` | `replacement_subclass`; `CHANGED_THRESHOLD` (constant) | Subclass substitution; evolution-signal hysteresis (0.005). |
| `IVTrajectory` | `GAP_SKIP_KM`, `GAP_WARN_AU`, `OPEN_TERMINAL_LOOKAHEAD_YEARS` (constants) | Gap-fix thresholds and the open-end Lambert horizon. |
| `IVSleepManager` | `hide_on_sleep` | Whether sleeping bodies are also hidden. |
| `small_bodies_groups.tsv` | `mag_cutoff`, `skip` | Per-group population limit; omit a group. |

## TODO

Roadmap items consolidated from the class headers (`IVBody`, `IVOrbit`,
`IVSmallBodiesGroup`, `IVAstronomy`), plus what the audit behind this document turned up.

- **Barycenters.** `BODYFLAGS_BARYCENTER` is reserved and unimplemented; Pluto–Charon and
  any true binary run with the primary pinned at the focus and an effective barycentric GM
  derived from the mean motion. Needs the orbitable massless body (the redesign shows it
  needs no special path) and phase-linked partner orbits (redesign Q5, undecided).
- **Top-body motion and multiple systems.** A root has no translation or velocity and sits
  at the Universe origin, so concurrent star systems cannot be placed; `IVTrajectory`'s LCA
  is null across systems; `max_camera_distance` (5e3 au) is a single-system limit. The
  header's plan is relative position and velocity in Universe for each solitary star or
  system primary (galactic drift comes with it). Hierarchical multi-star systems are
  expressible today but untested.
- **Maneuvering and resonant orbits.** `IVManeuveringOrbit` (impulse and constant thrust),
  `IVResonantOrbit` (Lagrange and other resonances; the Trojan shader's libration is the
  placeholder) and `create_from_state_and_environment` (rates estimated from J2, the
  grandparent and a sibling). With them, an API for changing a body's orbit context or
  identity: a spacecraft becoming a star-orbiter, an asteroid captured as a moon or
  promoted out of a group.
- **Perturbation of existing bodies by a new one** (the rogue-planet scenario). No
  mechanism yet drives one orbit's elements from another body; *Two kinds of project*
  names the two routes the existing conversions allow.
- **Network sync.** Hooks exist (`changed(is_intrinsic)`, `serialize()`, `NetworkState`,
  client gating of time and speed); the RPC layer, `parent_name` in the serialized form,
  and rotation sync do not. Multiplayer worked in Godot 3 and was never finished for 4.
- **Rotation.** Wobble and tumbling (four grades; even the axisymmetric case would improve
  the 117 flagged moons that today spin uniformly or, lacking a period, not at all);
  rotational precession (the axis getters take a `time` they ignore); attitude laws that
  are state rather than a per-frame write to the visual, so `get_orientation(time)` and
  sleeping queries answer correctly for a pointing spacecraft. The v0.3 rotator family
  covers all of these seams.
- **The v0.3 `IVBody` redesign** itself: positioner / rotator / geometry composition,
  surface anchors (pads, rovers), fixed positioners, the proximity service replacing
  camera-parented sleep and lazy triggers, and the body answering its own surface
  geometry — the prerequisite for project-built collisions.
  [IVBody_REDESIGN_v0.3.md](https://github.com/ivoyager/planetarium/blob/master/IVBody_REDESIGN_v0.3.md).
- **Editor constructability** of bodies and orbits alongside table generation (ongoing).
- **Long spans.** A movable epoch (`IVAstronomy`) for applications past ~10,000 years,
  where float32 `iv_time` fails first and float64 seconds eventually follow; the JPL planet
  fits already clamp at ±3000.
- **Kepler solvers.** The 1e-5 rad Newton tolerance on the true-anomaly solvers is marked
  to tighten, and a better-conditioned starter or algorithm is wanted above e ≈ 0.8; the
  shader's unrolled five steps are the same solver.
- **Small-body groups.** The factor of three applied to every group's `s` and `g` (added
  for the Hildas, cause unknown — verify each group's source units before trusting a
  blanket divisor); group orbit lines drawn at epoch elements while the points precess;
  `de` (eccentricity libration) unimplemented; the Trojan libration approximation; comet
  and artificial-satellite group classes reserved; `get_orbit_elements` flagged
  experimental and not reflecting Trojan libration.
- **Audit findings in `IVBody`.** `_set_system_radius()` computes the radius-multiple and
  table-value candidates but never stores them — only the outermost-satellite branch
  writes `_system_radius`, so `get_system_radius()` is 0.0 for any body without satellites
  (no Core caller today). `begin` and `end` are not in `PERSIST_PROPERTIES`, so a
  table-driven lifespan is lost across a save and load. `set_gravitational_parameter()`
  does not update satellite orbits (documented, unimplemented).
- **Threading contract for `IVBody`.** Property getters are threadsafe, anything through
  `characteristics` is not; the header's TODO is to document (and enforce) this.
