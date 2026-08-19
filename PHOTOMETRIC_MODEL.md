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
  Earth is also the one body whose map and table value do not agree, by 2.7× — see the
  TODO.
- **A map carries whatever a body's shells do not.** Earth's are surface, clouds and a
  thin limb ring — the limb's rim term is zero everywhere but the extreme edge — so
  nothing draws Rayleigh scattering across the disc, and it is an open question whether
  the surface map should therefore hold top-of-atmosphere reflectance or whether that
  term belongs in the renderer. Over ocean it is most of the signal either way.
- Spacecraft and small-body values are **derived from the shipped models** (measured
  render response at sun-facing geometry), not from literature — they exist to expose
  the model correctly.
- A body with no albedo value meters at `IVExposureManager.default_albedo`; an empty
  table cell is treated as unknown, never as zero.
- A body with **no color map at all** renders its surface class's `fallback_color`,
  which `IVAssetPreloader` rescales in linear light so its luminance equals the metering
  albedo — a mapless grey moon exposes exactly like a mapped one, and shows its true
  darkness next to its parent planet.
- Very bright icy bodies owe their catalog value to coherent backscatter at full phase
  (the *opposition surge*), which the shading model does not have. That is **not** a
  reason to hold their maps under key: a geometric albedo is a zero-phase quantity, so
  `map mean = p` carries each body's own surge as a level, exactly as it does for every
  other body in the set. Dione, Rhea, Tethys and Enceladus were levelled to their full
  table value on 2026-08-17, the two above 1.0 (Enceladus 1.375, Tethys 1.229) through
  **range tags**. The mapless members of the family are still clamped — see the TODO.
- The convention covers a packed `.glb` body's **embedded base-color texture** exactly
  as it covers a cube strip. A model whose texture was authored for display rather than
  reflectance is corrected at the texture, never by moving the table value — the table
  carries the catalog albedo and metering divides by it. Two things differ from a strip.
  The level is the texture weighted by **surface area over the mesh**, not a flat mean of
  the image: a model's texture is a UV atlas that is a third to a half unused, and the flat
  mean blends the body with whatever that background happens to be. And the texture is the
  body's **only** lever — a packed model keeps the `StandardMaterial3D` the glTF importer
  authored, so it has no range tags and no disc-photometry term (see the TODO).

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

There is no metering side to this yet: a body's emission does not participate in the
exposure it is rendered at, so an all-night-side view exposes as if the lights were not
there. Physically that is not far off — rural lighting is ~10³× and city cores ~10⁵×
starlit terrain, so at a dark-adapted rest exposure everything lit is honestly blown out,
as in real ISS photography where exposing for the cities loses the stars. What the
physical anchor changed is the *extent*: the chain is now ~192× a linear texel at rest
exposure rather than the ~6,400× above, so clipping begins around 16 DN instead of ~1 DN
and the dim tail (villages, roads, fishing fleets) renders in range for the first time
while city cores still clip.

Expect clipped cores to keep a coloured fringe. The map's authored 3000 K tint is linear
(1.0, 0.19, 0.02) — a 50:1 red-to-blue ratio, ~5.6 EV — so the channels clip in sequence
and a core reads white at the centre through yellow and orange rings on the way out. That
spread is a property of the tint, not of the level: lowering the anchor moves the rings
inward but cannot close them. Metering emission into the camera is the fix.

## Shell effects

Shells (`shells.tsv`) are concentric sub-models around a body's surface.

### Cloud shells

A cloud deck (e.g. Earth's) is an overlay shell whose color is white with coverage in
the alpha channel. It is lit by the same light as the surface, so under an exposure
metered for the *cloudless* surface albedo, cloud tops overexpose by a factor of a few —
bright, occasionally clipped white, which matches real orbital photography. No separate
cloud compensation exists, deliberately: compensating for clouds would crush the surface.

### Atmosphere limbs

`atmosphere_limb.gdshader` draws the thin haze ring at a body's edge (Earth, Venus,
Titan; per-body `limb_*` columns in `shells.tsv`). Two physical behaviors matter:

- Both glow terms are gated by **local sunlitness**: the shell is thin, so a fragment
  whose sun is below its local horizon is inside the planet's own shadow and cannot
  scatter. This is what kills the (unphysical) glowing ring a night-side close-up would
  otherwise paint, while the *real* ring of light around a backlit planet — visible at
  inferior-conjunction geometry, where the whole limb sits at grazing sunlight —
  survives.
