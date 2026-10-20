# Graphics Profiling

This document records the measured graphics performance of this plugin on a weak machine. It
covers two kinds of cost:

- **Frame time**: GPU time per frame, and how much each graphics option and each automatic
  optimization reduces it.
- **Shader compile time**: a one-time cost, paid when a shader program is first drawn. Under the
  Compatibility renderer, and so in the web export, compiling blocks the main thread.

These measurements are the basis for the graphics options, the fitted defaults and the length of
a first web visit. The document holds measurements only. The models behind them are in
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) and [VISUAL_MODEL.md](VISUAL_MODEL.md), and each
section here names the one it depends on.

**All figures were measured in the [Planetarium](https://github.com/ivoyager/planetarium) on one
laptop** (*The reference machine*) on 2026-09-29, with Godot 4.7.2 and ivoyager_core v0.2.1.dev
(8001cf3), unless a figure gives its own date. The figures depend on the Planetarium's
configuration: its scale, its camera poses, and above all its light stack, which has no shadow maps
under Compatibility (`apply_gl_compatibility_shadows` off) and has the empty-shadow-pass skip on.
That stack was one light when measured. On 2026-10-13 it was replaced by three unshadowed
size-domain lights, which compile the same programs and showed no change in frame time (GTX,
native GL, 3 poses). The ratios and orderings are the general result; the milliseconds apply to
this laptop only. A project configured differently should measure again before relying on a row
(*How this was measured*).

Two terms are used throughout:

- **Relief**: the GPU time an option saves, as a percentage of that view's frame time.
- **Visual cost**: the change in the rendered image, in 8-bit display codes, between screenshots
  taken before and after the change at the same frozen exposure.


## The short version

1. **On the Intel iGPU, atmospheres are the bottleneck.** At Core's defaults in a 1080p window,
   every view with an atmosphere runs at 6-16 fps through ANGLE (the web export's path, and
   Compatibility on any Intel GPU) and at 2-7 fps under Forward+ (the desktop default). Every view
   without an atmosphere runs at 16-54 fps. The GTX runs every view at 60 fps or better.
2. **The options that help most on the Intel:**
   - **Atmosphere quality.** Off reduces an atmosphere view's frame time to 0.24-0.49 of Normal's
     through ANGLE and 0.14-0.22 under Forward+; Min to 0.46-0.80 and 0.44-0.76. Reduced saves
     8-22 % through ANGLE and almost nothing under Forward+.
   - **Star catalog**, through ANGLE, which emulates each star's point sprite: cutting the catalog
     to V 11 saves 45 % of a dark-sky frame.
   - **Render scale**, on a native driver: 50 % saves 33-75 %. Through ANGLE a reduced scale adds
     time instead, so it is held at 100 %.
   - **MSAA off** saves 5-24 % on every path.
3. **At its fitted defaults the Intel runs every view at 25-33 fps under Forward+**, except Earth
   close up at 15, with atmospheres and glow Off. A browser cannot detect its GPU's type, so it also
   gets atmospheres Off, which removes the limb even on a fast GPU. The GTX at its fitted defaults
   runs every view at 70 fps or better.
4. **A first run through ANGLE spends about 90 s compiling shaders** at Min or Normal, against 36 s
   through NVIDIA's GL and 7-9 s under Vulkan, nearly all of it behind the boot screen. Off, the tier
   a first web visit gets, compiles about a third less. The packed models' materials add 20 s
   through ANGLE. After the warm-up no view stalls to compile. No single shader program comes near
   Chrome's 30-second GPU watchdog.
5. **The automatic optimizations save as much as the options do.** The exposure skips save 15-53 %
   of a lit frame through ANGLE; the airless shader variants save 14-23 % there and 76-83 % under
   Intel's Vulkan; the empty-shadow-pass skip saves 7-22 % of an Intel Forward+ frame.
6. **Glow under Forward+ costs 20-50 % of an airless frame on both GPUs**, but in most lit views it
   changes no pixel; it only draws bloom around crescents and small bright bodies. The Low tier
   turns it off. Skipping the pass while nothing in view is bright enough to bloom would remove its
   cost at Full and Reduced too (TODO).


## The reference machine

A Dell XPS 15 9500: an i7-10875H, Intel UHD Graphics (Comet Lake GT2, 24 EU, driver
31.0.101.2137) and a GTX 1650 Ti (driver 581.95), with a 3840x2400 panel at 250 % display scale,
on mains power. Godot 4.7.2. Its two GPUs give four render paths. A Planetarium user on a similar
machine uses one of them:

| Path | Who draws with it | Frame time from |
|---|---|---|
| **Intel, ANGLE** | Every browser on Windows, and the desktop Compatibility renderer on any Intel GPU | Frame interval (ANGLE has no GPU timestamps) |
| **Intel, Vulkan** | The desktop default, Forward+, on an integrated GPU | GPU time |
| **GTX, Vulkan** | The desktop default on a discrete GPU | GPU time |
| **GTX, GL** | The desktop Compatibility renderer on a discrete GPU | GPU time |

- **The Planetarium runs Compatibility through ANGLE on every Intel GPU.** It adds one
  `{"vendor": "Intel", "name": "*"}` entry to Godot's defaults in
  `rendering/gl_compatibility/force_angle_on_devices`. Godot's own list already forces ANGLE on
  Intel "HD Graphics" and Iris of Gen 7 to 9.5 by name, but not on "UHD Graphics" (the same Gen 9.5
  silicon, renamed) or Iris Xe. The setting is the project's, not Core's; Core only reads the result
  (`IVGraphicsManager.is_angle_d3d11()`). The reasons are in *Renderer*.
- **A browser on this laptop uses the Intel, ANGLE path.** Chrome on Windows compiles WebGL through
  ANGLE's D3D11 backend, and on a hybrid laptop the browser runs on the integrated GPU unless
  configured otherwise. No browser was measured (*Caveats*); the desktop ANGLE path uses the same
  translation, from Godot's own ANGLE build.
- **The Planetarium never uses Intel's own GL driver**, so it is not measured here. Core alone does
  not force ANGLE, so a project that keeps Godot's defaults will run UHD and Iris Xe GPUs through
  Intel's GL; *Renderer* gives the cost.


## Where the frame goes

GPU milliseconds per frame (the frame interval through ANGLE) at Core's defaults -- Normal
atmospheres, 100 % render scale, MSAA 2x, glow on, 4096 shadows, the whole star catalog -- in a
1920x1080 window. The budgets are 16.7 ms for 60 fps and 33.3 ms for 30.

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

- **Atmospheres are too expensive for a weak GPU.** On the Intel, every view with an atmosphere
  runs at 6-16 fps through ANGLE and 2-7 fps under Forward+, while every view without one runs at
  16-54 fps (*Atmosphere quality*).
- **Through ANGLE, stars are the other large cost.** The dark-sky views take 60 ms through ANGLE
  and 36 ms on the same Intel under Vulkan. D3D11 has no point sprites, so ANGLE emulates them, and
  the 2.55 million stars cost it about four times what they cost through Intel's own GL (*Star
  catalog*).
- **On the GTX every view runs at 60 fps or better.** Its slowest views are Earth close up and
  Titan, at 9-13 ms. Its problem is a dense screen: this laptop's panel has 4.4 times the pixels of
  a 1080p frame (*What the fitted defaults deliver*).

The views: each body in `tracking: "ground"` at longitude 90, latitude 10 (Earth at 1.6 radii at
longitude 45, Saturn at latitude 20). At the frozen date this shows most of the disc of Earth,
Venus and Mars, a crescent of Titan and the Moon, and only a thin backlit crescent of Jupiter
against the dark-adapted sky, which makes the Jupiter pose a star-field view. Juno is posed
through `VIEW_ZOOM`, and the two wide views through their own table rows, the Asteroids view
keeping the points it shows. Star bins drawn, identical on every path: 12, 11, 8, 14, 22, 18, 24,
20, 0, 18, 24 and 24 of 24.


## What the fitted defaults deliver

