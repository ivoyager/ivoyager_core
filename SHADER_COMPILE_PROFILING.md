# Shader Compile Profiling

How long this plugin's shaders take the GPU driver to compile and link, which renderer that
hurts on, what drives it, what was done about it, and what an edit to a given file costs. It is
here because the answer is counter-intuitive in both directions: the cost does not track how
long a shader is, and the file you would guess is expensive is not.

This is the **one-time** cost, paid at first draw.
[GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md) is its per-frame counterpart: what the same
shaders cost every frame once they are running, and which graphics options buy that back. A
reader asking whether a weak machine can run this at all needs both -- this document says
whether it can start, that one says how it then runs.

Measured 2026-09-02 and 2026-09-03 in the [Planetarium](https://github.com/ivoyager/planetarium)
against Godot 4.7.2 on an AMD RX 7900 XTX (driver 32.0.12033). Numbers are one machine's -- treat
the *ordering* and the *ratios* as the finding, not the absolute seconds -- and even the ordering
is this vendor's. Three later sections carry other parts: *A slower machine*, where a weaker
NVIDIA part multiplies the totals by about five and puts the shell shaders four times above the
atmosphere shader that leads here; *The web export*, whose Intel and ANGLE figures were taken
on 2026-09-10, with the v0.2.1 dev build's on 2026-09-27; and *The atmosphere's structure*, the
rebuild those last figures forced, timed on the slower machine the same day. The atmosphere
shaders' figures in the sections before it predate that rebuild.

Every figure here was taken under the shadowed multi-light stack, `apply_gl_compatibility_shadows`
at its default `true`. That setting is the largest remaining lever in this document, and the
Planetarium has since turned it off; see *The light configuration*.


## The symptom

Under the **Compatibility** renderer, a run made shortly after any shader edit starts slowly and
then drops a multi-second frame the first time the camera reaches certain bodies. It clears
after one run and stays cleared until the next shader edit.

That is not a bug in anything. GLES3 compiles a shader program **at first draw**, synchronously,
on the main thread. What the opening view draws compiles during startup; everything else
compiles the first time it is drawn, which is when you fly to a body whose shader nothing has
drawn yet. Forward+ shows the same effect an order of magnitude smaller.

Two things now stand between a first run and that experience. The expensive shaders compile
several times faster than they did (*What was done*), and `IVShaderWarmup` draws every shader the
project will use under the boot screen as soon as the simulator starts (*The warm-up*), so what
remains is paid under a progress message rather than in flight.


## What it costs

From-scratch compile and link of one specialization, timed as the duration of the frame in
which a fresh material first draws, **each shader in its own process** (see *How to measure it
again* for why that matters). "Before" is the shipped code of 2026-09-02; "after" is the current
code. The third pair is what one further specialization of the same shader costs -- the light
configuration changed, or a shadow pass -- which the renderer compiles in full.

| shader | before | after | +1 specialization, before | after |
|---|---|---|---|---|
| `atmosphere_limb` | **23.8 s** | **3.7 s** | 15.4 s | 1.6 s |
| `surface` | 10.3 s | 3.7 s | 5.9 s | 1.4 s |
| `surface.cube` | 10.6 s | 3.9 s | 6.0 s | 1.6 s |
| `cloud_shell` | 10.6 s | 3.5 s | 6.1 s | 1.5 s |
| `cloud_shell.cube` | 10.8 s | 3.6 s | 6.2 s | 1.6 s |
| `band_pattern` | 10.6 s | 3.9 s | 5.7 s | 1.5 s |
| `photosphere` | 1.0 s | 0.42 s | (unshaded: none) | |

The rest were measured once, in-app and in sequence, on 2026-09-02, and did not change:
`body_psf` 1.08 s, `rings` 0.55 s, `stars` 0.24 s, `path` 0.21 s, `farwarp_vertex` 0.20 s,
`starmap_background` 0.02 s; the three id shaders are trivial. Forward+ compiles the whole set
in about 12 s and the same shaders in 1-3 s each.

**Total for one variant of everything: about 25 s now, against about 100 s before.** Every
first draw also compiles the engine's four variants of the shader at the default specialization
before the one it needs (*Specializations*), so the per-shader figures above are the cost a
first visit actually pays, not the cost of one program.


## What drives it

**Loop unrolling.** The GL compiler fully unrolls a loop whose trip count it can see, inlines
whatever the body calls, and then optimizes the result -- and the atmosphere include nests a
6-node Gauss-Legendre quadrature and two 3-node layer loops, each node drawing several columns
of `erf`, `erfinv` and `exp`, inside an 8-tap ring loop that wraps both halves of the ray. Unrolled
that is a body some hundred times the source, and the optimizer's cost is superlinear in it.
The sun shader's 3x3x3 sunspot cell loop is the same thing at a smaller scale: 27 inlined
hash-drawn spot groups.

**Not source length, and not lit versus `unshaded`.** `body_psf.gdshader` is the longest source
in the plugin and among the cheapest to compile. `photosphere` is `unshaded` and cost 1 s;
`rings` is lit and costs 0.55 s. Nor is it "heavy includes" as such -- but be careful what an
include proves. `rings` costs 0.55 s while including `_photometry.gdshaderinc`, whose limb
kernels are two 16-cell loops of exactly the expensive shape; it calls neither, so they are
unreferenced and never reach the optimizer. An include a shader does not call into is free, and
says nothing about the loops in it. What matters is the *product* of trip count and what one
iteration inlines, in the functions actually reached.

**The outer loop is not enough.** Making only the 8-tap ring loop's bound opaque changed nothing
(28 s). The inner quadrature and layer loops are what had to stop unrolling; the ring loop's bound
went opaque with them because its body wraps both ray halves.

**And the light configuration decides how many of them there are.** Everything above is what
*one* program costs. How many a shader compiles is set by the lights reaching it, and that is the
other factor of four -- with a settings flag on it. See *The light configuration*.


## Don't hand-unroll, and don't fear a `while`

Two habits this measurement should retire.

**Writing a loop out longhand is the expensive case, not the cheap one.** It hands the compiler
exactly the body that unrolling produces, minus the chance of ever not producing it. If a loop
is short and its body trivial the difference is nothing either way; if the body is heavy,
longhand is the version that costs 24 s. Where the trip count is a genuine constant of the
algorithm, write the loop and let the bound be opaque.

**Nothing here forbids a `while` loop or a dynamic bound.** GLSL ES 1.00 -- the WebGL 1 profile
Godot 3's GLES2 renderer targeted -- restricted loops to constant bounds and effectively barred
`while`, and comments in this plugin still carry that caution (`_orbit.gdshaderinc`). Godot 4
has no such target: the web export builds with `-sMAX_WEBGL_VERSION=2`, the Compatibility
renderer emits `#version 300 es`, and `shader_compiler.cpp` translates `while`, `do` and `for`
straight through. The measurements above are themselves the proof, since every one of the fast
numbers comes from a loop whose bound the compiler cannot resolve.

What is still true is a runtime point, unrelated to compiling: a divergent trip count costs
every lane in the group the maximum, so a loop with an early `break` saves nothing across a
warp that contains one slow fragment. That argues for keeping trip counts uniform across
neighbouring fragments. It has never argued for longhand.

**Nor call a heavy function from a second place.** A call site is a copy as surely as a
written-out loop is: every compiler here may inline, and FXC -- a browser's on Windows -- inlines
every call, so a function reached from ten places is compiled ten times. That, not any loop, is
what the atmosphere was paying for; see *The atmosphere's structure*. Write the second use as
another iteration of a loop the first already runs.


## What was done

The trip counts in `_atmosphere.gdshaderinc` and `photosphere.gdshader` are now
`uniform int`s -- `iv_atm_gl_first`, `iv_atm_gl_nodes`, `atm_shell_nodes`,
`iv_atm_ring_max_taps`, `spot_cell_reach` -- carrying exactly the values the constants had.
What a uniform buys is a bound the compiler cannot see, and a loop it cannot unroll. Every
Godot 4 GL target is GLSL ES 3.0 or WebGL 2, where a dynamic trip count is ordinary; the
"constant bound so every target copes" caution the ring loop used to carry was a WebGL 1
concern.

`atm_shell_nodes` and `spot_cell_reach` restate the lengths of node tables their loops index,
so any other value is wrong and nothing sets them. The three `iv_atm_*` globals are the
exception, and they are why the atmosphere's are globals at all: they carry the user's
Atmosphere Quality (*Atmospheres* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)), whose
Reduced tier runs a shorter rule out of the same packed table. **That is a tier change no
shader pays a compile for** -- the source is one program either way, which is what let the
setting be a live one rather than a restart.

