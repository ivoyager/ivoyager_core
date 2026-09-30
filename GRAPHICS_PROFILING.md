# Graphics Profiling

What this plugin's graphics cost on a weak machine, and what each graphics option and automatic
saving buys back: per frame, in GPU time, and once, in the shader compiling a first draw pays for.
It is the measured basis for the option set, the fitted defaults and what a first web visit costs,
and it holds measurements only -- the models behind them are in
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) and [VISUAL_MODEL.md](VISUAL_MODEL.md), and each
section here names the one it depends on.

**Every figure was measured in the [Planetarium](https://github.com/ivoyager/planetarium) on one
laptop** (*The reference machine*), on 2026-09-29, against Godot 4.7.2 and ivoyager_core
v0.2.1.dev (8001cf3), unless a figure gives its own date. The Planetarium's configuration is part of
what the figures describe -- its scale, its poses, and above all its light stack: one unshadowed
light under Compatibility (`apply_gl_compatibility_shadows` off) and the empty-shadow-pass skip on.
Treat the ratios and orderings as the finding and the milliseconds as this laptop's; a project
configured otherwise should measure again before it trusts a row (*How this was measured*).

**Relief** is the GPU time an option saves, as a share of that view's frame. **Visual cost** is the
change in the rendered image, in 8-bit display codes on screenshots taken before and after at one
frozen exposure.


## The short version

1. **On the Intel iGPU, air is what does not fit.** At Core's defaults in a 1080p window every view
   with an atmosphere runs at 6-16 fps through ANGLE -- the web's path, and Compatibility on any
   Intel GPU -- and at 2-7 fps under Forward+, the desktop default; every view without one runs at
   16-54. The GTX runs every view at 60 fps or better.
2. **The levers that work there:**
   - **Atmosphere quality Off** takes an atmosphere frame to 0.24-0.49 of Normal's through ANGLE and
     0.14-0.22 under Forward+; **Min** to 0.46-0.80 and 0.44-0.76. Reduced buys 8-22 % through
     ANGLE and almost nothing under Forward+.
   - **The star catalog**, through ANGLE, where every star is an emulated point sprite: V 11 takes
     45 % off a dark-sky frame.
   - **Render scale**, on a native driver: 50 % saves 33-75 %. Through ANGLE it costs instead, and
     is held at 100 %.
   - **MSAA off** saves 5-24 % everywhere.
3. **At its fitted defaults the Intel runs every view at 21-27 fps under Forward+**, Earth close up
   aside at 12, with atmospheres Off. A browser cannot tell its GPU's type and takes Off too, giving
   up the limb on a fast GPU. The GTX, fitted, runs every view at 70 fps or better.
4. **A first run through ANGLE compiles for about a minute and a half** at Min or Normal, against
   36 s through NVIDIA's GL and 7-9 s under Vulkan, nearly all of it under the boot screen; Off, a
   first web visit's tier, compiles a third less. One stall is left after it: the first spacecraft,
   11 s through ANGLE (TODO). No single program comes near Chrome's 30-second watchdog.
5. **The savings that need no option are worth as much as the options.** The exposure skips take
   15-53 % off a lit frame through ANGLE; the airless shader twins 14-23 % there and 76-83 % under
   Intel's Vulkan; the empty-shadow-pass skip 7-22 % of an Intel Forward+ frame.
6. **Glow under Forward+ costs a fifth to a half of an airless frame on both GPUs** and changes no
   pixel in most lit views (TODO).


## The reference machine

A Dell XPS 15 9500: an i7-10875H, Intel UHD Graphics (Comet Lake GT2, 24 EU, driver
31.0.101.2137) and a GTX 1650 Ti (driver 581.95), with a 3840x2400 panel at 250 % display scale,
on mains power. Godot 4.7.2. Its two GPUs give four render paths, and every visitor to the
Planetarium on a machine like it lands on one of them:

| Path | Who draws with it | Frame time from |
|---|---|---|
| **Intel, ANGLE** | Every browser on Windows, and the desktop Compatibility renderer on any Intel GPU | Frame interval (ANGLE has no GPU timestamps) |
| **Intel, Vulkan** | The desktop default, Forward+, on an integrated GPU | GPU time |
| **GTX, Vulkan** | The desktop default on a discrete GPU | GPU time |
| **GTX, GL** | The desktop Compatibility renderer on a discrete GPU | GPU time |

- **Compatibility runs through ANGLE on every Intel GPU in the Planetarium** -- one
  `{"vendor": "Intel", "name": "*"}` entry added beside Godot's own defaults in
  `rendering/gl_compatibility/force_angle_on_devices`. Godot's own list already forces ANGLE on
  Intel "HD Graphics" and Iris of Gen 7 to 9.5 by name, but not "UHD Graphics" (the same Gen 9.5
  silicon, renamed) or Iris Xe. The switch is the project's, not Core's; Core only reads the result
  (`IVGraphicsManager.is_angle_d3d11()`). Its reasons are in *Renderer*.
- **A browser here is Intel, ANGLE.** Chrome on Windows compiles WebGL through ANGLE's D3D11
  backend, and a hybrid laptop's browser runs on the integrated GPU unless told otherwise. No
  browser was measured (*Caveats*); the desktop ANGLE path is the same translation out of Godot's
  own ANGLE build.
- **Intel's own GL driver is no path at all in the Planetarium**, and is not measured here. Core
  alone does not force ANGLE, so a project that leaves Godot's defaults will run UHD and Iris Xe
  parts through it; *Renderer* says what that costs.


## Where the frame goes

GPU milliseconds per frame (the frame interval through ANGLE) at Core's defaults -- Normal
atmospheres, 100 % render scale, MSAA 2x, 4096 shadows, the whole star catalog -- in a 1920x1080
window. The budgets are 16.7 ms for 60 fps and 33.3 ms for 30.

| View | Intel, ANGLE | Intel, Vulkan | GTX, Vulkan | GTX, GL |
|---|---:|---:|---:|---:|
| Earth at 1.6 radii | 173 | 634 | 9.1 | 12.7 |
| Earth at 3 radii | 104 | 257 | 5.7 | 7.7 |
| Venus at 3 radii | 61 | 143 | 4.9 | 5.3 |
| Mars at 3 radii | 101 | 208 | 6.8 | 9.6 |
| Titan at 3 radii | 148 | 209 | 11.3 | 12.2 |
| The Moon at 3 radii | 23.2 | 25.3 | 2.3 | 1.3 |
| Jupiter's night side, dark sky | 56 | 38 | 3.9 | 2.3 |
| Saturn at 3 radii | 44 | 44 | 3.6 | 2.2 |
| The Sun at 3 radii | 27.2 | 36.6 | 3.0 | 2.1 |
| Juno close up | 18.5 | 26.8 | 2.0 | 0.9 |
| Whole system, dark sky (`VIEW_SYSTEM`) | 60 | 36 | 4.1 | 2.3 |
| Asteroid belt, 80,569 points (`VIEW_ASTEROIDS`) | 61 | 39 | 4.9 | 2.9 |

- **Air is what a weak GPU cannot afford.** Every view with an atmosphere runs at 6-16 fps through
  ANGLE and 2-7 fps under Forward+ on the Intel, where every view without one holds 16-54 fps
  (*Atmosphere quality*).
- **Stars are the rest of it through ANGLE.** The dark-sky views cost ANGLE 60 ms where the same
  Intel under Vulkan takes 36: D3D11 has no point sprites, so ANGLE emulates them, and the 2.55
  million stars cost it about four times what Intel's own GL paid for them (*Star catalog*).
- **On the GTX nothing misses 60 fps.** Its slowest views are Earth close up and Titan, at
  9-13 ms. What it must carry is a dense screen: this laptop's panel is 4.4 times a 1080p frame
  (*What the fitted defaults deliver*).

The views: each body in `tracking: "ground"` at longitude 90, latitude 10 (Earth at 1.6 radii at
longitude 45, Saturn at latitude 20), which at the frozen date shows Earth, Venus and Mars most of a
disc, Titan and the Moon a crescent and Jupiter only a thin backlit crescent against the
dark-adapted sky -- so that pose is a star-field view; Juno through `VIEW_ZOOM`; the two wide views
through their own table rows, the Asteroids view keeping the points it shows. Star bins drawn,
identical on every path: 12, 11, 8, 14, 22, 18, 24, 20, 0, 18, 24 and 24 of 24.


## What the fitted defaults deliver

What a user of this laptop gets at a plain launch: the fitted defaults (*Fitted defaults*), in the
window the Planetarium opens -- its 1152x648 at the screen's 250 % display scale, 2880x1620 -- with
the render scale fitted to the whole 3840x2400 screen. Milliseconds per frame as the frame
interval, which is what a user sees; on the GTX that is the CPU's time, the GPU's being shorter. A
browser on this laptop takes the Intel's ANGLE path at that column's settings:

| View | Intel, ANGLE | Intel, Vulkan | GTX, Vulkan | GTX, GL |
|---|---:|---:|---:|---:|
| Tier; settings | Low: Off, 100 %, MSAA off, V 11 | Low: Off, 50 %, MSAA off, V 11 | Reduced: Reduced, 70 %, 2048 | Reduced: Reduced, 70 % |
| Earth at 1.6 radii | 157 | 80 | 11.8 | 12.3 |
| Earth at 3 radii | 73 | 48 | 8.2 | 7.7 |
| Venus at 3 radii | 49 | 41 | 7.6 | 7.3 |
| Mars at 3 radii | 45 | 39 | 10.8 | 9.0 |
| Titan at 3 radii | 40 | 41 | 13.9 | 10.7 |
| The Moon at 3 radii | 40 | 37 | 6.6 | 6.6 |
| Jupiter's night side, dark sky | 48 | 43 | 8.4 | 9.2 |
| Saturn at 3 radii | 61 | 48 | 10.2 | 10.1 |
| The Sun at 3 radii | 57 | 43 | 6.1 | 6.1 |
| Juno close up | 31 | 40 | 8.6 | 8.9 |
| Whole system, dark sky | 42 | 37 | 7.3 | 6.0 |
| Asteroid belt | 43 | 38 | 7.8 | 6.1 |

- **The GTX runs everything at 70 fps or better** at its fitted tier.
- **The Intel runs every view at 21-27 fps under Forward+**, the desktop default, but Earth close up
  at 12. Its frames there are the CPU's as much as the GPU's: the GPU takes 23-34 ms of them.
- **Through ANGLE it is slower in every view but Titan and Juno**, the window drawn at full size:
  14-25 fps with air and 16-32 without, Earth close up at 6. So the Intel is better off in Forward+
  at its fitted defaults, which is what it runs unless its user chooses otherwise (*Renderer*).
- **A browser's window is its own size**; this one's is 2.25 times the pixels of the 1080p frames
  above, and render scale is held at 100 % there. At Min the same path takes the atmosphere views
  to 75-257 ms, which is why a browser, whose GPU's type is unknown, is fitted Off (*Fitted
  defaults*).


