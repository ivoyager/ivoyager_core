# The Photometric Model

This document describes how I, Voyager renders physically calibrated light: what the
numbers mean, where they come from, and which classes, shaders and settings carry them.
It is about the logic and the science; implementation detail lives in the class and
shader docs.

## Overview

With `IVCoreSettings.enable_physical_light = true` *and* user Option `physical_light =
true`, the simulator abandons its legacy
hand-tuned lighting (the `nonphysical_*` settings) for a single physically consistent
scale. Sunlight follows the inverse-square law, every brightness is derived from catalog
data (magnitudes, radii, albedos), and one absolute anchor ties the whole system to real
sky photometry. Because real scene brightness spans a factor of billions between a sunlit
surface and the Milky Way, a **compensating camera** (`IVExposureManager`) meters the
scene every frame and adapts a relative exposure, the way an eye or a camera on
"auto" would. The system requires `IVCoreSettings.dynamic_lights`.

Four shader globals carry the state to materials:

- `iv_exposure` — the relative exposure. 1.0 is the *authored empty-sky look*; smaller
  values darken self-luminous content (stars, the sky panorama) as the camera stops
  down for a bright subject. Lit surfaces do not read it; they receive exposure baked
  into `light_energy` by `IVDynamicLight` (never both — that would double-expose).
- `iv_emission_luminance_scale` — rendered units per cd/m² (exposure × gain), which
  renders an emission map (city lights) at the physical luminance its `shells.tsv`
  `emission_luminance` column asserts. 0.0 while the system is off.
- `iv_emission_energy_scale` — gates the by-eye emission channel, `shells.tsv`
  `emission_energy_multiplier`: 1.0 while the system is off, 0.0 while it runs. The two
  emission globals are never both nonzero, so a shell authors both columns and the shader
  sums the channels rather than branching.
- `iv_limb_scale` — rebases the atmosphere-limb glow while the system is active
  (see *Atmosphere limbs* below).

Every one is neutral whenever physical light is off — 1.0 where it multiplies an authored
value, 0.0 where it gates a channel the authored look does not use — so every shader
renders the authored look unchanged.

**Why not Godot's own physical light units and auto exposure?**
1. Both come with `CameraAttributesPhysical`, whose exposure and auto-exposure act
*after* tonemapping, on the finished image — so they would drag the HUD and every overlay
along with the scene.
2. Auto exposure is Forward+ only. Our system also runs in Compatibility (e.g., for our
Planetarium web export).
3. Metering the framebuffer would meter the wrong thing: the subject here is often one
body's disc, sometimes a few percent of a frame that is otherwise empty sky. Our system
acts more like an astrophotographer: it has knowledge of subject and understands (based on
custom settings) when to compensate and when to let objects blowout.

## The calibration chain: one anchor

Astronomers measure the brightness of extended objects in **magnitudes per square
arcsecond** (mag/arcsec²) — the magnitude a patch of sky one arcsecond on a side would
have. Smaller numbers are brighter; the darkest night sky is ~22, the Milky Way's
brightest bulge patches ~20.

The single absolute anchor is `IVExposureManager.background_peak_magnitude_per_arcsec2`
(default 20.0): the surface brightness represented by a full-white texel in the Milky
Way background panorama. From it and the star-field settings (`IVStarSettings`), the
manager derives:

- `sky_energy` — the panorama's physical `energy_multiplier` at exposure 1.0 (≈ 0.087).
  This **welds the panorama to the star field**: the star shaders' own photometric chain
  (PSF area, intensity scale, faint-end magnitude, and the FOV/resolution compensation,
  which together model a fixed-f-number camera sensor) is evaluated at the map's
  per-texel surface brightness. Panorama and stars therefore brighten and dim as one
  photometric system, at any FOV or resolution.
- `gain` — rendered units per physical luminance (cd/m²), ≈ 80. Every other luminance
  in the system multiplies this one number to become a screen value.

Pure conversions (magnitude → illuminance, surface brightness → luminance, a star's
disc luminance from absolute magnitude and radius) live in `IVAstronomy`'s Photometry
section.

## Sunlight and ambient

`IVDynamicLight` computes the star's illuminance at the camera's distance from its
absolute magnitude — true 1/r², so Saturn really receives ~1% of Earth's light — and
carries `illuminance × gain / π × exposure` as `light_energy` (times the authored
`energy_multiplier` and the analytic occlusion factor during eclipses). Ambient light
becomes physical **integrated starlight** (`ambient_starlight_illuminance`, ~2×10⁻⁴
lux — the summed light of all stars): the manager rewrites the `Environment` ambient
energy every frame *with exposure folded in*, making the `Environment` the single
ambient authority — engine ambient compensates spacecraft models (plain
`StandardMaterial3D`) directly, and the occlusion manager feeds the same value to the
custom body shaders. The same starlight level is the illuminance floor in metering, so
a fully dark surface meters as starlit terrain.

## The compensating camera

`IVExposureManager` meters per frame and smooths exposure in EV. (An **EV**,
exposure value, is one photographic "stop" — a factor of two in light.)

The model: the camera **rests fully dark-adapted** at `exposure_max_ev` EV above the
authored sky look. That resting state is both the empty-sky exposure far from any body
and the bound night-side adaptation rides to — deep space and deep night are one
continuous state. Metering only ever pulls exposure *down* from rest, and only in
response to what is actually in view:

- Each body contributes two **candidates**: its lit surface (luminance
  `albedo × illuminance / π`, plus the starlight floor) weighted by the lit fraction of
  its on-screen area, and its dark surface (starlight only) weighted by the dark
  fraction. Weights ramp in log screen-fraction space between `meter_fraction_start`
  and `meter_fraction_full`.
- The lit candidate's hold additionally follows the **lit fraction of the disc**
  (`nightside_onset_lit_fraction` → `nightside_full_lit_fraction`): rounding a body to
  its night side, stars and dark terrain emerge gradually while the sun is still well
  above the limb, and a half-lit face is never overexposed. A geometric horizon cutoff
  (`nightside_twilight_angle`) trims the last sliver of crescent close in.
- The sun's disc clips white at any scene exposure, so it is never "lit surface"; it
  meters only when it grows into the subject of the view (its own later ramp,
  `star_meter_fraction_start/full`), and an occluded sun does not meter at all.
- A **screen-edge gate** restricts metering to what is actually in the frame: a body's
  influence ramps from zero as its disc crosses the frame edge to full once its center
  is `meter_edge_fraction` (default 15%) of the frame inside. Panning toward a bright
  planet, it enters the frame still overexposed and compensation completes as it moves
  in; a body just out of frame — the sun behind the camera, most of all — has no
  influence at all.
- A shell that fills in shells.tsv's **`exposure_ceiling`** adds a **ceiling candidate**: an
  exposure the camera may not exceed while that shell is in view, weighted by the shell's own
  screen area on the same ramp and edge gate as everything else, and by nothing else — no
  phase, no lit fraction, no luminance. This is the one metering input that is asserted rather
  than derived, and deliberately: what a rendered atmosphere or a city-light layer should cost
  the rest of the frame is not a photometric question. A camera exposed for a body's disc
  really does blow its limb out, and the reference photographs that show limb structure are
  exposed *for* the limb and show no stars — both are correct, and which one a viewer wants is
  taste. Lower candidates still win, so a ceiling never brightens a view the body's own disc
  has already metered down; it acts only where the others release. Earth's surface shell is
  the shipped cell, for its city lights.
- An atmosphere limb row fills **`limb_exposure_ceiling`** instead, and it is the same
  assertion held by different geometry — because **a limb is a ring, not a disc**, and a
  screen area that credits the whole body holds a ceiling in views that contain no limb at
  all. The limb candidate samples the ring in azimuth on the **disc's** silhouette circle —
  the limb's own foot, which is where its light is and where a viewer sees it — and carries
  the limb's whole height above each foot, up to the limb shell. A sample counts by three
  things. How much of that height is **sunlit**: the shadow is the disc's cylinder, so at a
  foot whose solar zenith is past 90° the shadow stands at `disc / sin(zenith)` and only the
  limb above it is still in daylight — full credit at the terminator, none where the shadow
  tops the shell. Whether it **forward-scatters** toward the camera: the cosine of its own
  scattering angle, the sun's direction against that sample's line to the camera, clamped at
  zero. And how far **inside the frame** that foot sits (`limb_meter_edge_fraction`, wider
  than the body gate because it is also doing centrality). Their share of the ring scales the
  **shell's** screen area, on the limb's own much later ramp (`limb_meter_fraction_start` /
  `_full`) — which is the "how much more readily than a disc may a limb clip" knob, and the
  answer is *much*. So the ceiling holds where the lit ring is the view and releases where it
  is not: zoom past the ring on a close pass over Venus, Mars or Titan, pan it out of the
  window, or swing round to where the sun is behind the camera, and exposure returns to the
  full dark-adapted rest. Earth, Venus, Mars and Titan all fill the cell.
- **A LIT LIMB AND A BRIGHT ONE ARE DIFFERENT THINGS, and only the phase separates them.**
  How much of a limb is out of its body's shadow says nothing about how bright it is, because
  a limb's brightness is dominated by forward scattering: at a fixed foot solar zenith of
  105°, Titan's single-scatter ring radiance runs **2.1e-3 at phase 90 and 2.6e-1 at phase
  168, a factor of 126**, on identical shadow geometry. That is why a shadow measure alone
  cannot tell the two views the camera has to distinguish apart — coming out of a night side
  at phase 70 and blazing backlit at phase 149 put the in-frame limb feet at solar zenith
  109° and 100°, nine degrees apart on the same side of the terminator, while the rendered
  frame is black in one and 6.5 % clipped in the other. Neither term substitutes for the
  other: the shadow alone fires on a black frame, and forward scattering alone fires on a
  limb that is fully in the body's umbra. Their product tracks the rendered frame — measured
  over a full rotation at the camera floor, every zero-product view clips at most 0.1 % of
  the frame and every non-zero one at least 1.2 %.