Verified 2026-09-03 by screenshot A/B on both renderers over 17 staged views -- Earth (zoom,
45 deg, top, backlit crescent), Venus (zoom, 45 deg, backlit), Titan, Mars, the Sun, Jupiter,
Saturn, Uranus, Neptune -- with a repeat capture in each run to establish the noise floor. Every
view matched the reference within that floor; the residual pixels were orbit lines and body
symbols moving with the sub-second timing jitter between runs, not the limb or the crescent.
Forward+ was bit-identical on most views. The `atm_disc` finite guard, which is documented as
sensitive to the surrounding compilation, produced no new artefact at grazing incidence.

`_photometry.gdshaderinc`'s limb kernel took the same treatment on 2026-09-04: `LIMB_KERNEL_CELLS`
is now `uniform int limb_kernel_cells`, never set. Its loops are the shape that unrolls badly --
sixteen cells each inlining `limb_cell_light()`, an `asin` and several trig calls -- and the five
shell shaders and `body_psf` reach them.

**This one is not measured.** What bounds it is `body_psf` at 1.08 s while unrolling the sky-side
kernel at two call sites, which puts one unroll well under half a second there; the shell shaders
unroll the surface kernel once each but inside a far larger body, where the optimizer's
superlinear cost may make the same loop dearer. Expect tenths of a second per shader rather than
the atmosphere's twenty, and about five times that on a weak GPU. Renders were spot-checked at
Earth and Jupiter rather than A/B'd -- the loop runs the same sixteen iterations either way, so
only float reassociation could move a pixel.


## Specializations

The per-shader figure is not one program. Read from `drivers/gles3/shader_gles3.cpp` in the
4.7.2 source:

- **First bind compiles five programs.** `_initialize_version()` compiles all four variants of
  the scene shader (`mode_color`, `mode_color_instancing`, `mode_depth`, `mode_depth_instancing`)
  at the default specialization mask, and then `_version_bind_shader()` compiles the
  specialization actually requested, which practically always differs from the default (the
  default has every light type enabled). Nothing in the engine avoids this.
- **Every further specialization is a full compile.** The mask is set per draw from the lights
  reaching the instance, the reflection probes, the lightmap, and the pass. An instance is drawn
  `MAX(1, positional light passes + directional_shadow_count)` times, so the base pass is fused
  with the first shadowed directional light and each further one adds a pass of its own.
  `RENDER_SHADOWS` is a separate depth-pass specialization, taken by anything carrying
  `IVGlobal.LOCAL_SHADOW_CASTER`.
- **The base pass does not read the instance's layer mask.** It reads the instance's omni, spot
  and area caches, its reflection probes and its lightmap, and it sets `DISABLE_LIGHT_DIRECTIONAL`
  from `directional_light_count == directional_shadow_count` -- a fact about the frame, not about
  the instance. The layer mask enters through the additive branch alone, where a light whose cull
  mask misses the instance *clears* `USE_ADDITIVE_LIGHTING` while leaving the PSSM and PCF bits
  set: a different program, not a cheaper one. That is the whole reason one shader compiles a
  different program per size domain.
- **Compile is synchronous.** `glLinkProgram` is followed at once by the `GL_LINK_STATUS` query;
  there is no use of `KHR_parallel_shader_compile`, and the queue-and-use-defaults branch is an
  `if (false)` TODO. Nothing short of an engine patch changes that.


## The light configuration

What a lit shell shader compiles, per Compatibility light set:

| `apply_gl_compatibility_shadows` | color programs | depth programs | what a first visit can still pay |
|---|---|---|---|
| `true` (default) | 3 | +1 (`RENDER_SHADOWS`) | 1 -- the middle domain, which the default `warm_radii` never takes |
| `false` (single-light fallback) | 1 | 0 | nothing |