## The options

Relief at 1920x1080 against Core's defaults, as a range over the views where the option acts;
views where it does nothing are left out rather than averaged in. Every figure is an off, on, on,
off block within one session (*How this was measured*), except for a restart option, which is
compared across sessions.

| Option | Intel, ANGLE | Intel, Vulkan | GTX, Vulkan / GL | Visual cost |
|---|---|---|---|---|
| **Atmosphere quality** (air views) | Reduced -8 to -22 %; Min -20 to -54 %; Off -51 to -76 % | Reduced 0 to -16 %; Min -24 to -56 %; Off -78 to -86 % | Vulkan: Off -24 to -74 %, Reduced to -31 % and Min to -42 % away from Earth; GL: Reduced -10 to -37 %, Min -5 to -55 %, Off -37 to -86 % | Reduced: a few pixels at the limb. Min: crescent cusps and Mars' twilight. Off: no limb |
| **3D render scale** 70 % / 50 % | held at 100 % | -12 to -47 % / -33 to -75 % | Vulkan -12 to -42 % / -33 to -70 %; GL 50 %: -27 to -68 % | Softer lines and labels; at 50 % the star field coarsens |
| **Renderer**: Compatibility against Forward+ | 1.4-3.7x faster in air views, 1.5-1.7x slower in star-heavy ones | -- | GL 1.1-1.4x slower in air views, 1.5-2.2x faster in airless ones | Compatibility loses hover identification of orbits and asteroids, FXAA, TAA and local shadow maps |
| **Star catalog** V 11 / V 9.5 (star-heavy views) | -16 to -45 % / -33 to -67 % | -13 to -28 % / -22 to -41 % | Vulkan -15 to -34 % / -25 to -53 %; GL -13 to -34 % / -26 to -50 % | None in lit views; a dimmer diffuse glow at V 11 and a sparser sky at V 9.5 in dark ones |
| **Shadow resolution** (near a craft; Forward+) | -- | Off -25 %, 2048 -15 %, 8192 +96 % | Vulkan: Off -8 %, 2048 -1 %, 8192 +3 % | Spacecraft self-shadowing only |
| **MSAA** off / 4x / 8x | -8 to -20 % / +4 to +13 % / +17 to +34 % | -5 to -24 % / +3 to +20 % / +19 to +42 % | Vulkan -5 to -28 % / +6 to +10 % / +21 to +46 %; GL -7 to -17 % / +3 to +12 % | Off: stair-stepped lines and craft edges |
| **FXAA** (Forward+) | -- | 0 to +7 % | +5 to +12 % | Smoother lines, slightly softer |
| **TAA** (Forward+) | -- | +25 to +75 % | +30 to +51 % | Ghosts orbit lines |
| **Frame rate cap** | not measured | not measured | not measured | Motion only |

### Atmosphere quality

Four tiers (`atmosphere_quality`), of which the first two are one shader program and change live,
and the last two are programs of their own, bound when bodies are built, so a change into or out of
them takes a restart. What each gives up, and how, is *Atmosphere quality, and what Reduced, Min and
Off give up* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md). Each tier's frame as a share of
Normal's (the first table):

| View | Intel, ANGLE: R / Min / Off | Intel, Vulkan | GTX, Vulkan | GTX, GL |
|---|---|---|---|---|
| Earth at 1.6 radii | 0.92 / 0.80 / 0.49 | 1.01 / 0.76 / 0.14 | 0.98 / 0.80 / 0.75 | 0.90 / 0.95 / 0.63 |
| Earth at 3 radii | 0.81 / 0.64 / 0.35 | 0.94 / 0.76 / 0.17 | 1.19 / 1.13 / 0.76 | 0.79 / 0.78 / 0.39 |
| Venus at 3 radii | 0.82 / 0.65 / 0.41 | 0.84 / 0.59 / 0.22 | 0.79 / 0.82 / 0.56 | 0.63 / 0.61 / 0.35 |
| Mars at 3 radii | 0.79 / 0.46 / 0.24 | 0.95 / 0.56 / 0.14 | 0.83 / 0.80 / 0.44 | 0.78 / 0.57 / 0.18 |
| Titan at 3 radii | 0.78 / 0.54 / 0.31 | 0.93 / 0.44 / 0.15 | 0.69 / 0.58 / 0.26 | 0.70 / 0.45 / 0.14 |

An airless view costs the same in every tier, to within the noise. The GTX's Vulkan figures at
Earth are inside that path's noise (*How this was measured*), which is why Reduced and Min read
above 1.0 there.

- **Through ANGLE, Off takes every atmosphere view on the Intel to 24-85 ms**, and it is the fitted
  default on a known integrated GPU and in every browser.
- **Under Forward+ on the Intel, Reduced buys almost nothing** -- that compiler's cost is set by a
  shader's structure rather than its node count -- but Min takes a quarter to a half off, and Off
  more than four fifths, taking every atmosphere view from 2-7 fps to 11-34.
- **Reduced's visual cost is a few pixels at the limb**: at most 14 codes, over at most 1.8 % of the
  frame, at every pose measured. Min's and Off's are larger and specific -- Earth's crescent cusps
  and Mars' twilight at Min, everything beyond the limb at Off -- and are measured in
  [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md).
- **Min and Off each compile programs of their own**, which is what lets a first web visit, at Off,
  compile no quadrature at all (*What each shader costs*).

### 3D render scale

`render_scale`: 100, 85, 70 or 50 % of the window's pixels, upscaled with FSR 1 on Forward+ and
bilinear on Compatibility; the 2D GUI keeps full resolution. It saves the per-pixel share of a
frame, so least where the vertex stage or a fixed-size pass dominates -- the star field, the
asteroid points, glow:

| View | Intel, Vulkan: 70 % / 50 % | GTX, Vulkan | GTX, GL: 50 % |
|---|---|---|---|
| Earth at 1.6 radii | -47 / -75 % | -41 / -70 % | -68 % |
| Titan at 3 radii | -41 / -56 % | -34 / -57 % | -61 % |
| Saturn at 3 radii | -31 / -52 % | -27 / -47 % | -32 % |
| The Moon at 3 radii | -15 / -39 % | -17 / -42 % | -38 % |
| Whole system, dark sky | -18 / -35 % | -12 / -35 % | -32 % |

- **85 % buys nothing measurable** in the airless views (-6 to +7 %); 70 % is the first step that
  pays.
- **What it costs on screen is resolution.** Orbit lines, names and body edges soften, and the star
  field changes because each star is a render-pixel PSF magnified back up: at 50 % on the GTX, 78 %
  of a dark sky's pixels move by more than 2 codes, and 11 % of an Earth or Mars view's.
- **Both builds render at physical pixels** (`display/window/dpi/allow_hidpi`): a laptop at 2x
  renders four times the pixels of the window its layout describes, so on such a screen 50 % is the
  1x cost rather than a sacrifice. That is what the fitted defaults use it for.