- **The two radii of a limb do different jobs, and one circle cannot do both.** The foot is
  where the ring is on screen and where its shadow question has to be asked; the shell is how
  tall the answer is and how big the thing is in the frame. Asking both at the shell puts
  every question about the limb further around the body than the limb the viewer is looking
  at — 15° of body arc from Titan's camera floor, where the disc's silhouette stands 41° off
  axis and the shell's 56° — and it asked the shadow as a yes/no at one radius, so the whole
  in-frame arc crossed together and compensation stepped. Measured on Titan at the camera
  floor with the limb panned through screen centre: coming out of the night side, that step
  put the camera at full compensation with the terminator still a frame and a half off screen
  and *nothing* in the frame clipping; and going the other way it released while the limb was
  still blowing out 5.5 % of the frame, 85 % of its own peak. Taking the foot from the disc
  and grading by lit height fixes both — the release now spans 25° of rotation instead of 9°,
  and the onset arrives with the terminator at the frame edge.
- The winning (lowest) candidate becomes the target; exposure glides toward it at
  `adapt_darken_ev_per_second` / `adapt_brighten_ev_per_second`, or snaps when the jump
  exceeds `snap_ev_threshold` (camera teleports).

At full metering a body's light energy is `metering_key / albedo`, which renders a
surface whose map matches its albedo at the mid-exposure key. `meter_transition_exponent`
shapes the zoom-out experience: how gradually a body overexposes versus how quickly the
stars then arrive.

Unshaded HUD content (orbit lines, labels, small-body points) reads none of this and is
identical at every exposure.

## Body surfaces and albedo

A surface albedo map is rendered as `map × N·L × light_energy` — the engine supplies
the sun angle (Lambert shading), so the map must carry **reflectance, not baked
lighting**. The convention, shared with the asset pipeline: **a map's sphere-averaged
linear luminance equals the body's V-band geometric albedo** (the `albedo` column in
the body tables). *Geometric albedo* is the standard catalog quantity: the body's
full-phase brightness relative to a perfect flat white reflector of the same size. The
identity is a consistency convention rather than physics — under a Lambert falloff a
sphere disc-integrates to 2/3 of its map mean, measured 0.644 on the shipped Moon — but
with metering holding `light_energy = metering_key / albedo`, any body whose map follows
it renders at the same correct exposure. The disc photometry section below closes most of
that 2/3 for the bodies it covers, and it does so without touching any map level.

Notes and special cases:

- Table albedos follow Mallama et al. (2017) for the planets. **Earth is deliberately
  its cloudless value** (0.15, not the with-clouds 0.43): the surface map carries no
  clouds, so metering against the cloudless albedo exposes the surface correctly and
  lets cloud tops run bright, exactly as in real photographs (see *Cloud shells*).
  Earth is also the one body whose map and table value do not agree, by 2.4× — its map
  means 0.0614 — and that gap is the anchor doing its job rather than an error:
  solid-angle weighted, the map's land mean is 0.182 with the ice sheets and 0.097
  without, so 0.15 sits inside the continents' own range.
- **A map carries whatever a body's shells do not**, and for Earth that question is now
  settled: the map holds **surface** reflectance throughout, and the renderer draws the
  atmosphere over it (see *Atmospheres*). A top-of-atmosphere build was tried and reverted:
  a map carrying the atmosphere over water and not over land is neither of the two things a
  reference image ever is, a surface-reflectance product or an exposed photograph. The
  ocean therefore stays at its water-leaving level (luma 0.0084) and the Rayleigh veil,
  drawn by the atmosphere shell over the whole disc, supplies the atmosphere's share
  — which is why that share was never baked into the map.
- Spacecraft and small-body values are **derived from the shipped models** (measured
  render response at sun-facing geometry), not from literature — they exist to expose
  the model correctly.
- A body with no albedo value meters at `IVExposureManager.default_albedo`; an empty
  table cell is treated as unknown, never as zero.
- A body with **no color map at all** renders its surface class's `fallback_color`,
  which `IVAssetPreloader` rescales in linear light so its luminance equals the metering
  albedo — a mapless grey moon exposes exactly like a mapped one, and shows its true
  darkness next to its parent planet. That rescale is **clamped at `1.0 / max_channel`**,
  so a body brighter than white renders at reflectance 1.0 while metering divides by its
  table value: Calypso (1.34) and Helene (1.67) land at 75 % and 60 % of key. Accepted as
  it stands — a flat class colour is a placeholder standing in for a body nobody has
  imaged, so it is not worth the exactness a real map gets.
- Very bright icy bodies owe their catalog value to coherent backscatter at full phase
  (the *opposition surge*), which the shading model does not have. That is **not** a
  reason to hold their maps under key: a geometric albedo is a zero-phase quantity, so
  `map mean = p` carries each body's own surge as a level, exactly as it does for every
  other body in the set. Dione, Rhea, Tethys and Enceladus were levelled to their full
  table value on 2026-08-17, the two above 1.0 (Enceladus 1.375, Tethys 1.229) through
  **range tags**. The mapless members of the family are clamped at 1.0 instead, as above.
- The convention covers a packed `.glb` body's **embedded base-color texture** exactly
  as it covers a cube strip. A model whose texture was authored for display rather than
  reflectance is corrected at the texture, never by moving the table value — the table
  carries the catalog albedo and metering divides by it. Two things differ from a strip.
  The level is the texture weighted by **surface area over the mesh**, not a flat mean of
  the image: a model's texture is a UV atlas that is a third to a half unused, and the flat
  mean blends the body with whatever that background happens to be. And the texture is the
  body's **only** lever — a packed model keeps the `StandardMaterial3D` the glTF importer
  authored, so it has no range tags and no disc-photometry term (see the TODO).
- **One frame serves both surface paths**, which is what lets a map be authored without
  knowing which path will draw it. A spheroid samples its cube on the shared `SphereMesh`'s
  own UV, and a custom mesh is authored as that same sphere displaced — same frame, same
  unwrap — so the two are interchangeable and a body can gain a mesh without re-registering
  its maps. Every equirect master is **centred on the prime meridian**, with no per-body
  offset: `map_offset` was removed once it was established that no shipped map had ever set
  one. A model-space direction renders at east longitude `atan2(−x, −z)`.

Two things the asset side does to satisfy it are worth knowing here, because they
constrain what a map can look like. A map whose display stretch carries more ratio
contrast than its body has reflectance range cannot be **gained** to level — the gain
that lifts the mean drives bulk terrain, not a tail, past white — so it is
**de-stretched**: a power law in linear light with chromaticity untouched, the exponent
solved as the least compression that reaches the target without clipping. And a map
whose reflectance occupies a narrow slice of [0, 1] is stored **packed** into that
slice, with the slice named in the file (see the next section).

## Range tags: a texture's own reflectance range, named in its file name

An albedo map stores reflectance in [0, 1], but no body *uses* [0, 1] — Deimos tops out
near 0.25 and Triton bottoms out near 0.30, so both spend most of their 8 bits on values
that never occur. A texture may therefore be stored **packed** into its own range, with
that range specified in the file name (so it cannot be detached from the file accidentally):

```
Triton.albedo.1024.l02462.png
Saturn.albedo.1024.l01682.h08149.png
Io.albedo.1024.lr00679.lg00562.h13169.hg10775.hb10724.png
```

`l` and `h` are the physical linear values that the file's 0.0 and 1.0 stand for, in units
of 1e-4 — five digits, so `h08149` is 0.8149 and the range reaches 9.9999. The file stores
`(physical − lo) / (hi − lo)`, and the four shaders that sample an albedo map —
`surface.gdshader`, `surface.cube.gdshader`, `cloud_shell.gdshader` and
`cloud_shell.cube.gdshader` — recover physical light with one affine step before
`albedo_color` (or `clouds_color`) is applied. `IVAssetPreloader.parse_range_tags()` reads
them; `IVShellsModel` feeds them as the `albedo_range_lo` / `albedo_range_hi` uniforms, per
shell, so an overlay deck is packed on the same terms as a surface.

An **`r`, `g` or `b` after the letter narrows a tag to one channel**, and channel tags are
applied after the un-narrowed ones whatever order the name lists them in. So a name carries
one number where the channels agree and an override only where they do not — Io above says
red runs to 1.3169 while green and blue stop near 1.07, and says it in five tags rather than
six numbers. A map that runs out of headroom in a single channel is what this is for.

Four properties make this work and constrain any future extension:

- **Affine, never a gamma.** An affine reconstruction commutes with filtering and mip
  selection, so a packed map mips correctly, and it maps a flat fill to a flat fill, so an
  unimaged region stays a single BC1 block. A per-asset gamma would buy slightly more
  precision and break both.
- **The bounds are containment, not a fit.** They come from the map's true extrema rounded
  outward onto the tag grid, so packing cannot clip a texel.
- **Defaults are the identity and are never written.** `lo` is 0.0 and `hi` is 1.0 unless a
  tag says otherwise, each independently, so an untagged file renders exactly as before and
  a tagged one states only what is not already true — `.l02462` alone, never a redundant
  `.h10000` beside it. This is additive; no existing asset has to move.
- **`hi` above 1.0 is meaningful, not an error.** It says the texture holds reflectance a
  channel really reaches past white — how a strongly backscattering surface, or an
  over-saturated bright terrain like Io's, is represented rather than flattened to fit a
  limit only 8-bit storage imposed. Nothing in the chain clamps it, and that is not an
  assumption: `rings.gdshader` has driven `ALBEDO` far above 1.0 since well before this
  work, for the same reason at a much larger factor.