With shadows on, `dynamic_lights.tsv` gives Compatibility the far sun light (unshadowed, cull
`0b0001`) plus the shadowed middle (`0b0010`) and near (`0b0100`) lights, so
`directional_shadow_count` is 2 and every lit instance is drawn twice. A shell shader draws in the
two larger size domains, and across them the additive clearing above yields three distinct color
programs; anything close enough to count as "terrain" adds the shadow depth pass.

With shadows off there is one unshadowed light, `directional_shadow_count` is 0, and so
`uses_additive_lighting` is false: one pass, no additive, PSSM or PCF bits, and no shadow pass at
all. Nothing per-instance is left in the mask, so **every lit body in every size domain binds the
same program** -- and a first visit can no longer reach a specialization the quads missed.

The saving is two of the table's "+1 specialization" columns per lit shader plus a depth program,
wherever they were being paid: partly in the start sequence, partly in the opening view's first
frame, partly in the warm-up. *A slower machine* remeasures that GPU's whole cold start after this
landed alongside three other changes -- the warm-up's shader selection, the photosphere
consolidation and the limb kernel's bound -- so the drop from about 200 s to about 120 s is their
sum. Two effects are this change's alone, nothing else being able to produce them: the warm-up
falls from 82 s to 1.5 s, and the residual after the boot screen disappears. The `surface` frame
that section used to report at 35 s -- "the few specializations two layers select rather than a
single program", and a frame longer than Chrome's 30-second GPU watchdog, though no one program in
it was (*The web export*) -- is a single program under the fallback, and out of this measurement's
reach entirely.

Two side effects, neither about compiling. `update_directional_shadow_atlas()` runs only under
`if (r_directional_shadow_count)`, so with no shadowed light the 4096² depth atlas is never
allocated. And IVGraphicsManager skips `directional_shadow_atlas_set_size()` on this path, which
is safe precisely because that allocation is lazy: the project setting behind it is read into
`LightStorage` at construction, long before any GDScript runs, but nothing is committed until a
directional shadow is actually rendered.

What the fallback costs is local shadow maps -- spacecraft self-shadowing, and crater walls
shadowing a lander. The analytic astronomical shadows (rings, eclipses, transits, and the
camera-fraction dimming that carries them onto craft) are independent and work either way.

### `directional_shadow_count` stops being a constant

Everything above assumes that count is fixed for a session. `IVCoreSettings.apply_empty_shadow_pass_skip`
(opt-in; *Local shadow maps* in [VISUAL_MODEL.md](VISUAL_MODEL.md)) breaks that assumption: a
shadowed light clears `shadow_enabled` while nothing in its reach would draw into its map or read
it, so with shadows on the count takes **2, 1 or 0** instead of a constant 2. It is a fact about
the frame, not about the instance, so each distinct value is its own program set for **every lit
shader** -- compiled synchronously, on the main thread, on the first frame that reaches it. A
warm-up can only ever cover the configuration it is run in. **That, not frame time, is why the
skip is opt-in**, and why a Compatibility project should weigh it: it moves compile work from "all
of it under the boot screen" to "some of it in flight". The relief it buys is a Forward+ effect
(27-30 ms an iGPU frame; *Addendum: the empty shadow passes* in
[GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)) and the risk here is a Compatibility one.

