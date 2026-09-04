# Shader Compile Cost

How long this plugin's shaders take the GPU driver to compile and link, which renderer that
hurts on, what drives it, what was done about it, and what an edit to a given file costs. It is
here because the answer is counter-intuitive in both directions: the cost does not track how
long a shader is, and the file you would guess is expensive is not.

Measured 2026-09-02 and 2026-09-03 in the Planetarium against Godot 4.7.2 on an AMD RX 7900 XTX
(driver 32.0.12033). Numbers are one machine's -- treat the *ordering* and the *ratios* as the
finding, not the absolute seconds. A weaker GPU multiplies them by about five without changing
their order; see *A slower machine*.


## The symptom

Under the **Compatibility** renderer, a run made shortly after any shader edit starts slowly and
then drops a multi-second frame the first time the camera reaches certain bodies. It clears
after one run and stays cleared until the next shader edit.

That is not a bug in anything. GLES3 compiles a shader program **at first draw**, synchronously,
on the main thread. What the opening view draws compiles during startup; everything else
compiles the first time it is drawn, which is when you fly to a body whose shader nothing has
drawn yet. Forward+ shows the same effect an order of magnitude smaller.

Two things now stand between a first run and that experience. The expensive shaders compile
several times faster than they did (*What was done*), and `IVShaderWarmup` draws every shader
under the boot screen as soon as the simulator starts (*The warm-up*), so what remains is paid
under a progress message rather than in flight.


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
`rings` is lit and costs 0.55 s. Nor is it "heavy includes" as such: `_photometry.gdshaderinc`
carries two 16-cell constant-bound loops that unroll just the same, and the two cheapest lit
shaders in the plugin include it. What matters is the *product* of trip count and what one
iteration inlines.

**The outer loop is not enough.** Making only the 8-tap ring loop's bound opaque changed nothing
(28 s). The inner quadrature and layer loops are what had to stop unrolling; the ring loop's bound
went opaque with them because its body wraps both ray halves.


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


## What was done

The trip counts in `_atmosphere.gdshaderinc` and `photosphere.gdshader` are now
`uniform int`s -- `atm_gl6_nodes`, `atm_shell_nodes`, `atm_ring_max_taps`, `spot_cell_reach` --
carrying exactly the values the constants had. Nothing sets them and nothing should: they
restate the lengths of the node tables the loops index, so any other value is wrong. What a
uniform buys is a bound the compiler cannot see, and a loop it cannot unroll. Every Godot 4 GL
target is GLSL ES 3.0 or WebGL 2, where a dynamic trip count is ordinary; the "constant bound
so every target copes" caution the ring loop used to carry was a WebGL 1 concern.

Verified 2026-09-03 by screenshot A/B on both renderers over 17 staged views -- Earth (zoom,
45 deg, top, backlit crescent), Venus (zoom, 45 deg, backlit), Titan, Mars, the Sun, Jupiter,
Saturn, Uranus, Neptune -- with a repeat capture in each run to establish the noise floor. Every
view matched the reference within that floor; the residual pixels were orbit lines and body
symbols moving with the sub-second timing jitter between runs, not the limb or the crescent.
Forward+ was bit-identical on most views. The `atm_disc` finite guard, which is documented as
sensitive to the surrounding compilation, produced no new artefact at grazing incidence.


## Specializations

The per-shader figure is not one program. Read from `drivers/gles3/shader_gles3.cpp` in the
4.7.2 source:

- **First bind compiles five programs.** `_initialize_version()` compiles all four variants of
  the scene shader (`mode_color`, `mode_color_instancing`, `mode_depth`, `mode_depth_instancing`)
  at the default specialization mask, and then `_version_bind_shader()` compiles the
  specialization actually requested, which practically always differs from the default (the
  default has every light type enabled). Nothing in the engine avoids this.
- **Every further specialization is a full compile.** The mask is set per draw from the lights
  reaching the instance, the reflection probes, the lightmap, and the pass: base pass; one
  additive pass per shadowed directional light, with `USE_ADDITIVE_LIGHTING` cleared when the
  light's cull mask misses the instance's layer but the PSSM and PCF bits still set; and the
  shadow-map depth pass (`RENDER_SHADOWS`) for anything carrying `IVGlobal.LOCAL_SHADOW_CASTER`.
  Under the Compatibility light set IVDynamicLight builds -- the far sun light plus the shadowed
  middle and near lights -- a lit body shader therefore compiles three color programs across the
  size layers, plus the shadow pass once the camera is close enough for the body to be "terrain",
  each at the "+1 specialization" cost in the table.
- **Compile is synchronous.** `glLinkProgram` is followed at once by the `GL_LINK_STATUS` query;
  there is no use of `KHR_parallel_shader_compile`, and the queue-and-use-defaults branch is an
  `if (false)` TODO. Nothing short of an engine patch changes that.


## The warm-up