**It is not only an 8-bit win.** A body cubemap imports as BC1, whose 5-bit red and blue
endpoints are 8.23 DN apart, so a map whose whole signal is smaller than one endpoint step
comes through as blocks rather than as faint detail. Packing puts the signal across the
full scale *before* compression.

**Metering is unaffected.** `IVExposureManager` divides by the body's table albedo, and the
shader restores exactly the values an unpacked map would have shown, so the tag is
invisible to exposure by construction.

## Disc photometry: how brightness falls toward the limb

The engine's diffuse gives radiance proportional to `µ₀` (cos incidence), and an airless
regolith body does not do that. At full phase such a body is nearly **flat** across its
disc — the full Moon reads as a disc, not as a lit ball — so a cos falloff renders half
the projected disc about 1.4× too dark and its outer quarter about 2× too dark.

The law is **Lunar-Lambert** (McEwen 1991; ISIS `lunarlambert`), a one-parameter blend of
Lommel-Seeliger and Lambert:

```
I = A · [ 2L · µ₀ / (µ + µ₀) + (1 − L) · µ₀ ]
```

`L = 0` is Lambert exactly and `L = 1` is Lommel-Seeliger, which is uniform across the
disc at zero phase. It is preferred to Minnaert (`µ₀^k · µ^(k−1)`) because its radiance is
bounded everywhere — Minnaert's diverges at the limb and needs a clamp with no physical
meaning — and because `L` is the parameter planetary photometry publishes.

`_photometry.gdshaderinc` holds it, shared by `surface.gdshader`,
`surface.cube.gdshader`, `band_pattern.gdshader` and the two `cloud_shell` variants, so no
path can drift from another. Four properties are what make it cheap:

- **It rides on `ALBEDO`, not a `light()` override.** The engine's diffuse already
  supplies the leading `µ₀`, so dividing that out leaves `ALBEDO *= 2L/(µ + µ₀) + (1 − L)`.
  The specular lobe (Earth's sun glint), `AO` / `AO_LIGHT_AFFECT` and the shadow path all
  stay on the built-in path.
- **It is an exact no-op at `µ = µ₀ = 1`** — the subsolar-subobserver point, which is what
  metering keys and what every map is authored to (the disc-core rule). So no map level
  changes and the exposure chain is untouched.
- **It takes the macroscopic normal**, not the normal-mapped one. This is a law about the
  body's disc; per-texel relief is the normal map's job. The equirect path gets that for
  free (the engine applies `NORMAL_MAP` after `fragment()`); the cube path, which writes
  `NORMAL` itself with relief in it, builds the macroscopic normal from `dir`.
- **`VIEW` survives farwarp unchanged**, because the remap scales a view-space position
  along its own ray and so leaves screen direction alone.

`L` is a `shells.tsv` column, so it is per surface class with a per-body override
available. It ships as **1.0 for `ICE_WORLD` and 0.6 for the other airless regolith
classes** — `ROCKY_WORLD`, `DESERT_WORLD`, `VOLCANO_WORLD` and the three asteroid
classes — and is left empty (Lambert, unchanged) everywhere else. 1.0 is Lommel-Seeliger,
which is what a flat disc at zero phase means; the 0.6 is an **in-app judgment**, made
because a constant 1.0 read overbright on those bodies across the range of phase angles
the app actually shows. That is the `L(α)` gap below wearing a different hat: a constant
fitted at full phase is too generous everywhere else, and 0.6 buys back the average at
the cost of the zero-phase case it was derived from.

**The opposition surge `B(α)` is deliberately absent, and it cancels rather than being
missing.** A catalog albedo is a zero-phase quantity, so every map already carries its own
body's surge as a level, and metering has no phase term either
(`lit_luminance = albedo · illuminance / π`). Adding a surge to the shader alone would
therefore *dim* every body at `α > 0`, and adding the CPU mirror the rings use for their
phase boost would cancel it straight back out for any body metering on its own. What the
omission really costs is a small-phase difference between two bodies sharing one frame,
across a coherent-backscatter peak one or two degrees wide.

### An overlay shell must carry its surface's law

A shell over a surface reproduces its body's map only through the alpha blend
`A·C + (1−A)·S`, which is an identity when the shell's colour is the map's own — where a
feature is opaque the result is the map, where there is none it is the surface. Two
different laws break that identity **everywhere except the subsolar point**, and
progressively: the mismatch is the ratio of the two disc factors, which grows without
bound toward the limb.

Neptune is the worked case and the only body in the shipped set where the question arises.
Its surface took `lunar_lambert` 0.466 on 2026-08-18 while its cloud deck was still
Lambert, which put **the whole projected disc more than 10 % out, 42 % of it more than
20 %, and 7.4 % of it more than 50 %** — the composite running 19.4 % dark on average over
the deck's own texels, and every feature reading as a dark smear toward the limb.

So a deck takes its surface shell's own `lunar_lambert` / `minnaert_k`. This is a table
entry rather than something inherited automatically, because a deck over a Lambert surface
correctly wants neither and Earth's is exactly that: **if a surface shell sets either
column, its overlay shells must set it too.**

### The other direction: Minnaert for a cloud deck

Venus, Titan and the giants are limb-*darkened* relative to Lambert, so Lunar-Lambert is
the wrong law for them — and a negative `L` does not reach the other direction, it puts a
hard black ring around the limb (the zero-phase radiance `L + (1−L)t` crosses zero at
`t = |L|/(1+|L|)`, costing 2.8 % of the disc area at `L = −0.2` and 11 % at `L = −0.5`).
The law for that direction is **Minnaert**, `I = A·µ₀^k·µ^(k−1)`, in the same
albedo-factor form `ALBEDO *= (µ₀·µ)^(k−1)`. For `k > 1` the exponent is positive, so it
is bounded by 1, never negative, and still exactly 1.0 at `µ = µ₀ = 1`; only `k < 1`
diverges, and that direction is Lunar-Lambert's job.

It lives in the same include and is carried by `band_pattern.gdshader`, which is what the
cloud-deck bodies actually use, as the `minnaert_k` column. Two bodies have a measured
value and carry it: **Venus 1.35** (MESSENGER/MASCS, visible band) and **Titan 1.085** (a
full-Minnaert fit to PIA14602). Centre-relative radial mean at full phase:

| r/R | Venus k=1 | Venus k=1.35 | Titan k=1 | Titan k=1.085 |
|---|---|---|---|---|
| 0.50 | 0.905 | 0.833 | 0.880 | 0.863 |
| 0.87 | 0.660 | 0.444 | 0.633 | 0.575 |
| 0.97 | 0.465 | 0.221 | 0.445 | 0.371 |

`band_pattern.gdshader` carries `lunar_lambert` as well, for the `k < 1` direction, and
**Uranus and Neptune were each measured rather than assumed similar**. Irwin et al. (2024)
Fig. 8 has a panel per planet, so neither has to inherit the other's law:
`scripts/irwin_limb_darkening.py` in the build project fits `I = A·µ₀^k·µ^(k−1)` over each
disc with the subsolar direction free — necessary because Voyager met both at a non-zero
phase angle, so the bright point sits off disc centre and an azimuthally averaged radial
profile folds that offset in and reports it as limb darkening.

| planet | panel (a) | (b) | (c) | adopted k | F | `lunar_lambert` |
|---|---|---|---|---|---|---|
| Uranus | 0.789 | 0.788 | 0.786 | 0.788 | 0.777 | 0.330 |
| Neptune | 0.717 | 0.719 | 0.713 | 0.716 | 0.822 | 0.466 |

Each planet's spread across three independently processed panels is ≤ 0.006, against a
0.072 gap between them — **twelve times the measurement's own scatter**, so the difference
is real and Neptune is measurably the flatter of the two. Uranus's 0.788 also reproduces
the 0.767 in the build project's `records/Uranus.md`, arrived at by a different fit, which
is the cross-check that makes the method believable. The `L` values match each `k`'s disc
factor rather than its pointwise profile: no `L` reproduces a `k < 1` curve pointwise, and
the best pointwise fit is set by the last few percent of the limb, where the figure is
JPEG ringing. Jupiter and Saturn have no measured value here and stay Lambert.

### Level and law are coupled

**A body renders its catalog geometric albedo only if `A × F = p`**, where `A` is the
map's or parameter's level and `F` is its law's disc factor — the fraction of the
subsolar level that the full disc averages at zero phase:

| law | F |
|---|---|
| Lunar-Lambert | `(2 + L)/3` — 1.000 at L = 1, 0.867 at L = 0.6, 0.667 at Lambert |
| Minnaert | `2/(2k + 1)` — 0.631 at k = 1.085, 0.541 at k = 1.35 |

The sphere-mean convention (`A = p`) is therefore exact **only at F = 1**, i.e. only under
Lommel-Seeliger. It is where *"a Lambert sphere would want 1.5×"* comes from — 1.5 is
1/F — and it is why metering, which keys the *subsolar point*, can be right while a
**face-on disc reads wrong**: the eye judges the disc average, and that is `F` times what
metering set.

The four bodies with no map — Venus, Titan, Uranus, Neptune — were exempted from the
asset-side level pass on the belief that `albedo_color` already carried the convention.
It did not, and because their `F` is 0.54–0.67 the error was large enough to see. Measured
against `A = p/F`, and corrected 2026-08-18:

| body | law | F | A was | A needed | rendered at | now |
|---|---|---|---|---|---|---|
| Venus | Minnaert 1.35 | 0.541 | 0.777 | 1.275 | 0.61× | 1.00× |
| Titan | Minnaert 1.085 | 0.631 | 0.657 | 0.349 | 1.88× | 1.00× |
| Uranus | L = 0.330 | 0.777 | 0.559 | 0.628 | 0.76× | 1.00× |
| Neptune | L = 0.466 | 0.822 | 0.476 | 0.538 | 0.72× | 1.00× |

Two shader consequences. **Titan's level lives in two places**: `band_pattern` builds its
base as `mix(albedo_color, band_tint_color, …)`, so both endpoints carry level and scaling
one alone leaves the tinted regions behind. And **Venus needs `A` above 1.0** — at
`p = 0.689` it would under *any* law in this family, Lambert included — so the shader
gained `albedo_ceiling` (the band-top clamp, 1.0 being a storage convention rather than a
physical bound) and `albedo_scale` (physical reflectance per unit of `albedo_color`, since
an sRGB `Color` cannot hold a channel above 1.0).

**The mapped bodies are not corrected for this**, and the residual is uniform rather than
per-body: they follow `A = p` at L = 0.6–1.0, so they render at 0.87–1.00× of their
catalog albedo. That spread is small enough to read as correct, which is why only the four
outliers were reported.

Measured on the shipped Moon albedo and normal cubemaps at full phase, radial mean
relative to disc centre:

| r/R | L = 0 | L = 1 |
|---|---|---|
| 0.25 | 0.900 | 0.922 |
| 0.50 | 0.797 | 0.892 |
| 0.71 | 0.620 | 0.808 |
| 0.87 | 0.519 | 0.869 |
| 0.95 | 0.408 | 0.926 |
| 0.99 | 0.288 | 0.997 |
| **disc-integrated / (centre × area)** | **0.644** | **0.884** |

The 0.644 is the 2/3 above, arrived at from the render rather than from the geometry, and
`L = 1` takes it to 0.884 — the residual is the Moon's own albedo structure, not the law.

**What the constant costs.** Real `L` falls with phase angle (McEwen: about 1.0 at full,
about 0.5 by 90°), so a constant 1.0 is right where it was anchored and progressively too
generous toward the terminator as a body swings away from full. Making `L` a function of
phase is the refinement; the shader already has both `µ` and `µ₀` in hand and the phase
angle is one dot product away.

## Night-side emission

A body's emission map (Earth's city lights) is self-luminous, so it reads
`iv_emission_luminance_scale` — exposure × gain, pure units and exposure — against the
per-body `emission_luminance` column in `shells.tsv`, which states in cd/m² what a
full-white texel of that body's map is. The level is per body because it is a property of
the map, not of the renderer: a single global scale could only ever be right for one body,
and would silently mis-state the second one.