Four things hold it down. The setting is off by default. A project on the single-light fallback has
no shadowed lights, so it is inert there -- which is the [Planetarium](https://github.com/ivoyager/planetarium)'s
case on the web, and why that project can turn it on. Flips are made rare rather than merely
correct: on is immediate, off waits 120 frames, and the enable and disable thresholds sit at 1.25
and 2.0 times the reach. And the warm-up declares its own quads (below) so that it still compiles
the count the app runs. Where a project measures the stalls anyway, the lever is to couple the two
shadowed lights into one decision, taking the reachable counts from three to two at the cost of
the receiver half of the predicate.

The Shadow Resolution option's Off (`IVDynamicLight.shadow_maps_enabled`) is the one other way
the count moves: it holds the count at 0 until a resolution is chosen again. That is a user action
rather than a camera move, and the warm-up covers whichever state the session starts in.

Under the skip, the lazy atlas allocation above is paid once, not per flip. Read from
`light_storage.cpp` in the 4.7.2 source, for both renderers: nothing frees the depth atlas when
the count returns to zero. Only `directional_shadow_atlas_set_size()` with a different size frees
it, and the next directional shadow drawn allocates it again at that size, so a flip reuses the
atlas it left and a session pays one allocation per size it uses. Under the shadowed stack that
first allocation lands at startup, craft or no craft, because the table starts both maps live and
the skip retires them only after its delay.

That is why Off also shrinks the atlas. Holding the count at 0 alone would keep whatever an earlier
resolution allocated until a restart, so IVGraphicsManager also sets the size to 256 -- the minimum
of the engine's own project setting, and a size no option uses -- which frees any atlas and
allocates nothing while no map is drawn. Measured on Forward+ on the GTX 1650 Ti: texture memory
falls by 64 MiB when 4096 goes Off and by 16 MiB from 2048, and nothing is allocated at 256. Not 0,
which the engine passes only at teardown: a shadowed directional light drawn at size 0 would have
no atlas framebuffer to render into, and the Compatibility renderer divides by that size.


## The warm-up

`IVShaderWarmup` (`program/shader_warmup.gd`) draws spatial shaders on a small quad in front of
the camera, one shader per frame, once at a planet-scale layer and once at a craft-scale layer
carrying the shadow-caster bit; between them those reach the base, additive and shadow
specializations bodies use. It is opt-in: add it to `IVCoreInitializer.program_nodes` from a
preinitializer. Its `progress_changed` signal is emitted one frame before the draw that stalls,
so the text a handler sets is the text that stays on screen through the stall, and the screen
covering it should wait for `finished` rather than `simulator_started`.

**Which shaders, and why not all of them.** It warmed every spatial `Shader` in
`IVGlobal.resources` until 2026-09-04, which compiles whatever the project does not draw. The
shell shaders are where that costs real time, and they are also the ones that can be selected
*exactly*: `IVAssetPreloader` resolves each body's shell spec at load -- including the swap to a
cubemap variant, so the spec names the shader that will really be bound -- and the warm-up reads
those specs. The scene tree cannot answer the same question, because a body's visual is built
lazily on the camera's first visit, which is the stall being warmed against. The rest of Core's
shaders are added on the conditions `IVBodyFinisher` and `IVSBGFinisher` apply when they add the
node that binds one: a body with rings, a body with an orbit, `IVBodyPSF.is_applicable_to_any_body()`,
a `small_bodies_groups` row not flagged `skip` (and its `lp_integer` for the Lagrange variant),
and `IVFragmentIdentifier` in `IVGlobal.program` for the three id overlays -- which it is not
under Compatibility, where it erases itself.

A shader that no such condition can decide is deliberately **not** warmed, and `stars_shader` is
the one Core shader in that position: `IVStarsVisual` is a scene node, so nothing in the tables
says whether the project kept it. Under the default trigger that costs nothing anyway -- the star
field is in the opening view, so it has compiled before this node runs. Set
`extra_shader_names` (keys in `IVGlobal.resources`) for it, and for a project's own shaders;
`warm_core_shaders = false` turns the automatic selection off entirely.

In the Planetarium this selects **14 shaders** where the sweep took 16, and the two it drops are
`cloud_shell_shader` and `stars_shader`. `cloud_shell_shader` is the one the project genuinely
never draws: only `PLANET_EARTH_CLOUDS` and `PLANET_NEPTUNE_CLOUDS` name it, both bodies ship
cubemap decks, and unlike a surface a cloud shell cannot arise with no channels at all. Against
the table above that is 3.5 s plus a further specialization, so roughly 5 s of the 11 s warm-up
line below -- inferred from those figures, not separately measured. Note that `surface_shader`
is *not* in that category and never was: a shell with no channels keeps the table-named shader,
and 29 of ~190 bodies have a cubemap, so the plain `surface.gdshader` is what every
fallback-coloured moon draws.

Its `trigger` picks the moment, and the two cases differ in what they can reach:

- **`SIMULATOR_STARTED`** (the default, and what the Planetarium uses behind its boot screen).
  The system tree exists, so the quads draw in the real scene and compile the specializations
  bodies actually use. It cannot usefully run earlier: `IVCamera` does not process until the
  simulator starts, so until then it sits at Godot's default range at a heliocentric float32
  position, where a quad a metre in front of it rounds to nothing.
- **`ASSETS_PRELOADED`**, for a project with a splash screen and `wait_for_start = true`, which
  is where such a project waits for the user and where `IVAssetPreloader` does its own work.
  There is no system tree yet, so the warm-up adds its own camera and one unshadowed directional
  light. That reaches the scene-independent part of each shader -- the four variants at the
  default specialization mask, over half of what a first draw costs -- while the specializations
  the scene itself selects still compile when a body is first drawn. Gate the splash screen's
  start button on `finished` and even that residual stays off the user's flight.

A project that wants the moment itself uses `MANUAL` and calls `warm_up()`.

**What the two radii buy.** `warm_radii` defaults to a planet-scale and a craft-scale radius,
which resolve to layers `0b0001` and `0b0100`, the second carrying the shadow-caster bit. Under
the shadowed stack the second radius earns its place through the shadow-caster bit, which is the
only way to reach the `RENDER_SHADOWS` depth program; its *color* program is one no body binds,
since a craft-scale body draws a packed model's engine material rather than a shell shader. Under
the single-light fallback both radii select the same program, so the second quad costs a frame
rather than a compile.

Neither radius lands in the middle domain (`0b0010`, 0.1-100 km), so with shadows on the middle
light's additive specialization is never warmed and is paid on the first visit to a small moon.
That is a real gap in the coverage -- closable by adding a radius between the two -- but it does
not explain the residual stalls below: Titan and Mars are both `0b0001` bodies. The gap is worth
more attention once `apply_empty_shadow_pass_skip` is on, since the middle light is then the one
most likely to flip.

The quads are also the reason the warm-up declares itself to that skip. They are not bodies, so
nothing registers them with it; a light whose size domain they leave empty would switch its map
off partway through and the remaining shaders would compile a shadowed-light count the app never
runs -- a silent loss of coverage, not an error. `IVShaderWarmup` therefore registers the camera
its quads hang from through `IVDynamicLight.add_local_shadow_geometry()`,
with every domain bit and the caster bit, and removes it with the quads. Warming *all* the
reachable counts instead is not the answer: the warm-up cannot know which ones a session will
reach, that depends on the project's scene and the user's camera, and it would multiply a phase
that already costs 11 s here to pre-pay stalls most projects never take.

What a cold start costs on this GPU under the default trigger, both caches emptied (2026-09-03):

| phase | time | what compiles |
|---|---|---|
| start sequence, before the camera's first processed frame | 19 s | the base specialization of the body shaders: those frames still issue draws, at float32 garbage positions since the origin has not been shifted, and whatever they bind compiles |
| the first processed frame | 7 s | what the opening view actually needs |
| the warm-up | 11 s | the additive and shadow specializations, and the shaders nothing in view uses |
| engine shaders during the build | 1.4 s | canvas, sky, blit |

About 38 s under the boot screen. After it, flying to Earth, Venus, Titan, the Sun, Jupiter,
Saturn, Phobos and Neptune in turn produced two hitches, 0.4 s at Jupiter and 1.3 s at
Neptune, against a run of multi-second stalls before; whether those two are a specialization
the quads do not reach or a texture's first upload is not yet known. Engine materials on
spacecraft models are not in the registry and still compile on first sight; they are cheap. A
run whose programs the driver has cached passes through the warm-up in a frame per shader,
about a second in all.


## A slower machine

A laptop GTX 1650 Ti (Godot 4.7.2, driver 581.95), remeasured 2026-09-04 against the current code
with every shader source made novel so neither cache could answer:

**About 120 s under the boot screen, against the fast GPU's 38 s** -- 82 s of it in the single
start-sequence frame, 22 s in the opening view's first frame, and 1.5 s in the warm-up. The same
run with the driver's cache warm reaches the end of the boot screen in **14 s**, so compiling
costs this machine about 105 s and everything else about 14 s. Forward+, equally cold, clears it
in **20 s**.

**Nothing stalls after the boot screen.** The ten-body tour -- Earth, Venus, Titan, Mars, the Sun,
Jupiter, Saturn, Phobos, Uranus, Neptune -- produced no frame over 100 ms, where the shadowed
light stack had cost 12 s at Titan and 5 s at Mars.

That, and the warm-up's collapse from 82 s to 1.5 s, is the single-light fallback doing what *The
light configuration* says it does: one program per lit shader means the opening view compiles the
whole set, and the quads that follow find nothing left. The warm-up still earns its place -- it is
what guarantees a shader nothing in view binds is drawn under the screen rather than in flight --
but on this configuration it is no longer where the time goes.

**Per shader, from the harness** (`addons/tools/time_shader_compiles.py`, one process each, same
day). This is where the two machines stop agreeing about which shader is expensive:
`atmosphere_limb` costs **6 s**, while `surface`, `surface.cube`, `cloud_shell`,
`cloud_shell.cube` and `band_pattern` cost **27-32 s each** -- four to five times the shader that
leads on the RX 7900 XTX, where all six sat within 3.5-3.9 s of one another. Everything else is
under 2 s. Whatever the AMD compiler does cheaply with a shell shader's body, this one does not,
so *What it costs* cannot be read as a ranking that holds anywhere but where it was taken.

That figure is five programs rather than one (*Specializations*), and the harness times a single
program directly in its second column: **about 5 s** for each of those five shaders, against
1.4-1.6 s on the fast GPU. One program is therefore well inside Chrome's 30-second GPU watchdog on
this part -- but through native GL, on a discrete GPU. A browser on Windows compiles through
ANGLE's D3D11 path, a third compiler again, which on an Intel iGPU multiplied the limb shader about
17x and on this GPU put one limb program past a minute, until *The atmosphere's structure* took it
under 2 s (*The web export*).

Two consequences worth carrying:

- **The in-app measurement no longer isolates a single program.** With the warm-up compiling
  nothing, the smallest unit it can time is a frame holding many shaders. Per-program figures come
  only from the harness now.
- **Most of the old warm-cache baseline was the shadow atlas, not compiling.** Before the
  fallback, the opening view's first frame cost 8-9 s whether the shaders were novel or cached;
  with no shadowed light the 4096² depth atlas is never allocated, and that frame is 1.2 s warm.
  The warm baseline fell from 26 s to 14 s with it.


## What an edit costs

Editing a file invalidates every shader that `#include`s it, so its cost is the sum over that
set, at the "after" figures:

| edited file | shaders hit | Compatibility |
|---|---|---|
| `_atmosphere.gdshaderinc` | 6 | **22 s** (was 88 s) |
| `_sun_occlusion.gdshaderinc` | 7 | **23 s** (was 88 s) |
| `_photometry.gdshaderinc` | 7 | **20 s** (was 63 s) |
| `body_psf.gdshader` | 1 | **1.1 s** |

`_display`, `_farwarp` and `_point_spread_function` reach nearly every shader in the plugin, so
editing one of those costs roughly the whole 25 s; `_detail.gdshaderinc` reaches seven and costs
about 24 s. With the warm-up in place the whole of that is paid on the loading screen of the
next Compatibility run.


## Where the caches are

Two of them, stacked, and you have to know about both to reason about a slow run.

**Godot's** is per-project and keyed on the GLSL that Godot *generates*. Its location depends on
how you launch:

- an editor run (F5) writes `<project>/.godot/shader_cache`
- a standalone run (`--path`, or an exported build) writes
  `%APPDATA%/Godot/app_userdata/<project name>/shader_cache`

These do not share entries. Clearing the wrong one measures nothing. **The web build has no
Godot cache at all**: `_load_from_cache()` and `_save_to_cache()` are compiled out under
`WEB_ENABLED`, because WebGL has no program-binary API.

**The GL driver keeps its own program cache underneath Godot's.** Deleting Godot's cache while
the shader source is unchanged still returns in well under a second, because the driver answers
from its own. Only a genuinely novel source misses both -- which is exactly what a real edit is.


## The web export

The web export is GLES3, and a first-time visitor arrives with neither cache; on the web there
is only the browser's. Chrome keeps a GPU shader disk cache, so a repeat visitor on the same
browser profile compiles nothing until the site's shaders change -- the "first run after an
update" the boot screen speaks of. Firefox may not; measure before promising.

Chrome's GPU process has a watchdog that kills the process, and with it every WebGL context, when
its main thread spends too long in one task: 30 s on Windows, 25 s on macOS and 15 s elsewhere
(`kGpuWatchdogTimeout` in Chromium's `gpu/ipc/common/gpu_watchdog_timeout.h`), and on Windows up
to four such periods when the thread was waiting rather than working
(`kMaxCountOfMoreGpuThreadTimeAllowed`, `gpu_watchdog_thread.h`). Godot queries each program's link
status as soon as it links (*Specializations*), so the figure to hold against that limit is one
program's compile, not a frame's. Through native GL on this GPU the worst single program is under
4 s. But this GPU is a fast discrete part, the in-app method can no longer isolate one program (*A
slower machine*), and a browser on Windows does not compile through native GL at all, so the
harness is what has to answer.

**A weak part, through both compilers.** Measured 2026-09-10 on the Intel UHD iGPU of the laptop
[GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md) uses, one shader per process, both caches
bypassed. Chrome on Windows compiles through ANGLE and D3D11, so the app was run through Godot's
own ANGLE build as well as native GL. Through ANGLE it had not drawn its first frame after 8.5
minutes of CPU spent compiling.

| Shader | Intel GL, first draw | +1 variant | Intel ANGLE / D3D11, first draw | +1 variant |
|---|---:|---:|---:|---:|
| `stars` | 0.4 s | 0.1 s | 0.5 s | 0.1 s |
| `body_psf` | 0.8 s | 0.2 s | 1.1 s | 0.2 s |
| `rings` | 1.3 s | 0.3 s | 4.6 s | 0.5 s |
| `surface.cube` | 9.5 s | 2.0 s | 69.1 s | 13.4 s |
| `atmosphere_limb` | 16.5 s | 3.7 s | 282.5 s | 50.2 s |
| `atmosphere_limb`, 4-node variant | 17.4 s | 4.0 s | 313.9 s | 82.3 s |

"First draw" includes the engine's four default variants plus the one drawn; "+1 variant" is one
more specialization. Reproduce either column with `--driver`; see *How to measure it again*,
which also covers reaching the iGPU rather than the discrete part.

**Through ANGLE the limb shader is a first-visit hazard, not a delay.** It takes 283 s to reach
its first draw and 50 s for every further variant, about 17x its native-GL time, and
`surface.cube` takes 69 s. One limb program alone outlasts the 30 s watchdog, so a first visit in
Chrome, on Windows, on an iGPU like this one probably cannot finish compiling it at all;
`surface.cube`, at about 13 s a program here, is merely minutes of unresponsive page. A tier that
leaves the atmosphere's quadrature out is then the only one sure to load -- out of the limb shader,
and, by *The v0.2.1 dev build* below, out of the disc shaders' `atm_disc_air()` as well -- which
is why atmosphere quality earns a restart option rather than a runtime one (*A possible option
set* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)).

**That was the include before *The atmosphere's structure*, below.** On this same part through
ANGLE the rebuilt limb shader reaches its first draw in 10.9 s and `surface.cube` in 22.9 s, five
programs each, and a further variant of either takes 3.6 s at most. The hazard is now a delay,
and a tier without the quadrature is what would shorten a first visit rather than what lets one
load at all.

**Code volume is what compiles, not iteration count.** The 4-node atmosphere variant compiles no
faster than the shipped shader, and by this measurement slightly slower, because its loop bounds
are already opaque uniforms -- the node count never reaches the compiler (*Don't hand-unroll, and
don't fear a `while`*). A tier that has to pay less at first load must therefore leave code out,
not run fewer iterations of it.

**The browser itself has still not been timed.** Nothing in this toolchain runs in one.
`--driver opengl3_angle` gets as close as a desktop run can -- the same ANGLE and D3D11 path, out
of the libraries Godot ships -- but Godot's ANGLE build is not Chrome's and its compile flags may
differ; Firefox is a third path again. The browser-shaped data points are all bad ones: the
Claude desktop app's embedded Chromium had not finished compiling the opaque-bound limb shader
after 14 minutes, against 1.8 s for a trivial shader, with no watchdog and an unidentifiable GL
backend; and the dev build below never loads. Do not load the export in that embedded browser at
all -- it shares a renderer and a GPU process with the app's own UI, which freezes with it. Measure
an actual load in real Chrome and Firefox, on a weak machine, before trusting any number here for
the web -- and before releasing on the strength of one.

### The v0.2.1 dev build

**The hazard, realised.** The v0.2.1.dev1 web export, deployed 2026-09-27, never passes its boot
screen, where v0.2 loads after Chrome's page-unresponsive prompt. In the embedded Chromium above it
logged `Loaded assets` and then held its GPU process at a full core for 14 minutes, the page's
renderer idle -- a program compiling, not a script looping -- until the process was killed. It
never reaches the warm-up: the opening view (`VIEW_HOME`, Earth at three radii) draws
`surface.cube`, `cloud_shell.cube` and `atmosphere_limb` in its first frames.

Measured the same day through `--driver opengl3_angle` on the GTX 1650 Ti, one shader per process
but eight to twelve processes at a time, so every absolute figure carries contention and the ratios
are the finding. v0.2 was tagged on 2026-08-01, before physical light and the single-scattering
atmosphere:

| Shader | v0.2, first draw | +1 variant | now, first draw | +1 variant |
|---|---:|---:|---:|---:|
| `atmosphere_limb` | 5.3 s | 0.1 s | 479 s | 167 s |
| `surface.cube` | 10.5 s | 0.5 s | 239 s | 46 s |
| `cloud_shell.cube` | 9.8 s | 0.6 s | 209 s | 49 s |
| `surface` | | | 213 s | 45 s |
| `cloud_shell` | | | 204 s | 47 s |
| `band_pattern` | | | 229 s | 36 s |

Those six are the shaders that include `_atmosphere.gdshaderinc`. Every other spatial shader
stays under 14 s a first draw and 1.5 s a variant even so (`rings` 13.6 s, `photosphere` 6.5 s,
`body_psf` 3.1 s, the path and id shaders about 1 s).

**Under that contention each of the six had a program past the 30 s watchdog; alone, only the
limb shader does.** Timed again one process at a time (*The atmosphere's structure*), a limb
program took 74 s and a disc shader's 16 to 24 s -- inside the watchdog, by less than a factor of
two, which a CPU half as fast as this laptop's i7-10875H would use up.

**What FXC chokes on is the disc quadrature, and it is volume rather than any one construct.**
`surface.cube` with one piece cut out at a time, same conditions:

| `surface.cube`, through ANGLE | first draw | +1 variant |
|---|---:|---:|
| as shipped | 239 s | 46 s |
| loop bounds constant again | 230 s | 48 s |
| no `isnan()` in `atm_disc()`'s finite guard | 256 s | 35 s |
| no far half-ray in `atm_disc()` | 116 s | 12 s |
| haze column without its top | 96 s | 12 s |
| detached layer compiled out | 72 s | 7.7 s |
| no `atm_disc_air()` | 21 s | 1.8 s |
| no atmosphere call at all | 14 s | 0.7 s |
| textures alone | 11 s | 0.4 s |

- **The opaque loop bounds are a native-GL lever only.** Under FXC a constant and a uniform
  bound compile alike, so restoring constants on the web would buy nothing.
- **Nor is it `isnan()`.** ANGLE compiles a shader that calls it with
  `D3DCOMPILE_IEEE_STRICTNESS`, but taking it out left the first draw where it was. Otherwise its
  D3D11 backend compiles every shader at `D3DCOMPILE_OPTIMIZATION_LEVEL2`, retrying with
  validation and then optimization skipped only when a compile fails
  (`Renderer11::compileToExecutable`), so nothing a page does can ask for a cheaper compile.
- **It was how many times the columns were inlined.** FXC inlines every call. `atm_disc()`
  reached the exponential column about ten times, and each could inline up to fourteen Chapman
  columns through the haze's branches -- on the order of 140 copies before optimization started.
  Removing any one large piece halved the time or better, as an optimizer superlinear in body
  size would, and no one piece was the culprit. The limb shader carried `atm_disc()` and the
  ring's two half-rays both, which is why it was the worst.

**So a fix had to shrink what FXC sees**: evaluate each column once per loop iteration rather
than once per call site, which keeps the model, or leave the quadrature out of the web build.
The first is done -- *The atmosphere's structure*, below. The second is not; see *TODO* in
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md).


## The atmosphere's structure

**Every heavy function now has one call site.** Rebuilt on 2026-09-27 on the finding above, that
FXC inlines every call, so a function reached from ten places is compiled ten times and the
atmosphere reached its heaviest ones from dozens. Each is now reached once, inside a loop:

- `atm_exp_columns()` evaluates an exponential column's terms in a loop, so a call site carries
  one Chapman function where the haze's branches wrote out up to seven slants.
- `atm_ray_path()` integrates a whole view ray as one loop over four segments, so one quadrature
  node, `atm_node()`, serves the lit part in front of a disc, both halves of a tangent ray and
  every thin-layer crossing. There had been four copies of it in a disc shader and eight in the
  limb shader.
- A node's view and sun columns, and the thin layer's partial columns, each come from one loop.
- `atm_receiver_light()` hands a surface or cloud shell everything it takes from the air above
  it -- the view tint, the sun transmittance, and the plane-parallel diffuse the twilight
  subtracts -- from one loop of two columns, four for a cloud deck, where three helpers had each
  evaluated their own.
- The limb shader integrates the handoff band's disc-hit ray as one more pass of the ring's tap
  loop, so it has one ray integral where it had two.

The model is untouched -- the same arithmetic, in the same order save where a loop now
accumulates a sum. The rule is in the include's header as THE STRUCTURE: a new term is a new
iteration, not a new call. It has one exception, and it is not a compiling one: under Forward+ and
Mobile only, `atm_exp_columns()` writes out the common case -- a haze with no top, Earth's,
Venus' and Mars' -- because Vulkan runs the term loop a third slower than two written-out terms,
while under Compatibility those two extra calls slow Intel's GL compiler's whole shader instead
(*Addendum: the atmosphere's structure, at runtime* in
[GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)). Compatibility, and so everything below, compiles
without it.

**What it bought.** Timed one process at a time on this laptop -- an i7-10875H, with the GTX
1650 Ti and the Intel UHD iGPU -- both caches bypassed. Each cell is seconds to the first draw,
which is five programs (*Specializations*), then for one more variant. Through ANGLE and D3D11,
which is Chrome's path on Windows:

| Shader | v0.2, GTX | before, GTX | after, GTX | before, Intel | after, Intel |
|---|---:|---:|---:|---:|---:|
| `atmosphere_limb` | 2.9 / 0.1 | 286 / 74 | 10.8 / 1.7 | 324 / 85 | 10.9 / 1.6 |
| `surface.cube` | 5.1 / 0.2 | 114 / 19 | 20.2 / 3.0 | 101 / 18 | 19.0 / 3.0 |
| `band_pattern` | | 118 / 24 | 19.5 / 4.1 | | 18.8 / 3.0 |
| `surface` | | 105 / 18 | 18.7 / 3.1 | | 16.4 / 2.6 |
| `cloud_shell.cube` | 4.9 / 0.4 | 95 / 20 | 16.3 / 3.4 | | 16.5 / 2.8 |
| `cloud_shell` | | 91 / 16 | 16.1 / 2.7 | | 16.0 / 2.7 |

Through native GL, which is what the desktop Compatibility renderer compiles with:

| Shader | before, GTX | after, GTX | before, Intel | after, Intel |
|---|---:|---:|---:|---:|
| `atmosphere_limb` | 7.3 / 1.5 | 4.9 / 0.9 | 16.4 / 3.8 | 2.8 / 0.5 |
| `surface.cube` | 31.1 / 5.0 | 8.2 / 1.2 | 9.5 / 2.1 | 5.2 / 0.9 |
| `band_pattern` | 30.1 / 5.2 | 7.3 / 1.1 | 8.5 / 1.6 | 4.0 / 0.8 |
| `surface` | 29.4 / 4.9 | 6.9 / 1.0 | 8.9 / 1.7 | 4.1 / 0.8 |
| `cloud_shell.cube` | 24.7 / 3.9 | 6.4 / 1.2 | 7.8 / 1.9 | 3.4 / 0.7 |
| `cloud_shell` | 26.2 / 5.0 | 5.9 / 1.0 | 7.7 / 1.9 | 3.2 / 0.7 |

- **Through ANGLE the six now take an eighth of the time between them**: 808 s to 102 s to a
  first draw on the GTX. The limb shader is 26x faster to its first draw and 43x per variant; a
  disc shader is 5-6x faster either way.
- **The two GPUs agree through ANGLE to within 13 %**, which says most of that time is FXC's, on
  the CPU, before either driver sees the shader. So a slower CPU than this one scales every
  figure in the first table, whatever GPU it drives.
- **Native GL gains less, and differently by vendor**: 3.8x across the six through NVIDIA's
  compiler, where a disc shader gains 4x and the limb shader 1.5x; 2.6x through Intel's, where
  the limb shader gains 6x and a disc shader 2x.
- **Two compiles of the same code differ by as much as 13 %** (`surface.cube` through ANGLE on
  the GTX, the same afternoon), which is the resolution of any one comparison here. At that
  resolution the three trims kept for the Intel iGPU's frame time (*Addendum: the atmosphere's
  structure, at runtime* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)) cost no measurable
  compile time. Folding the helpers into `atm_receiver_light()` took 9 to 23 % off every disc
  shader through ANGLE on both GPUs, ten measurements the same way.