Frame times on this laptop at a plain launch: the fitted defaults (*Fitted defaults*), in the
window the Planetarium opens (1152x648 at the screen's 250 % display scale, so 2880x1620), with the
render scale fitted to the whole 3840x2400 screen. Figures are milliseconds of frame interval,
which is what a user sees; on the GTX that is CPU time, the GPU time being shorter. The Intel
columns were measured on 2026-09-30, with glow off at Low (*Glow* gives the saving). A browser on
this laptop uses the Intel, ANGLE column's path and settings:

| View | Intel, ANGLE | Intel, Vulkan | GTX, Vulkan | GTX, GL |
|---|---:|---:|---:|---:|
| Tier; settings | Low: Off, 100 %, MSAA off, no glow, V 11 | Low: Off, 50 %, MSAA off, no glow, V 11 | Reduced: Reduced, 70 %, 2048 | Reduced: Reduced, 70 % |
| Earth at 1.6 radii | 145 | 66 | 11.8 | 12.3 |
| Earth at 3 radii | 64 | 40 | 8.2 | 7.7 |
| Venus at 3 radii | 39 | 33 | 7.6 | 7.3 |
| Mars at 3 radii | 35 | 33 | 10.8 | 9.0 |
| Titan at 3 radii | 30 | 34 | 13.9 | 10.7 |
| The Moon at 3 radii | 30 | 30 | 6.6 | 6.6 |
| Jupiter's night side, dark sky | 39 | 35 | 8.4 | 9.2 |
| Saturn at 3 radii | 49 | 40 | 10.2 | 10.1 |
| The Sun at 3 radii | 46 | 35 | 6.1 | 6.1 |
| Juno close up | 20 | 32 | 8.6 | 8.9 |
| Whole system, dark sky | 31 | 30 | 7.3 | 6.0 |
| Asteroid belt | 33 | 31 | 7.8 | 6.1 |

- **The GTX runs every view at 70 fps or better** at its fitted tier.
- **The Intel runs every view at 25-33 fps under Forward+**, the desktop default, except Earth close
  up at 15. These frames are limited by the CPU as much as the GPU: the GPU takes 18-28 ms of them.
- **Through ANGLE the Intel is slower in most views and faster at Titan and Juno**, with the window
  drawn at full size: 16-33 fps with an atmosphere and 20-49 without, and Earth close up at 7. So
  the Intel does better in Forward+ at its fitted defaults, which is what it runs unless its user
  changes it (*Renderer*).
- **A browser window can be any size.** The one measured here has 2.25 times the pixels of the
  1080p frames above, and render scale is held at 100 % there. At Min the same path takes 75-257 ms
  in the atmosphere views. That is why a browser, whose GPU type is unknown, is fitted with
  atmospheres Off (*Fitted defaults*).


## The options

Relief at 1920x1080 relative to Core's defaults, as a range over the views where the option has an
effect; views where it has none are left out rather than averaged in. Each figure comes from an
off, on, on, off block within one session (*How this was measured*), except for options that need a
restart, which are compared across sessions.

| Option | Intel, ANGLE | Intel, Vulkan | GTX, Vulkan / GL | Visual cost |
|---|---|---|---|---|
| **Atmosphere quality** (air views) | Reduced -8 to -22 %; Min -20 to -54 %; Off -51 to -76 % | Reduced 0 to -16 %; Min -24 to -56 %; Off -78 to -86 % | Vulkan: Off -24 to -74 %, Reduced to -31 % and Min to -42 % away from Earth; GL: Reduced -10 to -37 %, Min -5 to -55 %, Off -37 to -86 % | Reduced: a few pixels at the limb. Min: crescent cusps and Mars' twilight. Off: no limb |
| **3D render scale** 70 % / 50 % | held at 100 % | -12 to -47 % / -33 to -75 % | Vulkan -12 to -42 % / -33 to -70 %; GL 50 %: -27 to -68 % | Softer lines and labels; at 50 % the star field coarsens |
| **Renderer**: Compatibility against Forward+ | 1.4-3.7x faster in air views, 1.5-1.7x slower in star-heavy ones | -- | GL 1.1-1.4x slower in air views, 1.5-2.2x faster in airless ones | Compatibility loses hover identification of orbits and asteroids, FXAA, TAA and local shadow maps |
| **Star catalog** V 11 / V 9.5 (star-heavy views) | -16 to -45 % / -33 to -67 % | -13 to -28 % / -22 to -41 % | Vulkan -15 to -34 % / -25 to -53 %; GL -13 to -34 % / -26 to -50 % | None in lit views; a dimmer diffuse glow at V 11 and a sparser sky at V 9.5 in dark ones |
| **Glow** off (airless views) | -7 to -19 % | -19 to -37 % | Vulkan -33 to -51 %; GL -17 to -44 % | The bloom around a crescent or a small bright body; under Compatibility also a brighter dim end |
| **Shadow resolution** (near a craft; Forward+) | -- | Off -25 %, 2048 -15 %, 8192 +96 % | Vulkan: Off -8 %, 2048 -1 %, 8192 +3 % | Spacecraft self-shadowing only |
| **MSAA** off / 4x / 8x | -8 to -20 % / +4 to +13 % / +17 to +34 % | -5 to -24 % / +3 to +20 % / +19 to +42 % | Vulkan -5 to -28 % / +6 to +10 % / +21 to +46 %; GL -7 to -17 % / +3 to +12 % | Off: stair-stepped lines and craft edges |
| **FXAA** (Forward+) | -- | 0 to +7 % | +5 to +12 % | Smoother lines, slightly softer |
| **TAA** (Forward+) | -- | +25 to +75 % | +30 to +51 % | Ghosts orbit lines |
| **Frame rate cap** | not measured | not measured | not measured | Motion only |

### Atmosphere quality

`atmosphere_quality` has four tiers. Normal and Reduced share one shader program and change live.
Min and Off each have their own programs, bound when bodies are built, so changing into or out of
them takes a restart. What each tier omits, and how, is in *Atmosphere quality, and what Reduced,
Min and Off give up* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md). Each tier's frame time as a
fraction of Normal's (from the first table):

| View | Intel, ANGLE: R / Min / Off | Intel, Vulkan | GTX, Vulkan | GTX, GL |
|---|---|---|---|---|
| Earth at 1.6 radii | 0.92 / 0.80 / 0.49 | 1.01 / 0.76 / 0.14 | 0.98 / 0.80 / 0.75 | 0.90 / 0.95 / 0.63 |
| Earth at 3 radii | 0.81 / 0.64 / 0.35 | 0.94 / 0.76 / 0.17 | 1.19 / 1.13 / 0.76 | 0.79 / 0.78 / 0.39 |
| Venus at 3 radii | 0.82 / 0.65 / 0.41 | 0.84 / 0.59 / 0.22 | 0.79 / 0.82 / 0.56 | 0.63 / 0.61 / 0.35 |
| Mars at 3 radii | 0.79 / 0.46 / 0.24 | 0.95 / 0.56 / 0.14 | 0.83 / 0.80 / 0.44 | 0.78 / 0.57 / 0.18 |
| Titan at 3 radii | 0.78 / 0.54 / 0.31 | 0.93 / 0.44 / 0.15 | 0.69 / 0.58 / 0.26 | 0.70 / 0.45 / 0.14 |

An airless view has the same frame time in every tier, within noise. The GTX's Vulkan figures at
Earth are within that path's noise (*How this was measured*), which is why Reduced and Min read
above 1.0 there.

- **Through ANGLE, Off brings every atmosphere view on the Intel down to 24-85 ms.** It is the
  fitted default on a known integrated GPU and in every browser.
- **Under Forward+ on the Intel, Reduced saves almost nothing**, because that compiler's cost
  depends on a shader's structure rather than its node count. Min saves a quarter to a half, and
  Off more than four fifths, raising every atmosphere view from 2-7 fps to 11-34.
- **Reduced's visual cost is a few pixels at the limb**: at most 14 codes, over at most 1.8 % of the
  frame, at every pose measured. Min's and Off's are larger and specific (Earth's crescent cusps and
  Mars' twilight at Min, everything beyond the limb at Off) and are measured in
  [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md).
- **Min and Off each compile their own programs.** This is what lets a first web visit, at Off,
  compile no quadrature at all (*What each shader costs*).

### 3D render scale

`render_scale`: 100, 85, 70 or 50 % of the window's pixels, upscaled with FSR 1 on Forward+ and
bilinear on Compatibility; the 2D GUI stays at full resolution. It saves only per-pixel work, so it
saves least where the vertex stage or a fixed-size pass dominates: the star field, the asteroid
points, glow.

| View | Intel, Vulkan: 70 % / 50 % | GTX, Vulkan | GTX, GL: 50 % |
|---|---|---|---|
| Earth at 1.6 radii | -47 / -75 % | -41 / -70 % | -68 % |
| Titan at 3 radii | -41 / -56 % | -34 / -57 % | -61 % |
| Saturn at 3 radii | -31 / -52 % | -27 / -47 % | -32 % |
| The Moon at 3 radii | -15 / -39 % | -17 / -42 % | -38 % |
| Whole system, dark sky | -18 / -35 % | -12 / -35 % | -32 % |

- **85 % saves nothing measurable** in the airless views (-6 to +7 %); 70 % is the first step with
  a real saving.
- **The visual cost is resolution.** Orbit lines, names and body edges soften. The star field
  changes because each star is a PSF drawn in render pixels and then upscaled: at 50 % on the GTX,
  78 % of a dark sky's pixels change by more than 2 codes, and 11 % of an Earth or Mars view's.
- **Core clamps the frame before FSR**, which Godot 4.7.2 no longer does, at no measurable cost.
  Sharpening the unclamped frame drew dark specks and coloured centres in saturated light (*FSR 1
  sharpens what it is handed* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)).
- **Both builds render at physical pixels** (`display/window/dpi/allow_hidpi`). A laptop at 2x
  display scale renders four times the pixels of its logical window size, so on such a screen 50 %
  costs the same as 100 % on a 1x screen. The fitted defaults use it for that.
- **Through ANGLE's D3D11 backend a reduced scale adds time**, so the option is hidden and the scale
  held at 100 % there (`IVGraphicsManager.can_scale_render()`). Below 100 %, Godot 4.7.2's GLES3
  renderer ends each frame by stretching the depth and stencil buffer into the full-size target
  (`glBlitFramebuffer` in `rasterizer_scene_gles3.cpp`). D3D11 has no stretching copy for depth and
  stencil, and ANGLE appears to do it on the CPU, adding a roughly fixed 25-40 ms to every Intel
  frame and about 20 ms to every GTX frame at any scale below 100 % (2026-09-28). The web export
  uses the same renderer through the same translation. Three workarounds were considered and
  rejected: patching the engine (custom export templates, web included, until fixed upstream);
  turning off `allow_hidpi` for the web build (the browser would then stretch the GUI too); and
  rendering the 3D view into a smaller SubViewport (moving the camera, picking, the 3D HUD and
  screenshots into another viewport to work around one driver's missing copy).

### Renderer

`renderer`, desktop only, applied at restart: Forward+ or Compatibility. Forward+ is the default
everywhere, fitted or not, because Compatibility loses mouse-over identification of orbit lines
and asteroid points (`IVFragmentIdentifier` removes itself there), FXAA and TAA, and local shadow
maps. The rendered image matches to within a few codes. `IVGraphicsManager` writes the choice to
the file named in `application/config/project_settings_override`, which the engine reads at the
next start. A Forward+ run also records the GPU's type there, because a Compatibility run cannot
read it (`IVGlobal.video_adapter_type`). From the first table:

- **On the Intel, Compatibility (through ANGLE) is faster in every atmosphere view**, by 1.4-3.7
  times, and also faster at the Sun and Juno. Forward+ is 1.5-1.7 times faster in the star-heavy
  views, where ANGLE emulates point sprites. With atmospheres Off the two take about the same time
  for the air. At the fitted defaults (atmospheres Off, Forward+ at 50 % and Compatibility held at
  100 %) Forward+ is faster in all but two views (*What the fitted defaults deliver*).
- **On the GTX, Forward+ is faster in atmosphere views** (Earth close up in 9.1 ms against 12.7)
  and Compatibility in airless ones, where both are well within any budget.

**The Planetarium runs Compatibility through ANGLE on every Intel GPU** (*The reference machine*).
The reasons, measured on 2026-09-28 with both drivers from one build on the UHD at 100 % render
scale:

- ANGLE's frame time is 0.62-0.85 of Intel's own GL at Earth, Venus and Mars, the same at Titan,
  and 1.1-1.9 times as long in airless views, where the star field's point sprites cost about four
  times as much through ANGLE.
- **Intel's GL driver (31.0.101.2137) does not draw Saturn's rings at all**; ANGLE draws them as
  the GTX does (TODO in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)).
- On a first run, FXC takes several times as long as Intel's GL to compile the atmosphere shaders
  (*What each shader costs*); ANGLE caches them afterwards, in `shader_cache/EGL`.

### Star catalog

`star_catalog`, applied at restart: the whole catalog (2.55 million stars to V 15.4), 942,063 stars
to V 11, or 216,622 to V 9.5; `IVStarsVisual` loads a cut catalog as fewer magnitude bins. Each
view's frame time as a fraction of the whole catalog's:

| View | Intel, ANGLE: V 11 / V 9.5 | Intel, Vulkan | GTX, Vulkan | GTX, GL |
|---|---|---|---|---|
| Jupiter's night side, dark sky | 0.59 / 0.40 | 0.87 / 0.78 | 0.85 / 0.75 | 0.87 / 0.74 |
| Saturn at 3 radii | 0.84 / 0.67 | 1.03 / 0.95 | 1.09 / 1.00 | 1.05 / 0.97 |
| Whole system, dark sky | 0.56 / 0.33 | 0.74 / 0.59 | 0.66 / 0.47 | 0.68 / 0.50 |
| Asteroid belt | 0.55 / 0.35 | 0.72 / 0.60 | 0.67 / 0.54 | 0.66 / 0.52 |
| The Moon at 3 radii | 1.00 / 0.82 | 1.02 / 0.98 | 1.15 / 1.10 | 1.09 / 1.02 |
| Earth at 3 radii | 0.98 / 0.97 | 0.97 / 0.98 | 1.24 / 1.25 | 0.95 / 0.95 |

- **Through ANGLE this is the second-largest saving**, since ANGLE emulates every star's point
  sprite. V 11 alone takes the dark-sky views from 60 to 33 ms on the Intel.
- **In a lit view it saves little, because the exposure skips already drop the faint bins**: at
  Earth the skip has dropped 13 of 24 bins, including all of those V 11 removes.
- **The visual cost is in the dark sky only.** In lit-body views the cut stars are already below
  the exposure. In a dark-adapted wide view V 11 dims the diffuse glow of the faint end, and V 9.5
  visibly empties the sky. A cut also saves memory and load time: the catalog is about 51 MB of
  vertex data whole, 19 MB to V 11 and 4 MB to V 9.5, built by single-threaded GDScript in
  0.7-1.1 s, 0.26-0.40 s and 0.07-0.10 s on this CPU.

### Glow

`glow`: the engine's bloom pass, on by default. It applies live on Forward+ and at the next start on
Compatibility, where it determines whether the scene shaders tonemap (*Specializations*). It draws
bloom around overexposed objects that no PSF quad covers, such as a spacecraft, a small moon or a
crescent's rim (*Glow: the bloom pass* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)). Each
view's frame time with glow off, relative to on:

| View | Intel, ANGLE | Intel, Vulkan | GTX, Vulkan | GTX, GL |
|---|---:|---:|---:|---:|
| Earth at 1.6 radii | 0 % | +5 % | -24 % | -7 % |
| Venus at 3 radii | -5 % | -6 % | -25 % | -10 % |
| The Moon at 3 radii | -16 % | -37 % | -51 % | -36 % |
| Jupiter's night side, dark sky | -7 % | -28 % | -33 % | -18 % |
| Saturn at 3 radii | -8 % | -19 % | -33 % | -19 % |
| The Sun at 3 radii | -8 % | -24 % | -40 % | -20 % |
| Juno close up | -19 % | -34 % | -45 % | -44 % |
| Whole system, dark sky | -7 % | -27 % | -37 % | -17 % |

- **Its share is largest where the rest of the frame is cheap**: 20-50 % of an airless frame under
  Forward+, and little in an atmosphere view on the Intel. Through ANGLE, whose frames are
  expensive everywhere, it is 7-19 %.
- **Under Forward+ its only visible effect is on crescents and small bright bodies.** Turning it off
  changed no pixel by more than 2 codes at Earth at 3 radii, Venus, Mars, Titan, Saturn or the Sun;
  0.3-1.7 % of the pixels at Earth close up, Juno and the whole system; and 6.6 % of the Moon's
  crescent view and 7.9 % of Jupiter's, by up to the full range.
- **Under Compatibility, turning it off also restores the dim end**, which the pass crushes there:
  in the dark-sky views over three quarters of the pixels change, by 4-5 codes on average, and at
  Saturn 31 % change, by 2.
- **The Low tier turns it off** (*Fitted defaults*). It saves more there than at Core's defaults,
  because the rest of a Low frame is cheaper. Against glow on in the same session it saved 9-15 %
  of every Intel frame under Forward+ at 50 % scale, about 5 ms of GPU time, and 13-30 % through
  ANGLE at full size, except 5 % at Earth close up (2026-09-30). Full and Reduced keep it on,
  because the GTX's fitted frames have room for it (*What the fitted defaults deliver*).

### Shadow resolution

`shadow_resolution`: Off, 2048, 4096 or 8192. In the Planetarium it has an effect on Forward+
only, where shadow maps are used only for spacecraft-scale local shadows; eclipses, ring shadows
and transits are analytic and unaffected. **With the empty-shadow-pass skip, the resolution
matters only when a spacecraft or a local scene is in reach**: at Saturn, 8192 changed nothing. At
Juno close up:

| | Off | 2048 | 8192 |
|---|---:|---:|---:|
| Intel, Vulkan | -25 % | -15 % | +96 % |
| GTX, Vulkan | -8 % | -1 % | +3 % |

The atlas is 16, 64 and 256 MiB at 2048, 4096 and 8192; Off frees it (*The light configuration*).

### MSAA

`msaa_3d`: off, 2x (Core's default), 4x or 8x. Planet rims do not need it, since the surface
shaders already render each rim pixel through the camera's PSF. Lines do: orbit lines, ring edges,
spacecraft. Turning it off changes 0.02-0.2 % of a body view's pixels and 2.8 % of the Asteroids
view's (its orbits and points) by more than 2 codes. From the options table: off saves 5-28 %, and
8x adds 17-46 %, on every path.

### FXAA, TAA and Frame rate cap

**FXAA** (Forward+) is cheap line smoothing. **TAA** (Forward+) adds 25-75 % to a frame and leaves
ghost trails on the orbit lines, which are positioned in the vertex shader. It remains available
for a user who wants it, off by default.

**Frame rate cap** (`frame_rate_cap`): None, 60 or 30 fps, applied live as `Engine.max_fps`. None
keeps the cap the engine started with (`application/run/max_fps` or `--max-fps`). The cap saves
energy when frames are faster than the cap and nothing when they are slower. Godot enforces a cap
in software (a sleep on the desktop, skipped animation frames in a browser), so 30 on a 60 Hz
display may not pace evenly. Neither pacing nor energy is measured.

**Physical Light** is not a performance option. Turning it off keeps the unmetered exposure, so
every star draws at full size, and frames took up to 35 % longer (2026-09-10).


## Fitted defaults

`IVSettingsManager.graphics_target` is `NONE` by default, which applies Core's graphics defaults as
written. If a project sets `BROAD_HARDWARE` or `MODERN_GPU` (the Planetarium sets
`BROAD_HARDWARE`), those defaults are replaced at each start by the values
`IVGraphicsManager.get_fitted_defaults()` returns for the machine. A default the project sets
itself applies on every machine. Only defaults change: a user's own choice is cached and kept, and
Restore Defaults returns to the fitted values.

The tier is chosen from two things Godot reports before anything is drawn: the GPU's type and the
screen's physical pixel count (`IVGraphicsManager.get_graphics_tier()`):

| | Full | Reduced | Low |
|---|---|---|---|
| Machine | Discrete GPU, screen up to 6 MP | Discrete GPU, screen past 6 MP | Any other GPU, or one of unknown type, as in every browser |
| Atmosphere quality | Normal | Reduced | Off on an integrated GPU and in a browser; on a desktop GPU of unknown type, Min through ANGLE's D3D11, else Reduced |
| 3D render scale | 100% | Largest within 4.7 MP | Largest within 2.7 MP |
| MSAA | 2x | 2x | Off |
| Glow | On | On | Off |
| Shadow resolution | 4096 | 2048 | 2048 |
| Star catalog | All | All | To V 11 |

- **The renderer is not fitted.** Forward+ stays the default wherever it runs. Compatibility loses
  mouse-over identification of orbit lines and asteroids, which should be the user's choice to
  give up, and at Low's defaults Forward+ is faster on this Intel anyway (*Renderer*). The running
  renderer becomes the default only where the engine fell back from Forward+ or the command line
  chose another. `MODERN_GPU` hides the option.
- **Screen size is used as a proxy for GPU class.** Godot reports no memory size or model tier, and
  a laptop with two GPUs reports its discrete one (here, the GTX). What makes such a GPU
  struggle is a dense panel: at 3840x2400 it renders 4.4 times the pixels of a 1080p frame. The
  6 MP threshold keeps a 1440p or 3440x1440 desktop at Full and puts 4K and the denser laptop
  panels at Reduced. A fast GPU on a 4K monitor is also rated Reduced, and loses little by it.
- **Render scale is fitted to a pixel budget** rather than set in fixed steps: 4.7 MP puts a 4K or
  3840x2400 screen at 70 %, and 2.7 MP keeps a 1920x1200 screen at 100 % and puts 4K at 50 % (the
  same cost as 100 % on a 1x screen). It stays at 100 % on ANGLE's D3D11 path, where any reduction
  adds time.
- **Reduced atmospheres and 2048 shadows have no visible cost**, so a discrete GPU on a dense
  screen gets them too.
- **Low uses atmospheres Off on a known integrated GPU**, the only tier that makes an atmosphere
  close-up usable there: under Forward+ on this Intel, Reduced saves almost nothing and Min still
  takes 480 ms at Earth close up at 1080p (*Atmosphere quality*). **A browser also gets Off**,
  although its GPU's type is always unknown, for three reasons: a fast GPU loses only the limb,
  which its user can restore in Options; Min through this Intel's ANGLE takes the atmosphere views
  to 75-257 ms (*What the fitted defaults deliver*); and a first visit at Off compiles 57 s of
  programs against Min's 82 s (*What each shader costs*). **A desktop GPU of unknown type keeps the
  limb**, since it may be fast: it gets Min through ANGLE, where Min is the faster tier, and Reduced
  elsewhere, because Min ran slower than Normal at Earth through Intel's own GL (2026-09-28).
- **MSAA off, glow off and V 11 are used only at Low**, since each changes what a user sees:
  stair-stepped orbit lines, no bloom around a crescent or a small bright body, and a dimmer diffuse
  star glow in dark-sky views. Under Compatibility, glow off also restores the dim end the pass
  crushes there, so a browser loses less by it than a Forward+ desktop does (*Glow*).

On this laptop the GTX is rated **Reduced** (70 %, Reduced atmospheres, 2048 shadows) and the
Intel **Low**, with atmospheres and glow Off, at 50 % under Forward+ and 100 % through ANGLE. A
browser on this laptop gets Low, with atmospheres Off at 100 %. *What the fitted defaults deliver*
gives the frame times for each.

## A setting the machine can't carry

A graphics setting too heavy for a machine can leave its user unable to reach Options to undo it.
Options applies a change immediately but saves it only on Confirm Changes, so a live change that
crashes or freezes the app is discarded at the next start. That does not cover three cases:

- **A restart option is confirmed before its cost is visible.** Atmosphere quality into or out of
  Min or Off, Star Catalog and Renderer take effect only at the next start.
- **A confirmed setting can work in the view where it was tried and fail in another.** The
  Planetarium reopens the last view at every start, so a view that brings a machine down does so on
  every start.
- **A crash, a GPU reset or a lost WebGL context produces no frames at all**, and a web user has no
  practical way to clear the site's storage.

`IVCoreSettings.enable_graphics_rescue`, on by default outside editor builds, handles each case:

- **A start that never finishes resets the next one.** Before anything is drawn,
  `IVSettingsManager` marks the start unfinished in `start_marker.ivbinary`, beside the settings
  cache. It marks it finished after 10 s of running simulator, a quit or a window close. A start
  that finds the previous one unfinished restores `IVSettingsManager.graphics_settings` to the
  fitted defaults, if any differ, and IVGraphicsRescue tells the user why. A crash at a restored
  view recurs within those 10 s, so a crash loop repeats at most once. The false positive is a start
  ended from outside in its first seconds, by a killed process or a closed tab, which resets the
  user's graphics choices with a notice. Editor builds are excluded because stopping a run from the
  editor is exactly that case. A deliberate restart or reload that skips `IVStateManager.quit()`,
  such as the Planetarium's web-app update, calls `IVSettingsManager.mark_start_finished()` first.
- **A very slow frame rate triggers an offer.** IVGraphicsRescue asks, once per session, whether to
  restore the fitted defaults when more than half the frames over 10 s take longer than 250 ms and
  a graphics setting differs from its default. 250 ms indicates a machine near the limit of
  usability, and the changed setting indicates a choice beyond the fitted values. Frame time alone
  is not enough, since this laptop's Intel already takes 157 ms at Earth close up at its fitted
  defaults through ANGLE (*What the fitted defaults deliver*), and a weaker GPU takes longer. Frames
  drawn while a popup is open, while Options holds an unconfirmed change, or while the boot or
  splash screen is up are not counted; the last condition keeps the warm-up's compile stalls from
  triggering the offer.
- **A reset on request.** The user argument `--reset-graphics` restores the fitted defaults on any
  start. The Planetarium's web page passes it for a URL ending in `#reset-graphics`. On a lost WebGL
  context, where Godot's own page says only to reload and the same settings would likely lose the
  context again, the page offers a reload with the reset.


## Savings that need no option

Each of these removes work whose result never reaches the screen, so it is always on. Where one has
a switch for A/B testing, its relief is measured on current code; one without a switch carries the
date it was measured.

### The exposure skips

Under physical light, the background panorama is not drawn, and a star magnitude bin is not
submitted, while the compensating camera's exposure puts it below half a display code
(`IVWorldEnvironment.skip_invisible_starmap`, `IVStarsVisual.cull_invisible_bins`; *Skipping what
the camera has metered away* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)). Half a code is the
8-bit rounding boundary, so a skip changes any pixel by at most one code; at every pose here it
changed none. The saving, as a percentage of the frame time with the skips on:

| View | Intel, ANGLE | Intel, Vulkan | GTX, Vulkan |
|---|---:|---:|---:|
| Earth at 1.6 radii | 15 % | 0 % | 24 % |
| Earth at 3 radii | 23 % | 8 % | 18 % |
| Venus at 3 radii | 35 % | 0 % | 17 % |
| Mars at 3 radii | 23 % | 3 % | 14 % |
| Titan at 3 radii | 4 % | 0 % | 5 % |
| The Moon at 3 radii | 53 % | 28 % | 33 % |
| Saturn at 3 radii | 25 % | 11 % | 17 % |

Nothing is skipped in a dark-adapted view, where exposure is at rest, or with physical light off.
Through ANGLE, which emulates every star's point sprite, the skips save more in lit views than any
option except atmosphere quality. At Earth the skip leaves 11 of 24 bins, 15,641 of 2,551,210
stars.

### Empty shadow passes

Under the opt-in `IVCoreSettings.apply_empty_shadow_pass_skip`, a shadow-mapped `IVDynamicLight`
clears `shadow_enabled` while nothing in its reach would draw into its map or read from it (*Local
shadow maps* in [VISUAL_MODEL.md](VISUAL_MODEL.md)). The Planetarium turns it on. There it has an
effect only on Forward+, since its Compatibility lights have no maps. It changes nothing on screen:
a map with no caster and no receiver in reach contributes nothing. The saving, as a percentage of
the frame time with the skip on:

| View | Intel, Vulkan | GTX, Vulkan |
|---|---:|---:|
| The Moon at 3 radii | 22 % | 7 % |
| Jupiter's night side | 17 % | 0 % |
| The Sun at 3 radii | 17 % | 2 % |
| Whole system, dark sky | 14 % | 3 % |
| Juno close up | 7 % | 0 % |

At Juno the near light keeps its map for the craft's self-shadowing and only the middle light's
map is skipped; at Saturn at 3 radii a moon stays in reach and nothing is skipped. The skip is
opt-in because of its effect on shader compiling: *`directional_shadow_count` stops being a
constant*.

### Airless shaders

A body with no atmosphere draws with an `.airless` variant of its disc shader, which compiles the
atmosphere code to no-ops (THE AIRLESS VARIANT in `_atmosphere.gdshaderinc`;
`IVAssetPreloader.airless_shader_variants`). The full shader would render such a body identically,
with its atmosphere switched off at runtime, but on some compilers code that never runs still costs
frame time (*What drives the cost*). In the Planetarium every body except Earth, Venus, Mars and
Titan uses an airless variant. The saving, against the full shaders bound to the same bodies in the
running app:

| View | Intel, ANGLE: full / airless | Intel, Vulkan |
|---|---|---|
| The Moon at 3 radii | 28.5 / 21.8 ms (-23 %) | 103 / 23.8 ms (-77 %) |
| Europa at 3 radii | 38.6 / 31.2 ms (-19 %) | 114 / 23.5 ms (-79 %) |
| Neptune at 3 radii | 60.6 / 49.3 ms (-19 %) | 216 / 37.0 ms (-83 %) |
| Jupiter's night side | 61.1 / 52.6 ms (-14 %) | 118 / 27.8 ms (-76 %) |

Under Forward+ on the Intel, the full shader makes an airless body's frame four to six times as
long. On the GTX the airless variants saved 5-42 % through NVIDIA's GL and up to 18 % under Vulkan
(2026-09-27). They add nothing to a first visit's compile time: an airless program compiles in a
third of the time of a full one (*What each shader costs*). The Off tier's closed-form veil is an
exact no-op for a body with no air, so it could have been included in the airless variants,
sparing Off its own programs. But it added about 4.5 s to every airless program through ANGLE, and
every first visit compiles those in every tier, so Off has separate variants instead.

### The limb annulus

The limb shell draws only a camera-facing ring of its sphere, from two pixels inside the disc's
handoff band out to the shell's silhouette (`limb_annulus_mesh`; *Atmospheres* in
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)). Every limb fragment over the disc's interior would
be discarded, because the surface and cloud shaders composite that air themselves. On Intel's GL
driver a discarded fragment was not cheap: a limb shader that discarded at its first statement
still cost twice as much as one with a dead-code body, and branching around the body recovered only
3-6 %. So the only way to save that cost was not to generate those fragments. Measured when it was
built (2026-09-11, Intel's own GL): it saved 19-54 % of an atmosphere frame, at no compile cost and
with no visible change beyond single rim pixels that any change of tessellation moves.

### Level of detail, and shells nobody can see

- **The sphere LOD ladder.** A body with no mesh of its own selects a shared sphere mesh each frame
  by on-screen size, from 256x128 down; each level serves every body whose silhouette error stays
  within 0.15 px (*The sphere LOD ladder* in [VISUAL_MODEL.md](VISUAL_MODEL.md)). A fixed 128x64
  sphere was indistinguishable at 1.6 radii but not closer: at the ISS, framing Earth's horizon, it
  changed 2.4 % of pixels by more than 2 codes. Its relief has not been measured separately.
- **Culling on true bounds, and the handoff gates.** While a body lies within a quarter of the
  camera's far plane, its shells drop the farwarp box and cull and select their mesh LOD on their
  own bounds (`IVFarwarpManager.true_bounds_far_fraction`). A body handed off to its PSF point stops
  drawing its shells (`IVShellsModel.cull_handed_off`), and rings stop at their own handoff
  (`IVRings.cull_handed_off`) (*Farwarp* and *Culling, visibility and lifecycle* in
  [VISUAL_MODEL.md](VISUAL_MODEL.md)). Most of what these remove is the 65,000-triangle meshes of
  Ceres and the moons, which were previously drawn off screen in every view. Through ANGLE on the
  Intel (2026-09-29) they saved 2.2-7.4 ms, 2-16 % of a frame, at nine poses from the Moon to the
  whole system. On screen, a sub-pixel moon is now culled at 4000 radii, and Ceres's own mesh
  changes 6 cusp pixels.

### Proximity sleep

`IVBodyProximityMonitor` sleeps a `can_sleep` body (every moon, by default) while it draws nothing
and shows no HUD. That takes it out of its own `_process` and out of every per-body loop that skips
a hidden body (*Culling, visibility and lifecycle* in [VISUAL_MODEL.md](VISUAL_MODEL.md); the rule
is derived in §9.4 of [IVBody_REDESIGN_v0.3.md](IVBody_REDESIGN_v0.3.md)). The 16 planetary-mass
moons never sleep, since each draws a point of light at any distance. Every other moon draws nothing
past its distance cull at 4000 radii, and sleeps there unless one of its HUDs could show: a name,
symbol or orbit switched on for its group, Hide All off, and its orbit wide enough to be visually
separate from its planet at the camera's distance (`IVBody.min_visual_separation_multiplier`, 100
times the orbit). The monitor judges all of this from the planet's distance, with margins, since a
sleeping moon's own position goes stale. So sleep saves the most where those HUDs cannot show: with
moon HUDs switched off or under Hide All, all 161 sleep at Earth, and at the whole-system view they
sleep whatever the switches. With the default switches, names and orbits on for both moon groups, a
moon stays awake wherever its orbit is separable: 96 of the 161 at Earth.

A sleeping moon would not have drawn: with every moon awake a frame submits the same draw calls and
objects, and its GPU time is unchanged within the noise, so what sleep saves is main-thread CPU
time. Measured on 2026-10-17 in release exports at each path's fitted defaults, with the default
HUD switches (*Main-thread CPU time*, below), against every moon held awake:

| View | Moons awake with sleep, of 177 | Intel, ANGLE: CPU saved | GTX, Vulkan: CPU saved | GTX frame, with sleep / all awake |
|---|---:|---:|---:|---:|
| Earth at 3 radii (`VIEW_HOME`) | 112 | 0.7 ms | 0.9 ms | 5.6 / 6.3 ms |
| Jupiter at 200 radii (`VIEW_MEDIUM`) | 116 | 0.4 | 0.8 | 5.9 / 6.8 |
| Saturn at 1.2 au (`VIEW_FAR`) | 115 | 0.4 | 1.2 | 5.7 / 7.2 |
| Whole system (`VIEW_SYSTEM`) | 16 | 0.9 | 1.1 | 5.0 / 5.6 |

- **An awake moon nobody can see costs 6-14 µs a frame**: 3-4 µs in its own `_process`, the rest in
  the farwarp, exposure, occlusion and monitor loops. The saving reaches the frame only where the
  CPU limits it. Through ANGLE the Intel is GPU-bound at 21-26 ms and its frame interval does not
  move; the GTX's frame is the CPU's, and all moons awake lengthen it by 11-26 %.
- **`IVSunOcclusionManager` feeds only the shells the renderer draws**, and that is what keeps an
  awake moon this cheap. Until it skipped a body whose shells are all past their distance cull
  (b716d97 fed them), every moon awake meant feeding about 48 such moons, each testing its planet
  and siblings as occluders: 1.3-2.1 ms of a frame on either path. Under sleep the skip saves at
  most 0.16 ms (Jupiter).
- **The monitor costs 0.13-0.27 ms a frame**, under 1 % of an Intel frame through ANGLE: 11-15 µs
  for the bodies it holds awake, 5-8 µs for the banded sleep sweep, and the rest the per-body pass
  that sets HUD visibility and pushes mouse targets. About 0.1 ms of that pass is the 23 bodies that
  never sleep, and each awake moon adds about 1 µs, so banding the pass by distance as the sweep is
  banded could save at most about 0.1 ms.

**The moon HUDs the default switches show cost more than the monitor does.** `visual_groups.tsv`
turns names and orbits on for both moon groups, and at a `min_visual_separation_multiplier` of 100
their HUDs keep 45-99 moons awake that would sleep with moon HUDs off:

| View | Moons kept awake | Draw calls added, ANGLE / Forward+ | Intel, ANGLE: frame | GTX: render CPU / GPU |
|---|---:|---|---:|---|
| Earth at 3 radii | 96 | 206 / 294 | +1.9 ms | +0.37 / +0.61 ms |
| Jupiter at 200 radii | 45 | 198 / 288 | +1.7 | +0.38 / +0.64 |
| Saturn at 1.2 au | 99 | 158 / 238 | +1.8 | +0.34 / +0.35 |
| Whole system | 0 | 0 | 0 | 0 |

Through ANGLE that is about 8 % of the frame, with the render CPU up 1.1-2.0 ms; waking the moons
costs 0.2-0.7 ms of script time. Halving `min_visual_separation_multiplier`, to 50, would leave
about 40 % fewer moons separable from Earth.

**Against v0.2's rule**, which slept every moon outside the camera's planet system, a frame at Earth
costs 1.9 ms more through ANGLE and 1.0 ms more on the GTX, nearly all of it moon HUDs v0.2 never
drew. At Jupiter, Saturn and the whole system the two rules cost within 0.5 ms of each other
through ANGLE.


## Levers not offered

Each of these was measured and left out of the options, for the reason given.

- **Cloud decks.** Removing Earth's and Neptune's cloud decks saved 6-7 % of an Intel frame at Earth
  and 22-26 % of a GTX frame (2026-09-10), and changes a fifth of an Earth view's pixels. Suitable
  for a lowest tier at most.
- **Sunspot detail.** The photosphere's sunspot cells took 36 % of an Intel frame at the Sun close
  up (2026-09-10). A level of detail by disc size would remove most of that without an option; not
  built.
- **The number of asteroids.** Each asteroid costs more than a star, since the points shader solves
  Kepler's equation for every one every frame. But there are 1/32 as many as stars: all 80,569 take
  3-5 % of an Intel frame and 6-10 % of a GTX frame, even in the Asteroids view. The cost is in the
  vertex stage and is paid whenever a group is shown, since a group is never frustum-culled (its
  farwarp bounds contain every place the camera can go). With the star field drawn, showing them
  cost nothing on the Intel, because they cover star sprites and that GPU is fragment-bound. No cut
  could save more than those 3-5 %, so how many a project loads remains the project's choice
  (`mag_cutoff`, `IVCoreSettings.sbg_mag_cutoff_override`).
- **A runtime tier below Reduced.** Normal and Reduced are one program that selects a rule from a
  packed node table, so a lower rule would add no compile. But the ring cannot go below two taps:
  one tap produces exactly the dotted arc the pixel filter exists to close, and moves the limb by
  60-100 % of its maximum. Two nodes change the disc's air by 18 % at Earth. Three nodes with two
  taps saves 9-16 % of the atmosphere's own cost, while changing the disc's air up to five times as
  much as Reduced does. A tier cheaper than Reduced has to compile less code, which is what Min and
  Off do.
- **Star sprites as quads.** D3D11 has no point sprites, so ANGLE emulates `gl_PointSize`, and the
  star field costs about four times as much through ANGLE as through Intel's own GL. Drawing each
  star as two triangles instead costs twice as much as the points through ANGLE, because four
  vertex shader runs per star cost more than the emulation. So the star field stays as points.
- **A glare-wing or Milky Way toggle.** The glare wing draws the faint end of the star field;
  removing it saves 11-25 % of a star-heavy Intel frame but changes half of a dark sky by 10 codes.
  The Milky Way is already skipped automatically wherever exposure hides it (*The exposure skips*),
  which covers every view where drawing it cost time without changing the image.


## Compiling shaders

The Compatibility renderer compiles a shader program **at its first draw, synchronously, on the
main thread** (*Specializations*), so compile time appears as stalled frames. Shaders drawn by the
warm-up and the opening view compile behind the boot screen; any they miss stall the app later, in
flight. Forward+ compiles its pipelines in a background thread and draws with an ubershader in the
meantime, so it spends a fraction of the time and shows it as slower frames rather than stalls. The
web export compiles on every first visit, because it has no program-binary cache (*Where the
caches are*).

### What a first run costs

Time from launch to the end of the boot screen at each row's settings, in a 1920x1080 window. Cold:
every Core shader's source made novel and Godot's caches set aside. Warm: the same run repeated.

| Path, tier | Cold | Warm | Compiling | of which the opening view | the warm-up |
|---|---:|---:|---:|---:|---:|
| Intel, ANGLE, Low (Off, no glow) | 64 s | 9 s | 55 s | 25 s | 27 s |
| Intel, ANGLE, Min | 97 s | 10 s | 88 s | 48 s | 35 s |
| Intel, ANGLE, Normal | 107 s | 10 s | 97 s | 54 s | 39 s |
| GTX, GL, Reduced | 48 s | 12 s | 36 s | 21 s | 13 s |
| GTX, Vulkan, Reduced | 23 s | 16 s | 7 s | 7 s | 0.3 s |
| Intel, Vulkan, Reduced | 21 s | 13 s | 9 s | 7 s | 0.4 s |

- **Through ANGLE a first run spends about 90 s compiling at Min or Normal**, nearly all of it in
  FXC on the CPU, so a slower CPU takes proportionally longer regardless of the GPU. A first web
  visit on this laptop uses that path at Low's settings: its 55 s matches the 57 s sum of its
  programs (*What each shader costs*), and was the same with glow on (2026-09-30). The browser's
  own ANGLE build may differ (*The web export*).