- **Through ANGLE's D3D11 a reduced scale costs instead**, and the option is hidden and the scale
  held at 100 % there (`IVGraphicsManager.can_scale_render()`). Below 100 % Godot 4.7.2's GLES3
  renderer ends each frame by stretching the depth and stencil buffer into the full-size target
  (`glBlitFramebuffer` in `rasterizer_scene_gles3.cpp`); D3D11 has no stretching copy for depth and
  stencil, and ANGLE evidently does it on the CPU, adding a roughly fixed 25-40 ms to every Intel
  frame and about 20 ms to every GTX one whatever the scale (2026-09-28). The web runs the same
  renderer through the same translation. Three ways round it were weighed and none taken: patching
  the engine (custom export templates, web ones included, until upstream took it), turning off
  `allow_hidpi` for the web build (the browser would stretch the GUI too), and rendering the 3D view
  into a smaller SubViewport (moving the camera, picking, the 3D HUD and screenshots into another
  viewport for one driver's missing copy).

### Renderer

`renderer`, desktop only and at restart: Forward+ or Compatibility. Forward+ is the default
everywhere, fitted or not, because Compatibility gives up mouse-over identification of orbit lines
and asteroid points (`IVFragmentIdentifier` removes itself there), FXAA and TAA, and local shadow
maps; the picture itself matches to a few codes. `IVGraphicsManager` writes the choice to the file
the project names in `application/config/project_settings_override`, which the engine reads at the
next start, and a Forward+ run records the GPU's type there for a Compatibility run, which cannot
read it (`IVGlobal.video_adapter_type`). From the first table:

- **On the Intel, Compatibility (through ANGLE) is the faster renderer wherever there is air**,
  1.4-3.7 times, and draws the Sun and Juno faster too; Forward+ is 1.5-1.7 times faster in the
  star-heavy views, where ANGLE pays for point sprites. At Off the two draw the air in about the
  same time, and at the fitted defaults -- atmospheres Off, Forward+ at 50 % and Compatibility held
  at 100 % -- Forward+ is the faster in all but two views (*What the fitted defaults deliver*).
- **On the GTX, Forward+ is the faster renderer in atmosphere views** (Earth close up in 9.1 ms
  against 12.7) and Compatibility in airless ones, where both are far inside any budget.

**The Planetarium runs Compatibility through ANGLE on every Intel GPU** (*The reference machine*).
Measured on 2026-09-28, both drivers from one build on the UHD at 100 % render scale:

- ANGLE takes 0.62-0.85 of Intel's own GL frame at Earth, Venus and Mars and as long at Titan, and
  1.1-1.9 times as long in airless views, the star field's point sprites costing about four times as
  much through ANGLE.
- **Intel's GL driver (31.0.101.2137) does not draw Saturn's rings at all**; ANGLE draws them as
  the GTX does (TODO in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)).
- A first run compiles the atmosphere shaders through FXC in several times what Intel's GL takes
  (*What each shader costs*); ANGLE caches them after, in `shader_cache/EGL`.

### Star catalog

`star_catalog`, at restart: the whole catalog (2.55 million stars to V 15.4), 942,063 to V 11 or
216,622 to V 9.5, which `IVStarsVisual` loads as fewer magnitude bins. Each view's frame against the
whole catalog's:

| View | Intel, ANGLE: V 11 / V 9.5 | Intel, Vulkan | GTX, Vulkan | GTX, GL |
|---|---|---|---|---|
| Jupiter's night side, dark sky | 0.59 / 0.40 | 0.87 / 0.78 | 0.85 / 0.75 | 0.87 / 0.74 |
| Saturn at 3 radii | 0.84 / 0.67 | 1.03 / 0.95 | 1.09 / 1.00 | 1.05 / 0.97 |
| Whole system, dark sky | 0.56 / 0.33 | 0.74 / 0.59 | 0.66 / 0.47 | 0.68 / 0.50 |
| Asteroid belt | 0.55 / 0.35 | 0.72 / 0.60 | 0.67 / 0.54 | 0.66 / 0.52 |
| The Moon at 3 radii | 1.00 / 0.82 | 1.02 / 0.98 | 1.15 / 1.10 | 1.09 / 1.02 |
| Earth at 3 radii | 0.98 / 0.97 | 0.97 / 0.98 | 1.24 / 1.25 | 0.95 / 0.95 |

- **Through ANGLE this is the second-largest lever**, since every star is an emulated point sprite
  there. V 11 alone takes the dark-sky views from 60 to 33 ms on the Intel.
- **In a lit view it saves only what the exposure skips have not already**: at Earth the skip has
  already dropped 13 of 24 bins, and V 11's cut is among them.
- **What it costs on screen is the dark sky.** In lit-body views exposure has already buried the
  cut stars; in a dark-adapted wide view V 11 dims the diffuse glow of the faint end and V 9.5
  visibly empties the sky. It also saves memory and load time: the catalog is about 51 MB of
  vertex data whole, 19 MB to V 11 and 4 MB to V 9.5, built by single-threaded GDScript in
  0.7-1.1 s, 0.26-0.40 s and 0.07-0.10 s on this CPU.

### Shadow resolution

`shadow_resolution`: Off, 2048, 4096 or 8192, acting on Forward+ only in the Planetarium, where
the maps serve spacecraft-scale local shadows alone -- eclipses, ring shadows and transits are
analytic and unaffected. **With the empty-shadow-pass skip, the resolution matters only with a
spacecraft or a local scene in reach**: at Saturn, 8192 moved nothing. At Juno close up:

| | Off | 2048 | 8192 |
|---|---:|---:|---:|
| Intel, Vulkan | -25 % | -15 % | +96 % |
| GTX, Vulkan | -8 % | -1 % | +3 % |

The atlas is 16, 64 and 256 MiB at 2048, 4096 and 8192; Off frees it (*The light configuration*).

### MSAA

`msaa_3d`: off, 2x (Core's default), 4x or 8x. The planet rims do not need it, since the surface
shaders already image each rim pixel through the camera's PSF; what does is lines -- orbit lines,
ring edges, spacecraft. Off moves 0.02-0.2 % of a body view's pixels and 2.8 % of the Asteroids
view's (its orbits and points) by more than 2 codes. From the options table: off saves 5-28 %, and
8x adds 17-46 %, on every path.

### FXAA, TAA and Frame rate cap

**FXAA** (Forward+) is cheap line smoothing. **TAA** (Forward+) costs a quarter to three quarters
of a frame and ghosts the orbit lines, which are positioned in the vertex shader; it stays an
option for a user who wants it, off by default.

**Frame rate cap** (`frame_rate_cap`): None, 60 or 30 fps, applied live as `Engine.max_fps`; None
leaves the cap the engine started with (`application/run/max_fps` or `--max-fps`). It saves energy
when a frame beats the cap and nothing when it misses. Godot holds a cap in software -- a sleep on
the desktop, skipped animation frames in a browser -- so 30 on a 60 Hz display may not pace evenly.
Neither is measured.

**Physical Light** is not a performance option: turning it off keeps the unmetered exposure, so
every star draws at full size, and it cost up to 35 % more (2026-09-10).


## Fitted defaults

`IVSettingsManager.graphics_target`, `NONE` by default, applies Core's graphics defaults as
written. A project that sets `BROAD_HARDWARE` or `MODERN_GPU` -- the Planetarium sets the first --
has them replaced at each start by those `IVGraphicsManager.get_fitted_defaults()` gives for the
machine, and a default the project sets itself holds on every machine. Only defaults move: a user's
own choice is cached and stands, and Restore Defaults returns to the fitted values.

The tier comes from two things Godot reports before anything is drawn, the GPU's type and the
physical pixel count of the screen (`IVGraphicsManager.get_graphics_tier()`):

| | Full | Reduced | Low |
|---|---|---|---|
| Machine | Discrete GPU, screen up to 6 MP | Discrete GPU, screen past 6 MP | Any other GPU, or one of unknown type, as in every browser |
| Atmosphere quality | Normal | Reduced | Off on an integrated GPU and in a browser; on a desktop GPU of unknown type, Min through ANGLE's D3D11, else Reduced |
| 3D render scale | 100% | Largest within 4.7 MP | Largest within 2.7 MP |
| MSAA | 2x | 2x | Off |
| Shadow resolution | 4096 | 2048 | 2048 |
| Star catalog | All | All | To V 11 |

- **The renderer is not fitted.** Forward+ stays the default wherever it runs: Compatibility loses
  mouse-over identification of orbit lines and asteroids, which should be the user's trade to make,
  and at Low's defaults Forward+ is the faster renderer on this Intel anyway (*Renderer*).
  The running renderer becomes the default only where the engine fell back from Forward+ or the
  command line chose another. `MODERN_GPU` hides the option.
- **The screen stands in for the GPU's class.** Godot reports no memory size or model tier, and a
  laptop with both GPUs reports its discrete one -- this laptop's GTX among them. What makes such a
  part struggle is a dense panel: at 3840x2400 it renders 4.4 times a 1080p frame. 6 MP keeps a
  1440p or 3440x1440 desktop at Full and puts 4K and the denser laptop panels at Reduced; a fast GPU
  on a 4K monitor is rated Reduced too, and loses little by it.
- **Render scale fits a pixel budget** rather than taking a fixed step: 4.7 MP puts a 4K or
  3840x2400 screen at 70 %, and 2.7 MP keeps a 1920x1200 screen at 100 % and takes 4K to 50 %, the
  1x cost on a 2x screen. It stays at 100 % through ANGLE's D3D11 path, where any reduction costs.
- **Reduced atmospheres and 2048 shadows cost nothing visible**, so a discrete GPU on a dense screen
  takes them too.
- **Off is Low's tier on a known integrated GPU**, the only one that makes an atmosphere close-up
  usable there: under Forward+ on this Intel, Reduced buys almost nothing and Min still takes 480 ms
  at Earth close up at 1080p (*Atmosphere quality*). **A browser takes Off too**, though its GPU's
  type is always unknown: a fast GPU loses only the limb, which its user can restore in Options,
  where Min through this Intel's ANGLE takes the atmosphere views to 75-257 ms (*What the fitted
  defaults deliver*), and a first visit at Off compiles 57 s of programs against Min's 82 s (*What
  each shader costs*). **A desktop GPU of unknown type keeps the limb**, since it may be a fast one:
  Min through ANGLE, where it is the fast tier, and Reduced elsewhere, Min having run slower than
  Normal at Earth through Intel's own GL (2026-09-28).