**Earth is anchored at 0.3 cd/m².** Two independent routes agree on 0.1–1 cd/m² for the
brightest urban cores viewed at nadir:

- VIIRS DNB radiances for bright cores run ~100–500 nW/cm²/sr, i.e. 1–5 × 10⁻⁵ W/m²/sr
  band-integrated; at an effective ~150 lm/W across the DNB passband for warm city-light
  spectra that is 0.15–0.75 cd/m².
- Built up from the ground, lit pavement at ~20 lux and ~0.1 albedo returns 20 × 0.1 / π
  ≈ 0.6 cd/m², and area-averaging a city over its dark roofs, parks and gaps gives
  ~0.05–0.3 cd/m².

0.3 sits mid-range and deliberately lets the brightest cores oversaturate. What it is
anchored *to* is the weak link, not the arithmetic: the shipped map is a **visual** Black
Marble product whose intensity keeps its full 8-bit span, so 255 DN is wherever the
imagery producers stretched white — near the brightest real cores, but not a measured
radiance. VNP46A4 is the calibrated-radiance product if this is ever to be measured
rather than reasoned.

The map must be **true black where there is no light**, because the emission chain
multiplies whatever is there by ~6,400× at the exposure a deep-night camera reaches:
a source whose "black" is a faint floor lights the whole night side, and any dim tint that
8-bit rounding cannot represent arrives as saturated speckle. Point sources on true black
are also **BC1's worst case**, so an emission strip is imported lossless while surface
maps are not.

**Emission does not meter, and that is a decision rather than a gap.** A body's lights do
not participate in the exposure they are rendered at, so an all-night-side view exposes as
if they were not there. Physically that is where it belongs — rural lighting is ~10³× and
city cores ~10⁵× starlit terrain, so at a dark-adapted rest exposure everything lit is
honestly blown out, as in real ISS photography where exposing for the cities loses the
stars. What the physical anchor changed is the *extent*: the chain is now ~192× a linear
texel at rest exposure rather than the ~6,400× above, so clipping begins around 16 DN
instead of ~1 DN and the dim tail (villages, roads, fishing fleets) renders in range for
the first time while city cores still clip. Judged in-app once the lights came down to
physical levels, metered for starlight, that blowout reads correctly and needs no camera
term.

Expect clipped cores to keep a coloured fringe. The map's authored 3000 K tint is linear
(1.0, 0.19, 0.02) — a 50:1 red-to-blue ratio, ~5.6 EV — so the channels clip in sequence
and a core reads white at the centre through yellow and orange rings on the way out. That
spread is a property of the tint, not of the level: lowering the anchor moves the rings
inward but cannot close them. Metering emission into the camera is the one thing that
would, which is why **bloom reopens this question** — a bloom pass spreads a clipped core
outward instead of containing it, so the decision above is worth re-judging when one
lands.

## Shell effects

Shells (`shells.tsv`) are concentric sub-models around a body's surface.

### Cloud shells