**What it did not change, which is the picture.** Measured two ways, against the include as it
was:

- *Numerically*, by evaluating the include's entry points -- `atm_disc_air()` on surface and
  cloud shells, `atm_limb()`, and the per-fragment helpers -- over a grid of 262,144 geometries
  (four camera distances, sixteen phase angles, eight rolls, impact parameters packed toward the
  silhouette) for Earth, Venus, Mars and Titan at the Normal and Reduced tiers and with the taste
  multipliers on, each float written out as its own four bytes. The largest change anywhere is
  6.6e-6 of an image's maximum through NVIDIA's GL, 5.9e-5 through Vulkan and 1.2e-4 through
  Intel's GL, with no NaN or infinity appearing or disappearing; the unchanged include differs
  from itself by 1.3e-3 between the NVIDIA and the Intel driver. So what moves is reassociation,
  a tenth of what a change of GPU already moves.
- *On screen*, in 18 poses -- Earth, Venus, Mars and Titan each at four longitudes 90 degrees
  apart, and Earth at 1.6 and 30 radii -- with sim time frozen and the HUDs hidden: on
  Compatibility at most 1 code, which is what a second run of the same build moves; on Forward+
  one pixel of the 37 million moves 3 codes, at the pose where a same-build rerun moves one pixel
  3 codes too, and nothing else moves more than 2. Folding in the receiver's helpers, measured
  against the rebuilt include before it, moves no more than that floor: 1 code on
  Compatibility, and the same one pixel 3 codes on Forward+.