- The limb rides `light_energy` like any lit surface, but its authored glow values
  target the legacy O(1) energies, and physical exposure spans 20+ EV. The
  `iv_limb_scale` global (`IVExposureManager.limb_physical_scale`, default 0.02)
  rebases it: invisible in ordinary views, emerging as the twilight arc and the backlit
  ring when night or backlit exposure opens up.

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
moon meters dark and night adaptation opens up inside a totality.

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

Forward+ and Compatibility (GL / web) render the same photometric values. While physical
light is active the Compatibility renderer's legacy post-tonemap brightness offset
(`tonemap_exposure` 1.2, which also brightened HUD ~6% relative to Forward+) is retired
and restored on deactivation. Compatibility's 8-bit output can band on very dim content
(deep night ambient); Forward+ resolves the same values smoothly.

## Settings summary

| Where | Setting | What it does |
|---|---|---|
| `IVCoreSettings` | `enable_physical_light` | Instantiates the system (default false; zero cost off). Requires `dynamic_lights`. |
| user options | `physical_light` | Runtime toggle (cached setting; Options row appears when enabled). |
| `IVExposureManager` | `background_peak_magnitude_per_arcsec2` | The absolute anchor (mag/arcsec² of a full-white panorama texel). |
| | `metering_key` | Rendered value a fully metered surface lands at (mid-exposure target). |
| | `meter_fraction_start` / `meter_fraction_full` | Screen-fraction ramp: when a body begins to influence metering / fully drives it. |
| | `star_meter_fraction_start` / `_full` | The same ramp for the sun's disc (much later — the sun meters only as a subject). |
| | `meter_edge_fraction` | Screen-edge gate width: compensation completes when a body's center is this fraction of the frame inside. |
| | `ring_meter_albedo` | Lit-ring metering reflectance (bright-ring level of the shipped assets, before the phase boost). |
| | `exposure_max_ev` | Dark-adapted resting exposure, in EV above the authored sky. The empty-sky and deep-night state. |
| | `meter_transition_exponent` | Shapes zoom-out: slower climb into overexposure, faster star arrival. |
| | `nightside_onset_lit_fraction` / `nightside_full_lit_fraction` | Lit-disc fractions where night adaptation begins / completes. |
| | `nightside_twilight_angle` | Horizon fade width on the last crescent sliver (close range). |
| | `adapt_darken_ev_per_second` / `adapt_brighten_ev_per_second`, `snap_ev_threshold` | Adaptation rates and the instant-jump threshold. |
| | `default_albedo` | Metering albedo for bodies without a table value. |
| | `limb_physical_scale` | Atmosphere-limb glow rebase while active (`iv_limb_scale`). |
| | `emission_luminance_scale` | Luminance of a full-white emission texel at multiplier 1.0. |
| | `ambient_starlight_illuminance` | Integrated starlight: ambient level and the metering floor. |

## TODO

- **Meter the night side.** Emission needs to enter the metering the way lit surfaces do,
  so the camera stops down over cities instead of clipping them — see *Night-side
  emission* for why everything lit is blown out at rest exposure today.
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
  column would need `IVShellsModel` to see the body's albedo, which it does not today.
  (The isotropic-scatterer model behind those numbers omits backscattering and roughness
  and reads 0.64 for the Moon against a published ~1.0, so it is a trend, not a source of
  values.) **The `FALLBACK` class still has no shader** — the moons left on it are on
  `StandardMaterial3D` and out of reach of any shader term; giving that class the surface
  shader with a flat `albedo_color` would bring them in.