- **The opening view used to be one frame.** Its first draw compiled every shader in view (51 s
  through ANGLE, 26 s through NVIDIA's GL) in a single frame, so the boot screen could not show
  progress. The warm-up now holds the opening view back until the warm-up's own steps have drawn
  (*The warm-up*). The table's two right-hand columns predate that change; both are now spent in
  warm-up steps.
- **After the warm-up nothing stalls.** A tour of every kind of body after a cold boot (Earth,
  Venus, Titan, Mars, the Moon, Phobos, Jupiter, Saturn, Neptune, the Sun, Juno and both wide views)
  drew no frame over 0.3 s, and under Vulkan no frame stalled. A visit to each of the twelve bodies
  with a packed model after a cold boot drew no frame over 90 ms through ANGLE or 15 ms through
  NVIDIA's GL, and compiled no program the warm-up had not (2026-09-30).
- **The packed models' materials take 20 s of the warm-up through ANGLE at Low, and 1.5 s through
  NVIDIA's GL** (2026-09-30, measured with seven material keys; there are six now). The table's
  warm-up column predates them. They compile per material key, not per model: Godot generates one
  shader per `BaseMaterial3D` key (`_compute_key()` in `material.h`) and shares it between
  materials. The twelve bodies (seven spacecraft, Hyperion, Eros, Bennu, Itokawa and Arrokoth)
  share six keys, about 3 s each through ANGLE. The seventh key, 3.3 s through ANGLE, had emission
  on with nothing emitted: Godot's glTF importer enables emission for any `emissiveFactor`,
  `[0, 0, 0]` included, and Hubble's two panels, the ISS's base metal, Hyperion, Bennu and Arrokoth
  had one until it was removed from the assets. Without the warm-up of packed models
  (`warm_packed_models = false`), Juno's four materials stall its first appearance for 11 s through ANGLE
  and 1.5 s through NVIDIA's GL.
- **A warm start compiles nothing.** Godot's cache supplies the programs, with the driver's cache
  beneath it; the warm-up then takes one frame per shader, 0.3-1.5 s in total.

### What each shader costs

Seconds to compile a shader's first draw, which is five programs (*Specializations*), from
`time_shader_compiles.py`, one shader per process, through ANGLE (FXC, on this CPU) and through
NVIDIA's GL. Each further specialization takes about a sixth of the first draw's time through
ANGLE and an eighth through GL.

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
| `body_psf` | 1.3 | 0.8 |
| `stars`, `path`, `farwarp_vertex` and the id shaders | 0.3-0.5 | 0.3-0.4 |

Total compile time in the Planetarium, summed over the shaders a session draws:

| Tier | The four air bodies' programs | The whole session |
|---|---:|---:|
| Normal (and Reduced) | 60 s / 25 s | 92 s / 37 s |
| Min | 50 s / 19 s | 82 s / 31 s |
| Off | 24 s / 8 s | 57 s / 20 s |

(ANGLE / NVIDIA GL.) The sums match the in-app cold starts, apart from the engine's own shaders
(*What a first run costs*).

- **An atmosphere shader takes three times as long to compile as its airless variant**, and the
  atmosphere shaders are what make a first visit long. Off compiles no quadrature and no limb
  shader, which is why it is the tier for a first load. Min has less code than Normal, and its
  programs compile a sixth faster.
- **No single program comes near a browser's watchdog.** The heaviest through ANGLE is about 3.6 s
  (`band_pattern`'s 18.0 s first draw averaged over its five programs, and its 3.2 s further
  specialization), against Chrome's 30 s limit (*The web export*).
- **Through ANGLE the time is spent in FXC, on the CPU**, before any driver sees the shader: the
  Intel and the GTX agreed to within 13 % when both were timed through ANGLE (2026-09-27). Every
  ANGLE figure scales with CPU speed, whatever the GPU.
- **Forward+ stalls little on any of them**: a first draw's frame takes 0.2-2.7 s and a further
  specialization no stall, the rest of the work going to a background thread while an ubershader
  draws. Its whole first run compiles in 7-9 s (*What a first run costs*).
- **Intel's own GL is not measured here** (*The reference machine*). Its compiler was several times
  faster than FXC on the atmosphere shaders (23 s against 90 s for the atmosphere set, 2026-09-28).

### What an edit costs

Editing a file invalidates every shader that includes it, so the recompile cost is the sum over
the shaders that include it and that a session draws. For the Planetarium's Normal session, at
most:

| Edited file | Shaders in a session | ANGLE | NVIDIA GL |
|---|---:|---:|---:|
| `_farwarp`, `_display`, `_point_spread_function`, `_sun_occlusion` | 9-16 | 86-92 s | 33-37 s |
| `_atmosphere.gdshaderinc` | 8 | 82 s | 32 s |
| `_detail.gdshaderinc`, `_photometry.gdshaderinc` | 8 | 73-74 s | 28 s |
| `_detail.cube.gdshaderinc` | 4 | 43 s | 16 s |
| One disc body include (`_surface.cube` and the rest) | 2 | 19-24 s | 7-9 s |
| `_atmosphere_limb.gdshaderinc` | 1 | 10 s | 5 s |

A variant's own include affects only that variant: `_atmosphere.min.gdshaderinc` invalidates the
six `.min` shaders, `_atmosphere.off.gdshaderinc` the five `.off` ones, and an edit inside
`_atmosphere`'s `ATM_AIRLESS` exclusion none of the airless variants. Timing every shader in the
plugin, all variants, takes about 240 s through ANGLE and 95 s through NVIDIA's GL. With the
warm-up in place, all of an edit's recompile happens behind the next Compatibility run's boot
screen.

### What drives the cost

Compile time does not depend on source length, or on whether a shader is lit or `unshaded`:
`body_psf.gdshader` is among the longest sources in the plugin and among the cheapest to compile.
It depends on the code the compiler has after inlining and unrolling, and the optimizer's time
grows faster than that code's size. Each compiler here enlarges the source in its own way.

- **Native GL unrolls a loop whose trip count is a compile-time constant**, inlines whatever the
  loop body calls, and then optimizes the result. So every loop in the atmosphere, the sun's
  sunspot cells and the photometry's limb kernel has an opaque `uniform int` bound
  (`iv_atm_gl_first`, `iv_atm_gl_nodes`, `atm_shell_nodes`, `iv_atm_ring_max_taps`,
  `spot_cell_reach`, `limb_kernel_cells`, `atm_min_disc_points` and others) set to the value a
  constant would have. With constant bounds the limb shader compiled six times slower through
  AMD's GL driver. Making only the outer loop's bound a uniform was not enough; the inner loops are
  the ones that must not unroll.
- **FXC, ANGLE's compiler on Windows, inlines every call**, so a function is compiled once per call
  site. It unrolls loops with constant and uniform bounds alike, so the opaque bounds do not help
  there. The cost came from the atmosphere calling its heaviest functions from dozens of places:
  through ANGLE on this CPU its six shaders took 808 s in total to their first draws, and one limb
  program took over a minute, past Chrome's GPU watchdog. Giving each heavy function one call site
  brought the total to about 100 s (2026-09-27; *The atmosphere's structure*, below).
- **An include costs nothing for functions the shader does not call.** `rings.gdshader` includes
  `_photometry.gdshaderinc`, whose limb kernels are two sixteen-cell loops of exactly the expensive
  kind, but calls neither, so they never reach the optimizer. An include alone says nothing about
  a shader's compile cost.
- **Compile time depends on code size, not iteration count.** A four-node quadrature compiles no
  faster than the six-node one, since the bound is opaque either way. A tier that must compile
  faster has to leave code out, which is why Min and Off have their own programs and Reduced does
  not.

### Writing a shader that compiles

- **Don't hand-unroll.** A loop written out by hand gives the compiler the same code that unrolling
  would, and removes the chance that it won't unroll. Where a trip count is a constant of the
  algorithm, write the loop and make the bound a uniform.
- **`while` loops and dynamic bounds are fine.** GLSL ES 1.00, the WebGL 1 profile that Godot 3's
  GLES2 renderer targeted, restricted loops to constant bounds, and old comments still warn about
  it. Godot 4 has no such target: the web export builds with `-sMAX_WEBGL_VERSION=2`, the
  Compatibility renderer emits `#version 300 es`, and `shader_compiler.cpp` passes `while`, `do`
  and `for` through unchanged. One runtime concern does apply: a divergent trip count costs every
  lane in a group the maximum, so keep trip counts uniform across neighbouring fragments.
- **Don't call a heavy function from a second place.** Each call site is a separate copy after
  inlining, just as a written-out loop is. Write the second use as another iteration of a loop the
  first use already runs.
- **On some compilers, code that never runs still costs frame time.** Intel's compilers size a whole
  shader for its heaviest part. An airless body drawn with the full surface shader, with the
  atmosphere switched off at runtime, takes four to six times as long under Intel's Vulkan as with
  the atmosphere compiled out, and a fifth longer through ANGLE. Through Intel's GL, a disc
  shader's air in front of the disc ran twice as fast in a shader containing nothing else of the
  ray. So a body with no atmosphere binds an `.airless` variant that compiles the atmosphere to
  no-ops (*Airless shaders*, above), and each tier with different code binds variants of its own.

### The atmosphere's structure

**Every heavy function in `_atmosphere.gdshaderinc` has one call site**, inside a loop (THE
STRUCTURE in its header):

- `atm_exp_columns()` evaluates an exponential column's terms in a loop, so it contains one call to
  the Chapman function, where a haze's branches would otherwise write out up to seven slants.
- `atm_ray_path()` integrates a whole view ray as one loop over its segments, so one quadrature
  node, `atm_node()`, serves the lit part in front of a disc, both halves of a tangent ray and every
  thin-layer crossing.
- A node's view and sun columns, and the thin layer's partial columns, each come from one loop.
- `atm_receiver_light()` hands a surface or cloud shell everything it takes from the air above it
  -- the view tint, the sun transmittance, and the plane-parallel diffuse the twilight subtracts --
  from one loop of two columns, four for a cloud deck.
- The limb shader integrates the handoff band's disc-hit ray as one more pass of the ring's tap
  loop.

The rule: add a new term as a new loop iteration, not a new call. The Min variant relaxes it:
`atm_min_point()` has one call site per segment kind, two in the limb shader, and a Min program
still compiles faster through FXC than its full counterpart (*What each shader costs*).

**One exception is for frame time, not compile time.** Under Forward+ and Mobile only,
`atm_exp_columns()` writes out the common case (a haze with no top: Earth's, Venus' and Mars')
because NVIDIA's Vulkan runs the term loop a third slower than two written-out terms. Under
Compatibility the two extra calls slow the whole shader by 11-33 % through Intel's GL, airless
bodies included, while ANGLE runs the written-out form 23-33 % faster. The preprocessor cannot tell
those two drivers apart, so Compatibility keeps the loop.

**The same source runs at a different speed through every compiler.** Giving each heavy function
one call site changed the atmosphere's own frame cost, evaluated alone over a grid of geometries,
by a factor of 0.8 through NVIDIA's GL, 1.0-1.3 through Vulkan, 1.3-1.5 through ANGLE and anywhere
from 0.12 to 2.9 through Intel's GL (2026-09-27). Measure a change to a shader's structure on every
path before keeping it. A change that is mathematically exact has measured anywhere from 10 %
faster to 15 % slower on Intel, depending on the view.

### Specializations

A shader's compile time always covers more than one program. From `drivers/gles3/shader_gles3.cpp`
and `rasterizer_scene_gles3.cpp` in the 4.7.2 source:

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
  first frame drawn with `BG_SKY`, and only a radiance-size change or the Sky's release frees it, so
  a session's first sky frame gives every scene shader a new key. In the Planetarium that frame
  falls in the start sequence, when `IVWorldEnvironment` adds the starmap on `assets_preloaded`,
  about a second before the warm-up, so every program compiled during the start and the warm-up
  carries the bit. The risk is `skip_invisible_starmap`, which turns the sky off while exposure
  has metered it black. If the skip engaged before the sky's first draw, the warm-up would compile
  every shader without the bit, and the first view dark enough to show the Milky Way would compile
  everything on screen again, in flight.
- **Glow determines where Compatibility tonemaps.** With the pass on, the scene and sky passes leave
  tonemapping to a post pass and every scene and sky shader drops `APPLY_TONEMAPPING`, so every
  program differs between glow on and off. That is why the Glow option needs a restart there.
  `time_shader_compiles.py` draws with no Environment, so it times the glow-off programs; a cold
  start takes the same compile time with either (*What a first run costs*).
- **Compiling is synchronous.** `glLinkProgram` is followed at once by the `GL_LINK_STATUS` query;
  there is no use of `KHR_parallel_shader_compile`, and the queue-and-use-defaults branch is an
  `if (false)` TODO. Nothing short of an engine patch changes that.

### The light configuration

The number of programs a lit shader compiles depends on the lights that reach it. Under
Compatibility, `IVCoreSettings.apply_gl_compatibility_shadows` sets that:

| `apply_gl_compatibility_shadows` | color programs per lit shader | depth programs | what can still compile in flight on a first visit |
|---|---|---|---|
| `true` (Core's default) | 3 | +1 (`RENDER_SHADOWS`) | the middle size domain's, which the default `warm_radii` never reach |
| `false` (the Planetarium) | 1 | 0 | nothing |

With shadows on, `dynamic_lights.tsv` gives Compatibility the far sun light (unshadowed, cull
`0b0001`) and the shadowed middle (`0b0010`) and near (`0b0100`) lights, so
`directional_shadow_count` is 2 and every lit instance is drawn twice; across the two larger size
domains the additive clearing above yields three color programs, and anything close enough to
count as terrain adds the depth pass. With shadows off the same three lights carry no maps, so
`directional_shadow_count` is 0 and `uses_additive_lighting` false: one pass, no additive, PSSM or
PCF bits and no shadow pass. The base pass takes its unshadowed light count as a uniform and tests
each light's cull mask per fragment, so **every lit body in every size domain binds the same
program**, and a first visit cannot reach a specialization the warm-up missed.

Turning shadows off has two other effects. `update_directional_shadow_atlas()` runs only under
`if (r_directional_shadow_count)`, so with no shadowed light the depth atlas is never allocated;
and `IVGraphicsManager` skips `directional_shadow_atlas_set_size()` on that path, which is safe
because the allocation is lazy. The visual loss is local shadow maps: spacecraft self-shadowing,
crater walls on a lander. The analytic astronomical shadows (rings, eclipses, transits, and the
camera-fraction dimming that carries them onto craft) work either way.

#### `directional_shadow_count` stops being a constant

`IVCoreSettings.apply_empty_shadow_pass_skip` (*Empty shadow passes*, above) clears a shadowed
light's `shadow_enabled` while nothing in its reach would draw into its map or read from it, so
under a shadowed light stack the count can be 2, 1 or 0. The count is a per-frame value, so each
value needs its own set of programs for **every lit shader**, compiled synchronously on the first
frame that uses it, and a warm-up covers only the value it runs at. **That, not frame time, is why
the skip is opt-in.** Under Compatibility, where its frame-time relief is small, it moves some
compiling from behind the boot screen to stalls in flight, in exchange for a Forward+ saving.
Without Compatibility shadow maps it has no effect there, which is why the Planetarium can turn it
on.

Where the risk applies, four things limit it. The setting is off by default. Changes of the count
are kept rare: enabling is immediate, disabling waits 120 frames, and the enable and disable
thresholds are 1.25 and 2.0 times the reach. `IVShaderWarmup` registers the camera its quads are
attached to through `IVDynamicLight.add_local_shadow_geometry()`, with every domain bit and the
caster bit, so the warm-up still compiles the count the app runs at. Warming every reachable count
instead would multiply the warm-up's length to prevent stalls most projects never hit. Finally, a
project that does measure stalls can couple the two shadowed lights into one decision, reducing
the reachable counts from three to two at the cost of the receiver half of the test.

The Shadow Resolution option's Off (`IVDynamicLight.shadow_maps_enabled`) holds the count at 0
until a resolution is chosen again. That is a user action rather than a camera move, and the
warm-up covers whichever state the session starts in. According to `light_storage.cpp`, for both
renderers, nothing frees the depth atlas when the count returns to zero; only
`directional_shadow_atlas_set_size()` with a different size does. So when the skip toggles, the
existing atlas is reused, and Off also sets the size to 256 (the engine setting's minimum, and a
size no option uses), which frees any atlas and allocates nothing while no map is drawn. On
Forward+ on the GTX, texture memory falls by 64 MiB from 4096 to Off and by 16 MiB from 2048. The
size is not set to 0, which the engine uses only at teardown: a shadowed light drawn at size 0 has
no atlas framebuffer, and the Compatibility renderer divides by that size.

### The warm-up

`IVShaderWarmup` (`program/shader_warmup.gd`) draws spatial shaders on a small quad in front of the
camera, one shader per frame, then each packed model's materials, one model per frame. It draws
each once at a planet-scale layer and once at a craft-scale layer carrying the shadow-caster bit;
together these reach the base, additive and shadow specializations that bodies use. It is opt-in,
added to `IVCoreInitializer.program_nodes` from a preinitializer. Its `progress_changed` signal is
emitted one frame before the draw that stalls, so the text a handler sets stays on screen during
the stall. It runs once per session.

**It draws only the shaders the project will bind.** A body's shell shaders come from the specs
`IVAssetPreloader` resolved at load, with the cubemap, airless, Min and Off substitutions already
applied, so each spec names the shader that will actually be bound. The scene tree cannot supply
this, because a body's visual is built only when the camera first visits it, and that is the
stall the warm-up prevents. The rest of Core's shaders are added under the same conditions
`IVBodyFinisher` and `IVSBGFinisher` use to add the node that binds each one: a body with rings, a
body with an orbit, `IVBodyPSF.is_applicable_to_any_body()`, a `small_bodies_groups` row not
flagged `skip` (and its `lp_integer` for the Lagrange variant), and `IVFragmentIdentifier` for the
id overlays, which removes itself under Compatibility. In the Planetarium that is 15 shaders under
Compatibility and 17 under Forward+:

- `photosphere`, `body_psf`, `rings`, `path`, `farwarp_vertex`, `orbiting_positions_id` and
  `orbiting_positions_lp_id`, plus `path_id` and `instance_id` under Forward+;
- the four atmosphere bodies' `atmosphere_limb`, `surface.cube` (Earth, Mars), `band_pattern`
  (Venus, Titan) and `cloud_shell.cube` (Earth); in a Min session their `.min` variants, and in an
  Off session the `.off` variants of the last three and no limb;
- the airless `surface.cube`, `surface`, `band_pattern` and `cloud_shell.cube` that every other body
  with a shader binds.

A shader whose use no such condition can determine is deliberately not warmed, since an
unnecessary compile adds seconds to the boot screen. `stars_shader` is the one Core shader in that
position: `IVStarsVisual` is a scene node, so nothing in the tables says whether a project kept it.
Add it, and a project's own shaders, to `extra_shader_names` (the Planetarium adds it). A shader
left out compiles at the opening view's first draw, still behind the boot screen but not counted in
its progress. `warm_core_shaders = false` turns the automatic selection off.

**A packed model's materials are not shaders in `IVGlobal.resources`**, so they are read from an
instance of the scene `IVAssetPreloader` loaded, which shares them with the model built on a first
visit. Each distinct model is one step, named for the first body that uses it; in the Planetarium
that is 11 models for 12 bodies, the two Voyagers sharing one. Six of those steps compile nothing,
because those models share material keys with earlier ones (*What a first run costs*).
`warm_packed_models = false` turns these steps off.

**The trigger sets when it runs.** `SIMULATOR_STARTED`, the default and the Planetarium's choice,
draws in the real scene, so the quads reach the specializations bodies actually use. It cannot
usefully run earlier, since `IVCamera` does not process before the simulator starts, and a quad a
metre in front of it rounds to nothing at a heliocentric float32 position. `ASSETS_PRELOADED`, for
a project with a splash screen and `wait_for_start = true`, adds its own camera and one unshadowed
light. That reaches the scene-independent part of each shader (the four variants at the default
mask, more than half of a first draw's compile time) and leaves the scene's own specializations to
compile at a body's first draw. With either trigger the warm-up holds `IVStateManager` until
`finished` (`show_splash_screen` true under `SIMULATOR_STARTED`, `ok_to_start` false under
`ASSETS_PRELOADED`), so a boot or splash screen shown at those points covers it with no extra
wiring. `MANUAL` and `warm_up()` are for a project that wants to choose the moment itself.

**It holds back the opening view.** The camera's first draw is a single frame that compiles every
shader in view, and a frame cannot report its own progress. So under `SIMULATOR_STARTED`
(`hold_opening_view`) the camera draws only `hold_layer`, from `system_tree_built` (the frame that
adds the camera) until the warm-up steps are done. The quads carry that layer bit, and so does every
`Light3D` for the duration, because the camera's cull mask culls a light by the light's own layers
(`renderer_scene_cull.cpp`) and the quads must be lit as bodies are; shadow casters are filtered by
the same mask. The warm-up then releases the view and gives the opening view `SETTLE_FRAMES` to
draw before it releases the boot screen, so anything the steps missed still compiles behind the
screen. A game load or an exit that cancels the warm-up leaves the hold on, since the outgoing
camera still draws before it is freed, and the next `system_tree_built` moves the hold to the new
camera for the retry. Cold, on the GTX through ANGLE at Reduced (2026-10-14), the frames before
the first step went from 63 s of compiling to 0.6 s; the warm-up's own time rose from 60 s to
126 s, and the opening view's draw after it took 31 ms. The cold start as a whole took the same
time within run-to-run noise (135 s against 132-140 s).

**Why two radii.** `warm_radii` resolve to layers `0b0001` and `0b0100`, the second carrying the
shadow-caster bit. Under a shadowed light stack the second is needed for that bit, the only way to
reach the `RENDER_SHADOWS` depth program. Neither lands in the middle domain (`0b0010`,
0.1-100 km), so its additive specialization compiles in flight on a first visit to a small moon.
Without shadow maps both radii select the same program, and the second quad costs a frame but no
compile.

### The web export

The web export is the Compatibility renderer running on the browser's WebGL 2, which on Windows is
ANGLE's D3D11 backend and FXC. A first-time visitor has no cache Godot can use (*Where the caches
are*). So a first visit on a machine like this one compiles what *What a first run costs* measures
through ANGLE, at the fitted Off tier: 57 s of programs (*What each shader costs*), all of it
behind the boot screen. A repeat visit on the same Chrome profile compiles nothing.

**Chrome's GPU watchdog** kills the GPU process, and every WebGL context with it, when its main
thread spends too long in one task: 30 s on Windows, 25 s on macOS and 15 s elsewhere
(`kGpuWatchdogTimeout`, `gpu/ipc/common/gpu_watchdog_timeout.h` in Chromium), and on Windows up to
four such periods when the thread was waiting rather than working. Godot queries each program's
link status as soon as it links, so the time to compare against the limit is one program's
compile, not a frame's: at most 3-4 s through ANGLE here (*What each shader costs*). When the
context is lost, the Planetarium's page offers a reload into the fitted defaults (*A setting the
machine can't carry*).

**ANGLE compiles every shader at its highest optimization level.** Its D3D11 backend asks FXC for
`D3DCOMPILE_OPTIMIZATION_LEVEL2`, retrying with validation and then optimization skipped only when a
compile fails (`Renderer11::compileToExecutable`), and adds `D3DCOMPILE_IEEE_STRICTNESS` to a
shader that calls `isnan()`. A page has no way to request a cheaper compile. A shader can only
control how much code FXC sees after inlining (*What drives the cost*).

**No browser has been measured.** `--rendering-driver opengl3_angle` is the closest a desktop run
gets: the same translation, from Godot's own ANGLE build. But a browser ships its own ANGLE build
with its own flags, and Firefox uses a different path again. Measure an actual first load in Chrome
and Firefox on a weak machine before relying on a figure here for the web. **Never load the export
in a browser embedded in another app's UI**: if it shares that app's renderer and GPU process, it
freezes the app while it compiles.

### Where the caches are

There are two cache layers, and a slow run cannot be diagnosed without accounting for both.

**Godot's cache** is per project and keyed on the GLSL that Godot *generates*:

- an editor run (F5) writes `<project>/.godot/shader_cache`;
- a standalone run (`--path`, or an exported build) writes
  `%APPDATA%/Godot/app_userdata/<project name>/shader_cache`, where `EGL` holds ANGLE's program
  blobs beside Godot's own `SceneShaderGLES3` and the rest.

The two locations share nothing, so clearing the wrong one invalidates the measurement. **The web
build has no Godot cache at all**: `_load_from_cache()` and `_save_to_cache()` are compiled out
under `WEB_ENABLED`, since WebGL has no program-binary API.

**The GL driver keeps its own cache underneath.** With Godot's cache deleted and the source
unchanged, a compile still returns in well under a second, because the driver's cache supplies it.
Only novel source misses both caches, and that is exactly what an edit produces. Browsers keep a
GPU shader cache too: Chrome does, so a repeat visitor on the same profile compiles nothing until
the site's shaders change. Firefox may not.


## How this was measured

### Frame time

Each path was launched with `--disable-vsync` and a 1920x1080 window at display scale 1
(`[core_settings] apply_display_scale=false` in the Planetarium's `ivoyager_override2.cfg`), except
where a table says full screen. A temporary Assistant suite forced the settings, and at each pose:

- **Sim time frozen** at 2026-03-20 12:00 and the sim paused; the 2D GUI and every HUD hidden (the
  Asteroids view keeps the points it shows).
- **Settled for 6 s**, then **the star bins pinned**: the bin skip switched off and back on, which
  leaves exactly the bins whose brightest star peaks at half a code or more, regardless of the
  previous view (*A view's cost depends on the view before it*, below). Then **the exposure
  frozen**, so an option's change to the image could not change the metering.
- **Measured** as the median GPU time over a few seconds of frames, from the main viewport's
  timestamp queries (`viewport_get_measured_render_time_gpu`). ANGLE has no timestamp queries, so
  there the median frame interval is used, which includes the CPU's share and can only overstate
  the GPU's.

An option's relief is measured within one session, at one pose, as an **off, on, on, off** block of
2.5-second samples, and given as the mean of the two ons against the mean of the two offs. The GTX
1650 Ti runs at its 40 W power cap here, with its clock varying between about 1650 and 1790 MHz,
and a single on-sample compared with a pose's baseline moved by up to 20 % with nothing changed;
the block cancels a linear drift. The two off-samples of one block then differ by a median of
1-3 % through ANGLE and the GTX's GL and 4 % under Vulkan, with one block in ten above 12 %. That is
the resolution of a relief figure. A restart option (Min, Off, a star cut) is compared across
sessions, so the drift is not cancelled. Forward+ has an extra trap: after a changed MSAA setting,
or the first time a session draws a shader, it compiles a new pipeline in the background and draws
with a slower ubershader until it is ready. So every setting was applied once before timing, and
every restart session visited its poses once before measuring.

Screenshot comparisons were taken at the same frozen exposure and reported as the mean, the 99th
percentile and the maximum absolute difference per pixel in 8-bit display codes, with the share of
pixels differing by more than 2 and more than 8. A session's first screenshot differs from every
later one by a fixed few thousand pixels, and was discarded. A screenshot stalls the GPU, and the
GTX downclocks for seconds afterwards (a frame sampled then read up to 60 % slow), so every
screenshot at a pose was taken after its timing, never between samples.

**Running on the Intel.** Godot exports `NvOptimusEnablement = 1` and
`AmdPowerXpressRequestHighPerformance = 1`, so on a hybrid laptop every OpenGL run, ANGLE
included, runs on the discrete GPU. The Intel runs use a copy of the executable with those two
exports patched to 0, which Windows then runs on the iGPU. Vulkan takes `--gpu-index`; which index
is the Intel varies, so check the adapter (the run's log names it). A Forward+ run records its
GPU's type in `user://override.cfg`, and a later Compatibility run's graphics tier follows that
record, so back the file up around a run that switches GPU.

**The run's own state.** Any Assistant-driven run rewrites the cached startup view on quit, and one
that forces settings rewrites the settings cache, so both were copied aside and restored. A setting
written just before quit can be lost (the cache is written by a worker task), and a number that
arrives as JSON is a float, which the cache drops for an int setting at the next start.

### A view's cost depends on the view before it

**Pin the star bins in any frame A/B.** A drawn star bin is hidden once its brightest star falls
below half a display code, and shown again only when it rises above one code. For a faint bin,
whose peak is its glare wing, that gap is about 3.5 EV. So at a settled exposure, which bins are
drawn depends on the exposure the camera *arrived* with. The Moon at 3 radii through ANGLE on the
Intel takes 14.1 ms on a first visit and 20.4 ms after the camera has been to Titan or Jupiter, at
the same settled exposure: a difference of five bins, 537,000 stars. The Planetarium's
`ProbeExposureSuite` pins them with `set_exposure_skips` and reads them back with
`get_exposure_skips`. The alternative is to take every build through the same poses in the same
order.

### Main-thread CPU time

*Proximity sleep* times script work rather than the GPU. A temporary Assistant suite took over the
process slots of `IVBodyProximityMonitor`, `IVFarwarpManager`, `IVSunOcclusionManager` and
`IVExposureManager` (same priority, next sibling) to time each one inside the frame, and took the
process step, every `_process` and the deferred-call flush, from `process_frame` to `frame_pre_draw`.
At each pose it alternated five states in palindromic order, three rounds of 1.5-second samples:
sleep as shipped, every moon held awake, v0.2's rule, and the first two with moon names and orbits
off. Each sleep state began with every moon asleep, so the monitor woke only what it had to. The
window was 1920x1080 at display scale 1, the tiers Reduced on the GTX and Low on the Intel.

- **The CPU's clock moves a frame's script time by up to 30 % between rounds**, more at Jupiter on
  the GTX, so a difference under about 0.3 ms is read from the in-frame timers, not from the step.
- **The editor's debug binary spends a quarter to three quarters longer** on the same script work
  than a release export. The release export ran the suite with `debug_only=false` under
  `[assistant]` in `ivoyager_override2.cfg`, written before exporting, since the pck embeds it.

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
module docstring lists the pitfalls it avoids: one process per shader, since a driver can carry
work from one compile into the next frame; a uniquely named uniform appended, since a comment does
not change the GLSL that Godot hashes; the whole directory copied, since a runtime `Shader` has no
path for relative includes to resolve against.

`--driver opengl3_angle` compiles through the ANGLE and D3D11 libraries Godot ships, the path a
browser takes on Windows. Running on a weak GPU is the separate step above; the flag alone runs
ANGLE on the discrete GPU, which hardly matters for FXC's share of the time, since that is CPU work.

**To A/B an edit before making it**, copy the shaders directory, edit the copy and time both with
`--shaders-dir`, **one run at a time**. Compiling is CPU-bound: a second process compiling
alongside can double a figure, and of a pair run together, the shorter finishes under load while
the longer then runs alone. Two compiles of the same code still differ by up to about 13 %.

**A cold start in the app** needs novel source for every shader (a uniquely named uniform appended
to each Core `.gdshader`), with Godot's `shader_cache` (and so `EGL`) and its `vulkan` pipeline
cache moved aside, and both restored afterwards. Engine shaders and the `StandardMaterial3D`
shaders of packed models still hit the driver's own cache this way, which takes a fraction of a
second. **To verify the warm-up's coverage**, parse the `.cache` files Godot rewrites for every new
specialization: `GLSC`, u32 version 3, u32 variant count, then per variant a count and per program
a u64 specialization key, whose bit order is the `#[specializations]` list in
`drivers/gles3/shaders/scene.glsl`. Snapshot them after the warm-up and after a flight, and diff
the keys; a `StandardMaterial3D` version is one whose file names `metallic_texture_channel`.
Godot's `--print-fps` detects a stall but misses one under a second and cannot attribute it.

The frame and screenshot suites, the cold-start driver and the atmosphere's entry-point probe (which
writes the include's outputs as raw floats over a grid of geometries, and times them) are session
scripts, not yet in the tools submodule.


## Caveats

- **One machine.** The ratios and orderings are the general result; the milliseconds apply to this
  laptop. A newer integrated GPU (Iris Xe, Radeon 680M) is several times faster than this UHD but is
  also fragment-bound. Which shader is expensive to compile depends on each vendor's compiler, and
  the orderings above are NVIDIA's and FXC's.
- **The resolution of a relief figure** is a few percent through ANGLE and the GTX's GL, and
  5-10 % under Vulkan, whose frame times vary more on both GPUs. A comparison across sessions, as
  for Min, Off and the star cuts, has an error of up to about 10 % through the GTX's GL and 25 %
  through its Vulkan. That is why the GTX's Vulkan star-cut column reads above 1.0 at the Moon,
  Saturn and Earth, where the cut removes little or nothing.
- **Through ANGLE the figure is the frame interval**, which includes the CPU's share and can only
  overstate the GPU's; on the GTX a frame interval is mostly the CPU's.
- **Not measured**: any browser; the Mobile renderer; Intel's own GL driver today; the frame rate
  cap's pacing and energy; the sphere LOD ladder's relief on its own. Figures carrying an earlier
  date were measured on the code of that date and not taken again.

## TODO

- **Glow under Forward+ costs 20-50 % of an airless frame and changes no pixel in most lit views**,
  and Full and Reduced keep it (*Glow*). Skipping the pass while nothing in view exceeds the glow
  threshold would be an automatic saving, like the exposure skips. It needs the frame's brightest
  source, which the exposure metering may already know.
- **The moon HUDs take about 8 % of an Intel frame through ANGLE**, some 200 draw calls of names and
  orbit lines (*Proximity sleep*). Fewer, larger draws per group is the lever; not investigated.
- **Sunspot level of detail by disc size** (*Levers not offered*).
- **85 % render scale** saved nothing measurable in the airless views on either native path;
  measure it at an atmosphere view before keeping the step.
- **Measure a first web visit in a real browser** on a weak machine, Chrome and Firefox (*The web
  export*).
- **Render scale through ANGLE** waits on the engine's scaled depth copy (*3D render scale*).
- **Intel's newer parts and drivers**: the ANGLE switch assumes every Intel GPU prefers ANGLE, on
  the evidence of this UHD alone.