`IVShaderWarmup` (`program/shader_warmup.gd`) draws every spatial shader in `IVGlobal.resources`
on a small quad in front of the camera, one shader per frame, once at a planet-scale layer and
once at a craft-scale layer carrying the shadow-caster bit; between them those reach the base,
additive and shadow specializations bodies use. It is opt-in: add it to
`IVCoreInitializer.program_nodes` from a preinitializer. Its `progress_changed` signal is
emitted one frame before the draw that stalls, so the text a handler sets is the text that stays
on screen through the stall, and the screen covering it should wait for `finished` rather than
`simulator_started`.

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

The same cold start on a laptop GTX 1650 Ti (Godot 4.7.2, driver 581.95, Compatibility), measured
2026-09-03 with every shader source made novel so neither cache could answer:

**About 200 s under the boot screen, against 38 s** -- 99 s of it in the single start-sequence
frame, and 82 s in the warm-up. Nothing reorders: the same shaders dominate, at tens of seconds
each where the RX 7900 XTX pays seconds.

The honest denominator is the same run with the driver's cache warm, which reaches the end of the
boot screen in **26 s** and passes the warm-up in 4.4 s. Compiling therefore costs this machine
about 170 s and everything else about 26 s -- and the *first processed frame* line in the table
above is not compile cost here at all: that frame ran 8-9 s whether the shaders were novel or
cached.

Two things do not simply scale:

- **One shader's warm-up frame reached 35 s** (`surface`; `cloud_shell` 28 s). That frame covers
  the few specializations two layers select rather than a single program, so no one program is
  measured at 35 s -- but several seconds each is what it implies, and that is not comfortably
  clear of the ten-second Chrome GPU watchdog (*The web export*). The weak GPU is where that risk
  lives.
- **The residual after the warm-up is a freeze rather than a blip.** Flying the same tour, Titan
  stalled 12 s and then 4 s and Mars 5 s, the other eight bodies clean, against 0.4 s and 1.3 s on
  the faster GPU. Whatever specialization the quads miss costs proportionally more here, and is
  worth finding.

Forward+ on the same machine, equally cold, clears the boot screen in **31 s** including its
warm-up -- a sixth of the Compatibility figure, and barely worse than a fully cached Compatibility
run. The renderer gap is not an artefact of the fast GPU.


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

Chrome's GPU process has a watchdog that kills the process, and with it the WebGL context, when
a single GPU operation runs on the order of ten seconds. The 16-26 s limb compiles of the old
code sat inside that range, which is what could make a first web visit fatal rather than slow;
the current worst single compile is under 4 s on this GPU. On a weaker one it is not, and the
margin there is thin (*A slower machine*).

**The browser has not been measured.** The harness exports to web (see below); in the Claude
desktop app's embedded Chromium the opaque-bound limb shader had not finished compiling after
14 minutes, against 1.8 s for a trivial shader, with no watchdog and an unidentifiable GL
backend. Real Chrome and Firefox on Windows go through ANGLE's D3D11 path and are a different
compiler again. Measure an actual load in each before trusting any number here for the web.


## How to measure it again

Use a scratch Godot project, outside this one, that puts a shader on a quad in front of a camera
and prints the frame time of its first draw. It needs a full copy of the shaders directory (so
the relative `#include`s resolve), a trivial shader drawn first, and a command-line or URL
option naming which shader to time, so one run measures one shader. The traps, each of which
cost a run:

- **One shader per process.** In a sequence the AMD driver leaks work from earlier compiles into
  later first-draw frames: `photosphere` read 9.7 s after three limb compiles and 1.07 s alone,
  and the 10.6 s this document used to carry for it was that artefact.
- **A comment does not invalidate anything.** Godot hashes the GLSL it generates and the parser
  drops comments, so appending `// bust` changes the file on disk and nothing downstream. Append a
  uniform, and give it a new name every run, or the driver cache answers.
- **Time across frames.** `RenderingServer.force_draw()` cannot be used from inside an
  `ivoyager_assistant` method: the server dispatches in `_process`, and re-entering the renderer
  there deadlocks the application. A helper with `_process` and `Time.get_ticks_usec()` deltas,
  assigning the material on frame N and reading the delta on N+1, is what the harness does. A
  deadlocked instance keeps holding port 29071, so every later run talks to the corpse; check for
  stray processes before believing a "no response".
- **A runtime `Shader` has no resource path**, so the relative `#include "_x.gdshaderinc"` the
  shipped files use will not resolve. Load the shader from a file, in a full copy of the shaders
  directory.
- **Discard the first shader measured.** It also pays the probe quad's own first draw; the
  harness draws a trivial shader first for that reason.
- **Toggle the light for the specialization cost.** Hiding the directional light after a first
  draw forces one more specialization of every lit material in view; the harness reports it as
  its own line. An `unshaded` shader shows nothing there, because the renderer pins its light
  bits.

Godot's `--print-fps` is enough to *find* a stall in a normal session -- it prints one line per
second, and a hang shows up as a single low-FPS second -- but not to attribute one.