A cloud deck (e.g. Earth's) is an overlay shell whose color is white with coverage in
the alpha channel. It is lit by the same light as the surface, so under an exposure
metered for the *cloudless* surface albedo, cloud tops overexpose by a factor of a few —
bright, occasionally clipped white, which matches real orbital photography. No separate
cloud compensation exists, deliberately: compensating for clouds would crush the surface.

### Atmospheres

`atmosphere_limb.gdshader` draws a body's atmosphere on an enclosing overlay shell (Earth
at scale 1.035, Venus 1.032, Titan 1.415, Mars 1.07) as **single scattering of sunlight
along the view ray** through up to three layers authored on that shell's `shells.tsv` row —
a Rayleigh gas and a Henyey-Greenstein haze, each exponential in altitude (the haze may
have a TOP, above which its scale height changes), and a Gaussian detached layer — with one extinction optical depth per sRGB channel at the disc, an
albedo and an asymmetry (the `atm_*` columns; `_atmosphere.gdshaderinc` documents every
one). Five looks come out of the one integral and the physical parameters alone: the thin
bright band beyond the limb (the ISS "blue band", ~33 km to half brightness on Earth, which
is the Rayleigh tangent-path number), the veil in front of the disc that brightens toward
its edge (what EPIC's full disc shows), the twilight stratification where a grazing sun
reddens, the forward-scattered ring and cusp extension of a backlit crescent, and Titan's
stacked haze shells.

The numbers are physical ones. Optical depths are derived where a law exists (Bodhaine's
Rayleigh atmosphere; CO₂ cross-sections against surface pressure) and typical literature
values where one does not (a global-mean aerosol; Mars at a clear-season dust 0.4); the
build tree's `scripts/atmosphere_params.py` turns the spectral laws into the three channel
values and `scripts/limb_model.py` verifies the shader's quadrature against a numeric
single-scatter integral (within 11 % worst case). Titan's opaque disc is its haze's optical
limb — 295 km up, where the tangent optical depth at 550 nm reaches 1 — not its surface,
and the haze the shader carries is the column above that disc.

- **An aerosol has a top, and modelling it as a pure exponential erases the structure a
  detached layer is detached FROM.** `atm_haze_top_km` / `atm_haze_top_scale_height_km` give
  the haze a second, shorter scale height above a break altitude. Titan is the case: the
  Doose scale height that fits its main haze near the disc extrapolated seven e-folds up to
  the detached layer, which left the layer buried under the main haze's forward-scattering
  peak at exactly the high phases where the reference frames show it best (contrast 1.36× at
  30° falling to nothing beyond 150°). With the top at 80 km above the disc (375 km altitude,
  the main haze top the Cassini-era literature describes) and a 10 km scale height above it,
  the modelled gap minimum lands at 407–429 km — inside the published 400–450 km separation —
  and the shell renders 1.8–2.3× the gap from phase 90° to 175°. The break removes mass, it
  does not redistribute it: `atm_haze_tau` still means the column the unbroken exponential
  would have, and the profile below the top is untouched, so the bright ring's own level moves
  under 5 % below 40 km.

How it lands in the renderer:

- The shell's output is **I/F riding `light_energy` like a surface**: its custom `light()`
  adds `LIGHT_COLOR × ATTENUATION / π`, so a texel reads `I/F × light_energy`, exposure
  included, with no rebase. It composites with `blend_premul_alpha` — the path radiance
  added, what lies behind kept by one minus the luma of the transmittance — and the
  chromatic part of that transmittance is applied by the surface and cloud shaders
  themselves (`atm_view_tint`), which is exact and lets a cloud deck 10 km up escape the
  air beneath it.
- **Every shell of the body takes its sunlight through the same atmosphere.** `IVShellsModel`
  propagates the limb row's `atm_*` columns to the surface and cloud shells, whose photometry
  slot multiplies its sunlight by `atm_sun_transmittance` — the column above that shell's own
  altitude along the sun ray. This is what turns a cloud deck at the limb the colour of sunset.
- **That factor is the TOTAL illumination, direct plus diffuse, and not `exp(-column)`**
  (2026-08-28). Absorbed light is gone and takes the exponential; scattered light is not, and
  the sun leg is the one place nothing else accounts for it — a view ray's scattered light IS
  the path radiance, which the model adds separately, so `atm_view_tint` and the limb's alpha
  keep `exp()` and must. The split needs no new parameter, because the delta-scaling's own
  depth already contains it: `1 − ωg = (1 − ω) + ω(1 − g)`, absorption plus delta-scaled
  scattering. The scattered half then takes the conservative two-stream `1 / (1 + ¾τ)`, exact
  in the diffusion limit, which against real sky-plus-sun illuminance holds to a few percent
  from noon down to a solar zenith of 87°. Earth's surface at its own terminator had been
  reading 7.4e-4 of vacuum in green — the direct beam alone, at an airmass of 34 — which is
  why nothing beneath the glow survived there. It costs one divide and no new column
  evaluation. What it changes, over the lit half of a disc at phase 90 in linear light:
  Earth +2.0 %, Mars +6.9 %, falling to +0.3 % and +2.4 % near the subsolar point where the
  anchoring is defined; Venus and Titan move under 1 %, their air being thin above their
  optical limbs.
- **Every disc is fully covered, and that is a rule about the map rather than a setting.**
  The disc branch draws over the whole body, so a shell beneath an atmosphere must carry
  SURFACE reflectance and let the renderer supply the rest; a top-of-atmosphere map would
  count the air twice. Earth was built that way from the start (land 0.15 → ~0.16 with the
  veil; the ocean's surface level plus the veil lands near the 0.04 a TOA product shows), and
  the other three were re-referenced on 2026-08-24 — Venus and Titan in their `albedo_scale`
  and `albedo_color` cells (×1.045/1.058/1.100 and ×1.020/1.028/1.034), Mars in a range tag on
  its albedo cube (`Mars.albedo.2048.h13575.hg13592.hb13387.png`, ×1.357/1.359/1.339, sphere
  mean 0.170 → 0.231). Each body's level at the disc core is unchanged by construction; what
  the veil adds is the darkening toward the limb — Mars 0.90 of its old brightness at
  μ = 0.42 and 0.83 at 0.14, a limb darkening a Lambert disc did not have.
- **This was a per-body uniform until the last two bodies were re-referenced.**
  `atm_veil_extent` mixed the disc term against a rim-and-twilight window, for a body whose
  map already carried its own atmosphere. With every body converted it was identically 1, so
  it was retired along with `atm_veil_window()` and the `mix` in `atm_sun_transmittance` and
  `atm_view_tint` (both of which lost an argument). Removing it re-rendered all four bodies
  bit-identically but for a single pixel of Mars at 1 DN, a last-ULP difference where the old
  `mix` compiled to a fused multiply-add. It bought no performance either way: `atm_limb()`
  called `atm_disc()` unconditionally and applied the window afterward, so an extent-0 body
  always paid for the disc quadrature and discarded it. What retiring it forfeits is an
  early-out that was never implemented, over the 91 % of a low-phase disc where the window
  was exactly 0.
- **What lies BENEATH an atmosphere is not attenuated by its full extinction.** A
  forward-scattering aerosol returns most of what it removes to the beam's own direction, so
  the transmittance a surface or cloud shell rides is delta-scaled: `τ* = τ(1 − ωg)`, computed
  once per fragment in `atm_layers()` and applied in `atm_exp_column_beneath()`. Rayleigh air
  is g = 0 and stays unscaled, which is right — its removal from the direct beam is real and
  is what reddens a low sun. **No source term is scaled**, so the ring and the disc's own path
  radiance are bit-identical and the partner relation `g* = g/(1+g)` never appears (g enters
  only the phase function). It is a stand-in for the multiple scattering this model does not
  carry and is deliberately not energy-conserving: the light it stops removing is not
  re-deposited anywhere. Two-way transmittance at the disc core, before → after: Mars
  0.437 → 0.700, Earth 0.632 → 0.741, Venus 0.886 → 0.939, Titan 0.912 → 0.966 (green). This
  is what lets a dusty disc take a full veil at all — undscaled, Mars' would have darkened to
  0.52 of its brightness at μ = 0.5 and kept 6 % of its terrain contrast at μ = 0.2.
- **The shell must outrun the profile.** The shader draws on the limb shell's front faces, so
  a ray whose tangent altitude clears the shell gets no fragment: the atmosphere is cut off
  there, and if it is still rendering at that altitude the cut is a hard edge against the sky.
  The roll-off is about one e-fold of the scale height per step and spans ~8 of them from
  clipped white to invisible — 60 km on Earth, 500 km on Titan — and overexposure slides the
  whole band outward without narrowing it, so the shell has to clear the fade-out altitude at
  the *worst* exposure the camera can hold while a lit limb is in frame (dark-adapted against a
  crescent, ~23 EV over on Earth). That is what sets the `scale` cells: Earth 1.035, Venus
  1.032, Mars 1.07, Titan 1.415. Measured, not guessed — see `tables/README.md`. The shader
  then fades the ring out over the last three scale heights of whatever shell it is on, so the
  boundary is a ramp at any exposure and an under-sized shell costs the faintest part of the
  roll-off instead of showing an edge.
- **A ray that meets the disc keeps BOTH halves of its tangent path, because the disc is not
  always a surface.** Where it is — Earth's, Mars' — the far half is extinguished by the ground
  and by the column above it (tangent optical depth 27.3 and 18.3 at the disc), and a hard
  bright ring against a black backlit disc is what a photograph shows. Where the disc is the
  body's own *optical* limb, it is a stand-in for haze that really does transmit: Titan's sits
  at tangent optical depth 1.0, so discarding the far half threw away 0.60 of the ray at the
  rim — a 1.60× step sunlit — and at high phase threw away *all* of it, since the lit part of a
  backlit ray is entirely the far half. That was a 255 → 0 cliff in one pixel, and it cut off
  the whole warm inner band of the backlit ring. `atm_ray_half()` now runs for the far half too,
  at the ray's own tangent altitude *below* the disc and floored at the disc, which makes its
  view extinction `tangent column − own column above z` exactly as for the ring — (down to the
  far surface) + (the sub-disc chord) + (the near half) — with no new term. Rendered, the rim
  is continuous at every phase, and Earth and Mars are **bit-identical** while Venus gains at
  most 3 DN over 204 pixels of its rim.
- **What ends the far half is that chord, so its gate is set on the chord's own EXTINCTION and
  not on a count of scale heights.** The two coincide only for a body whose disc tangent
  optical depth is already of order the threshold. A fixed `h_v > −2 H_ref` cut Titan where the
  chord had attenuated the half by e^−7.5 — four orders of magnitude over its own night side —
  so at the dark-adapted rest the glow ended on a hard circle 90 km inside the disc that reads
  as a second surface behind it. The gate is now the depth at which the chord reaches
  `ATM_FAR_GATE_TAU` = 30, taken on the channel with the thinnest chord (the one that reaches
  deepest) and computed in altitude before any `exp()`, for the reason the 46 H_ref lit-window
  above gives. Per body that is Earth −2.2 km, Mars −5.9, Venus −9.1 and **Titan −163** against
  a former −16.9 / −22.2 / −10.0 / −90; only Titan's moves anything, and there the ring's inner
  edge goes from a one-pixel cliff to a 40 km exponential roll-off that reddens as it dims,
  because red is the channel the chord thins last. Everything from 80 km below the disc outward
  is unchanged, and Earth, Venus and Mars render **bit-identically** (verified against a
  same-shader control: their frame-to-frame diff is the same either way). The gate costs one
  compare outside a thin annulus — 11.0 % of Titan's disc, 0.4 % Mars, 0.3 % Venus, 0.1 % Earth
  — and inside it the disc branch roughly doubles.
- **What an atmosphere costs the frame is a taste decision, not a photometric one**, so the
  limb's brightness does not meter: a shell asserts a `limb_exposure_ceiling` or it does not
  (see *The compensating camera*). What is geometric — where the limb is, how much of it the
  frame holds, how much of its height is out of the body's own shadow, and whether it is
  scattering toward the camera or away — is measured, and decides how much of that assertion
  applies. **Nothing about the atmosphere is evaluated
  on the CPU at all**: the camera works from the disc's radius and the limb shell's, both
  plain table values, so there is no second copy of the profile to keep in sync with the
  include.
- **What the atmosphere does change about metering is WHEN the camera adapts.** A body with an
  atmosphere is lit past its own terminator — the shadow is a cylinder of the disc's radius, so
  air at radius r keeps the sun until its foot point's solar zenith angle reaches
  `π − asin(disc / shell)` — and its limb is seen from farther round the body. The
  night-adaptation cutoff therefore uses the atmosphere's geometry while the luminance it
  adapts to stays the surface's albedo. Taken at the limb shell's own top, the terminator
  runs to 104.9° on Earth, 101.7° on Venus, 110.8° on Mars and 128.0° on Titan, against 90°
  for an airless body. Without an atmosphere row the formula reduces exactly to the old one.
- **Taste, gated.** With physical light off, two by-eye multipliers act — `atm_intensity` on
  the radiance and `atm_thickness` on every altitude scale. The `iv_limb_scale` global gates
  them: 1.0 lets them act, 0.0 (written while physical light is active) forces both to exactly
  1.0, so one table row serves both modes and the physical look is the physical parameters.

Two float32 traps the include documents, both found as a black curve across Venus' night
side: a literal below about 1e-14 compiles to zero in the shader language, and a valid but
tiny float passes `> 0.0` yet comes out of the GPU's `log()` as −∞.

## The Sun

The sun disc's surface brightness is derived from its absolute magnitude and radius
(`IVAstronomy.get_star_disc_luminance` — ~1.8×10⁹ cd/m²) times gain and exposure, so
approaching it, the metering dims the scene until granulation and sunspots resolve
instead of a white blowout. The disc and the far point sprite are co-calibrated and
crossfade by apparent size (`IVShellsModel` sun mode), both capped at the shared
half-float-safe constant that also bounds the star field. As a metering subject the sun
uses its own late screen-fraction ramp (see above).

What resolves is generated, not sampled: `_sun_photosphere.gdshaderinc` draws limb
darkening, granulation, bipolar spot groups and faculae as functions of the unit-sphere
direction, with no map, no pole and no seam. Two invariants keep it inside the
calibration rather than beside it. Every modulation is **mean-neutral** over the disc —
limb darkening by per-channel disc-average normalization, granulation by construction —
so the disc keeps exactly the derived mean surface brightness and the disc/point
crossfade stays photometric. And the intensity→color relation is a closed-form Planck
ratio that is **exactly white at the mean**, so an umbra reddens as it darkens (~4100 K
at 0.15 of continuum) while the star's absolute tint remains the B−V chain's business
and the disc matches the far point by construction. The photometric anchors — Pierce &
Slaughter (1977) limb darkening, the Neckel & Labs center-to-limb color trend, the
umbral brightness-size relation — are cited in the include.

## Stars and the Milky Way background

The star field (`stars.gdshader`, `IVStarsVisual`, settings in `IVStarSettings`) is
already photometric: each star's rendered intensity follows its catalog magnitude
through a PSF (point-spread function — the little blur disc a lens makes of a point)
with FOV and resolution compensation equivalent to a fixed-f-number camera. Physical
light multiplies `iv_exposure` into that chain, so stars dim and vanish when a sunlit
body meters the scene down, and return at rest exposure.

The background panorama (`starmap_background.gdshader`) is a linear-radiance image of
the Milky Way. Its level is not authored: it is computed from the anchor
(`sky_energy`, see the calibration chain), which corrected the legacy by-eye level —
the panorama had been ~6× too bright relative to the stars it sits behind. At rest
exposure the whole sky rides `exposure_max_ev` above the authored look.

## Rings

Saturn's rings (`rings.gdshader`, `rings.tsv`) carry their authored scatter model
(forward/back-scatter, unlit-side transmission), riding `light_energy` like a surface.
Their shadows — on the planet and from the planet on them — and all eclipse and transit
dimming come from the **analytic occlusion system** (`IVSunOcclusionManager` with
`_sun_occlusion.gdshaderinc`), which computes sun visibility per fragment instead of
shadow maps; the same system supplies the eclipse factor metering uses, so an eclipsed
moon meters dark and night adaptation opens up inside a totality. The same term covers a
spacecraft passing into its planet's shadow, confirmed in-app.

The lit ring face is brighter per unit area than any Lambert sphere — the shader's
backscatter response near zero phase angle exceeds an albedo of 2 — so a camera
metering the globe alone would clip the rings white. The lit face therefore meters as
its **own candidate**: a flat annulus whose screen fraction is its area foreshortened
by the camera's elevation from the ring plane, lit at the sun's elevation, with
`ring_meter_albedo` (the bright-ring reflectance of the shipped assets, measured
before the phase boost) and a CPU mirror of the shader's phase boost carrying the map
response. Near opposition the candidate pulls exposure below the globe's target and
the B ring holds detail; at quadrature or near ring-plane equinox the dim rings stop
mattering and the globe meters as before. The unlit face never needs a candidate — a
thin layer shows its bright face only from the sun's side of the plane.

## Renderer parity

Forward+ and Compatibility (GL / web) meter identically — the CPU chain above is the same
code and produces the same `light_energy`, ambient and `iv_exposure` on both. While physical
light is active the Compatibility renderer's legacy post-tonemap brightness offset
(`tonemap_exposure` 1.2, which also brightened HUD ~6% relative to Forward+) is retired
and restored on deactivation. Compatibility's 8-bit output can band on very dim content
(deep night ambient); Forward+ resolves the same values smoothly.

**The two renderers do not share a colour space.** Forward+ and Mobile are linear at both
ends of a shader: a `source_color` texture is decoded on sample and the finished frame is
encoded to sRGB. Compatibility is display-referred at both ends instead — a `source_color`
texture arrives still encoded, and what a shader writes is taken as encoded too, decoded for
the light multiply and re-encoded into the framebuffer. Measured by rendering a known
constant through the light path on three bodies spanning an 11x range of `light_energy`
(0.73 to 8.20): Forward+ renders `enc(ALBEDO * energy)` to within a code, Compatibility
`enc(dec(ALBEDO) * energy)` with a constant 0.826 in linear, that residual being Godot's own
approximate transfer rather than the exact piecewise one. On a stock two-node project, on
screen, identically on 4.5.1 through 4.7.2: a shader writing 0.25 displays 137 under
Forward+ and 64 under Compatibility — 64 being 0.25 read back as already encoded — while an
sRGB texture byte of 128 round-trips to 128 under both. The two conventions agree for a
value that is only sampled and multiplied by light, and agree for nothing else. They did
not agree for:

- **Arithmetic on a sampled colour.** A range tag's affine unpack, a disc-photometry factor,
  a band tint, `albedo_scale`, `albedo_ceiling`, a ring's phase boost: every one states a
  *linear* coefficient, and applying one to a display-referred value makes a multiplier `m`
  act like `m^2.4`. Enceladus' range tag of `hi` 2.64 blew 89 % of its disc to flat white
  and Mimas' 1.79 blew 64 %; Venus blew 35 %; Lommel-Seeliger (`lunar_lambert` 1.0, every
  `ICE_WORLD`) did it again on top, so untagged Ganymede blew 11 %. Saturn, whose range is
  narrow and offset rather than tall, came out 12 % over-saturated instead — the "stretched"
  look.
- **A computed radiance.** An atmosphere's path radiance, an emission map in cd/m², a star's
  flux: nothing samples these, so nothing cancels, and they were displayed raw. A veil at
  I/F 0.05 rendered at 0.05 where it should read 0.25, which cost Earth's lit disc its
  softening entirely and erased Titan's detached haze layer from the lit side, while the
  bright backlit limb — near the top of the range, where the curve barely bends — looked
  correct throughout.

`_display.gdshaderinc` is the fix and the only place that decides any of it. A shader decodes
what it samples, does its colour arithmetic in linear, and encodes what it writes; the
`iv_display_encode` global (written once by `IVGraphicsManager`) makes every conversion the
identity on a renderer that handles its own colour space, so those render bit-identically.
Measured against Forward+ over the lit disc, every airless body now lands within 1 %
(Mercury, Callisto, Ganymede, Mimas, Enceladus all 1.00–1.01, against 1.11–1.73 before), and
the white blowouts are gone (Mimas 64.3 % → 0.3 %, against Forward+'s own 0.2 %).

A lit **opaque** surface is fully reached by this, at any exposure: the renderer performs
its light multiply in linear between the decode and the encode, so an airless body matches
Forward+ to within 0.004 of a display unit at every level of its disc, across `light_energy`
from 0.96 to 3.52.

**The blend is not, and that boundary is now deliberate.** It runs after a shader returns
and therefore on display-referred values, where a sum is not a sum: compositing gives
`enc(A) + enc(B)` where the linear pipeline gets `enc(A + B)` — equal where either term
dominates, 1.5x apart at worst, and worst of all for a *faint* term over a bright one,
since `enc` lifts 0.02 to 0.155. Correcting a blend needs the fragment to know what the
framebuffer already holds, and a fragment cannot know it — it can only carry an ESTIMATE
of the shells beneath it, and an estimate is exactly what the correction converts into
*structured colour error* wherever the encode slope is steep. The full estimate-based
scheme was built and then retired; what it won, what it cost, and which parts are worth
recovering are recorded below under *What the estimate machinery proved*, because the two
are not the same list.

**What stays approximate on Compatibility, accepted for now.** All of it is the blend,
none of it is per-body tuning, and it is structurally coherent — no colour casts, no
cross-shell misregistration, stable as the cloud deck drifts:

- **A faint additive glow over a lit disc lands crushed, and it is a RADIAL error, not a
  uniform one.** The atmosphere limb hands its path radiance to the engine's own
  conversion, which crushes it hardest where it is faintest — so the deficiency grows from
  the disc centre outward and reaches its worst exactly at the limb. Measured against
  Forward+ in radial bands (disc core / outer disc / limb and beyond-limb ring): Earth
  0.73 / 0.59 / 0.12, Mars 0.73 / 0.53 / 0.05, Venus 0.78 / 0.64 / 0.20, Titan 0.96 / 0.84
  / 0.03. **The beyond-limb ring is effectively absent on every one of them**, which on
  Titan — whose whole disc is its atmosphere, and whose lit-side limb is the thing a viewer
  looks at — is the most visible defect the renderer now has. The twilight air-glow goes
  the same way, so a terminator reads as a plain transparent fade rather than Forward+'s
  glowing band.
- **A bright translucent overlay cannot pass the fragment's 1.0 clamp, and its convex mix
  dims.** A cloud deck saturates at the fragment before `blend_mix` runs, so partial
  coverage never reaches white, and the encoded-space mix runs its fringes dark.
- **A lit surface's last codes cut early at the terminator.** The final encode acts on the
  lit-plus-emission sum between the bracket's halves, where no per-slot write reaches, and
  its power curve has no linear segment — the dying sunlight loses its lowest codes and
  the fade to black is slightly abrupt.

**What the estimate machinery proved, and where it actually failed.** Retiring it is not a
verdict that it did not work — measured in the same radial bands, the full build put
**every atmosphere body at 0.998–1.004 of Forward+ in every band**, ring included. Three
things are worth keeping straight, because they decide what a future patch should attempt:

- **The beyond-limb RING needs no estimate at all.** A ray that misses the disc has empty
  sky behind it, so its pedestal is the constant 0 — the same standing the rings shell has,
  and the reason that one restatement was kept. The limb shader already branches on exactly
  this test (impact parameter against the disc radius). Recovering the ring is therefore
  free of the failure below, and it is the largest single visible gap in the list above.
- **The scalar pedestal was sound on a body without a cloud deck.** Venus and Titan carry
  no map at all and Mars no deck, and the veil over their discs measured 1.000 with the
  body table's albedo as the whole estimate. Its known residual was Mars' lit side at
  +4–10 %, the disc's own albedo spread about one number.
- **The failure was EARTH, and it was structural.** Earth stacks three shells; the deck
  carries procedural warp and FBM detail no other shell can reproduce; the ocean adds a
  specular glint no albedo sample knows; its clear ocean sits at a third of any workable
  scalar while its deck sits far above one; and the deck *drifts* (`_rotate`), so every
  cross-shell sample misregisters unless each consumer tracks the drifting frame. Sampling
  the surface and cloud maps cross-shell to fix the scalar's bimodality is what tipped the
  error from *level* to *structure*: at the day-side disc, 15.8 codes mean absolute
  per-pixel error against Forward+ with 28 % of the disc more than 20 codes out and
  saturation at 0.86x — a grey-washed ocean — breaking into overt colour casts over the
  Sahara once the deck had drifted, which in live running it always has.

Two method lessons came with it, and both cost a round to learn. **Aggregate luma metrics
cannot see this class of error**: disc-mean ratios and per-decile luma scored that
grey-washed Earth as near-perfect, because grey and blue at equal luminance are the same
number — a colour claim needs per-channel or saturation measurement. And **a harness that
pauses to be deterministic freezes the deck at zero drift**, the one state in which every
cross-shell estimate is exact; the defect only appears once the capture runs time forward
and comes back (`scratch/compat/drift_repro.py`).

**The background panorama takes the same treatment as everything else** — the earlier
account that `shader_type sky` "does not respond" was wrong. The GLES3 sky pass expects
display-referred COLOR exactly as its scene pass expects display-referred ALBEDO: it
decodes COLOR for its exposure and tonemap arithmetic and re-encodes on write
(`drivers/gles3/shaders/sky.glsl`), so an untreated linear COLOR lands in the framebuffer
nearly raw, darkest where the curve bends hardest — measured 0.68x of Forward+ at the sky's
median luma, 0.80x at p90. `starmap_background.gdshader` decoding its sample and encoding
its output moved those to 0.81x and 0.96x; with `display_write()` below, the sky sits at
**1.00x at both**, with Forward+ unchanged.

**What remained at the dim end everywhere was the engine's own approximate transfer pair,
and `display_write()` pre-inverts it.** A written colour does not reach the framebuffer as
written: the display-referred renderer's fragment tail decodes it with a polynomial and
re-encodes it with a power curve that has no linear segment
(`drivers/gles3/shaders/tonemap_inc.glsl`), a bracket that is nearly the identity above
~0.3 and crushes below it — a written 0.05 landed at 0.030, everything under ~0.0008 linear
at exactly zero, and the whole lit path carried the polynomial's misfit (the "constant
0.826" above). So a fragment now writes the value whose trip through the engine's own
conversions LANDS the exact-sRGB value Forward+ lands: the power curve's inverse names the
linear value the final encode must see, and three Newton steps on the convex cubic name the
value whose decode is that, within 5e-4 of a display unit — with no upper clamp, since a
range-tagged or limb-flattened albedo legitimately exceeds 1.0 before the engine's light
multiply and must survive (a 1.0 cap was measured darkening Ganymede's bright end 13–23
codes). `display_encode()` stays the exact-sRGB transfer for arithmetic ABOUT the
framebuffer — an alpha weight, a mix — which the framebuffer now really holds. Measured
over the lit disc: Ganymede 1.000, Callisto 0.998, the sky 1.00 at every percentile; a
body with an atmosphere sits under Forward+ by its crushed veil, the first accepted
deficiency above. The final encode of a LIT result sits between the bracket's halves where
no per-slot write reaches on its own — that residual is the terminator's early cut,
accepted above.

**An eclipsed body found the two write paths this scheme must keep apart.** The maintainer's
Compatibility pass caught Mimas in Saturn's shadow rendering as a solid white disc at a
dark-adapted exposure — dim grey ambient on Forward+ — and the bisect ran through five wrong
suspects before landing on two real defects stacked. First, `display_write()`'s dark boost,
sub-code where a value meets only the final encode, is anything but sub-code on a slot the
renderer DECODES AND THEN MULTIPLIES: an eclipsed albedo of exactly 0 landed at 8e-4 linear,
and a dark-adapted light energy of 1e3+ rendered that floor as the white disc.
`display_write_albedo()` inverts only the polynomial decode — zero writes zero, exactly —
and the boosted `display_write()` stays for EMISSION and unshaded radiance, which meet the
final encode with nothing multiplied in between. Second, the `compat_albedo_shadow` fallback
multiplies the occluder shadow into ALBEDO because AO is ambient-only on this renderer —
which left the SPECULAR lobe unshadowed, so an eclipsed body kept its full sunlit sheen
(F0 0.02 times a dark-adapted light energy clears white on its own; established by zeroing
the terms pairwise). The shadow now rides SPECULAR too, as the square root, since F0 scales
as SPECULAR². Mimas in eclipse lands within one code of Forward+.

**The rings' restatement is the one blend correction kept.** A partially transparent sheet is
dimmed by the display-referred blend itself — `alpha * enc(C)` against the linear
pipeline's `enc(alpha * C)`, 0.73x over Saturn's lit ring face — so the ring self-lights on
the display-referred branch and hands `display_mix` a zero pedestal: it stands over empty
sky almost everywhere, and the escalation case is pedestal-blind. The engine lights only
the sunlit face (the unlit face is ambient alone), and the shader's existing model-space
side test — `IVRings` keeps +y sunward — says which this is;
`IVSunOcclusionManager._feed_ring_material` now passes `sun_light_energy` beside the sun's
direction. Two confounds had to fall before the diffuse model could be chosen honestly. The
`IVRings` Compatibility overrides of `litside_phase_boost` / `unlitside_phase_boost`
(1.25 / 1.5 against the 3.0 / 2.0 every other renderer uses) are retired along with the
matching metering constant in `IVExposureManager`: tuned against the old display-referred
pipeline, where a boost `m` acted as `m^2.4`, they became a deliberate divergence once it
was corrected — and they were quietly dimming every Compatibility ring measurement by
0.88x, which made a Burley restatement (the engine's documented default diffuse at these
shells' roughness of 1.0) look closer than it is. With the mask removed and the
boosts equal, the end-to-end measurement is unambiguous: a LAMBERT self-light lands the
lit ring face at 0.99x of Forward+ and the Burley one at 1.23x — at this near-equinox
grazing incidence, where the sun stands a degree or two off the ring plane and Burley's
grazing terms run 1.5–2x over Lambert, the engine's own ring shading sits close to
Lambert.

## Settings summary

| Where | Setting | What it does |
|---|---|---|
| `IVCoreSettings` | `enable_physical_light` | Instantiates the system (default false; zero cost off). Requires `dynamic_lights`. |
| user options | `physical_light` | Runtime toggle (cached setting; Options row appears when enabled). |
| `IVExposureManager` | `background_peak_magnitude_per_arcsec2` | The absolute anchor (mag/arcsec² of a full-white panorama texel). |
| | `metering_key` | Rendered value a fully metered surface lands at (mid-exposure target). |
| | `meter_fraction_start` / `meter_fraction_full` | Screen-fraction ramp: when a body begins to influence metering / fully drives it. |
| | `star_meter_fraction_start` / `_full` | The same ramp for the sun's disc (much later — the sun meters only as a subject). |
| | `limb_meter_fraction_start` / `_full` | The same ramp for an atmosphere limb's ceiling, on the sunlit, forward-scattering, in-frame share of its ring (later again — a limb may clip far more readily than a disc). |
| | `meter_edge_fraction` | Screen-edge gate width: compensation completes when a body's center is this fraction of the frame inside. |
| | `limb_meter_edge_fraction` | The same gate on the limb ring's own samples (taken at the limb's foot), wider: it is also the centrality test. |
| | `ring_meter_albedo` | Lit-ring metering reflectance (bright-ring level of the shipped assets, before the phase boost). |
| | `exposure_max_ev` | Dark-adapted resting exposure, in EV above the authored sky. The empty-sky and deep-night state. |
| | `meter_transition_exponent` | Shapes zoom-out: slower climb into overexposure, faster star arrival. |
| | `nightside_onset_lit_fraction` / `nightside_full_lit_fraction` | Lit-disc fractions where night adaptation begins / completes. |
| | `nightside_twilight_angle` | Horizon fade width on the last crescent sliver (close range). |
| | `adapt_darken_ev_per_second` / `adapt_brighten_ev_per_second`, `snap_ev_threshold` | Adaptation rates and the instant-jump threshold. The rates are in WALL-CLOCK seconds (they describe the viewer's eye), which is why they carry no `IVUnits` factor where `nightside_twilight_angle` and `ambient_starlight_illuminance` do. |
| | `default_albedo` | Metering albedo for bodies without a table value. |
| | `emission_luminance_scale` | Luminance of a full-white emission texel at multiplier 1.0. |
| | `ambient_starlight_illuminance` | Integrated starlight: ambient level and the metering floor. |

## TODO

- **Disc photometry: `L(α)`, and the parameter's axis.** `L` ships as a constant, which is
  right where it was anchored (full phase) and progressively too generous as a body swings
  away — the reason `ROCKY_WORLD` had to be hand-tuned down to 0.6 rather than sitting at
  its physical 1.0. The shader already has `µ` and `µ₀`, and the phase angle is one dot
  product away. Underneath that, **surface class is probably the wrong axis**: the
  parameter is governed by albedo, not composition, and at zero phase the Hapke disc
  profile is entirely multiple scattering, so the best-fit `L` falls from ~0.95 at albedo
  0.01 to ~0.10 at albedo 0.53 — dark bodies want the flat disc, bright ones want Lambert.
  The classes cut across that: `ICE_WORLD` spans Iapetus 0.25 to Enceladus 1.375 and
  `ROCKY_WORLD` spans Ceres 0.09 to Mimas 0.962. Deriving `L` per body from the `albedo`
  column would take one `IVShellsModel` push of the table value to the shell materials.
  (The isotropic-scatterer model behind those numbers omits backscattering and roughness
  and reads 0.64 for the Moon against a published ~1.0, so it is a trend, not a source of
  values.)
- **Two classes of body never reach the surface shader**, so neither gets disc photometry
  or range tags, and both would be closed by the same kind of work. The **`FALLBACK`
  surface class has no shader** — the moons left on it are on `StandardMaterial3D`, out of
  reach of any shader term, and giving the class the surface shader with a flat
  `albedo_color` would bring them in. And **the five packed `.glb` body models** (Hyperion,
  Bennu, Eros, Itokawa, Arrokoth) keep the `StandardMaterial3D` Godot's glTF importer
  authored, because `IVBodyVisual._build_packed_model` sets basis, visibility ranges and
  layers and returns without touching materials; range tags are parsed from a **map file
  name**, and an embedded texture has none. Their levels are compliant (0.980–1.090 of
  target), so what the gap costs is the disc law plus any body whose terrain will not fit
  under white — which is what took Mimas off this path and onto a mesh with range-tagged
  cubemaps.
- **Atmospheres, follow-ups.** The δ-scaled transmittance landed 2026-08-24 (above), so the
  remaining items are: the truncation fraction is `f = g`, the δ-HG form, where δ-Eddington
  would use `f = g²` and recover about half as much (Earth's disc +6 % rather than +13 % over
  bright cloudless land) — nothing here measures which is closer, and a multiple-scattering
  reference in `limb_model.py` is what would settle it. Titan's detached layer
  is an epoch (450–510 km in 2016–17, 500 km in 2005–07, gone 2012–15); the table carries
  one. The planet's own shadow is in the model but an eclipse by another body is not:
  `sun_occlusion_visible_fraction` at the tangent point would add it. On the Compatibility
  renderer the limb's whole radiance crosses the engine's conversion bracket and blends on
  an sRGB-encoded target, so its veil and band render well under Forward+ — the first
  accepted deficiency above.
- **Earth's terminator band on FORWARD+ — measured 2026-08-28, PART of it fixed, and what is
  left is a decision rather than a bug.** Measure it with `scratch/compat/termband.py` in the
  assets build tree, which poses the body at a solved phase 90 (so the terminator runs through
  the disc centre, where it is widest on screen, rather than wherever a guessed longitude put
  it) and reports against μ0 with a contrast metric — the illumination taken out as a median
  profile on one-pixel bins, since "no features here" is a statement about contrast that no
  luma profile can see. What it says: Earth's relative feature contrast falls **0.21 → 0.054**
  across μ0 ∈ [−0.06, +0.06], a 4× collapse, while Mars over the same span **rises** 0.066 →
  0.113, its craters gaining contrast as the light grazes. That is the reported defect,
  quantified.
  - **The band is the atmosphere's own path radiance, and it is correct.** Calibrated against
    the metering row (`I/F × luminance/albedo × gain × exposure`), Mars' terminator matches
    `limb_model`'s path radiance to **7 %** across the whole band and Earth to 16–46 %, the
    excess being the rebuilt ambient. So the glow is not too bright by any measure available
    here; what was wrong is that nothing underneath it survived.
  - **Fixed: the surface was lit by the direct beam alone.** See the two-stream entry above.
    It bought Earth +5–17 % contrast across the day-side half of the band and Mars +10–90 %,
    for +2.0 % / +6.9 % of disc level. It is a real correction and it is not enough.
  - **The deck's edge is what reads as a wall, and a cutoff law only moves it** (tried and
    rejected 2026-08-28). Commenting out Earth's cloud row settles the Mars asymmetry: the
    features that survive inside the band are RELIEF, not albedo — Mars has abundant relief
    to shade at grazing incidence and Earth's map has almost none, which is why Earth's
    contrast falls 0.214 → 0.054 across the band while Mars' *rises* 0.066 → 0.113. What
    reads as a defect is the abrupt end of the white clouds. Isolated by hiding the shell,
    the deck's own contribution falls 0.0691 → 0.0049 → 0 over µ0 +0.065 → −0.005, an
    e-folding length collapsing from 91 pixels to 2. A `clouds_grazing_extent` carrying the
    deck to its own geometric shadow at µ0 = −0.0565 (3.2° past the disc's terminator, the
    part the engine's N·L cannot deliver rebuilt as EMISSION) was rendered at
    k = 0/0.35/0.5/0.7/1.0 and **moved the wall without removing it** — a linear ramp to a
    hard zero translates its corner but keeps its shape, and the deck is still 16 % of the
    pixel where it stops. Removing it needs the falloff SHAPE changed: a layer law, whose
    radiance carries no µ0 projection (which is why this model's own glow survives to
    µ0 −0.13 while the deck inside it does not), ENDED by a shadow graded through the deck's
    own thickness rather than cut at a line. A layer law without that grading is worse, not
    better. Both need the deck's optical depth separated from its coverage, which
    `Earth.clouds.albedo.512.png` cannot supply: RGB is 255 in one distinct value with alpha
    carrying everything, so reflectance is pinned at 1.0 and a range tag would buy nothing.
  - **What else remains, and why it is a decision.** Earth's band survives because at μ0 < 0.06 the
    surface cannot compete on albedo: the ocean is 0.05 and the glow is 65–80 % of the pixel
    even after the fix (measured p90/p10 across the band, 1.5 on the day side collapsing to
    1.27). And the night-side half is structural — the engine's N·L zeroes both the surface
    and the deck at μ0 = 0 while the glow runs on to μ0 ≈ −0.13. Two things are true there and
    neither can ride on ALBEDO: a deck 10.19 km up leaves the body's shadow only at
    μ0 = −0.0565, so it is in direct sunlight for 3.2° past the ground's terminator; and the
    diffuse sky does not scale as μ0 at all — real ground illuminance at the terminator is
    ~0.3 % of solar, not zero. Carrying either means an EMISSION term, a model for the
    twilight irradiance, and a fresh look at how it meters. Worth checking the veil's twilight
    width against full-disc imagery (EPIC, Himawari) in the same pass, since both are one
    calibration.
  - **Compatibility's terminator looks CORRECT here only because it crushes the same term.**
    Measured at the safety point with the fix in: Earth's band renders 13.6 codes on
    Compatibility against Forward+'s 64.6 at μ0 = +0.05, and goes to exactly zero below
    μ0 = −0.01 where Forward+ still glows to −0.13. So the veil deficiency is masking the band
    defect, and recovering the veil — the second Compatibility candidate below — would import
    the band along with it. They are one term and should be judged together.
- **Compatibility, what a targeted patch could still recover** (the retreat of 2026-08-28 is
  the base; see *What the estimate machinery proved* above). Two candidates, in order of
  confidence: the limb's beyond-limb RING, whose pedestal is provably the constant 0 and
  whose absence is the most visible remaining defect (Titan); and the veil over the disc with
  the body table's albedo as a SCALAR pedestal, which measured 1.000 on every body without a
  cloud deck. Neither may sample another shell's map — that is what produced colour casts.
  A cloud deck wanting to whiten past the fragment's 1.0 clamp can escalate alpha from its
  OWN lit radiance without knowing anything about the ground beneath it.
- **Sky radiance staleness.** Metallic spacecraft surfaces reflect the sky's radiance
  cubemap, which Godot rebakes only when the sky material is touched — so it holds
  whatever exposure was current at the last bake (usually activation). Today the effect
  is invisible (measured zero contribution at metered exposures), but a session that
  activates at rest exposure would leave permanently bright foil reflections near
  planets, and the correct Milky Way sheen on deep-space craft is likewise missing when
  the bake happened dark. Fix: retrigger the bake when exposure has moved more than
  ~half an EV since the last one.
- **Earthshine / planetshine.** There is no light in the renderer from a planet onto
  its satellites or spacecraft — Godot has no runtime global illumination, and emission
  maps illuminate nothing but themselves. A craft's planet-facing side in orbital night
  is therefore honestly black. Real earthshine is a designed feature if wanted: a
  per-body secondary light with physical energy (`albedo × illuminance × (R/d)² ×
  phase`) riding the same exposure chain.
- **Bloom**: the disc/point co-calibration and f16 caps were done with a future bloom
  pass in mind; the remaining work is the bloom itself. It also reopens **night-side
  metering**, settled today on the judgment that blown city cores read correctly at
  physical light levels (see *Night-side emission*) — a bloom pass spreads a clipped core
  outward rather than containing it, so that judgment is worth re-making once one exists.
- **Anchor refinement**: the 20.0 mag/arcsec² anchor is good to a few tenths against
  LMC/SMC levels in the shipped map; a tighter cross-check against published integrated
  photometry is possible.
- **Sun surface tuning**: in-app judgment of the procedural photosphere (every parameter
  is a uniform) and granulation time evolution, which is static by decision rather than
  oversight — a granule lives ~10 minutes, so the time input belongs on the sim clock.