**What it costs each frame** depends on the compiler, and the four paths measured disagree; the
figures, and the reasons found, are in *Addendum: the atmosphere's structure, at runtime* in
[GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md). Through NVIDIA's GL every atmosphere view got 25
to 42 % faster, and under Forward+ every one is within 11 % of what it was. Through the Intel
iGPU's GL the atmosphere views got faster but for Earth close up, and the bodies with no
atmosphere 24 to 46 % slower; through ANGLE, the web's path, the atmosphere itself costs 1.3 to
1.5 times what it did on that iGPU.

**What is left.** Without any atmosphere call, `surface.cube` takes 7.3 s to a first draw through
ANGLE on the GTX, against 5.1 s for v0.2's whole shader, and that floor is the photometry kernel,
the point-spread function, the occlusion and four bicubic cube samples. The receiver's helpers
add 1.0 s to it, `atm_disc_air()` 9.9 s, and the two together 12.9 s -- FXC's cost still grows
faster than the code does. Every program now compiles well inside Chrome's watchdog; but a first
web visit still compiles every shader the opening view and the warm-up draw, the six above take
about 100 s of this laptop's CPU between them, and a slower CPU pays more. The tier that leaves
the quadrature out of the web build stays on the *TODO* in
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md).


## How to measure it again

`addons/tools/time_shader_compiles.py`, in the [tools](https://github.com/ivoyager/tools)
submodule, is the harness. Run it from the project directory:

```
python addons/tools/time_shader_compiles.py                  # every shader
python addons/tools/time_shader_compiles.py surface atmosphere_limb
python addons/tools/time_shader_compiles.py --renderer forward_plus
```

**To reproduce the ANGLE column**, add `--driver opengl3_angle`, which runs the Compatibility
renderer through the ANGLE and D3D11 libraries Godot ships instead of native GL. The run header
names the driver, because the driver is half of what a figure means. Reaching a *weak* GPU is the
separate step: Godot exports `NvOptimusEnablement`, so on a hybrid laptop every run lands on the
discrete part until you use an executable copy with that export cleared -- see *How this was
measured* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md). Running the flag alone gets you ANGLE
on the wrong GPU.