- **MSAA off and V 11 are Low's alone**, since each changes what a user sees -- stair-stepped orbit
  lines, and a dimmer diffuse star glow in dark-sky views.

On this laptop that makes the GTX **Reduced** (70 %, Reduced air, 2048 shadows) and the Intel
**Low** with atmospheres Off, at 50 % under Forward+ and 100 % through ANGLE; a browser here is Low
at Off and 100 %. *What the fitted defaults deliver* measures each.

## A setting the machine can't carry

An option too heavy for a machine can leave its user unable to reach Options to undo it. Options
applies a change at once but writes it only on Confirm Changes, so a live change that crashes or
freezes the app is gone at the next start. Three things get past that:

- **A restart option is confirmed blind.** Atmosphere into or out of Min or Off, Star Catalog and
  Renderer show their cost only at the next start.
- **A confirmed option can be fine where it was tried and not elsewhere**, and the Planetarium
  reopens the last view at every start, so a view that brings a machine down does so every time.
- **A crash, a GPU reset or a lost WebGL context gives no frames at all**, and a web visitor has no
  practical way to clear the site's storage.

`IVCoreSettings.enable_graphics_rescue`, on by default outside editor builds, answers each:

- **A start that never finishes resets the next one.** `IVSettingsManager` marks each start
  unfinished in `start_marker.ivbinary`, beside the settings cache and before anything is drawn, and
  finished after 10 s of running simulator, a quit or a window close. A start that finds the last
  one unfinished restores `IVSettingsManager.graphics_settings` to the fitted defaults, if any
  differed, and IVGraphicsRescue says why. A crash at a restored view recurs within those 10 s, so a
  crash loop repeats once at most. The false positive is a start ended from outside in its first
  seconds, a killed process or a closed tab, which costs a user their graphics choices with a
  notice. Editor builds are excluded because stopping a run from the editor is exactly that, and a
  deliberate restart or reload that skips `IVStateManager.quit()`, as the Planetarium's web-app
  update does, calls `IVSettingsManager.mark_start_finished()` first.
- **A crawl gets an offer.** IVGraphicsRescue asks once a session whether to restore the fitted
  defaults when more than half the frames over 10 s take longer than 250 ms and a graphics setting
  differs from its default. 250 ms marks a machine near the limit of use, and the setting a choice
  beyond the fit -- a condition the frame time alone cannot carry, since this laptop's Intel already
  takes 157 ms at Earth close up at its fitted defaults through ANGLE (*What the fitted defaults
  deliver*), and a weaker GPU takes longer. Frames
  drawn while a popup is open, Options holds an unconfirmed change or the boot or splash screen is
  up don't count, the last so that the warm-up's compile stalls are not taken for a crawl.
- **A reset on request.** User argument `--reset-graphics` restores them on any start. The
  Planetarium's web page passes it for a URL ending `#reset-graphics`, and on a lost WebGL context,
  where Godot's own page says only to reload and the same settings would likely lose it again,
  offers a reload that does.


## Savings that need no option

Each of these removes work whose result never reaches the screen, so it is always on. Where one
has a switch for A/Bs, the relief is today's; otherwise it is dated.

### The exposure skips

Under physical light, the background panorama stops being drawn, and each star magnitude bin stops
being submitted, once the compensating camera has metered it below half a display code
(`IVWorldEnvironment.skip_invisible_starmap`, `IVStarsVisual.cull_invisible_bins`; *Skipping what
the camera has metered away* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)). Half a code is the
8-bit rounding boundary, so a skip moves any pixel by one code at most, and at every pose here it
moved none. What they save, as a share of the frame they leave:

| View | Intel, ANGLE | Intel, Vulkan | GTX, Vulkan |
|---|---:|---:|---:|
| Earth at 1.6 radii | 15 % | 0 % | 24 % |
| Earth at 3 radii | 23 % | 8 % | 18 % |
| Venus at 3 radii | 35 % | 0 % | 17 % |
| Mars at 3 radii | 23 % | 3 % | 14 % |
| Titan at 3 radii | 4 % | 0 % | 5 % |
| The Moon at 3 radii | 53 % | 28 % | 33 % |
| Saturn at 3 radii | 25 % | 11 % | 17 % |

Nothing is skipped in a dark-adapted view, where exposure is at rest, nor with physical light off.
Through ANGLE, where every star is an emulated sprite, they are worth more than any option but the
atmosphere tiers in lit views. At Earth the skip leaves 11 of 24 bins, 15,641 of 2,551,210 stars.

### Empty shadow passes

A shadow-mapped `IVDynamicLight` clears `shadow_enabled` while nothing in its reach would draw into
its map or read it, under the opt-in `IVCoreSettings.apply_empty_shadow_pass_skip` (*Local shadow
maps* in [VISUAL_MODEL.md](VISUAL_MODEL.md)). The Planetarium turns it on, where it acts on Forward+
alone, Compatibility having no maps there. It is exact by construction: a map with no caster and no
receiver in reach contributes nothing. Its share of the frame it leaves:

| View | Intel, Vulkan | GTX, Vulkan |
|---|---:|---:|
| The Moon at 3 radii | 22 % | 7 % |
| Jupiter's night side | 17 % | 0 % |
| The Sun at 3 radii | 17 % | 2 % |
| Whole system, dark sky | 14 % | 3 % |
| Juno close up | 7 % | 0 % |

At Juno the near light keeps its map for the craft's self-shadowing and only the middle one
retires; at Saturn at 3 radii a moon keeps one in reach and nothing retires. Why it is opt-in is a
compile question: *`directional_shadow_count` stops being a constant*.

### Airless shaders

A body with no atmosphere draws with an `.airless` twin of its disc shader, which compiles the
atmosphere to no-ops (THE AIRLESS VARIANT in `_atmosphere.gdshaderinc`;
`IVAssetPreloader.airless_shader_variants`). The full shader would render such a body identically,
its atmosphere gated off at runtime, but some compilers make a body pay for code it never runs
(*What drives the cost*). In the Planetarium that is every body but Earth, Venus, Mars and Titan.
What they save, against the full shaders bound to the same bodies in the running app:

| View | Intel, ANGLE: full / airless | Intel, Vulkan |
|---|---|---|
| The Moon at 3 radii | 28.5 / 21.8 ms (-23 %) | 103 / 23.8 ms (-77 %) |
| Europa at 3 radii | 38.6 / 31.2 ms (-19 %) | 114 / 23.5 ms (-79 %) |
| Neptune at 3 radii | 60.6 / 49.3 ms (-19 %) | 216 / 37.0 ms (-83 %) |
| Jupiter's night side | 61.1 / 52.6 ms (-14 %) | 118 / 27.8 ms (-76 %) |

Under Forward+ on the Intel the full shader costs an airless body four to six times its frame.
On the GTX they saved 5-42 % through NVIDIA's GL and up to 18 % under Vulkan (2026-09-27). They
cost a first visit nothing: an airless program compiles in a third of a full one's time (*What each
shader costs*). The Off tier's closed-form veil is an exact no-op for a body with no air, so it
could have lived in these twins and cost Off no programs of its own; it added about 4.5 s to every
airless program through ANGLE, which every first visit compiles in every tier, so Off has twins of
its own instead.

### The limb annulus

The limb shell draws a camera-facing ring of its own sphere, from two pixels inside the disc's
handoff band out to the shell's silhouette (`limb_annulus_mesh`; *Atmospheres* in
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)), because every fragment over the disc's interior
discards: the surface and cloud shaders composite that air themselves. On Intel's GL driver a
discarding fragment was not cheap -- a limb shader that discarded at its first statement still cost
twice what a dead-code body did, and branching around the body recovered 3-6 % -- so the only saving
was not to generate those fragments. Measured when it was built (2026-09-11, Intel's own GL):
19-54 % of an atmosphere frame, no compile cost, and no visible change beyond single rim pixels that
any change of tessellation moves.

### Level of detail, and shells nobody can see

- **The sphere LOD ladder.** A body with no mesh of its own picks its shared sphere per frame by
  on-screen size, from 256x128 down, each rung serving every body whose silhouette sag stays within
  0.15 px (*The sphere LOD ladder* in [VISUAL_MODEL.md](VISUAL_MODEL.md)). A fixed 128x64 was
  indistinguishable at 1.6 radii but not closer: at the ISS, framing Earth's horizon, it moved 2.4 %
  of pixels by more than 2 codes. Its relief has not been measured on its own.
- **Culling on true bounds, and the handoff gates.** A body's shells drop the farwarp box while the
  body lies inside a quarter of the camera's far plane, and cull and pick their mesh LOD on their
  own bounds there (`IVFarwarpManager.true_bounds_far_fraction`); a body handed off to its PSF point
  stops drawing its shells (`IVShellsModel.cull_handed_off`), and rings stop at their own handoff
  (`IVRings.cull_handed_off`) (*Farwarp* and *Culling, visibility and lifecycle* in
  [VISUAL_MODEL.md](VISUAL_MODEL.md)). Most of what they retire is Ceres's and the moons' own
  65,000-triangle meshes, drawn off screen in every view before. Through ANGLE on the Intel
  (2026-09-29): 2.2-7.4 ms, 2-16 % of a frame, at nine poses from the Moon to the whole system; on
  screen, a sub-pixel moon now takes its 4000-radii cull and Ceres's own mesh 6 cusp pixels.


## Levers not offered

Each of these was measured and left out of the option set, for the reason given.

- **Glow.** Switching the engine's glow off saves little in an atmosphere view but a large share of
  an airless one: 7-19 % through ANGLE, 17-44 % through the GTX's GL, 19-37 % under Forward+ on the
  Intel and 33-51 % on the GTX. Under Forward+ that changed no pixel at Earth, Mars, Titan, Saturn
  or the Sun, and 7-8 % of a crescent view's; under Compatibility, whose RGB10A2 feed crushes the
  dimmest codes, it lifts those over three quarters of a dark sky, by 4-5 codes on average. It is
  part of the photometric model rather than a quality setting: what it draws is the bloom of what
  the camera has not exposed for -- a blown limb, a spacecraft, a small moon -- which no PSF quad
  covers (*Glow: the bloom pass* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)). What it costs
  where it draws nothing is a TODO.
