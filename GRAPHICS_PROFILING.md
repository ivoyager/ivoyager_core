# Graphics Profiling

What each candidate graphics option would buy back on a weak GPU, and what it would cost on
screen.

Every figure here is **per-frame** GPU time.
[SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md) is its one-time counterpart: what these
same shaders cost the driver to compile at first draw. That is the sharper constraint on the web
— it decides whether a weak machine starts at all, where this document decides how it then runs.

**Every figure here was measured in the [Planetarium](https://github.com/ivoyager/planetarium)**
(v0.2.1.dev) against Godot 4.7.2, on 2026-09-10 unless an addendum gives its own date, on the
Intel UHD integrated graphics that stands in for the web app's least capable visitors, with a GTX
1650 Ti alongside. That project's configuration is what the figures describe — its scale, its
eight camera views, its HUD defaults, and the lights its renderers ship with, Compatibility taking
one unshadowed light (`apply_gl_compatibility_shadows` off) except where an addendum says it turned
that on — so a project configured otherwise should re-measure before it trusts a row. *Caveats*
bounds them further.

This is the Markdown copy of an illustrated report. The illustrated version adds a frame-time
chart and the screenshot comparisons that the figure notes below summarize.

**Relief** is the GPU time saved, as a share of that scene's frame. **Visual cost** is the change
in the rendered image, measured in 8-bit display codes on screenshots taken before and after.


## The short version

1. On the Intel iGPU with the **Compatibility** renderer, which is the web app's renderer,
   ordinary views run at 20-35 fps. **Any view with an atmosphere runs at 1-2 fps.** The limb
   shell alone is 75-95% of those frames: Earth close up takes ~490 ms and Titan ~900 ms.
2. The four big levers, in order:
   - **Atmosphere quality.** A reduced tier saves 22-38% with no visible change; off saves
     76-95%. Both predate the atmosphere's rebuild, since which Reduced buys far less through
     Intel's GL (*Addendum: below Reduced*).
   - **3D render scale.** 75% saves 17-28%; 50% saves 30-66%.
   - **The renderer itself, on desktop.** Compatibility is 1.4-8x faster than Forward+ on the
     iGPU.
   - **Star-catalogue depth.** V 11 saves 29-31% in dark-sky views; V 9.5 saves 43-52%.
3. Of the existing options:
   - **Shadow Resolution** matters on Forward+. 16384 adds up to 49 ms a frame even on the GTX,
     and 2048 in place of the then-default 8192 saves 27-39% of an iGPU frame.
   - **MSAA** is a modest lever: off saves 5-13% on the iGPU against 2x, and 5-23% on the GTX.
   - **FXAA and TAA** cost rather than save.
   - **Physical Light** saves nothing, and turning it off costs up to 35%.
4. **A first web visit is minutes of compiling on these machines.** Through ANGLE on the iGPU,
   which is Chrome's path on Windows, one limb-shader program used to compile for longer than
   Chrome's 30-second GPU watchdog allows, so the web could not load at all. Since 2026-09-27 each
   program compiles in seconds, but every shader the first view draws still has to. This is a
   first-load cost rather than a frame-rate one; see *The web export* and *The atmosphere's
   structure* in [SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md).
5. Several costs buy nothing visible and can go with no option at all: the Milky Way and most of
   the star field in any lit-body view, the limb shell's disc-interior fragments, and sphere
   detail a body's on-screen size does not earn. Together they are worth 10-30% in most views and
   far more at Earth and Titan. The limb's interior has since gone, for 19-54% of an iGPU
   atmosphere frame (see *Addendum: the limb annulus, measured*), and the sphere detail is now
   distance-selected (see *Addendum: the sphere LOD ladder*).
6. **The atmosphere was rebuilt on 2026-09-27 for what it costs to compile, and it runs at a
   different speed through every compiler measured**: faster through NVIDIA's GL, level under
   Forward+, mixed through Intel's GL and dearer through ANGLE. The bodies with no atmosphere
   now draw with airless variants of their shaders, which carry none of it: identical on screen,
   and on the iGPU in a quarter to three fifths of the time (see *Addendum: the atmosphere's
   structure, at runtime*).


## Where the frame goes today

GPU time per frame, in ms, at 1920x1080. The budgets are 16.7 ms for 60 fps and 33.3 ms for 30 fps.

| View | Intel UHD, Compatibility | Intel UHD, Forward+ | GTX 1650 Ti, Compatibility | GTX 1650 Ti, Forward+ |
|---|---:|---:|---:|---:|
| Earth fills the screen | 490 | 4112 | 26.2 | 18.0 |
| Earth at 3 radii | 689 ✱ | 1802 | 13.9 | 9.8 |
| Titan at 3 radii | 900 | 1251 | 19.3 | 29.2 |
| Saturn at 45° | 41.2 | 263 | 5.1 | 5.2 |
| Jupiter's moons | 28.6 | 65.7 | 2.6 | 4.0 |
| Sun close-up | 44.0 | 73.3 | 4.8 | 12.6 |
| Whole system, dark sky | 30.8 | 64.2 | 13.7 | 20.0 |
| Asteroid belt | 33.2 ✱ | 61.2 | 17.0 | 23.7 † |

✱ That run hit the driver slow state described under *Caveats*, so the value reads high.
† That scene's baseline drifted during its run.


## How this was measured

**Machine and setup.**

- Dell XPS 15 9500: i7-10875H, Intel UHD Graphics (Comet Lake GT2, 24 EU) and GTX 1650 Ti,
  driver 581.95.
- Godot 4.7.2, window at 1920x1080, sim paused, v-sync off, frame rate uncapped.

**Timing.** GPU time is the main viewport's timestamp-query interval: GL timestamps on
Compatibility, Vulkan on Forward+. Each figure is the median of at least five frames, taken after
a warm-up that absorbs any shader compile.

**Toggling options.** Each option was toggled in the running app by a scratch Assistant probe
suite, and reverted before the next. Toggles were settings, Environment and Viewport properties,
node visibility, shader uniforms, runtime shader swaps and star-mesh rebuilds.

**Reaching the Intel iGPU.** Godot exports `NvOptimusEnablement = 1`, so the Intel runs used a
copy of the executable with that export cleared. Windows' default then puts OpenGL on the iGPU.
Vulkan used `--gpu-index 0`.

**The eight views.**

- Earth filling the screen, day side, 1.6 radii
- Earth at 3 radii
- Titan at 3 radii, with its haze ring
- Saturn at 45°, with rings and about 40 moon orbits
- Jupiter's moon system from above
- The Sun at 3 radii
- The whole system in the dark-adapted sky (`VIEW_SYSTEM`)
- The asteroid belt with its 70k points (`VIEW_ASTEROIDS`)

HUDs were left at their defaults and the 2D GUI was hidden.

**Screenshot comparisons.** The same pose is captured before and after each change. Reported as
the mean and 99th-percentile absolute difference per pixel, and the share of pixels that move by
more than 2 or 8 codes.


## All options, ranked

The ranking is by how much a weak GPU gets back for how little it gives up on screen. Relief is
given for the Intel iGPU on Compatibility (the web's case) and for the GTX 1650 Ti. Ranges span
the views where an option acts; views where it does nothing are left out rather than averaged in.
Intel figures for the atmosphere views come from runs in the driver's normal state.

### High relief

| # | Option | Relief, Intel iGPU | Relief, GTX 1650 Ti | Visual cost | Verdict |
|---|---|---|---|---|---|
| 1 | **Atmosphere quality**: Full / Reduced / Off. Runtime shader swap, or restart. | Reduced -22 to -38%; Off -76 to -95% (atmosphere views) | The shell is 15-39% of the frame | Reduced: none visible. Up to 15 codes on 1-2% of pixels, confined to the limb band. Off: no air at all, and Titan loses its identity. | Built as Normal / Reduced, and a runtime setting rather than a restart one (see *Addendum: the quality tiers, built*). Off is not built. |
| 2 | **3D render scale**: 100 / 85 / 75 / 50%. Runtime. FSR 1 on Forward+. | 75%: -17 to -28%; 50%: -30 to -66% | 75%: -13 to -36%; 50%: -25 to -64% | Soft lines and HUD text. At 50%, orbit lines turn chunky, and the star field coarsens because star size follows render height. | Built as 100 / 85 / 70 / 50% (see *3D render scale*). On a 2x hi-DPI screen, 50% simply restores 1x cost. |
| 3 | **Renderer** (desktop): Auto / Forward+ / Compatibility. Restart. | Compatibility 1.4-8x faster than Forward+ | Mixed: Compatibility faster in 5 of 8 views | Compatibility loses mouse-over identification of orbit lines and asteroids, FXAA and TAA, and local shadow maps. The picture itself matches. | Built as Forward+ / Compatibility, with the Planetarium defaulting integrated GPUs to Compatibility (see *The renderer, on desktop*). |
| 4 | **Star catalogue depth**: all (V 15) / V 11 / V 9.5. Restart, or a 0.3-1.1 s rebuild. | V 11: -17 to -29%; V 9.5: -26 to -43% (star-heavy views) | V 11: -28 to -31%; V 9.5: -44 to -52% | None in lit-body views, where exposure hides faint stars. In dark-sky views, V 11 dims the diffuse star glow (about 7 codes over a third of the sky) and V 9.5 is visibly sparser. | Built as a restart option, its choices named by star count (see *The star field*). It also saves memory and load time. |
| 5 | **Shadow resolution** (existing; Forward+ only in the Planetarium) | vs 8192 on Forward+: 2048 -27 to -39%; 16384 +18 to +88% | 2048: -1 to -10%; 16384: +28 to +387% | Spacecraft-scale self-shadowing only. Eclipses and ring shadows are analytic and unaffected. | Keep. Drop 16384, add Off, and default to 4096. All three are built. |

### Moderate relief

| # | Option | Relief, Intel iGPU | Relief, GTX 1650 Ti | Visual cost | Verdict |
|---|---|---|---|---|---|
| 6 | **MSAA** (existing): off / 2x / 4x / 8x, default 2x | Off: -5 to -13%; 4x: +9 to +11% | Off: -5 to -23%; 4x: +3 to +15% | Stair-stepped orbit lines; the dense ring-plane orbits shimmer. Planet rims are already anti-aliased by the shaders' own PSF. | Keep. Consider Off as the web default. |
| 7 | **Glow**: on / off. Runtime. | -12 to -16% in light views; ~0 in atmosphere views | -1 to -16%; Forward+ -5 to -29% | Small. No bloom on blown extended sources (up to 58 codes beside a bright limb). On Compatibility, off also restores the dimmest codes. | Add. |
| 8 | **Star glare wing**: full / off. Runtime. | -11 to -25% (star-heavy views) | -15 to -16%; Forward+ -24% | No change in lit-body views. In dark-sky views half the sky moves (mean 10.5 codes): halos go, and the faint end moves about 3 mag brighter. | Fold into a "Star field" setting with catalogue depth. |
| 9 | **Milky Way background**: on / off. Runtime. | -10 to -17% | -5 to -13% | None in any lit-body view, where exposure already puts it below one code. In dark-sky views the Milky Way goes (8 codes on 62% of pixels). | Now skipped automatically below half a code (see the addendum). A user toggle is optional. |
| 10 | **Cloud decks**: on / off. Runtime. | -6 to -7% (Earth views) | -22 to -26%; Forward+ -22 to -38% | Large: Earth and Neptune lose their clouds (19% of pixels in an Earth view). | Lowest tier only. |
| 11 | **Frame-rate cap**: 30 / 60 / uncapped. Runtime. | Up to -50% energy when a frame beats the cap | Same | Motion smoothness only. No help when a frame already misses the cap. | Built as None / 60 / 30 fps (see *Smaller levers*). |

### Low relief, or better made automatic

| # | Option | Relief, Intel iGPU | Relief, GTX 1650 Ti | Visual cost | Verdict |
|---|---|---|---|---|---|
| 12 | **Sphere mesh detail**: 256x128 today. Restart, or runtime. | 128x64: -13 to -27%; 64x32: -17 to -38% | 128x64: -10 to -27%; 64x32: -16 to -34% | 128x64 is indistinguishable **in the eight views**, none nearer than 1.6 radii, with 0.16 px of silhouette error on a screen-filling disc. 64x32 shows rim artefacts. Closer than that it is not (see the addendum). | Not an option: distance LOD. Built since (see *Addendum: the sphere LOD ladder*). |
| 13 | **Sun surface detail** (sunspot cells). Runtime uniform. | -36% (Sun close-up only) | Not measured | No sunspots. | Automatic LOD by disc size. |
| 14 | **FXAA** (existing; Forward+ only) | +0 to +6% | +1 to +16% | A benefit: smoother lines, at a slight blur. | Keep. |
| 15 | **TAA** (existing; Forward+ only, experimental) | +10 to +27% | +4 to +39% | Ghosts orbit lines, which are positioned in the vertex shader. | Remove, or keep it hidden. |
| 16 | **Physical light** (existing) | Off: -5 to +26% | Off: +0 to +35% | Changes the whole look. Off keeps the unmetered exposure, so every star draws at full size, which is why it costs. | Not a performance setting. Move it to another section. |
| 17 | **HUD layers and body PSF quads**: orbits, labels, symbols, asteroid points | 0 to -5% | 0 to -5%; asteroid points -16% at the belt | Content, not quality. | No option needed; already user-controlled. |


## Atmospheres

On the iGPU the limb shell dominates the frame. Hiding it takes Earth-fill from ~490 to 116 ms
and Titan from ~900 to 60 ms. Zeroing the optical depths as well, so the surface and cloud shaders
stop compositing air, brings Earth to 97 ms and Titan to 40 ms. What's left is the surfaces, the
clouds, and a 22-24 ms floor of stars, sky and HUD. On the GTX the shell is a much smaller share
(15-22% at Earth, 39% at Titan on Forward+), so this is overwhelmingly an integrated-GPU problem.

Three knobs already in `_atmosphere.gdshaderinc` reduce the cost:

- **A lower-order along-ray quadrature.** A padded 4- or 3-node Gauss-Legendre table is a valid
  rule for both GL loops.
- **A lower cap on the beyond-limb ring taps.** `iv_atm_ring_max_taps` accepts any value.
- **Dropping the detached layer.** `atm_layer_tau` = 0.

The first two are what the built Reduced tier is; the third is not built (see *Addendum: the
quality tiers, built*).

Each was measured on the iGPU, with the screenshots diffed against the shipped render:

| Variant | Earth fill | Titan | Visual difference vs shipped |
|---|---:|---:|---|
| 4-node quadrature | -19% | -16% | Max 2 codes (Earth), 15 (Titan); 0.4% of Titan's pixels differ by more than 2 |
| 3-node quadrature | -23% | -26% | Max 3 / 21 codes |
| **4-node + 2 ring taps** | **-25%** | **-38%** | 1.2% / 1.8% of pixels differ by more than 2 codes, max 12 / 15, all in the limb band |
| ... plus early interior discard | -22 to -37% | -35 to -39% | Identical to the row above (the discard is exact) |
| Detached layer off | -9% | -33% | Titan's outer haze shell disappears |
| 1 ring tap (diagnostic) | -19% | -52% | Not assessed |
| Limb shell off | -76% | -94% | No limb, no haze ring |
| All air off | -80% | -95% | 87% of Earth's pixels change |

*Figure notes (illustrated version).* At 2x on Titan's limb, the shipped shader, 4-node, 4-node + 2
taps and 3-node are indistinguishable. Layer-off loses the outer haze band, and all-air-off loses
everything. Seen whole, Titan in this app is its haze. That is why Off is a real loss there, and
why Reduced is the tier to default to.

### Why the shell costs so much on Intel, and the exact fix

Most of the shell's fragments lie over the disc interior. There they return nothing: they
discard, and the surface and cloud shaders composite that air themselves. On the Intel driver,
those fragments are not cheap.

- **Discard first.** A limb shader that discards at its very first statement still costs 249 ms
  at Earth-fill, against 116 ms for a shader whose body is dead code.
- **Branch around the body.** An explicit `if` around the whole body recovers only 3-6%.
- **Early discard.** An exact interior discard before any setup recovers only 0-10%.
- **Unrolling doesn't help.** Making the loop bounds constants again, so the loops unroll, is
  12-22% slower.

The driver evidently runs much of this large program for pixels that contribute nothing.

What does work is not generating those fragments at all. Draw the limb shell as a camera-facing
annulus around the silhouette instead of a full sphere. `atm_limb()` needs only the view ray,
which a ring on the shell's near side supplies; a flat billboard would stand behind the disc
across the handoff band and lose it to the depth test. The dead-code shader bounds what that
buys: at Earth-fill the shell's interior cost falls from ~370 ms toward the floor, leaving only
the rim's real work. Built and measured since, the rim's work proved the larger part of what was
left (see *Addendum: the limb annulus, measured*).


## 3D render scale

Rendering the 3D scene at a fraction of the window and upscaling is the one lever that works
everywhere, in proportion to pixel count. It costs 12-30% less than its pixel share because some
work doesn't scale: vertex work, and glow at fixed sizes. Compatibility upscales bilinearly.
Forward+ can use FSR 1, which measured the same as bilinear at 75% (-9 to -39%) and is sharper.

Two things make it matter more than the table suggests:

- **Both builds render at physical pixels.** `display/window/dpi/allow_hidpi` defaults to true:
  the web canvas is sized at its CSS size times devicePixelRatio, and on Windows Godot declares
  itself DPI-aware. So a laptop at 2x renders four times the pixels of a 1080p window, and every
  figure in this report was taken in a 1080p window. At that density 50% is not a sacrifice; it
  is the 1x cost.
- **The HUD is in the 3D pass.** Orbit lines, names and symbols scale with it, and the star field
  changes because its PSF is sized in render pixels.

*Figure notes (illustrated version).* At 100%, 75% and 50%, orbit lines thicken and the planet
edge softens, and 50% is clearly coarse; on the GTX this saves 22% and 35% of the Saturn frame.
Each star is drawn as a render-pixel PSF and then magnified, so lower scales give fewer, fatter
stars: detected peaks fall from 24k to 12k to 5.6k.

**Built since** as the user option 3D Render Scale (setting `render_scale`): 100, 85, 70 or 50%,
upscaled with FSR 1 on Forward+ and bilinear on Compatibility. Line and point picking, which had
assumed an unscaled buffer, now follows the scaled one (*Mouse picking* in
[VISUAL_MODEL.md](VISUAL_MODEL.md)). Glow halos keep their share of the frame on Forward+,
where they had widened as 1/scale; on Compatibility, whose glow has no levels to shift, they
still do, twice as wide at 50% (*Glow: the bloom pass* in
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)). The relief at 85% and 70% is not measured; the
figures above are for 75% and 50%.


## The renderer, on desktop

The Windows build runs Forward+. On the iGPU that is the wrong default by a wide margin: Earth-fill
takes 4.1 s instead of ~490 ms, Saturn 263 ms instead of 54 ms, the whole-system view 64 ms instead
of 34 ms. On the GTX the two trade places by view. Forward+ wins at Earth-fill (18 vs 26 ms) and
Compatibility wins everywhere else measured.

A restart-time Renderer option is cheap to build. Point
`application/config/project_settings_override` at a `user://` file and write
`rendering/renderer/rendering_method` there; Godot reads it before the renderer starts. "Auto"
would pick Compatibility when the adapter is integrated.

What Compatibility gives up on desktop:

- Mouse-over identification of orbit lines and asteroid points (`IVFragmentIdentifier` removes
  itself there)
- FXAA and TAA
- Local shadow maps (already off for Compatibility in the Planetarium)

**Built since** as the user option Renderer (setting `renderer`): Forward+ or Compatibility, in a
"Graphics (requires restart)" Options section, and on desktop only. IVGraphicsManager writes the
choice to the file the project names in `application/config/project_settings_override`, so it takes
effect at the next start, and a Forward+ run records the GPU's type there for `IVGlobal`, since the
Compatibility renderer cannot read it. The default by adapter is the project's to set: the
Planetarium defaults an integrated GPU to Compatibility, and a first run that starts in Forward+
there restarts itself into it before init builds anything (`planetarium/preinitializer.gd`). A
laptop with both GPUs counts as discrete, since Godot picks the discrete one.


## The star field

2.55 million point sprites are 0.38 G vertex operations a frame, plus a few million fragments,
whatever is on screen. In the dark-sky views they are the frame: removing the field saves 46-50%
of an iGPU frame and 53-67% of a GTX frame there.

**Catalogue depth.** The magnitude cutoff earns a restart option. The bins are already separate
files, so a restart can load fewer.

| Catalogue depth | Stars | Vertex data | Build time | Dark-sky views |
|---|---:|---:|---:|---:|
| All (to V 15.4) | 2,551,210 | ~51 MB | 0.7-1.1 s | -- |
| V 11 | 942,063 | ~19 MB | 0.26-0.40 s | -25 to -31% |
| V 9.5 | 216,622 | ~4 MB | 0.07-0.10 s | -40 to -52% |

Build times are single-threaded GDScript decode on this CPU, and the web's WASM build will take
longer. In lit-body views the cut is invisible, because exposure already buries those stars. In
dark-adapted wide views V 11 thins the faint glow and V 9.5 visibly empties the sky.

**Built since** as the user option Star Catalog (setting `star_catalog`), in the "Graphics
(requires restart)" section, its three choices named by star count: 2.6 million, 940,000 and
220,000. `IVStarsVisual` loads the lower of that cut and its own `magnitude_cutoff` when it
builds, so a change takes effect at the next start. Its default is the whole catalogue in every
configuration. The relief is not re-measured: the figures above are these same cuts, taken
before the field was split into bins, and in lit-body views the exposure skips now drop most of
what the cut would have saved (see *Addendum: the exposure skips, built and verified*).

**The glare wing.** `glare_scale` = 0 saves up to a quarter of a dark-sky frame. It is a bigger
visual change than the catalogue cut, because the wing is what draws the faint end. Two shader
variants that keep bright halos land in between:

- **Untapered wing:** -18%.
- **Wing gated to bright stars:** -21%.

Both still move the sky by 7-9 codes on average.

*Figure notes (illustrated version).* The whole-system view, dark-adapted: shipped, V 11 and V 9.5
across the top; glare off, untapered wing and gated wing below.


## The existing options

### MSAA

Off saves 5-13% of an iGPU frame, the low end in atmosphere views where fragment shading dwarfs
everything else, and 5-23% on the GTX. 4x costs 9-11% more than 2x on the iGPU and 3-15% on the
GTX. 8x, measured later, adds 12-52% to a 2x frame (see *Addendum: more shadow and MSAA
measurements*). The planet rims don't need it, because the surface shaders already image each rim
pixel through the camera's PSF. What does need it is lines: orbit lines, ring edges and spacecraft.

*Figure notes (illustrated version).* At 2x and off, only the lines change, and the dense
ring-plane orbits break into steps.

### Shadow resolution

Only Forward+ in the Planetarium draws shadow maps, and they serve only spacecraft-scale local
shadows. Their cost is not small.

- **8192, then the default, on the iGPU:** about 20-25 ms a frame in views with no spacecraft
  anywhere near. 2048 saves 27-39% there. Those frames need no map at all, and a skip that
  removes the passes rather than shrinking them beats that figure (see *Addendum: the empty
  shadow passes*).
- **16384:** a 1 GiB depth atlas at 32 bits. It costs +28% to +387% on the GTX, up to 49 ms a
  frame at the Sun view, and +18% to +88% on the iGPU.

Drop 16384. Add Off, which switches off the shadowed lights' maps. Default to 4096. The atlas
sizes are 16, 64, 256 and 1024 MiB. Later runs back 4096 as the default, and find resolution cheap
at any size on the web renderer (see *Addendum: more shadow and MSAA measurements*). All three are
built. Off switches the maps off through `IVDynamicLight.shadow_maps_enabled` and frees the atlas
(*`directional_shadow_count` stops being a constant* in
[SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md)).

### FXAA, TAA and Physical Light

**FXAA** is cheap line smoothing (+1 to +16%) and worth keeping.

**TAA** costs 4-39% and ghosts the orbit lines. It earns its "experimental" label, and is better
hidden.

**Physical Light** is not a performance option at all. Turning it off makes several views slower,
up to 35%, because the unmetered exposure keeps every star at full size. It belongs beside the
look settings, not under Graphics/Performance.


## Smaller levers

**Glow.** Glow saves 12-16% of an iGPU frame in light views and nothing in atmosphere views. On
the GTX it saves 1-16%, and 5-29% on Forward+. What goes is bloom around blown extended sources:
spacecraft, small moons, a bright limb. On Compatibility, turning glow off also returns the
dimmest codes that the RGB10A2 glow feed crushes.

**Cloud decks.** Clouds are cheap on the iGPU (-6 to -7%) but 22-26% of a GTX frame at Earth, 38%
on Forward+. Taking them off is a large visual loss, so this belongs in the lowest tier only.

*Figure notes (illustrated version).* At Saturn, glow off moves 8% of pixels by 5 codes or less.
The Milky Way changes nothing there, because metering on Saturn puts it below one code, yet on the
iGPU it still costs 10% of that frame. At Earth's limb, at 1.6 radii, a 128x64 sphere is
indistinguishable from 256x128, and 64x32 flecks the rim. That indistinguishability is what the
row above reads as a licence to default to 128x64, and it does not survive a closer view — see
*Addendum: the sphere LOD ladder*.

**Frame-rate cap.** Built as the user option Frame Rate Cap (setting `frame_rate_cap`): None, 60
or 30 fps, applied live as `Engine.max_fps`. None leaves the engine at the cap it started with,
which in the Planetarium is none, so the display's refresh rate bounds it. Godot holds a cap in
software — a sleep on the desktop, skipped animation frames in a browser — rather than by
presenting on every second refresh, so 30 on a 60 Hz display may not pace evenly. Neither that
nor the energy saved is measured.


## Free wins: relief with no visual change

These need no option. Each removes work whose result never reaches the screen.

| Change | Measured basis | Expected relief |
|---|---|---|
| **Limb shell as a camera-facing annulus**, not a full sphere (done; see addendum) | A dead-code limb body costs the same as a hidden shell. A discarding one costs about 1/3 of the full shader. | Measured on the iGPU: Earth-fill -37%, Venus close -54%, Titan and Mars close -19 to -20% |
| **Skip the sky pass** when the panorama x exposure is below half a display code (done; see addendum) | Milky Way off changes zero pixels in every lit-body view | -10 to -17% (iGPU), -5 to -13% (GTX) in those views |
| **Skip star bins** the current exposure renders below half a code; split the star mesh by bin (done; see addendum) | Cutting to V 11 changes zero pixels in lit-body views, yet stars cost 13-28% there | -13 to -28% in lit-body views |
| **Sphere distance LOD** (done; see addendum) | 128x64 measured indistinguishable at >= 1.6 radii, but not closer; a body drew 65,536 triangles down to a 2.5 px radius | -10 to -27% |
| **Skip shadow passes** when no local caster **or receiver** is in range (done; opt-in, see addendum) | An empty 8192 atlas costs ~20-25 ms per iGPU frame | Measured on the iGPU under Forward+: -39 to -46%, 27-30 ms a frame |
| **Sunspot LOD** by disc size | Sunspots are 36% of a Sun close-up | Near the Sun only |

**Small edits don't reliably pay on Intel.** Several of the shader-anatomy review's "exact"
micro-optimizations landed anywhere from -10% to +15% on the iGPU, depending on the view. Examples
are gating airless bodies out of the atmosphere functions, and two Newton steps in place of three
in the Compatibility colour write. Intel's code generation for shaders this large is erratic.
Structural changes are what paid every time: fewer nodes and taps, fewer fragments, fewer
vertices, less sky -- and, since, less code, where a runtime gate was not enough: an airless body's
shader now carries none of the atmosphere at all (*Addendum: the atmosphere's structure, at
runtime*).

The same review found a likely bug: `atm_ring_pixel()` doesn't normalize `path` by `weight_sum`,
and its midpoint tent weights sum to 2 at one tap and 10/9 at three. That lets a close-range ring
read up to about 11% bright.


## First load on the web

Frame time is only half of the web story. The other half is shader compilation, which the web pays
on every first visit because WebGL has no program-binary cache. Until 2026-09-27 it was the more
serious half: through Chrome's ANGLE and D3D11 path one limb-shader program compiled for longer
than Chrome's 30-second GPU watchdog allows, so a first visit on a machine like this one could not
finish compiling it at all, and the v0.2.1 dev build never passed its boot screen. Since *The
atmosphere's structure* in [SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md) one program
compiles in a few seconds there, and the hazard is a delay: a first visit still compiles every
shader its opening view and the warm-up draw, about two minutes of this laptop's CPU for the
atmosphere shaders alone. The rebuild also left the atmosphere dearer to draw through ANGLE than
it was (*Addendum: the atmosphere's structure, at runtime*).

The per-shader figures, both compilers, and what they mean for how a shader is written are in
*The web export* in [SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md). Two consequences
land on the option set, and this is where they come from:

- **An Off tier is what would shorten a first visit**, and it has to leave the quadrature out of
  the disc shaders as well as out of the limb shader: `atm_disc_air()` and the helpers are most of
  a disc shader's compile. A reduced tier does not help here: what compiles is code volume, not
  iteration count. The airless shader variants, built for their own sake, are most of the
  machinery (*Addendum: the atmosphere's structure, at runtime*).
- **Atmosphere quality therefore earns a restart option rather than a runtime one.** A session
  then compiles only the tier it uses, and the warm-up covers it.

**That second consequence applies only to an Off tier, and the built setting has none**, so it
is a runtime one — see *Addendum: the quality tiers, built*, and *Addendum: below Reduced* for
what a runtime tier under it could still give.


## A possible option set

**Graphics**

- Atmosphere quality: Normal / Reduced (built)
- 3D render scale: 100 / 85 / 70 / 50% (built)
- Star field: Full / Reduced (no wing) / Minimal (no wing, no Milky Way)
- Glow: on / off
- MSAA: off / 2x / 4x
- FXAA (Forward+)
- Shadow resolution (Forward+): off / 2048 / 4096 / 8192 (built)
- Frame-rate cap: none / 60 / 30 fps (built)

**Graphics (requires restart)**

- Renderer (desktop): Forward+ / Compatibility, default by adapter (built)
- Atmosphere Off (the tier that omits the quadrature from the limb and the disc shaders alike, and
  the only one needing a restart; every body on the airless shader variants of the runtime
  addendum)
- Star catalogue: V 15 / V 11 / V 9.5, shown as 2.6 million / 940,000 / 220,000 stars (built)
- Cloud decks: on / off

A first-run preset, chosen from the adapter, could set all of these at once. On an integrated GPU
or the web it would pick Compatibility, Reduced atmospheres, 75% scale on hi-DPI and MSAA off.


## Caveats

- **One machine.** Treat ratios and rankings as the finding, and absolute milliseconds as this
  laptop's. A newer iGPU (Iris Xe, Radeon 680M) is several times faster, but shares the same
  fragment-bound shape.
- **An Intel driver slow state.** In one of seven Intel Compatibility runs, MSAA 2x with glow's
  float buffer settled into a state about 2.3x slower in the atmosphere views. Toggling MSAA or
  glow cleared it. Repeat runs (three baselines, A/B interleaved) put the normal state at ~490 ms
  (Earth) and ~900 ms (Titan). Where a scene's baseline drifted mid-run, rows after the drift are
  excluded.
- **Estimates, not measurements.** The exposure skips are now built and verified for correctness,
  but their relief has so far been measured only on the GTX; the iGPU figures in *Free wins*
  remain bounds from proxies (see the addendum). The annulus's were too, and have since been
  measured below their bound, and the empty shadow passes above theirs. The sphere LOD ladder's
  iGPU relief is still outstanding. The Mobile renderer was not tested, and no browser was
  ([SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md), *The web export*).


## Open questions

- **Should Compatibility run through ANGLE on Intel iGPUs on desktop?** Opened 2026-09-27. Through
  ANGLE's D3D11 path the probe draws the rebuilt atmosphere on this laptop's UHD up to twice as
  fast as Intel's own GL driver does, and ANGLE takes the Forward+ fast path in
  `atm_exp_columns()` well where Intel's GL is slowed by it, so moving these parts would also let
  that path into Compatibility (*Addendum: the atmosphere's structure, at runtime*). Godot can do
  it by project setting (`rendering/gl_compatibility/driver.windows`, or per device,
  `force_angle_on_devices`). To answer it: whether a whole frame, not only the atmosphere, is
  faster through ANGLE on these parts -- ANGLE has no GPU timestamps, so that needs frame time
  measured in the app; what a desktop user's first run then pays compiling through FXC, which is
  the web's first visit (*The atmosphere's structure* in
  [SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md)); and whether Intel's newer parts and
  drivers agree with this one.


## Addendum: the limb ring and surface twilight

Added after the report was published, in answer to two questions: would a ring-shaped limb shell
need the four atmosphere worlds' surfaces rebaked, and would it change twilight colour on the
surfaces and on Earth's clouds?

**Neither.** Nothing is baked. The surface, cloud and band shaders compute the air in front of
themselves every frame, from the same `atm_*` values that `IVShellsModel` copies to them from the
limb row:

- the veil and twilight glow: `atm_disc_air()`;
- the sunset-reddened sunlight on the ground and on Earth's cloud deck, and the colour shift from
  looking through the air: `atm_receiver_light()`.

The limb shell contributes nothing over the disc interior. Any fragment whose ray meets the disc is
discarded (`atm_limb()` in `_atmosphere.gdshaderinc`, and the `discard` in
`atmosphere_limb.gdshader`'s fragment). Its whole job is the rays that miss the disc, plus the
outer 1% of the disc's radius (`ATM_RIM_HANDOFF`), where it and the disc shaders each draw part
of the edge haze. A ring only stops generating fragments that already contribute nothing. Two
variants that discard those interior fragments up front gave screenshots identical to the shipped
render at Earth and Titan, with zero pixels changed. The one constraint is that the ring's inner
edge must reach inside the `ATM_RIM_HANDOFF` band, plus about two pixels for the ring filter.

**What does change surface and cloud twilight is the quality tiers.**

- **Reduced:** the 4-node quadrature is also what the surface and cloud shaders use for the air in
  front of them. The change measured at most 2 display codes on Earth and up to 15 codes on 0.4% of
  Titan's pixels.
- **Off, as measured above ("All air off"):** zeroing the optical depths removes the twilight, the
  veil and the reddened sunlight entirely. Venus, Titan and Mars ship surface-reflectance maps
  that assume the air is added on top, so a no-air tier would render them wrong without
  re-levelled assets.
- **A better Off tier:** hide only the limb shell and keep the air on the disc. On the iGPU that
  saves nearly as much, 76% at Earth close-up and 94% at Titan against 80% and 95%. Surfaces and
  clouds keep their twilight. What goes is the band beyond the limb, a backlit crescent's glowing
  cusps and Titan's haze ring. The outermost 1% of the disc also loses the shell's part of the edge
  haze. This variant was measured but not screenshotted.


## Addendum: more shadow and MSAA measurements

Measured on 2026-09-11, after the report was published, to fill three gaps before the graphics
Options tooltips were given GPU-cost levels: shadow resolution on the web renderer, the 4096
setting, and 8x MSAA. The machine and method are the same. The views were five of the eight above
(Earth at 3 radii, Saturn at 45°, Jupiter's moons, the Sun close-up and the whole system), plus
close-ups of Juno and New Horizons (`VIEW_ZOOM`), which give the shadow maps something to cast.
Deep-space craft were chosen because they are always sunlit. The Planetarium ships with
Compatibility shadows off, so `IVCoreSettings.apply_gl_compatibility_shadows` was turned on for
the Compatibility runs.

Each figure is the change in GPU time against the mean of the scene's repeated baselines, leaving
out Juno's first, which was taken before its model had loaded. Repeated baselines within a scene
drifted by up to 16%, so a change of a few percent is noise; the large Forward+ iGPU changes are
well clear of it.

### Shadow resolution

Change on leaving the default 8192. The light views are Jupiter's moons, the Sun close-up and the
whole system; Saturn and Earth, where other work dominates the frame, moved less.

| Renderer, GPU | 4096, light views | 2048, light views | 4096, spacecraft | 2048, spacecraft |
|---|---:|---:|---:|---:|
| Forward+, Intel iGPU | -23 to -28% | -29 to -35% | -33% | -40 to -42% |
| Forward+, GTX 1650 Ti | 0 to -3% | -2 to -4% | -2% † | -2% † |
| Compatibility, Intel iGPU | 0 to -2% | -1 to -6% | -4 to -5% | -5 to -7% |
| Compatibility, GTX 1650 Ti | -2 to -3% | -4 to +3% | -2 to -6% | -1 to -3% |

† New Horizons only. Juno's GTX baselines drifted 16%, more than any setting moved it.

- **Forward+ on the iGPU is where resolution costs.** 4096 recovers about four-fifths of 2048's
  saving, with or without a craft in view. That backs 4096 as the default.
- **The GTX hardly notices** the difference between the three sizes.
- **Compatibility pays little at any size,** on either GPU, even with a craft casting. The iGPU's
  Forward+ cost does not carry over to the web renderer. What turning Compatibility shadows on
  costs in the first place was not measured.

### MSAA

Change against the default 2x, over the five views:

| Renderer, GPU | Disabled | 8x |
|---|---:|---:|
| Forward+, Intel iGPU | -10 to -19% | +12 to +52% |
| Forward+, GTX 1650 Ti | -5 to -13% | +15 to +36% |
| Compatibility, Intel iGPU | -10 to -19% ‡ | +17 to +49% |
| Compatibility, GTX 1650 Ti | -8 to -21% | +13 to +27% |

‡ Leaving out the Sun close-up, which read 11% slower with MSAA off.

8x adds 12-52% to a 2x frame in every combination. The Compatibility runs had Compatibility
shadows on, which the Planetarium's web setup does not, so the report's own Disabled figures for
that setup (-5 to -13% on the iGPU) stand.


## Addendum: the limb annulus, measured

Measured on 2026-09-11, after the annulus was built into this plugin (v0.2.1.dev): the limb
shell now draws a camera-facing ring of its own sphere, from two pixels inside the disc's handoff
band out to the shell's silhouette (`limb_annulus_mesh`; *Atmospheres* in
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)). Same machine and method, except that the shipped
sphere and the annulus were swapped within one process and interleaved A/B/A/B, each figure the
median of 15 frames.
The poses are close to, not identical with, the eight views above.

| View | Intel UHD, Compatibility | GTX 1650 Ti, Compatibility | GTX 1650 Ti, Forward+ |
|---|---:|---:|---:|
| Earth fills the screen (1.6 radii, day side) | 481 → 304 ms (-37%) | 24.2 → 21.7 ms (-10%) | 18.2 → 17.4 ms (-5%) |
| Earth at 3 radii | 225 → 129 ms (-43%) | 12.3 → 10.8 ms (-12%) | 10.1 → 9.3 ms (-8%) |
| Titan at 4.2 radii | 505 → 408 ms (-19%) | 16.1 → 13.7 ms (-15%) | 17.6 → 15.5 ms (-12%) |
| Venus at 1.5 radii | 300 → 139 ms (-54%) | 16.1 → 13.5 ms (-16%) | 11.5 → 11.0 ms (-4%) |
| Mars at 1.5 radii | 715 → 569 ms (-20%) | 31.1 → 27.7 ms (-11%) | 23.6 → 22.8 ms (-3%) |
| Jupiter's moons (no atmosphere) | 27.0 → 27.1 ms (0%) | 2.75 → 2.72 ms (-1%) | 4.10 → 4.15 ms (+1%) |

- **Below the bound, and why.** The interior did go; what the dead-code proxy could not see is
  how much the rim itself costs. At Earth-fill about 190 ms of the limb remains, all of it the
  annulus's own fragments, each running the ring's taps over both halves of its ray or the
  handoff band's disc quadrature. By an estimate a tenth of the shell's fragments, the annulus is
  now most of its cost, and that is exactly the work the Reduced tier (4 nodes, 2 taps) cuts, so
  the two stack.
- **No visible change.** Against the shipped sphere, a handful of single pixels on the disc's rim
  move per view, one by up to 110 codes, and nothing else does. Rotating the shipped sphere 0.7°
  about its pole, which moves nothing but its facets, moves as many rim pixels by as much: the rim
  is sensitive to the last bits of the interpolated ray, whatever mesh supplies it. Body icons
  match to 7 codes. At the ISS, 90 m from the station with farwarp compressing the limb, nothing
  moves by more than 2 codes at any row count from 6 to 16.
- **No compile or pipeline cost.** The annulus carries the sphere's vertex attributes, so
  Forward+ reuses the shader warm-up's pipeline: the surface-compile counter matches the sphere
  build's, and a position-only annulus, the negative control, adds one. The fragment stage is
  unchanged, and the Compatibility compile time with it: 7.3 s against 7.7 s.


## Addendum: the exposure skips, built and verified

Built into this plugin on 2026-09-19: under physical light the background panorama stops
being drawn, and each star magnitude bin stops being submitted, once the compensating camera
has metered it below **half** a display code. The star field is split into one mesh per
magnitude bin to make the second possible. The model, its derivation and its constants are
in *Skipping what the camera has metered away* in
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md); what follows is only what was measured.

**Half a code, not one.** Half is the 8-bit rounding boundary, and it is what turns the
promise from a measured one into a proved one: in the sRGB toe the encode is linear, so
removing a contribution under half a code moves the rounded result by at most one code at
any pose. Exact bit-identity is not available at any positive threshold — removing added
light can always carry some pixel across a boundary.

### Correctness

Captured at a frozen exposure with HUDs hidden, each mechanism forced off and then on within
one app run, 1920x1080, Forward+ on the GTX 1650 Ti.

| View | Metered exposure | What was skipped | Pixels changed |
|---|---:|---|---|
| Earth at 3 radii | 5.2e-7 | sky, and 13 of 24 bins | **0** of 2.07 M |
| Saturn at 45° | 2.8e-5 | sky, and 4 of 24 bins | **0** of 2.07 M |
| Saturn at 45°, star cull only | 2.8e-5 | 4 of 24 bins | **0** of 2.07 M |
| Jupiter's moons | 3.5e-4 | sky only (no bin qualified) | 337 (0.016 %), all by exactly 1 code |

Jupiter's is the marginal case and the one worth understanding: the sky sat at 0.099 of a
code, just under the threshold, and where faint stars already lit a pixel the removed sky had
been tipping it over a rounding boundary. It is the predicted worst case, not a defect, and
it is bounded at one code.

### Where each mechanism engages

An EV sweep at a fixed pose, reading the decision back from the app rather than inferring it:

| Exposure EV | Sky | Bins drawn |
|---:|---|---:|
| +1.0 (dark-adapted rest) | drawn | 24 / 24 |
| −9.0 | drawn | 24 / 24 |
| −10.0 | skipped | 24 / 24 |
| −14.0 | skipped | 21 / 24 |
| −16.0 | skipped | 18 / 24 |
| −20.0 | skipped | 12 / 24 |

The sky crosses at exposure 1.75e-3, which is where the shipped anchor puts it to the stop.
Nothing is skipped at rest, so the dark-adapted sky is untouched — and with physical light
off, where exposure is pinned at rest, neither predicate can fire at all.

At Earth the cull leaves 11 of 24 bins, which is 15,641 of 2,551,210 stars still
submitted: 99.4 % of the field's vertex work gone in the view that needs it most.

### Relief, so far

| View | Renderer / GPU | Off | On | Change |
|---|---|---:|---:|---:|
| Jupiter's moons (sky only) | Forward+, GTX 1650 Ti | 4.76 ms | 4.59 / 4.44 ms | −3 to −7 % |
| Earth at 3 radii | Forward+, GTX 1650 Ti | 10.0 / 10.4 ms | 9.9 / 10.7 ms | within noise |

Medians of 15 frames, A/B interleaved, sim paused. Earth is atmosphere-bound on this GPU, so
neither skip shows there even though both fire — which is the expected shape, not a
disappointment: the star field and the sky are a small share of a frame the limb dominates.

**The figures this change exists for are not measured yet.** The −10 to −17 % (sky) and
−13 to −28 % (stars) in the *Free wins* table are for the Intel iGPU under Compatibility, the
web app's case, and reaching that GPU needs the `NvOptimusEnablement`-cleared executable copy
described under *How this was measured*. That run is outstanding.


## Addendum: the sphere LOD ladder

Added on 2026-09-19, in answer to a question the report could not settle from its own data: the
row above calls 128x64 indistinguishable, but from what view? The eight views come no nearer
than 1.6 radii, and the quoted 0.16 px is 128's silhouette sagitta against a 540 px disc radius.
**Closer than that it is not indistinguishable**, and the shipped sphere is now chosen per frame
instead (`IVShellsModel`; *The sphere LOD ladder* in [VISUAL_MODEL.md](VISUAL_MODEL.md)).

**Why a near view is harder.** A facet's chord sags inside the true sphere by
`R x (1 - cos(PI / segments))` — 1.92 km at 128x64 on Earth, 0.48 km at 256x128, for facets
about 310 km and 155 km across. That is fixed in world units; what a view changes is how many
pixels it buys. Framing Earth's horizon from the ISS at the default 24 mm lens (52 degrees
vertical, f ~ 1107 px at 1080p) puts the limb 2,293 km away instead of the 7,958 km of a
screen-filling disc:

| View | Limb distance | Facet chord | Sagitta at 128x64 | at 256x128 |
|---|---:|---:|---:|---:|
| Earth at 3 radii | 18,020 km | 24 px | 0.13 px | 0.03 px |
| Earth fills the screen (1.6 radii) | 7,960 km | 55 px | 0.44 px | 0.11 px |
| ISS horizon, 24 mm | 2,293 km | 150 px | 0.93 px | 0.23 px |
| ISS horizon, 100 mm | 2,293 km | 630 px | 3.9 px | 0.97 px |

Twice the sagitta of the report's worst case, over a three times longer facet baseline, judged
against a near-straight horizon rather than a strongly curved limb. At a long focal length even
256x128 goes marginal.

**Measured.** At the ISS, 60 m off the station with the horizon across the frame, 1920x1080,
HUDs hidden, each rung pinned in turn and diffed against 256x128:

| Mesh | Mean | p99 | Pixels > 2 codes | > 8 codes |
|---|---:|---:|---:|---:|
| 128x64 | 0.30 | 5 | 2.43 % | 0.29 % |
| 64x32 | 1.13 | 23 | 7.86 % | 4.22 % |
| 32x16 | 4.30 | 87 | 13.63 % | 10.22 % |

For scale, the Reduced atmosphere tier moves 1.2-1.8 % of pixels by more than 2 codes with a
maximum of 12-15, and the limb annulus moved a handful of single pixels. 128x64 here is a larger
change than either, and it saturates: most of it is not the silhouette but the disc, because the
veil field is painted on a polyhedron up to the sagitta inside the true sphere, so the whole
pattern shifts radially.

**What the ladder does instead.** A rung serves every body whose on-screen radius keeps its sag
within 0.15 px, which gives ceilings of 1992, 498, 125, 31 and 7.8 px for 256, 128, 64, 32 and
16 segments — a 4x range each. The near end is unchanged: at the ISS, Earth measures 1043 px and
takes 256x128, exactly what shipped. The relief is at the far end, where before the ladder a body
drew 65,536 triangles down to a 2.5 px radius (`IVBody.psf_handoff`), and a body without a PSF
quad down to the 4000-radius cull at 0.28 px — dozens at a time in the system-wide views, which
is where the row's -10 to -27 % was coming from.

Verified in the app across a distance sweep and at the ISS: the rung always equalled what the
budget demands for the measured on-screen size, including during fast camera motion, and a
registered capture height of 4320 moved Earth from 32 to 64 segments and back on clearing. Two
Godot behaviours the design rests on were confirmed on 4.7.2 rather than assumed: an instance
keeps its `custom_aabb`, `sorting_use_aabb_center` and surface override material across a `mesh`
assignment, and five rungs drawn through one `ShaderMaterial` compiled no additional pipelines
(surface, draw and specialization counters flat), every rung sharing the sphere's vertex format.

**Not yet measured: the relief itself.** The figures in the rows above are the fixed-resolution
A/B from 2026-09-10, not a measurement of the ladder. What it actually returns on the Intel iGPU
under Compatibility — the web app's case, and the one the change exists for — is outstanding,
and needs the `NvOptimusEnablement`-cleared executable copy described under *How this was
measured*.


## Addendum: the empty shadow passes

Built into this plugin on 2026-09-19 and measured the same day: a shadow-mapped
`IVDynamicLight` now clears `shadow_enabled` while nothing within its reach would draw into
its map or read it, under the opt-in `IVCoreSettings.apply_empty_shadow_pass_skip` (*Local
shadow maps* in [VISUAL_MODEL.md](VISUAL_MODEL.md)). The Planetarium turns it on, where it
acts on desktop Forward+ only — that project ships `apply_gl_compatibility_shadows` false,
so its Compatibility renderer has no maps to skip.

**Both halves of the predicate earn their place.** A caster in reach is not enough: the map
also needs a receiver in the light's own `light_cull_mask`. At the ISS, 90 m off the
station, the near light stays on for the station's self-shadowing while the middle light
retires, because nothing in the 0.1-100 km size domain is anywhere near. A caster-only test
would have kept it.

**Relief.** Intel UHD, Forward+, 1920x1080, sim paused, HUDs hidden, exposure frozen; the
mechanism forced off and on within one app run, A/B/A/B, each figure the median of 15
frames.

| View | Maps configured | Passes skipped | Change |
|---|---:|---:|---:|
| Jupiter's moons | 66.5 / 70.4 ms | 40.3 / 40.7 ms | **-39 to -42%** |
| Whole system, dark sky | 64.1 / 61.7 ms | 34.8 / 34.5 ms | **-44 to -46%** |

The baselines reproduce this report's own table for those views (65.7 and 64.2 ms) to
within a percent. The saving is 27-30 ms — **above** the -27 to -39% the *Free wins* row
carried, which came from the 8192→2048 A/B: shrinking an atlas is not removing it. On the
GTX 1650 Ti the same A/B at Earth 3 radii sat inside a ±15% baseline drift, which is the
expected shape — *Addendum: more shadow and MSAA measurements* already had that GPU
noticing nothing between 2048 and 8192.

**No visible change, exactly.** At Earth 3 radii with both maps skipped, forced-off against
forced-on differ by **0 of 2,073,600 pixels**, maximum 0 codes. Unlike the exposure skips,
which are bounded at one code by a threshold argument, this one is exact by construction: a
map with no caster and no receiver in reach contributes nothing at all. At the ISS, where
the near light stays on either way, the render is likewise bit-identical across 1.0 M lit
pixels.

**The cost is a compile risk, not a frame-time one, and it is why this is opt-in.** A frame's
shadowed-directional-light count is a shader specialization input for every lit instance, so
with the skip on it takes 2, 1 or 0 instead of a constant 2, and each distinct value compiles
its own programs for every lit shader — synchronously on the main thread under Compatibility
([SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md), *The light configuration*). Flips
are therefore made rare rather than merely correct: on is immediate, off waits 120 frames, and
the enable and disable thresholds sit at 1.25 and 2.0 times the reach. Measured at Earth, the
middle light's idle counter climbs to 120 and flips once, with no chatter under ordinary
camera motion. `IVShaderWarmup` declares its own quads through
`IVDynamicLight.add_local_shadow_geometry()` so that the warm-up keeps compiling the
configuration the app actually runs.

**Not measured:** the flip's own cost, which belongs in
[SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md) when taken. The other question left
open here, whether Godot frees the depth atlas when the count returns to zero, is answered there
from the engine source: it does not, so a re-enable reuses the atlas rather than paying for it per
flip (*`directional_shadow_count` stops being a constant*).


## Addendum: the quality tiers, built

Built into this plugin on 2026-09-19 as the user setting `atmosphere_quality`, with the report's
first two knobs and **two tiers, not three**: Normal is the shipped rule, Reduced is the
4-node quadrature and 2 ring taps of the row above. Off is not built — it is the tier that needs
Venus, Titan and Mars re-levelled (*Addendum: the limb ring and surface twilight*), and the only
one a restart would buy anything for.

**It is a runtime setting, which this report did not expect.** *First load on the web* argues
that atmosphere quality earns a restart option, and that argument is about Off alone: what an
omitted tier saves is a compile, and a compile is what a session cannot pay twice. Normal and
Reduced are the **same shader source** — one packed node table, and three `int` globals
(`iv_atm_gl_first`, `iv_atm_gl_nodes`, `iv_atm_ring_max_taps`) selecting a rule out of it — so
no program is compiled, no pipeline added and no specialization reached when the tier changes.
Confirmed by A/B/A/B flips at Earth-fill with a forced draw and readback on each: 533, 590, 579
and 594 ms, flat, where a limb-shader compile is seconds.

**Normal is bit-identical to the shader it replaces.** Six poses at 1920x1080 with HUDs hidden,
sim time and exposure frozen, diffed against the same poses built from the pre-change shader in
the same session: **0 of 2,073,600 pixels** at Earth-fill, Earth at 3 radii, Venus, Mars and
Titan, and 1 pixel by 1 code at backlit Titan.

**What Reduced moves, and where.** Same poses, the tier flipped within one run:

| View | Mean | p99 | Max | Pixels > 2 codes | > 8 codes | Radius of the change |
|---|---:|---:|---:|---:|---:|---|
| Earth fills the screen (1.6 radii) | 0.07 | 2 | 23 | 1.13 % | 0.36 % | 889-903 px of a 900 px disc |
| Earth at 3 radii | 0.01 | 0 | 17 | 0.28 % | 0.02 % | 392-397 px |
| Venus at 1.5 radii | 0.01 | 0 | 6 | 0.16 % | 0 | — |
| Mars at 1.5 radii | 0.10 | 4 | 7 | 1.50 % | 0 | 994-1033 px |
| Titan at 4.2 radii | 0.02 | 1 | 4 | 0.12 % | 0 | 213-227 px |
| Titan backlit, 4.2 radii | 0.04 | 1 | 8 | 0.52 % | 0 | 178-258 px (the haze ring) |

Every pixel past 2 codes lies in a band a few pixels wide at the limb; the disc interior does
not move at all, and neither does anything beyond the band. That is the report's own "confined
to the limb band", measured on the poses above rather than the report's.

**Relief is not re-measured.** The -22 to -38 % in the table above is the 2026-09-10 iGPU
figure, taken before the limb annulus. The annulus addendum argues the two stack — the
annulus's remaining cost is the rim's own fragments, running the taps and the quadrature that
Reduced cuts — so the share should now be larger, not smaller. Confirming that needs the
`NvOptimusEnablement`-cleared executable copy described under *How this was measured*, and is
outstanding along with the sphere ladder's and the exposure skips'. The atmosphere's own share of
it has since been measured on the rebuilt include, probe by probe, in *Addendum: below Reduced*.

**One thing this measurement found that was not about the tiers, and is now fixed.** Earth,
alone of the four, did not render identically across two *processes*: about 1 code over its lit
disc, tracing cloud detail, with zero mean bias. The cause was its cloud deck, the only shipped
shell that moves relative to its body — `IVShellsModel._rotate` integrated per-frame deltas into
the deck's basis, so its phase was a function of the session's frame history and not of the
clock, and two processes had accumulated different amounts of unpaused sim time before the
capture paused them. The signature matches that arithmetic: at 1.6 radii an elapsed 61.8 sim s
(0.019 deg of deck) moves mean 1.08 codes with 16.6 % of pixels past 2 and a maximum of 79,
against the 1.34, 20.3 % and 71 measured here, so the two runs differed by roughly 75 sim s of
running. It reproduced within a run because a paused deck stops, which is exactly why it read as
a property of the process.

Fixed on 2026-09-19: the phase is now a closed form in the clock, and the deck's own shadow on
the surface — which had no phase term at all and so fell behind the deck it belongs to — is
carried with it (*The cloud deck's phase* in [VISUAL_MODEL.md](VISUAL_MODEL.md)). **A cross-run
A/B at Earth now has no floor of its own**: an excursion of 426,672 sim s and back to the same
instant, and two separate processes over all six poses, each render 0 of 2,073,600 pixels
changed. The 1-code, tens-of-pixels floor the other three bodies show across processes is
unrelated and remains.


## Addendum: the atmosphere's structure, at runtime

On 2026-09-27 `_atmosphere.gdshaderinc` was rebuilt so that each heavy function is reached from one
call site, inside a loop, for what it saves in compiling (*The atmosphere's structure* in
[SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md)). The same code runs at a different
speed, and the four compiler paths here -- NVIDIA's GL and Vulkan, Intel's GL, and ANGLE's D3D11 on
the Intel iGPU, which is the web's -- disagree about which way, so every figure below names its
path.

**In the app, the atmosphere views.** GPU milliseconds per frame at 1920x1080, sim paused and HUDs
hidden, the old include against the new, interleaved, median; Intel over three processes each,
the GTX over two:

| View | Intel, Compatibility | GTX, Compatibility | GTX, Forward+ |
|---|---|---|---|
| Earth at 3 radii | 84.6 → 75.4 | 6.63 → 4.77 | 5.19 → 5.34 |
| Earth at 1.6 radii | 141.3 → 182.3 | 15.26 → 8.82 | 9.59 → 8.80 |
| Venus at 3 radii | 69.0 → 45.9 | 3.83 → 2.64 | 3.92 → 3.49 |
| Mars at 3 radii | 162.5 → 88.5 | 8.43 → 5.30 | 6.84 → 6.34 |
| Titan at 3 radii | 281.6 → 95.3 | 8.06 → 6.02 | 7.88 → 8.07 |

- **Through NVIDIA's GL every view is faster**, by 25 to 42 %.
- **Under Forward+ every view is within 11 % of the old include**, given the one exception to
  the include's structure described below; without it Earth at 3 radii was 20 % slower.
- **On the Intel iGPU's GL the atmosphere views are faster but for Earth close up**, 29 % slower.
  The new include's runs scatter by about 25 % from process to process on this GPU where the old
  one's hold within a few percent; the ratios are medians over that scatter.

**Evaluated alone**, through the entry-point probe of
[SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md) -- GPU time over a 512x512 grid on the
iGPU and 2048x1024 on the GTX, and the frame interval through ANGLE, which has no GPU timestamps
-- the new include's cost against the old one's:

| Path | Air in front of a disc (`atm_disc_air()`) | Limb |
|---|---:|---:|
| Intel, GL | 2.4 to 2.9 | 0.12 |
| Intel, ANGLE | 1.45 | 1.32 |
| GTX, GL | 0.81 to 0.82 | 1.07 |
| GTX, Vulkan | 1.19 to 1.28 | 0.96 |

Earth close up is the one view the Intel GL disc cost decides: its surface and its cloud deck
each run `atm_disc_air()` over most of the screen, about three million evaluations a frame, where
the limb shell is a thin annulus. Through ANGLE -- the web, on this iGPU -- the atmosphere itself
now costs 1.3 to 1.5 times what it did, which is the price of the web loading at all.

**Why the disc is slower through Intel's GL, which is a property of that compiler worth
knowing.** A disc
shader's lit part in front of the disc, integrated by a plain loop in a shader holding nothing
else of the ray, runs at the old include's speed (0.98 to 1.1 of it); the same loop in a shader
that also holds the half-ray and thin-layer segments, even with those never executing for Earth,
runs at 2.1 to 2.4 times -- the Intel GL compiler evidently sizes a whole shader for its heaviest
part. Three changes that cut the state live across the ray's loop were kept for what they bought
on this GPU (no layer-node arrays, one accumulator, the half-ray's setup skipped when the far half
is off: 0.80 of the limb's cost and 0.87 to 0.93 of the disc's), and a second copy of the node for
the disc was not (it bought the disc 10 to 17 % and doubled the limb's cost).

**Why Vulkan was slower, and the one exception to the structure that it bought.** Through
NVIDIA's Vulkan the whole rebuild at first cost 1.7 to 1.8 times the old include in front of a
disc and 1.34 times at the limb, and what cost was the term loop in `atm_exp_columns()`, not the
loops around it: writing out its common case -- a haze with no top, which is Earth's, Venus' and
Mars' -- takes those to the table's 1.19 to 1.28 and 0.96, where unrolling a node's two columns
instead, the other suspect, changed nothing. Through ANGLE on the iGPU the same change takes 23 to
33 % off both. But under Compatibility its two extra calls slow Intel's GL compiler's whole shader
by 11 to 33 % in the app, airless bodies included, so it is compiled for Forward+ and Mobile only
(`CURRENT_RENDERER`). Compatibility keeps the loop -- desktop GL and the web alike, since the
preprocessor cannot tell them apart.

**Intel's two paths disagree with each other more than with anything else.** Through ANGLE this
iGPU runs the rebuilt limb up to twice as fast as through its own GL driver -- Venus 9.5 against
19.1 ms, Mars 25.7 against 38.7, Titan level -- although what ANGLE's column reports is a frame
interval, which can only overstate a GPU's time. Godot can run Compatibility through ANGLE on
Windows (`rendering/gl_compatibility/driver.windows`, or per device,
`force_angle_on_devices`), and moving Intel iGPUs there would also remove the one reason the Vulkan
exception above is kept out of Compatibility, which ANGLE takes well. Whether to is under *Open
questions*, with what it would take to answer.

**Bodies with no atmosphere pay for its code, and the three compilers here disagree about how
much.** Every airless body -- the Moon, Mercury, Jupiter and most of the rest -- draws with the
same surface shader as Earth, the atmosphere gated off by `atm_present()`, so it runs none of the
atmosphere and carries all of it. GPU milliseconds per frame at 1920x1080, sim paused and HUDs
hidden, two processes each, for the old include, the new one, and the new one with the
atmosphere compiled out of the surface shaders -- which renders an airless body identically:

| View | Intel, Compatibility | GTX, Compatibility | GTX, Forward+ |
|---|---|---|---|
| Moon at 3 radii | 23.7 / 32.1 / 10.7 | 2.96 / 1.26 / 0.97 | 2.68 / 2.65 / 2.46 |
| Moon at 1.5 radii | 55.3 / 80.6 / 18.9 | 7.84 / 2.34 / 1.59 | 4.55 / 4.33 / 3.70 |
| Mercury at 3 radii | 24.1 / 32.5 / 10.3 | 3.12 / 1.21 / 1.08 | 2.64 / 2.73 / 2.49 |
| Jupiter at 3 radii | 36.1 / 44.7 / 23.3 | 4.12 / 2.33 / 2.11 | 4.20 / 4.24 / 4.00 |
| Europa at 3 radii | 27.1 / 35.0 / 12.9 | 3.13 / 1.61 / 1.43 | 3.01 / 3.05 / 2.75 |

- **On Intel the new include costs these views 24 to 46 %**, for code they never execute: the
  whole-shader sizing above, on bodies with no atmosphere to size for. Compiled out, they draw
  in 0.34 to 0.64 of the old include's time.
- **Through NVIDIA's GL it is the new include that is faster, 1.8 to 3.4x**, and compiling the
  atmosphere out takes a further 9 to 32 % off.
- **Through Vulkan the include makes no difference to them** (within 5 %), and compiling it out
  takes 6 to 15 % off. That column predates the Vulkan exception above, which moves these views
  by at most 6 % either way.

**So every disc shader now has an airless variant**, built on 2026-09-27 as the largest runtime
lever the rebuild left. Each shader's body moved into an include (`_surface.gdshaderinc` and the
rest) behind two thin wrappers, and the `.airless` one defines `ATM_AIRLESS`, which
`_atmosphere.gdshaderinc` answers with no-op entry points (THE AIRLESS VARIANT in its header).
`IVAssetPreloader.airless_shader_variants` binds one wherever a body's overlay rows carry no
`atm_*` column -- the same test IVShellsModel applies before it propagates an atmosphere, now one
function for both -- beside the `cube_shader_variants` swap, and IVShaderWarmup warms whatever a
spec resolves to. In the Planetarium that is every body but Earth, Venus, Mars and Titan: the
surfaces of all the rest, Uranus' and Neptune's banded ones among them, and Neptune's cloud deck.

It renders them identically. Screenshots of the eight views below and of Venus, Mars, Titan and
Earth close up, against the build before it on the GTX, are bit-identical on Compatibility for
every airless body, and on Forward+ for all but 4 pixels of Jupiter at 1 code, the floor two
processes show anyway. GPU milliseconds per frame, before and after, the builds interleaved:

| View | Intel, Compatibility | GTX, Compatibility | GTX, Forward+ |
|---|---|---|---|
| Moon at 3 radii | 28.2 → 11.0 | 1.27 → 0.97 | 2.60 → 2.46 |
| Moon at 1.5 radii | 67.9 → 18.1 | 2.75 → 1.59 | 4.28 → 3.66 |
| Mercury at 3 radii | 28.0 → 10.8 | 1.33 → 0.96 | 2.55 → 2.55 |
| Jupiter at 3 radii | 39.0 → 22.9 | 2.36 → 2.23 | 3.96 → 4.02 |
| Europa at 3 radii | 35.0 → 13.8 | 1.87 → 1.32 | 2.96 → 2.74 |
| Uranus at 3 radii | 31.3 → 15.6 | 2.08 → 1.54 | 3.16 → 2.94 |
| Neptune at 3 radii | 48.9 → 21.5 | 2.50 → 1.95 | 4.54 → 3.72 |
| Earth at 3 radii, full shaders in both | 63.7 → 65.3 | 4.38 → 4.40 | 5.33 → 5.24 |

- **On the Intel iGPU these views now take 0.27 to 0.59 of their time**, well under what the old
  include drew them in too. The figures are the first of two rounds: in the second the build
  before fell into this driver's slow state (*Caveats*) and the airless one did not.
- **Through NVIDIA's GL they take 0.58 to 0.95, and under Forward+ 0.82 to 1.01**, the Earth
  control holding within 3 % on every path.
- **A first visit compiles about the same.** An airless shader takes 5.0 to 8.8 s to a first
  draw through ANGLE here, against 16 to 20 s for the full ones, and in the Planetarium no body
  draws the full `surface.gdshader` any more: the web's first visit drops that one and adds four
  airless ones, about 7 s on balance on this CPU.

The same machinery is most of the Off tier the web wants (*First load on the web*): with every
body on its airless variant and the limb shells not drawn, a first visit would compile none of
the quadrature.

A second variant would recover Earth: a disc shader without the far half and the thin layer, for
a body whose atmosphere has neither to show. Earth is that body among the four: it has no thin
layer, and its far half renders bit-identically without it (*Atmospheres* in
[PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md)). Not built either; it is a third program per disc
shader for one body.


## Addendum: below Reduced

Asked on 2026-09-27: is a runtime tier below Reduced worth having, or should Reduced itself be
redefined? Both tiers are one program selecting a rule out of a packed node table, so a lower one
would cost no compile either -- the question is what it gives up and what it buys.

**What it gives up**, from the entry-point probe of *The atmosphere's structure* in
[SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md), on a table extended with the 3- and
2-node Gauss-Legendre rules: each candidate against Normal, as the largest change anywhere and
the 99th percentile, both relative to the image's maximum.

| Earth | Limb, max | Limb, p99 | Disc air, max | Disc air, p99 |
|---|---:|---:|---:|---:|
| Reduced (4 nodes, 2 taps) | 8.0 % | 5.0 % | 0.60 % | 0.15 % |
| 4 nodes, 1 tap | 62 % | 39 % | 0.60 % | 0.15 % |
| 3 nodes, 2 taps | 9.8 % | 5.1 % | 2.9 % | 0.42 % |
| 3 nodes, 1 tap | 62 % | 39 % | 2.9 % | 0.42 % |
| 2 nodes, 1 tap | 61 % | 38 % | 18 % | 3.2 % |

- **The ring cannot go below two taps.** One tap is one sample per pixel, which is exactly the
  dotted arc the pixel filter exists to close (`atm_ring_pixel()`); it moves the limb by 60 to
  100 % of its maximum on every body.
- **Two nodes is too coarse.** The disc's air moves 18 % at Earth and 17 % at Titan.
- **Three nodes and two taps is Reduced plus a little.** The limb moves about as Reduced moves it,
  since the taps decide that; the disc's air moves 1.5 to 5 times as much as under Reduced, 2.9 %
  at worst on Earth and 12 % on Titan, where Reduced moves 8.4 %.

**What it buys**, from the same probe's bench: each rule's cost against Reduced's, the median over
the four bodies, for the air in front of a surface and for the limb. GPU time over 512x512 on the
iGPU through its GL, the frame interval there through ANGLE, and GPU time over 2048x1024 on the
GTX through its GL:

| Against Reduced: disc air / limb | Intel, GL | Intel, ANGLE | GTX, GL |
|---|---|---|---|
| Normal | 1.12 / 1.27 | 1.33 / 1.85 | 1.28 / 1.89 |
| 3 nodes, 2 taps | 1.01 / 0.95 | 0.90 / 0.91 | 0.85 / 0.84 |
| 3 nodes, 1 tap | 0.98 / 0.84 | 0.87 / 0.74 | 0.85 / 0.63 |
| 2 nodes, 1 tap | 0.92 / 0.84 | 0.77 / 0.73 | 0.71 / 0.56 |

- **The one acceptable candidate buys 9 to 16 % of the atmosphere's own cost, and nothing
  through Intel's GL.** The atmosphere being a share of an atmosphere view's frame rather than all
  of it, that is a few percent of a frame, for disc air that moves up to five times as much.
- **Through Intel's GL even Reduced now buys little**: 8 to 17 % off the disc air and 6 to 33 %
  off the limb, where the old include's Reduced took 14 to 21 % and 40 to 47 % (Earth's disc too
  noisy to read), and where ANGLE on the same iGPU takes 25 and 46 %. There the new include's cost is set by the compiler's
  whole-shader sizing (*Addendum: the atmosphere's structure, at runtime*), not by the node
  count.

**So there is no runtime tier worth adding below Reduced, and nothing gained by redefining it.**
What lowers the floor is compiling and carrying less, not iterating less: the airless shader
variants, now built, and an Off tier on top of them, both in the runtime addendum above.