**To A/B an edit before making it**, copy this directory, edit the copy, and time the same shaders
from both with `--shaders-dir`. Time them one process at a time: a compile is CPU-bound, other
processes compiling at the same time can double a figure, and a pair run side by side is not
fair either, since the shorter finishes under the load and the longer then runs alone. Every
comparison in *The atmosphere's structure* was timed that way.

**The rest of that section's instruments are not in the tools submodule yet**: the entry-point
probe that writes the include's outputs as raw floats and times them, and the in-app frame and
screenshot A/Bs that swap shader files under a running Planetarium, were session scripts.

It generates a throwaway Godot project holding a copy of this directory, the hosting project's
`[shader_globals]` block, and a scene that draws one shader on a quad and reports the frame time
of its first draw and of the frame after the light is hidden. Then it runs one Godot process per
shader. The copy is made fresh every run, so there is nothing to keep in sync: it measures the
shaders as they are on disk. A sky shader cannot go on a mesh and is reported as unmeasurable
rather than skipped silently -- `starmap_background` is the one.

Why it is built that way. Each of these cost a run before the harness existed:

- **One shader per process.** In a sequence the AMD driver leaks work from earlier compiles into
  later first-draw frames: `photosphere` read 9.7 s after three limb compiles and 1.07 s alone,
  and the 10.6 s this document used to carry for it was that artefact.