- **Cloud decks.** Taking Earth's and Neptune's decks off saved 6-7 % of an Intel frame at Earth and
  22-26 % of a GTX one (2026-09-10), and changes a fifth of an Earth view's pixels. A lowest tier's
  lever at most.
- **Sunspot detail.** The photosphere's sunspot cells were 36 % of an Intel frame at the Sun close
  up (2026-09-10). A level of detail by disc size would take most of that without an option; not
  built.
- **The number of asteroids.** Each costs more than a star, since the points shader solves Kepler's
  equation for every one of them every frame, but at 1/32 of the star count the whole 80,569 are
  3-5 % of an Intel frame and 6-10 % of a GTX one even in the Asteroids view, and cost is the vertex
  stage, paid whenever a group is shown (never frustum-culled, its farwarp bounds holding every
  place the camera can go). With the star field drawn, showing them cost nothing on Intel: they
  cover star sprites that GPU is fragment-bound on. No cut could return more than those 3-5 %, so
  what a project loads stays its own choice (`mag_cutoff`,
  `IVCoreSettings.sbg_mag_cutoff_override`).
- **A runtime tier below Reduced.** Normal and Reduced are one program selecting a rule from a
  packed node table, so a lower rule would cost no compile. But the ring cannot go below two taps --
  one tap is exactly the dotted arc the pixel filter exists to close, and moves the limb by 60 to
  100 % of its maximum -- two nodes move the disc's air 18 % at Earth, and three nodes with two taps
  buys 9-16 % of the atmosphere's own cost for disc air that moves up to five times as much as
  Reduced's. What lowers the floor is carrying less code, which is Min and Off.
- **Star sprites as quads.** D3D11 has no point sprites, so ANGLE emulates `gl_PointSize`, and the
  star field costs about four times as much through ANGLE as through Intel's own GL. Drawing each
  star as two triangles instead costs twice what the points do through ANGLE -- four vertex runs a
  star outweigh the emulation -- so the field stays points.
- **A glare-wing or Milky Way toggle.** The glare wing is what draws the faint end of the star
  field, and dropping it moves half a dark sky by 10 codes for 11-25 % of a star-heavy Intel frame;
  the Milky Way is skipped automatically wherever exposure hides it (*The exposure skips*), which is
  every view where it cost anything that bought nothing.


## Compiling shaders

The Compatibility renderer compiles a shader program **at its first draw, synchronously, on the
main thread** (*Specializations*), so what a first run compiles is paid as frames: under the boot
screen for whatever the opening view and the warm-up draw, and in flight for anything they missed.
Forward+ compiles its pipelines in the background and draws an ubershader meanwhile, so it pays a
fraction of that and pays it as slower frames rather than stalls. The web export compiles on every
first visit, having no program-binary cache (*Where the caches are*).

### What a first run costs

From launch to the end of the boot screen at the settings each row names, in a 1920x1080 window,
cold -- every Core shader's source made novel and Godot's caches set aside -- and then warm, the
same run again:

| Path, tier | Cold | Warm | Compiling | of which the opening view | the warm-up |
|---|---:|---:|---:|---:|---:|
| Intel, ANGLE, Min | 97 s | 10 s | 88 s | 48 s | 35 s |
| Intel, ANGLE, Normal | 107 s | 10 s | 97 s | 54 s | 39 s |
| GTX, GL, Reduced | 48 s | 12 s | 36 s | 21 s | 13 s |
| GTX, Vulkan, Reduced | 23 s | 16 s | 7 s | 7 s | 0.3 s |
| Intel, Vulkan, Reduced | 21 s | 13 s | 9 s | 7 s | 0.4 s |

- **Through ANGLE a first run is a minute and a half of compiling**, nearly all of it FXC on the
  CPU, so a slower CPU scales it whatever the GPU. The web's first visit on this laptop takes that
  path at Off, whose programs compile in 57 s against Min's 82 s (*What each shader costs*), and
  the browser's own ANGLE build may differ (*The web export*).
- **The opening view is one frame.** Its first draw compiles every shader in view -- 51 s through
  ANGLE, 26 s through NVIDIA's GL -- which is why the boot screen has to stay up until the warm-up
  finishes rather than until the simulator starts.
- **Afterwards, one stall is left: the spacecraft.** A tour of every kind of body after a cold boot
  -- Earth, Venus, Titan, Mars, the Moon, Phobos, Jupiter, Saturn, Neptune, the Sun, Juno and both
  wide views -- drew no frame over 0.3 s except the first sight of Juno: 11 s through ANGLE and
  1.5 s through NVIDIA's GL. A spacecraft model's `StandardMaterial3D`s are not in
  `IVGlobal.resources`, so the warm-up does not draw them (TODO). Under Vulkan the tour stalled
  nowhere.
- **A warm start compiles nothing.** Godot's cache answers, and the driver's under it; the warm-up
  then takes a frame per shader, 0.3-1.5 s.

### What each shader costs

Seconds to a first draw -- five programs (*Specializations*) -- from `time_shader_compiles.py`, one
shader per process, through ANGLE (FXC, on this CPU) and through NVIDIA's GL. A further
specialization costs about a sixth of a first draw through ANGLE and an eighth through GL.

| Shader | ANGLE: full / Min / Off / airless | NVIDIA GL: full / Min / Off / airless |
|---|---|---|
| `surface.cube` | 17.3 / 14.8 / 9.2 / 6.2 | 7.2 / 5.4 / 2.9 / 2.0 |
| `surface` | 16.4 / 13.1 / 7.7 / 5.1 | 7.5 / 5.2 / 2.9 / 1.7 |
| `band_pattern` | 18.0 / 15.0 / 8.5 / 6.1 | 7.0 / 4.8 / 2.6 / 1.9 |
| `cloud_shell.cube` | 14.5 / 11.3 / 6.6 / 4.6 | 5.5 / 4.5 / 2.3 / 1.6 |
| `cloud_shell` | 14.6 / 11.7 / 7.2 / 4.5 | 5.3 / 4.6 / 2.5 / 1.5 |
| `atmosphere_limb` (full / Min) | 10.4 / 9.0 | 5.0 / 4.6 |
| `rings` | 4.5 | 1.4 |
| `photosphere` | 2.6 | 1.1 |
| `body_psf` | 1.0 | 0.7 |
| `stars`, `path`, `farwarp_vertex` and the id shaders | 0.3-0.5 | 0.3-0.4 |

What the Planetarium compiles, summed over the shaders a session draws:

| Tier | The four air bodies' programs | The whole session |
|---|---:|---:|
| Normal (and Reduced) | 60 s / 25 s | 92 s / 37 s |
| Min | 50 s / 19 s | 82 s / 31 s |
| Off | 24 s / 8 s | 57 s / 20 s |

(ANGLE / NVIDIA GL.) The sums match the in-app cold starts to within their engine shaders (*What a
first run costs*).

- **An atmosphere shader costs three times its airless twin**, and it is the atmosphere that makes
  the first visit long. Off compiles no quadrature and no limb shader, which is what makes it the
  first-load tier; Min carries less code than Normal, and its programs compile a sixth faster.