- **The opposition surge itself is closed, not deferred.** `B(α)` divides out of every map
  uniformly (a catalog albedo is a zero-phase quantity, so the convention has always
  carried each body's own surge as a level), and metering has **no phase term** —
  `lit_luminance = albedo · illuminance / π` — so adding a surge to the shader alone dims
  every body at `α > 0`, while adding the CPU mirror the rings use cancels it straight back
  out for any solo metered body. What is left is a small-phase difference between bodies
  sharing one frame, over a coherent-backscatter peak ~1–2° wide: marginal, and it blocks
  no asset. The four surge moons were levelled to their full catalog value on 2026-08-17
  (build project, `records/albedo_levels.md`).
- **A mapless body with albedo above 1.0 is silently capped.**
  `IVAssetPreloader._get_fallback_color` clamps its rescale at `1.0 / max_channel`, so
  Calypso (1.34) and Helene (1.67) render at reflectance 1.0 while metering divides by
  their table value — 75 % and 60 % of key, with nothing to show for it. Mimas at 0.962
  is under the line. The fix is the same one the maps got: let the fallback exceed 1.0,
  since nothing downstream clamps `ALBEDO`.
- **The six packed `.glb` body models are outside the shader path, and two of them are
  badly under key.** `IVBodyVisual._build_packed_model` instantiates the `PackedScene`, sets
  its basis, visibility ranges and layers, and returns without touching materials, so Mimas,
  Hyperion, Bennu, Eros, Itokawa and Arrokoth all render on the `StandardMaterial3D` Godot's
  glTF importer authored. They therefore have no `albedo_range_lo`/`albedo_range_hi` — range
  tags are parsed from a **map file name** in the preloader's `maps_index` scan, and an
  embedded texture has none — and no `lunar_lambert`/`minnaert_k`. This is the same gap as
  the `FALLBACK` class above, reached by a different route. **Mimas** is the surge family on
  this path: its texture measures 0.235 of its 0.962 table albedo, and no gain can fix it
  because reaching target puts 42 % of its surface past 1.0, so a bounded gain tops out at
  35 % of key. **Hyperion** measures 0.331 of its 0.3 — a 2026-08-16 correction that
  measured the atlas's near-white background instead of the body and scaled it the wrong way;
  it needs 3.02× and can take it, 1.85 % of its surface clipping at full gain. Bennu is
  compliant (0.980), Eros and Itokawa are 1.09× over, Arrokoth 0.763× and gainable in place.
  The structural fix for Mimas is the deconstruction the five custom-mesh bodies already
  took — a geometry-only mesh plus range-tagged albedo and object-space normal Cubemaps,
  which puts the body on `surface.cube.gdshader` and makes 0.962 storable the way Enceladus'
  1.375 is. Asset-side detail in the build project, `records/albedo_levels.md`,
  `records/Mimas.md` and `records/Hyperion.md`. Separately, **Arrokoth renders 11.1× too
  small** — its glb units are neither metres nor covered by a `file_adjustments.tsv`
  `model_scale` row, so a 36 km body ships 3 km long.
- **Earth's albedo map, which is 2.7× under its table value and blocked on a question
  about the renderer.** Its source is a MODIS *land* product whose ocean is one painted
  triple — luma 0.0017, where a real ocean's top-of-atmosphere reflectance is ~0.04 — so
  the median texel of the map renders essentially black. Replacing that baseline with a
  derived clear-ocean value was built and reverted on 2026-08-17: it is physically
  defensible and reads too light in the app, because a map that carries the atmosphere
  over water and not over land is neither of the two things a reference image ever is.
  The real choice underneath is whether the map holds top-of-atmosphere or surface
  reflectance, and that is a renderer question — a haze baked into the map cannot respond
  to geometry, where an atmosphere term on the surface shader would, next to the limb item
  below. Note also that even a fully corrected map means about 0.09 against a table value
  of 0.15, which looks like a cloud-free *surface* albedo where every other body's column
  holds a published *geometric* one. Asset-side detail in the build project,
  `records/Earth.md`.
- **Physically correct atmosphere limb** using phase angle (lower priority — the current
  sunlit-gated glow is serviceable but approximate).
- **Verify spacecraft eclipse behavior** — a craft in its planet's shadow should meter
  dark (and does render dark); the metering-side parent-shadow term deserves a dedicated
  test around a fast orbiter like the ISS.
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
  pass in mind; the remaining work is the bloom itself.
- **Anchor refinement**: the 20.0 mag/arcsec² anchor is good to a few tenths against
  LMC/SMC levels in the shipped map; a tighter cross-check against published integrated
  photometry is possible.
- **Sun surface tuning**: in-app judgment of the procedural photosphere (every parameter
  is a uniform) and granulation time evolution, which is static by decision rather than
  oversight — a granule lives ~10 minutes, so the time input belongs on the sim clock.
- **Stale `bodies_2d` icons.** Every body whose map level changed carries an icon
  captured from the old level: the seventeen from the level pass, the five de-stretched,
  Earth, and the pre-existing Venus / Uranus / Neptune / Sun backlog. Recapture is the
  editor's body-2D capture dialog, a GUI step.