- **A comment does not invalidate anything.** Godot hashes the GLSL it generates and the parser
  drops comments, so appending `// bust` changes the file on disk and nothing downstream. The
  harness appends a uniquely named uniform instead, which is why a rerun is a real compile and
  not a cache hit.
- **Time across frames.** The material is assigned on frame N and the delta read on N+1, from
  `_process` and `Time.get_ticks_usec()`. `RenderingServer.force_draw()` is not an alternative
  from inside an `ivoyager_assistant` method: the server dispatches in `_process`, and re-entering
  the renderer there deadlocks the application. A deadlocked instance keeps holding port 29071, so
  every later run talks to the corpse; check for stray processes before believing a "no response".
- **A runtime `Shader` has no resource path**, so the relative `#include "_x.gdshaderinc"` the
  shipped files use will not resolve. The shader is loaded from a file, in a full copy of this
  directory -- which is why the whole directory is copied and not just the file under test.
- **The first shader measured is discarded.** It would also pay the probe quad's own first draw,
  so a trivial shader is drawn first.
- **The light is toggled for the specialization cost.** Hiding the directional light after a first
  draw forces one more specialization of every lit material in view, which is the second column.
  An `unshaded` shader shows almost nothing there, because the renderer pins its light bits.

Godot's `--print-fps` is enough to *find* a stall in a normal session -- it prints one line per
second, and a hang shows up as a single low-FPS second -- but not to attribute one. For a stall
inside a running Planetarium rather than a bare compile, a per-frame probe on the main scene root
that prints any frame over ~100 ms is what produced *A slower machine*'s phase numbers.