- **No single program is near a browser's watchdog.** The heaviest through ANGLE is about 3.6 s
  (`band_pattern`'s first draw over its five programs, and its 3.2 s further specialization), where
  Chrome allows 30 (*The web export*).
- **Through ANGLE the time is FXC's, on the CPU**, before any driver sees the shader: the Intel and
  the GTX agreed to within 13 % when both were timed through it (2026-09-27). A slower CPU scales
  every ANGLE figure, whatever GPU it drives.
- **Forward+ stalls little on any of them**: the frame of a first draw takes 0.2-2.7 s and a further
  specialization none, the rest of the work going to a background thread while an ubershader draws.
  Its whole first run compiles in 7-9 s (*What a first run costs*).
- **Intel's own GL is not measured here** (*The reference machine*); its compiler was faster than
  FXC by several times on the atmosphere shaders (23 s against 90 s for the atmosphere set,
  2026-09-28).

### What an edit costs

Editing a file invalidates every shader that includes it, so its cost is the sum over the shaders
reaching it that a session then draws. For the Planetarium's Normal session, at most:

| Edited file | Shaders in a session | ANGLE | NVIDIA GL |
|---|---:|---:|---:|
| `_farwarp`, `_display`, `_point_spread_function`, `_sun_occlusion` | 9-16 | 86-92 s | 33-37 s |
| `_atmosphere.gdshaderinc` | 8 | 82 s | 32 s |
| `_detail.gdshaderinc`, `_photometry.gdshaderinc` | 8 | 73-74 s | 28 s |
| `_detail.cube.gdshaderinc` | 4 | 43 s | 16 s |
| One disc body include (`_surface.cube` and the rest) | 2 | 19-24 s | 7-9 s |
| `_atmosphere_limb.gdshaderinc` | 1 | 10 s | 5 s |

An include's variant parts reach only their variant: `_atmosphere.min.gdshaderinc` the six `.min`
shaders, `_atmosphere.off.gdshaderinc` the five `.off` ones, and an edit inside `_atmosphere`'s
`ATM_AIRLESS` exclusion none of the airless twins. Timing every shader in the plugin, all variants,
takes about 240 s through ANGLE and 95 s through NVIDIA's GL. With the warm-up in place the whole of
it is paid under the next Compatibility run's boot screen.

### What drives the cost

Not source length, and not lit against `unshaded`: `body_psf.gdshader` is among the longest
sources in the plugin and among the cheapest to compile. What a compiler is handed after inlining
and unrolling is what it pays for, and its optimizer's cost grows faster than that code does. Each
compiler here has its own way of multiplying the source.

- **Native GL unrolls a loop whose trip count it can see**, inlines whatever the body calls, and
  then optimizes the result. So every loop in the atmosphere, the sun's sunspot cells and the
  photometry's limb kernel has an opaque `uniform int` bound -- `iv_atm_gl_first`,
  `iv_atm_gl_nodes`, `atm_shell_nodes`, `iv_atm_ring_max_taps`, `spot_cell_reach`,
  `limb_kernel_cells`, `atm_min_disc_points` and the rest -- carrying the value a constant would.
  With constant bounds the limb shader compiled six times slower through AMD's GL driver. The
  outer loop's bound alone was not enough; the inner ones are what must not unroll.
- **FXC, ANGLE's compiler on Windows, inlines every call**, so a function is compiled once per call
  site. It unrolls a constant and a uniform bound alike, and the opaque bounds buy nothing there.
  What cost was the atmosphere reaching its heaviest functions from dozens of places: through ANGLE
  on this CPU its six shaders took 808 s to their first draws between them, one limb program past a
  minute and so past Chrome's GPU watchdog, until each heavy function was given one call site, which
  took them to about 100 s (2026-09-27; *The atmosphere's structure*, below).
- **An include a shader does not call into is free.** `rings.gdshader` includes
  `_photometry.gdshaderinc`, whose limb kernels are two sixteen-cell loops of exactly the expensive
  shape, and calls neither; unreferenced, they never reach the optimizer. So an include proves
  nothing about the loops in it.
- **Code volume is what compiles, not iteration count.** A four-node quadrature compiles no faster
  than the six-node one, the bound being opaque either way; a tier that must pay less at first draw
  has to leave code out, which is why Min and Off are programs of their own and Reduced is not.

### Writing a shader that compiles

- **Don't hand-unroll.** Writing a loop out longhand hands the compiler exactly the body unrolling
  produces, minus the chance of it not producing it. Where a trip count is a constant of the
  algorithm, write the loop and make the bound a uniform.
- **Don't fear a `while` or a dynamic bound.** GLSL ES 1.00, the WebGL 1 profile Godot 3's GLES2
  renderer targeted, restricted loops to constant bounds, and old comments carry that caution. Godot
  4 has no such target: the web export builds with `-sMAX_WEBGL_VERSION=2`, the Compatibility
  renderer emits `#version 300 es`, and `shader_compiler.cpp` passes `while`, `do` and `for`
  straight through. What does hold is a runtime point: a divergent trip count costs every lane in a
  group the maximum, so keep trip counts uniform across neighbouring fragments.
- **Don't call a heavy function from a second place.** A call site is a copy as surely as a
  written-out loop is. Write the second use as another iteration of a loop the first already runs.
- **Code a body never runs still costs it, on some compilers.** Intel's compilers size a whole
  shader for its heaviest part: an airless body drawn with the full surface shader, the atmosphere
  gated off at runtime, takes four to six times as long under Intel's Vulkan as with the atmosphere
  compiled out, and a fifth longer through ANGLE; and through Intel's GL a disc shader's air in
  front of the disc ran at twice the speed in a shader holding nothing else of the ray. So a body
  with no atmosphere binds an `.airless` twin that compiles the atmosphere to no-ops (*Airless
  shaders*, above), and a tier of different code binds twins of its own.

### The atmosphere's structure

**Every heavy function in `_atmosphere.gdshaderinc` has one call site**, inside a loop (THE
STRUCTURE in its header):

- `atm_exp_columns()` evaluates an exponential column's terms in a loop, so a call site carries one
  Chapman function where a haze's branches would write out up to seven slants.
- `atm_ray_path()` integrates a whole view ray as one loop over its segments, so one quadrature
  node, `atm_node()`, serves the lit part in front of a disc, both halves of a tangent ray and every
  thin-layer crossing.
- A node's view and sun columns, and the thin layer's partial columns, each come from one loop.
- `atm_receiver_light()` hands a surface or cloud shell everything it takes from the air above it
  -- the view tint, the sun transmittance, and the plane-parallel diffuse the twilight subtracts --
  from one loop of two columns, four for a cloud deck.
- The limb shader integrates the handoff band's disc-hit ray as one more pass of the ring's tap
  loop.

The rule is a new term is a new iteration, not a new call. The Min variant relaxes it:
`atm_min_point()` has one call site per segment kind, two in the limb shader, and a Min program
still compiles faster than its full twin through FXC (*What each shader costs*).

**One exception is not about compiling.** Under Forward+ and Mobile only, `atm_exp_columns()`
writes out the common case -- a haze with no top, Earth's, Venus' and Mars' -- because NVIDIA's
Vulkan runs the term loop a third slower than two written-out terms. Under Compatibility the two
extra calls slow Intel's GL compiler's whole shader by 11-33 %, airless bodies included, while ANGLE
takes the written-out form 23-33 % faster; the preprocessor cannot tell the two apart, so
Compatibility keeps the loop.

**The same source runs at a different speed through every compiler.** Giving each heavy function
one call site changed the atmosphere's own cost, evaluated alone over a grid of geometries, by 0.8
times through NVIDIA's GL, 1.0-1.3 through Vulkan, 1.3-1.5 through ANGLE and anywhere from 0.12 to
2.9 through Intel's GL (2026-09-27). Measure a change to a shader's structure on every path before
keeping it; one that is exact on paper has landed anywhere from 10 % faster to 15 % slower on Intel,
depending on the view.

### Specializations

A shader's figure is never one program. Read from `drivers/gles3/shader_gles3.cpp` and
`rasterizer_scene_gles3.cpp` in the 4.7.2 source:

- **A first bind compiles five programs.** `_initialize_version()` compiles all four variants of
  the scene shader (`mode_color`, `mode_color_instancing`, `mode_depth`, `mode_depth_instancing`)
  at the default specialization mask, and `_version_bind_shader()` then compiles the one actually
  requested, which practically always differs from the default (the default has every light type
  enabled). Nothing in the engine avoids this.
- **Every further specialization is a full compile.** The mask is set per draw from the lights
  reaching the instance, the reflection probes, the lightmap and the pass. An instance is drawn
  `MAX(1, positional light passes + directional_shadow_count)` times, the base pass fused with the
  first shadowed directional light and each further one adding a pass of its own. `RENDER_SHADOWS`
  is a separate depth-pass specialization, taken by anything carrying
  `IVGlobal.LOCAL_SHADOW_CASTER`.
- **The base pass does not read the instance's layer mask.** It reads the instance's omni, spot
  and area caches, its reflection probes and its lightmap, and sets `DISABLE_LIGHT_DIRECTIONAL`
  from `directional_light_count == directional_shadow_count` -- a fact about the frame, not the
  instance. The layer mask enters through the additive branch alone, where a light whose cull mask
  misses the instance *clears* `USE_ADDITIVE_LIGHTING` and leaves the PSSM and PCF bits set: a
  different program, not a cheaper one. That is why one shader compiles a different program per
  size domain under a shadowed light stack.
- **`USE_RADIANCE_MAP` switches on once, for everything.** The base color pass sets it for every
  instance, unshaded ones included, once the sky has a radiance map (`sky->radiance != 0` in
  `_render_list_template()`; additive passes clear it). `_setup_sky()` allocates the map in the
  first frame drawn with `BG_SKY`, and nothing but a radiance-size change or the Sky's release frees
  it, so a session's first sky frame gives every scene shader a new key. In the Planetarium that
  frame falls in the start sequence, when `IVWorldEnvironment` adds the starmap on
  `assets_preloaded`, about a second before the warm-up, and every program the start and the
  warm-up compile carries the bit. What could move it is `skip_invisible_starmap`, which turns the
  sky off while exposure has metered it black: a skip engaging before the sky's first draw would
  have the warm-up compile every shader without the bit, and the first view dark enough to show the
  Milky Way would compile everything on screen again, in flight.
- **Compiling is synchronous.** `glLinkProgram` is followed at once by the `GL_LINK_STATUS` query;
  there is no use of `KHR_parallel_shader_compile`, and the queue-and-use-defaults branch is an
  `if (false)` TODO. Nothing short of an engine patch changes that.

### The light configuration

How many programs a lit shader compiles is set by the lights that reach it, and
`IVCoreSettings.apply_gl_compatibility_shadows` decides that under Compatibility:

| `apply_gl_compatibility_shadows` | color programs per lit shader | depth programs | what a first visit can still pay |
|---|---|---|---|
| `true` (Core's default) | 3 | +1 (`RENDER_SHADOWS`) | the middle size domain's, which the default `warm_radii` never reach |
| `false` (the Planetarium) | 1 | 0 | nothing |

With shadows on, `dynamic_lights.tsv` gives Compatibility the far sun light (unshadowed, cull
`0b0001`) and the shadowed middle (`0b0010`) and near (`0b0100`) lights, so
`directional_shadow_count` is 2 and every lit instance is drawn twice; across the two larger size
domains the additive clearing above yields three color programs, and anything close enough to
count as terrain adds the depth pass. With shadows off there is one unshadowed light,
`directional_shadow_count` is 0 and `uses_additive_lighting` false: one pass, no additive, PSSM or
PCF bits and no shadow pass, so **every lit body in every size domain binds the same program**, and
a first visit cannot reach a specialization the warm-up missed.

It has two side effects, neither about compiling. `update_directional_shadow_atlas()` runs only
under `if (r_directional_shadow_count)`, so with no shadowed light the depth atlas is never
allocated; and `IVGraphicsManager` skips `directional_shadow_atlas_set_size()` on that path, which
is safe because the allocation is lazy. What the single light gives up is local shadow maps --
spacecraft self-shadowing, crater walls on a lander. The analytic astronomical shadows (rings,
eclipses, transits, and the camera-fraction dimming that carries them onto craft) work either way.

#### `directional_shadow_count` stops being a constant

`IVCoreSettings.apply_empty_shadow_pass_skip` (*Empty shadow passes*, above) clears a shadowed
light's `shadow_enabled` while nothing in its reach would draw into its map or read it, so under a
shadowed stack the count takes 2, 1 or 0. It is a fact about the frame, so each value is its own
program set for **every lit shader**, compiled synchronously on the first frame that reaches it, and
a warm-up covers only the value it runs at. **That, not frame time, is why the skip is opt-in**: it
moves compiling from "all under the boot screen" to "some in flight" under Compatibility, where its
frame-time relief is small, to buy a Forward+ saving. Under the single-light fallback it is inert,
which is why the Planetarium can turn it on.

Four things hold the risk down where it applies. The setting is off by default. Flips are made rare
rather than merely correct: on is immediate, off waits 120 frames, and the enable and disable
thresholds sit at 1.25 and 2.0 times the reach. `IVShaderWarmup` registers the camera its quads hang
from through `IVDynamicLight.add_local_shadow_geometry()`, with every domain bit and the caster bit,
so the warm-up still compiles the count the app runs; warming every reachable count instead would
multiply the phase to pre-pay stalls most projects never take. And where a project measures stalls
anyway, the lever is to couple the two shadowed lights into one decision, taking the reachable
counts from three to two at the cost of the receiver half of the predicate.

The Shadow Resolution option's Off (`IVDynamicLight.shadow_maps_enabled`) holds the count at 0 until
a resolution is chosen again: a user action rather than a camera move, and the warm-up covers
whichever state the session starts in. Read from `light_storage.cpp`, for both renderers, nothing
frees the depth atlas when the count returns to zero; only `directional_shadow_atlas_set_size()`
with a different size does. So a skip's flip reuses the atlas it left, and Off also parks the size
at 256 -- the engine setting's minimum, and a size no option uses -- which frees any atlas and
allocates nothing while no map is drawn. On Forward+ on the GTX, texture memory falls by 64 MiB when
4096 goes Off and by 16 MiB from 2048. Not 0, which the engine passes only at teardown: a shadowed
light drawn at size 0 has no atlas framebuffer, and the Compatibility renderer divides by that size.

### The warm-up

`IVShaderWarmup` (`program/shader_warmup.gd`) draws spatial shaders on a small quad in front of the
camera, one shader per frame, once at a planet-scale layer and once at a craft-scale layer carrying
the shadow-caster bit; between them those reach the base, additive and shadow specializations bodies
use. It is opt-in, added to `IVCoreInitializer.program_nodes` from a preinitializer. Its
`progress_changed` is emitted one frame before the draw that stalls, so the text a handler sets is
the text on screen through the stall. It runs once per session.

**It draws what the project will bind, and nothing else.** A body's shell shaders come from the
specs `IVAssetPreloader` resolved at load -- the cubemap, airless, Min and Off swaps included, so a
spec names the shader that will really be bound -- because the scene tree cannot say: a body's
visual is built lazily on the camera's first visit, which is the stall being warmed against. The
rest of Core's shaders are added on the conditions `IVBodyFinisher` and `IVSBGFinisher` apply when
they add the node that binds one: a body with rings, a body with an orbit,
`IVBodyPSF.is_applicable_to_any_body()`, a `small_bodies_groups` row not flagged `skip` (and its
`lp_integer` for the Lagrange variant), and `IVFragmentIdentifier` for the id overlays, which erases
itself under Compatibility. In the Planetarium that is 15 shaders under Compatibility and 17 under
Forward+:

- `photosphere`, `body_psf`, `rings`, `path`, `farwarp_vertex`, `orbiting_positions_id` and
  `orbiting_positions_lp_id`, plus `path_id` and `instance_id` under Forward+;
- the four atmosphere bodies' `atmosphere_limb`, `surface.cube` (Earth, Mars), `band_pattern`
  (Venus, Titan) and `cloud_shell.cube` (Earth) -- their `.min` twins in a Min session, and in an
  Off session the `.off` twins of the last three and no limb;
- the airless `surface.cube`, `surface`, `band_pattern` and `cloud_shell.cube` that every other body
  with a shader binds.

A shader no such condition can decide is deliberately not warmed, since a needless compile is
seconds of boot screen. `stars_shader` is the one Core shader in that position -- `IVStarsVisual` is
a scene node, so nothing in the tables says a project kept it -- and it has compiled in the opening
view before the warm-up runs anyway. `extra_shader_names` takes it, and a project's own shaders;
`warm_core_shaders = false` turns the automatic selection off. A spacecraft model's own materials
are not shaders in `IVGlobal.resources` at all, which is the stall *What a first run costs* found.

**Its trigger picks the moment.** `SIMULATOR_STARTED`, the default and the Planetarium's, draws in
the real scene, so the quads reach the specializations bodies actually use; it cannot usefully run
earlier, since `IVCamera` does not process before the simulator starts and a quad a metre in front
of it rounds to nothing at a heliocentric float32 position. `ASSETS_PRELOADED`, for a project with a
splash screen and `wait_for_start = true`, adds its own camera and one unshadowed light, which
reaches the scene-independent part of each shader -- the four variants at the default mask, over
half of a first draw -- and leaves the scene's own specializations to a body's first draw. Either
way the warm-up holds `IVStateManager` until `finished` -- `show_splash_screen` true under
`SIMULATOR_STARTED`, `ok_to_start` false under `ASSETS_PRELOADED` -- so a boot or splash screen that
follows them covers it with no wiring of its own. `MANUAL` and `warm_up()` are for a project that
wants the moment itself.

**What the two radii buy.** `warm_radii` resolve to layers `0b0001` and `0b0100`, the second
carrying the shadow-caster bit. Under a shadowed light stack the second earns its place through
that bit, the only way to reach the `RENDER_SHADOWS` depth program; neither lands in the middle
domain (`0b0010`, 0.1-100 km), whose additive specialization a first visit to a small moon then
pays. Under the single-light fallback both radii select the same program, and the second quad costs
a frame rather than a compile.

### The web export

The web export is the Compatibility renderer through the browser's WebGL 2, which on Windows is
ANGLE's D3D11 backend and FXC, and a first-time visitor arrives with no cache Godot can use
(*Where the caches are*). So a first visit on a machine like this one compiles what *What a first
run costs* measures through ANGLE, at the fitted Off -- 57 s of programs (*What each shader
costs*), all of it under the boot screen -- and a repeat visit on the same Chrome profile compiles
nothing.

**Chrome's GPU watchdog** kills the GPU process, and every WebGL context with it, when its main
thread spends too long in one task: 30 s on Windows, 25 s on macOS and 15 s elsewhere
(`kGpuWatchdogTimeout`, `gpu/ipc/common/gpu_watchdog_timeout.h` in Chromium), and on Windows up to
four such periods when the thread was waiting rather than working. Godot queries each program's
link status as soon as it links, so the figure to hold against the limit is one program's compile,
not a frame's -- here 3-4 s at most through ANGLE (*What each shader costs*). A lost context is what
the Planetarium's page answers with a reload into the fitted defaults (*A setting the machine can't
carry*).

**ANGLE compiles every shader at its highest optimization level.** Its D3D11 backend asks FXC for
`D3DCOMPILE_OPTIMIZATION_LEVEL2`, retrying with validation and then optimization skipped only when a
compile fails (`Renderer11::compileToExecutable`), and adds `D3DCOMPILE_IEEE_STRICTNESS` to a shader
that calls `isnan()`; nothing a page does can ask for a cheaper compile. What a shader can control
is how much code FXC sees after inlining (*What drives the cost*).

**No browser has been measured.** `--rendering-driver opengl3_angle` is as close as a desktop run
gets -- the same translation, out of Godot's own ANGLE build -- but a browser ships its own, with
its own flags, and Firefox is another path again. Measure an actual first load in Chrome and Firefox
on a weak machine before trusting a figure here for the web. **Never load the export in a browser
embedded in another app's UI**: one that shares that app's renderer and GPU process freezes the app
with it while it compiles.

### Where the caches are

Two, stacked, and a slow run cannot be reasoned about without both.

**Godot's** is per project and keyed on the GLSL Godot *generates*:

- an editor run (F5) writes `<project>/.godot/shader_cache`;
- a standalone run (`--path`, or an exported build) writes
  `%APPDATA%/Godot/app_userdata/<project name>/shader_cache`, where `EGL` holds ANGLE's program
  blobs beside Godot's own `SceneShaderGLES3` and the rest.

They share nothing, and clearing the wrong one measures nothing. **The web build has no Godot cache
at all**: `_load_from_cache()` and `_save_to_cache()` are compiled out under `WEB_ENABLED`, WebGL
having no program-binary API.

**The GL driver keeps its own underneath.** Deleting Godot's cache while the source is unchanged
still returns in well under a second, because the driver answers from its own; only novel source
misses both, which is exactly what an edit is. A browser keeps a GPU shader cache too -- Chrome
does, so a repeat visitor on the same profile compiles nothing until the site's shaders change.
Firefox may not.


## How this was measured

### Frame time

Each path was launched with `--disable-vsync` and a 1920x1080 window at display scale 1
(`[core_settings] apply_display_scale=false` in the Planetarium's `ivoyager_override2.cfg`), except
where a table says full screen. A temporary Assistant suite forced the settings, and at each pose:

- **sim time frozen** at 2026-03-20 12:00 and the sim paused, the 2D GUI and every HUD hidden (the
  Asteroids view keeps the points its view shows);
- **settled 6 s**, then **the star bins pinned** -- the bin skip switched off and back on, which
  leaves drawn exactly the bins whose brightest star peaks at half a code or more, whatever view
  came before (*A view's cost depends on the view before it*, below) -- and **the exposure frozen**
  there, so no option's own change of the image could move the metering;
- **measured** as the median GPU time over the frames of a few seconds, from the main viewport's
  timestamp queries (`viewport_get_measured_render_time_gpu`), except through ANGLE, which has none:
  there the median frame interval, which includes the CPU's share and can only overstate the GPU's.

An option's relief is measured within one session, at one pose, as an **off, on, on, off** block of
2.5-second samples, and given as the mean of the two ons against the mean of the two offs. The GTX
1650 Ti runs against its 40 W power cap here, its clock wandering between about 1650 and 1790 MHz,
and a single on-sample against a pose's baseline moved by up to 20 % with nothing changed; the block
cancels a linear drift. Two off-samples of one block then differ by 1-3 % through ANGLE and the
GTX's GL at the median and 4 % under Vulkan, one block in ten past 12 %, which is the resolution of
a relief figure. A restart option (Min, Off, a star cut) is compared across sessions, which carries
the drift whole. Forward+ adds a trap of its own: it compiles a new pipeline in the background and
draws a slower ubershader until it lands, which a changed MSAA or a session's first visit to a
shader provokes, so every setting was applied once off the clock, and every restart session visited
its poses once before measuring.

Screenshot comparisons were taken at the same frozen exposure and reported as the mean, the 99th
percentile and the maximum absolute difference per pixel in 8-bit display codes, with the share of
pixels past 2 and past 8. A session's first screenshot differs from every later one by a fixed few
thousand pixels and was discarded. A screenshot stalls the GPU, and the GTX downclocks for seconds
after it -- a frame sampled then read up to 60 % slow -- so every screenshot at a pose was taken
after its timing, never between samples.

**Reaching the Intel.** Godot exports `NvOptimusEnablement = 1` and
`AmdPowerXpressRequestHighPerformance = 1`, so on a hybrid laptop every OpenGL run -- ANGLE
included -- lands on the discrete GPU. The Intel runs use a copy of the executable with those two
exports patched to 0, which Windows then puts on the iGPU. Vulkan takes `--gpu-index`; which index
is the Intel varies, so read the adapter back (the run's log names it). A Forward+ run records its
GPU's type in `user://override.cfg`, and a later Compatibility run's graphics tier follows that
record, so back the file up around a run that switches GPU.

**The run's own state.** Any Assistant-driven run rewrites the cached startup view on quit, and one
that forces settings rewrites the settings cache, so both were copied aside and restored. A setting
written just before quit can be lost (the cache is written by a worker task), and a number that
arrives as JSON is a float, which the cache drops for an int setting at the next start.

### A view's cost depends on the view before it

**Pin the star bins in any frame A/B.** A drawn star bin hides once its brightest star falls below
half a display code and returns only above one, and for a faint bin, whose peak is its glare wing,
that gap is about 3.5 EV. So at a settled exposure, which bins draw depends on the exposure the
camera *arrived* with. The Moon at 3 radii through ANGLE on the Intel costs 14.1 ms on a first
visit and 20.4 ms after the camera has been to Titan or Jupiter, at the same settled exposure: five
bins, 537,000 stars. The Planetarium's `ProbeExposureSuite` pins them with `set_exposure_skips`
and reads them back with `get_exposure_skips`; taking every build through the same poses in the
same order is the alternative.

### Compile time

`addons/tools/time_shader_compiles.py`, in the [tools](https://github.com/ivoyager/tools)
submodule, run from the project directory:

```
python addons/tools/time_shader_compiles.py                  # every shader
python addons/tools/time_shader_compiles.py surface atmosphere_limb
python addons/tools/time_shader_compiles.py --renderer forward_plus
python addons/tools/time_shader_compiles.py --driver opengl3_angle --godot <patched exe>
```

It generates a throwaway Godot project holding a copy of the Core's shaders and the host project's
`[shader_globals]`, and times one shader per process: the frame in which a fresh material first
draws (five programs, *Specializations*) and the frame after its light is hidden (one more). Its
module docstring carries the traps it encodes: one process per shader, since a driver can leak
work from one compile into the next frame; a uniquely named uniform appended, since a comment does
not change the GLSL Godot hashes; the whole directory copied, since a runtime `Shader` has no path
for relative includes to resolve against.

`--driver opengl3_angle` compiles through the ANGLE and D3D11 libraries Godot ships, the path a
browser takes on Windows. Reaching a weak GPU is the separate step above; the flag alone gets ANGLE
on the discrete part, which for FXC's share of the time hardly matters, since that is CPU work.

**To A/B an edit before making it**, copy the shaders directory, edit the copy and time both with
`--shaders-dir`, **one run at a time**: a compile is CPU-bound, a second process compiling alongside
can double a figure, and of a pair run together the shorter finishes under the load while the
longer runs alone. Two compiles of the same code still differ by up to about 13 %.

**A cold start in the app** needs novel source for every shader -- a uniquely named uniform
appended to each Core `.gdshader` -- with Godot's `shader_cache` (and so `EGL`) and its `vulkan`
pipeline cache set aside, and both restored afterwards. Engine shaders and the
`StandardMaterial3D` shaders of spacecraft models still hit the driver's own cache that way, which
is a fraction of a second. **To prove the warm-up's coverage**, parse the `.cache` files Godot
rewrites for every new specialization: `GLSC`, u32 version 3, u32 variant count, then per variant
a count and per program a u64 specialization key, whose bit order is the `#[specializations]` list
in `drivers/gles3/shaders/scene.glsl`. Snapshot them after the warm-up and after a flight, and diff
the keys. Godot's `--print-fps` finds a stall but hides one under a second and cannot attribute it.

The frame and screenshot suites, the cold-start driver and the atmosphere's entry-point probe (which
writes the include's outputs as raw floats over a grid of geometries, and times them) are session
scripts, not yet in the tools submodule.


## Caveats

- **One machine.** Treat ratios and orderings as the finding and milliseconds as this laptop's. A
  newer integrated GPU (Iris Xe, Radeon 680M) is several times faster than this UHD but shares its
  fragment-bound shape; which shader is expensive to compile is a property of each vendor's
  compiler, and the orderings above are NVIDIA's and FXC's.
- **The resolution of a relief figure** is a few percent through ANGLE and the GTX's GL, and 5-10 %
  under Vulkan, whose frames wander more on both GPUs; a comparison across sessions, as for Min,
  Off and the star cuts, carries up to about 10 % through the GTX's GL and 25 % through its Vulkan,
  which is why the GTX's Vulkan star-cut column reads above 1.0 at the Moon, Saturn and Earth,
  where the cut drops little or nothing.
- **Through ANGLE the figure is the frame interval**, which includes the CPU's share and can only
  overstate the GPU's; on the GTX a frame interval is mostly the CPU's.
- **Not measured**: any browser; the Mobile renderer; Intel's own GL driver today; the frame rate
  cap's pacing and energy; the sphere LOD ladder's relief on its own. Figures carrying an earlier
  date were measured on the code of that date and not taken again.

## TODO

- **Warm the spacecraft's materials.** The first sight of Juno after a cold boot stalls 11 s through
  ANGLE and 1.5 s through NVIDIA's GL: its model's `StandardMaterial3D`s are not in
  `IVGlobal.resources`, so `IVShaderWarmup` never draws them.
- **Glow under Forward+ costs 20-50 % of an airless frame on both GPUs and changes no pixel in most
  lit views.** A skip while nothing in view exceeds the glow threshold would be a saving with no
  option, as the exposure skips are; it needs the frame's brightest source, which the exposure
  metering may already know.
- **Sunspot level of detail by disc size** (*Levers not offered*).
- **85 % render scale** bought nothing measurable in the airless views on either native path;
  measure it at an atmosphere view before keeping the step.
- **Measure a first web visit in a real browser** on a weak machine, Chrome and Firefox (*The web
  export*).
- **Render scale through ANGLE** waits on the engine's scaled depth copy (*3D render scale*).
- **Intel's newer parts and drivers**: the ANGLE switch assumes every Intel GPU prefers ANGLE, on
  the evidence of this UHD alone.
