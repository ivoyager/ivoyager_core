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
Way background panorama. From it and the PSF camera settings (`IVPSFSettings`), the
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
disc luminance from absolute magnitude and radius) live in `IVPhotometry`, along with
the V-band anchors they are defined against.

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

- Table albedos follow Mallama et al. (2017) for the planets, **Earth's 0.434 included**
  since 2026-08-30. It had held 0.15, the cloudless value, from when this column also
  set exposure and one number had to serve both jobs; `meter_albedo` took that job and
  the cell went back to the catalog, so the column is now uniformly Mallama's.
- **Earth's map is the one that does not follow the convention, and cannot.** It means
  0.0614 against a table 0.434, because the catalog value describes a cloudy planet
  while the map is a cloudless surface — the clouds are a shell above it and the
  atmosphere is drawn by the renderer, so no single number is both. Solid-angle
  weighted, the map's land mean is 0.182 with the ice sheets and 0.097 without. Its
  exposure comes from `meter_albedo` and not from this cell, so the gap costs nothing;
  what it means is that the level tools' Earth row is a report, not a target.
- **A map carries whatever a body's shells do not**, and for Earth that question is now
  settled: the map holds **surface** reflectance throughout, and the renderer draws the
  atmosphere over it (see *Atmospheres*). A top-of-atmosphere build was tried and reverted:
  a map carrying the atmosphere over water and not over land is neither of the two things a
  reference image ever is, a surface-reflectance product or an exposed photograph. The
  ocean therefore stays at its water-leaving level (luma 0.0084) and the Rayleigh veil,
  drawn by the atmosphere shell over the whole disc, supplies the atmosphere's share
  — which is why that share was never baked into the map.
- **`meter_albedo` overrides `albedo` for metering, and for nothing else.** The two are
  the same number on every body that has only a map to show, which is why the column is
  empty everywhere but Earth. They part where a body's *shells* add light over that map:
  metering knows only `albedo × illuminance / π`, so an atmosphere drawn across the disc
  and a cloud deck above it return light the camera then over-exposes for. Earth carries
  0.30 — twice its cloudless 0.15, which is one stop, and near its real Bond albedo — and
  that is the whole of the correction. It is read by `IVExposureManager._get_albedo()`
  and, so a mapless surface still exposes the way metering assumes it will, by
  `IVAssetPreloader._get_fallback_color()`. `albedo` remains the asset-level target the
  rest of this section is about, and the value the UI reports. A body with neither column
  meters at `default_albedo`; an empty cell is unknown, never zero.
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

## Imaging a pixel: the rim, coverage, and one camera

A body's rim at high phase is where a point sample stops being a photometric answer. With
the sun within a radius or so of the limb the whole lit crescent is a sliver narrower than
a pixel — 0.55 px at 175° phase on a Jupiter 145 px across — so one shading sample per
pixel decides the rim by where the sample happens to land, and the line comes apart into
full-brightness dots and gaps. What is short is the shading **rate**, not coverage, which
is why no MSAA setting ever touched it: MSAA shades once per fragment.

The answer is to stop treating a pixel as a point and treat it as what it is, **the
camera's sampling aperture**. `limb_mean_incidence()` in `_photometry.gdshaderinc` images
each rim pixel through the camera's own PSF: the sunlight along the pixel's radial reach is
integrated in closed form on the sphere's exact parameterization (`µ₀ = A cos t + B sin t`,
whose chord integral is elementary), cell by cell under a Gaussian of `iv_psf_sigma` — the
same σ the star field and every PSF quad draw with. It costs 16 cells over ±3 px and only
within a few pixels of the silhouette; everywhere else the point sample is already the
answer and the function returns it. Two numbers come back: the pixel's true mean sun angle,
and its **coverage**, the fraction of the PSF's mass that lands on the body.

**Coverage is the silhouette's alpha**, replacing the fixed pixel-and-a-half fade the
shells used to carry. A body's edge is now the camera's own edge rather than a tuned ramp —
and that is what makes the resolved-to-unresolved handoff continuous. A crescent's rim, an
atmosphere's beyond-limb ring (`ATM_RING_FILTER_PX`) and the PSF quad's core are three
evaluations of one camera model instead of three separately fitted falloffs, so a body
shrinking toward a point hands its light across without a step, and a ring or a cusp thins
out instead of ending.

**The direction that sets:** where this renderer needs a fade, a ramp or a handoff at a
body's edge, derive it from the camera's PSF rather than tune a width — and name whatever
is left tuned. What is left tuned here is the specular fade, which keeps the old
pixel-and-a-half: put on coverage, the grazing lobe brightened a band along the rim, which
is a question about the BRDF at grazing incidence and not about sampling.

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
outward instead of containing it, and one has now landed (see *Glow: the bloom pass*), so
the judgment is due for re-making (see TODO).

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

- **The limb shell draws only the rays that miss the disc.** Its output is **I/F riding
  `light_energy` like a surface**: its custom `light()` adds `LIGHT_COLOR × ATTENUATION / π`,
  so a texel reads `I/F × light_energy`, exposure included, with no rebase. It composites
  with `blend_premul_alpha` — the path radiance added, what lies behind kept by one minus
  the luma of the transmittance — which is sound there because behind a beyond-limb ray
  stand only the sky and the stars.
- **The air in front of the disc is composited by the disc's own shaders** (2026-08-30,
  `atm_disc_air()`): each surface, band and cloud fragment evaluates the veil, the
  twilight glow and the far half of an optical-limb ray for its own ray, adds the path
  over everything it renders and multiplies the luma of the disc's view transmittance
  into all of it — lit albedo, emission, and the specular lobe as its square root — with
  `atm_view_tint` still carrying the chromatic complement, which is exact and lets a
  cloud deck 10 km up escape the air beneath it. In linear light this is algebraically
  identical to the limb shell's old disc branch (the path distributes through the deck's
  alpha mix with weight `α + (1 − α) = 1`); what it buys is that the composite no longer
  passes through the hardware blend at all, which is the one boundary the Compatibility
  renderer's display-referred pipeline cannot honour (see *Renderer parity*). The veil
  rides the `sun_light_energy` uniform as emission, one frame of exposure ramp behind
  like every compositing feed, far under a display code. At the very silhouette the two
  owners hand off over a thin feathered band (`ATM_RIM_HANDOFF`), because a polygonal
  mesh's silhouette sits its facet sagitta inside the true sphere and no disc fragment
  covers that sliver — a hard partition measured as a dotted arc of ~270 dark pixels.
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
(`IVPhotometry.get_star_disc_luminance` — ~1.8×10⁹ cd/m²) times gain and exposure, so
approaching it, the metering dims the scene until granulation and sunspots resolve
instead of a white blowout. The disc and the star's PSF quad are co-calibrated and
crossfade by apparent size (`IVShellsModel`'s disc LOD against the handoff `IVBodyPSF`
solves), both capped at the shared half-float-safe constant that also bounds the star
field. As a metering subject the sun
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
and the disc matches the quad by construction. The photometric anchors — Pierce &
Slaughter (1977) limb darkening, the Neckel & Labs center-to-limb color trend, the
umbral brightness-size relation — are cited in the include.

## Stars and the Milky Way background

The star field (`stars.gdshader`, `IVStarsVisual`, settings in `IVPSFSettings`) is
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

- **The disc's air no longer passes through the blend at all** (2026-08-30): the veil,
  the twilight glow and an optical-limb ray's far half are summed inside the disc
  shaders' own fragments (`atm_disc_air`, see *Atmospheres*), where the composite meets
  the display conversion once, as one value — exact by construction, with no estimate of
  anything. Measured in radial luma bands against Forward+ at the same poses (disc core /
  outer disc / limb-and-ring, before → after): Earth 0.66 / 0.48 / 0.22 →
  0.97 / 0.94 / 0.64, Mars 0.69 / 0.55 / 0.10 → 0.97 / 0.89 / 0.39, Venus
  0.93 / 0.87 / 0.46 → 0.99 / 0.98 / 0.79, Titan's core at 1.00. The twilight band came
  with it, being disc-branch path radiance.
- **A grazing disc ray can return a NaN, and one NaN is not a local defect.** The disc
  quadrature's intermediates span tens of orders of magnitude at the silhouette — a Chapman
  column that clamps at e^60 against an extinction that underflows to exactly zero — and
  their product was measured reaching the frame at about one fragment per two dozen views,
  always at the silhouette and on the lit side. Under Forward+ the glow pass smears that
  single fragment into a bright blob with a black core, which is what the four atmosphere
  bodies flashed as they turned; under Compatibility `display_write`'s own `max(value, 0.0)`
  scrubbed it before it could bloom, which is why the defect was renderer-specific. It
  resists attribution to a term because it is **sensitive to the surrounding compilation** —
  `isnan()` reads inside the loop stop it happening, while the same reads one scope out catch
  it without suppressing it — the same driver behaviour `atm_present()` was added for. So
  `atm_disc()` ends with a finite guard: a fragment falling back to no air in front of it is
  invisible in a field this smooth. Two related numerical corrections came with it — the
  tangent altitude is formed as `-R mu^2 / (1 + sqrt(1 - mu^2))` and never as `b_ray - R`
  (the difference of two planetary radii, which in float32 collapses to exactly zero for a
  grazing ray and puts a quadrature node on the ray's own tangent point), and `atm_disc_air()`
  now decides the handoff fade *before* running the quadrature, so the degenerate ray the
  shell owns outright is never evaluated at all.
- **The beyond-limb RING self-lights and restates** (2026-08-30, same pass): the limb
  shell's linear radiance had met the engine's own conversion raw and crushed — the ring
  measured 0.03–0.22 of Forward+, effectively absent, worst on Titan, whose lit-side limb
  is the thing a viewer looks at. Its pedestal is the provable constant 0 (empty sky and
  the stars), so the rings-shell restatement applies with no estimate of anything: on the
  display branch the fragment self-lights on `sun_light_energy` and writes its finished
  value through `display_write()` — with `blend_premul_alpha` the colour is the whole
  premultiplied term, so no `display_mix` pair is needed. Ring-annulus luma against
  Forward+, before → after: Earth 0.40 → 1.02, Mars 0.18 → 0.92, Venus 0.59 → 0.98,
  Titan 0.07 → 0.79 (that last diluted by the annulus estimator on a crescent pose;
  rendered, Titan's haze ring stands where its limb had simply been absent). Forward+
  re-renders bit-identically — the linear branch is untouched.
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
  this test (impact parameter against the disc radius). Recovered 2026-08-30, exactly this
  way — see the restatement bullet above.
- **The scalar pedestal was sound on a body without a cloud deck** — and is superseded
  (2026-08-30): relocating the disc branch into the disc shaders needs no pedestal at
  all, on any body, Earth included. Kept for the record: Venus and Titan carry no map and
  Mars no deck, and the veil over their discs measured 1.000 with the body table's albedo
  as the whole estimate, Mars' lit side +4–10 % its known residual.
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

## Glow: the bloom pass

`Environment.glow_enabled` is on in `resources/ivoyager_environment.tres` (2026-08-30,
intended as the Core default), with every other glow property at its engine default. This is
the bloom pass the sun's disc/point co-calibration and the f16 caps were built for. It is a
**display-stage camera effect**: it reads the rendered frame, not the light chain, so nothing
in the CPU photometry changes — what changes is which rendered values spill light into their
neighbors. Judged in-app on Forward+ at the defaults: good.

### Which glow settings a project may change

Godot exposes a dozen glow properties and they are not peers: two carry the contract this
whole model rests on, one is a real photometric lever, and the rest are taste. What makes
the difference is that **glow's threshold and the metering key are one agreement** — the
camera meters a surface to `metering_key` (0.5) so that anything the camera has *not*
exposed for is what clips, and glow's job is to spill exactly that and nothing else. A
setting that breaks that agreement does not merely look different; it decouples bloom from
the exposure system and every statement in this document about what blooms stops being
true.

| Setting | Ships | May a project change it? |
|---|---|---|
| `glow_bloom` | 0.0 | **No.** It is a floor under the threshold test, so any value above 0 blooms correctly exposed surfaces — the one thing the model forbids. It is also what keeps the fragment-id broadcast dark (below). |
| `glow_hdr_threshold` | 1.0 | **No, not downward.** 1.0 is the whole contract: "what clips, spills." Lowering it blooms metered content; raising it mutes the faint end for no gain, since the cap already flattens the bright end. |
| `glow_hdr_luminance_cap` | 12.0 | **Yes, knowingly.** The one photometric lever here — where bloom stops being proportional to flux (see below). Raising it buys honest wing energy on the brightest sources and costs bright-end size hierarchy and firefly damping. Inert under Compatibility, which clamps lower on its own. |
| `glow_blend_mode` | Screen | **Yes, except Soft Light.** Screen and Additive both composite pre-tonemap in linear and agree over dark sky. Soft Light is the odd one out: the engine applies it *after* tonemapping, on display-referred values, which is the one mode that is wrong here on principle rather than to taste. |
| `glow_levels`, `glow_intensity`, `glow_strength`, `glow_mix`, `glow_map*` | 2/3/4 at 0.8/0.4/0.1, 0.3, 1.0, 0.05, none | **Yes, freely.** Halo width, weight and shape. None of them touch which pixels qualify, only how their light is spread. |
| `glow_normalized` | off | **Yes, but it does nothing here.** It renormalizes the level weights on the CPU (free), and at fixed levels that is a uniform 1/1.3 rescale — indistinguishable from turning `glow_intensity` down. Tested; no visible change. |

One setting outside the glow group belongs in the same list: **the tonemapper**. Glow
composites *before* it, so `tonemap_mode` decides what a halo looks like after it is added.
The model assumes the shipped LINEAR tonemapper, under which the composite is a true
veiling-glare add.

**What the engine does with it** (verified in the 4.7.2 source;
`servers/rendering/renderer_rd/shaders/effects/copy.glsl` and `tonemap.glsl`):

- The pass reads the **pre-tonemap linear HDR buffer** through a downsample chain. Each
  texel's contribution is gated by `smoothstep(glow_hdr_threshold, threshold +
  glow_hdr_scale, max channel)` — defaults 1.0 and 2.0, so nothing below white contributes
  and contribution is full by 3.0 — and **capped at `glow_hdr_luminance_cap` = 12.0** per
  channel. A Reinhard weighting on the first downsample suppresses single-pixel fireflies,
  which also suppresses the sub-pixel star shimmer a bloom could otherwise amplify.
- The blurred levels (defaults 2/3/4 at 0.8/0.4/0.1 — quarter- to sixteenth-resolution)
  times `glow_intensity` 0.3 composite **before tonemapping, in linear light**, for every
  blend mode but Soft Light. The default Screen blend at `white` 1.0 is
  `color + glow − color·glow`: over dark sky — where every halo lives — that is an additive
  light sum to first order, rolling off only as the base nears white. Under our linear
  tonemap this is a true veiling-glare add, not a display-space paint-over. (The old
  Soft Light default is the display-referred one; it is gone from the defaults and nothing
  here should want it back.)

**The consequences land exactly where a camera's do.** `metering_key` is 0.5, so a correctly
metered surface sits below the threshold and does not bloom; only what the compensating
camera lets clip spills — the sun, bright star cores, a blown atmosphere limb, overexposed
cloud tops, clipped city cores, the near-opposition ring face. Because our exposure acts
pre-tonemap (in `light_energy` and `iv_exposure`), the threshold is applied *after*
adaptation: a source blooms exactly when the camera is exposed such that it clips, and an
eclipse that dims `light_energy` takes the bloom down with it, automatically. The background
panorama never reaches the threshold in either mode (peak ≈ 0.087 × 2^`exposure_max_ev` ≈ 0.7
at rest), so the Milky Way correctly does not bloom.

**The star PSF is not redundant with this, and could not be.** The PSF is the star's image —
the calibrated core-plus-skirt that carries photometric proportionality and the `sqrt(ln I)`
size law. Glow adds the wide scattering wings the Gaussian does not have, and its per-texel
energy caps at 12 while star peaks run to the 32768 f16 ceiling: bloom is proportional to
flux only between threshold and cap — roughly V 3 to 5.5 at the 1080 reference height and
reference fov, the band riding the same resolution and fov compensations as the field — and
every brighter star blooms at the cap, differentiated only by footprint, which grows as
`sqrt(ln I)`. That is why glow shows on a small subset of stars, and why that subset's halos
look alike. The cap is also half-deliberate protection: wings proportional to flux would
clip white around the brightest cores and re-flatten the bright end toward identical blobs —
the look the PSF size law exists to avoid.

**Which is why the wings are no longer the pass's job (2026-08-31).** That cap is a
brightness ceiling on a source whose brightness is the whole point: the sun runs V −26.7 at
Earth to −19.0 at Pluto, a factor 1225 in flux, and the bloomed halo moved only 39 → 29 px
across it — radius as `I^0.04`, one doubling per 19 magnitudes — while the brightest field
star's was 2. On Compatibility it is worse than flat: the glow buffers inherit the scene
buffer's RGB10_A2 and store `0.25 × color`, so the per-texel feed clamps at 4.0 whatever the
property says, `glow_hdr_luminance_cap` and `glow_levels` are byte-for-byte inert, and the far
sun's halo measures the same 4 px with glow on as with it off. The far sun therefore read as
an ordinary bright star on both renderers and as an ordinary star full stop on the web.

So a source now carries its own wings, in the shader, where the intensity is still a float32
that nothing has clamped: `psf_glare_*` in `_point_spread_function.gdshaderinc`, shared by the catalog
field (on its own point sprites) and by every in-scene body bright enough to warrant one (on a
quad, `body_psf.gdshader` — the law is the same, only the geometry differs, because
POINT_SIZE's driver maximum is as low as 1 in the GLES3 spec and the sun's glare runs to
hundreds of px). It is the same structural
move as the atmosphere's disc air and its beyond-limb ring: what a display-stage pass cannot
carry identically on two renderers gets computed before the conversion instead. Four things
about it:

- **The shape is physical; the amplitude cannot be.** A real PSF is Gaussian in the core and
  a power law in the wings, exponent ~2 over the decades that matter for an eye or a lens
  (the CIE disability-glare law, `L_veil = 10 E / θ²`). But that law puts ~10 % of a source's
  light in the wings, and 10 % of the sun's flux at the dark-adapted rest exposure is about
  4500× saturation over the *whole frame* — a photograph exposed for the Milky Way cannot
  also hold the sun. So the amplitude carries a compression exponent, `glare_gamma`, exactly
  as `intensity_gamma` does for the field, and the outer radius grows as `I^(gamma/2)`: one
  doubling per 5.3 magnitudes at the shipped 0.286, against the core's one per 19.
- **The pair is anchored, not chosen.** `glare_scale` 0.0126 is set so that at the far sun the
  glare reproduces the Forward+ glow halo it replaces (31 px at 32 codes against a measured
  29) — the appearance already judged good — leaving the growth law to restore the hierarchy.
  Measured at Pluto, 35.6 au: the halo's 32-code radius goes 29 → 44 px on Forward+ and
  **5 → 54 px on Compatibility**, and at Earth 39 → 102 and 6 → 122.
- **Where the wing stops is a rendering boundary and is drawn as one.** The core's rule — cut
  where it falls below one 8-bit step — needs nothing else, because a Gaussian is two orders
  down a pixel later. On a `1/r²` wing that same cut is 13 display codes and drew a plain
  circle around the sun. So the wing is faded to zero over its last octave (`PSF_GLARE_TAPER`),
  the same treatment the atmosphere ring takes at its shell, costing only the part below one
  step. `glare_max_px` bounds it, and bounds the AMPLITUDE rather than the radius, so the
  "drawn until it stops being representable" rule stays exactly true.
- **It costs about a tenth of a millisecond.** Median GPU frame time over the same pose,
  glare off → shipped: 1.339 → 1.438 ms on Forward+ and 1.589 → 1.593 ms on Compatibility,
  against ±0.03 ms of scatter across the nonzero constant sweep. Most of that is the field,
  not the sun: a wing widens every star's sprite (a V 6.5 star 3.7 → 8.7 px, Sirius 5.3 →
  24.9), and there is one sun. Sirius and Vega now exceed the 20 px the point-size note in
  `stars.gdshader` calls known-good, which is a stated platform risk rather than a hazard —
  a driver clamp truncates the wing's faint outer part and nothing else.

The glare does NOT take the disc/point crossfade: that ramp decides whether the camera
*resolves* the body, and glare belongs to the camera rather than to the subject. That is what
makes the persisting wing over a resolved disc the same thing as crescent glow — see *Point
sources: one PSF quad per bright body* in the sibling document, which owns the spatial half of
this system and the reflected-light magnitude a sunlit body rides on. On Forward+
the glow pass still adds its own halo on top, so the two renderers are close rather than
identical (Saturn station: 32-code radius 55 px against 59); the residual is the
display-referred blend's encoded add over a non-black sky, the boundary `_display.gdshaderinc`
already documents, and it vanishes over truly black sky. The shader header that anticipated
"bloom in proportion to true brightness" (`stars.gdshader`) was describing this; it gets
corrected with the eventual tuning change.

**The other defaults are right, or near enough.** `glow_bloom` must stay 0.0 — it blooms
below-threshold content, i.e. correctly exposed surfaces. The threshold at 1.0 means "what
clips, spills," which is the right meaning under a linear tonemap. Levels and intensity are
taste (halo width and weight). Additive blend instead of Screen is the strictly physical sum
and differs only over already-bright content. `glow_normalized` is free — a CPU
renormalization of the level weights, no GPU cost — but at fixed levels it only rescales the
whole effect by 1/1.3, which is why toggling it showed nothing; default off is right.

**The sun is glow-continuous through its handoff only under physical light.** There the disc
and the point both saturate the shared `PSF_LIGHT_MAX` through the crossfade, both sides
bloom at the cap, and the halo carries through. **With physical light off it does not**: the
nonphysical disc constant (~3.0, `IVShellsModel`) meets a point whose peak holds the f16 cap
through essentially the whole fade (at the sun's flux, `(1−w) × intensity` clears 32768 until
the last sliver of the ramp), so per-texel glow steps from the 12 cap to ~3 and the halo pops
off at the top of the crossfade instead of fading. This gap is long-standing —
invisible while both halves merely clipped to white, and the glow pass is its first consumer. See TODO; noting, for that fix, that
`IVBody2DCapturer` already writes its own preview brightness and must keep it.

**The HUD stays out of it, and the one thing that did not is fixed.** Orbit lines, labels
and points write ≤ 1.0 and cannot bloom (halos from nearby sources wash over them, as over
everything in the 3D buffer; the 2D GUI composites later and is untouched). The exception
was the **fragment-id broadcast**, and it was the worst case glow can produce: an id-bearing
fragment inside the mouse grid wrote its raw channels — up to 2048 — into the very buffer
glow reads, so every one of the 49 grid pixels bloomed at the cap. Measured hovering an
orbit line, **553 of the 625 pixels around the cursor were saturated**, a blob that got
worse the more id-bearing fragments the grid caught, which is why a crowded asteroid field
showed it first.

The broadcast now goes through `id_broadcast()` in `_fragment_id.gdshaderinc`, which carries
each channel in **[0.5, 1.0]** — topping out exactly AT the threshold, where the pass's
smoothstep is still zero — and the probe lifts it back out. The same box measures **31 of
625** saturated with hover picking bit-for-bit unchanged (same hits and misses on the same
pixels as before the change). Two things fell out of it that are worth knowing. A channel
now holds **1024 values, not 2048**, so an id is 30 bits rather than 33: the band is one
binade, whose half-float step is 1/2048, and a broadcast that does not survive RGBA16F
storage exactly decodes as the wrong id. And the band **narrows the probe's accept window**
from "every channel above 0.5" to "every channel inside one octave", so content brighter
than an id — a star, a lit limb — can no longer be mistaken for one; false positives went
down, not up. `glow_bloom` must stay 0.0 for this to hold, which it must anyway.

The probe itself reads at `POST_TRANSPARENT`, pre-tonemap and therefore pre-glow, so picking
was never at risk from glow — only the picture was.

**Captures.** Hi-res screenshots share the environment and get glow; halo radii are
resolution-relative (blur levels) where the PSF is absolute pixels, so a halo holds its share
of the frame while stars stay pin-sharp, and a taller render pushes fainter stars over the
threshold — both consistent with the fixed-f-number camera the star field already implements.
The 2D icon rig runs its own `World3D` on the default environment: **no glow in icons**,
which keeps transparent readbacks clean and costs the exact in-sim look of overexposed
content. Accepted.

**Compatibility gets a different pass, and it is ON there — a deliberate trade, not a free
win.** It was gated off on 2026-08-31 and back on with the PSF quad system, and the
measurements that argued for the gate all still stand: the pass adds no halo to a point source
(above), and enabling it moves tonemapping into a post pass that re-runs the transfer bracket
`display_write()` pre-inverts exactly once, so background content measures **0.041x at 6-8
codes, 0.19x at 8-10, 0.66x at 12-18, and 0.84x over the whole frame**, where Forward+
measures 1.000x at every level. That is the Milky Way and the faint stars, and with the pass
off the two renderers agree on the same frame to 0.8 %. What buys it back is **extended
sources**: spacecraft parts, small moons and asteroids sit outside the `IVBodyPSF` quad
system, which now draws its own wings for every source that has one, and the pass is the only
glow those others get anywhere. The rest of this paragraph is the mechanism. A project that
wants it off can author its own Environment.

**What the pass actually does on that renderer.**
Verified in the 4.7.2 GLES3 source (`drivers/gles3/rasterizer_scene_gles3.cpp`,
`shaders/effects/glow.glsl`, `post.glsl`): only `glow_intensity`, `glow_bloom` and the three
HDR properties act — levels, strength, blend mode, map and normalized are RD-only — the blend
is always Screen, and the chain is a fixed 4-level dual filter. More consequentially,
enabling glow flips the renderer into the post-effects path that `IVWorldEnvironment`
deliberately avoids for the adjustment stage on this renderer: the scene and sky passes defer
tonemapping to a post pass and render ×0.25 into RGB10_A2 (encoded headroom to 4.0), and the
full-resolution post pass screen-blends the glow **in the encoded domain** and then runs
`srgb_to_linear` → tonemap → `linear_to_srgb` — the approximate transfer bracket a second
time, where `display_write()` pre-inverts it exactly once. The dim end re-crushes (an encoded
0.05 lands at 0.030, 0.1 at 0.089; above ~0.3 the bracket is near identity): the defect the
display pipeline work removed returns for all dim 3D content, plus the full-res buffer, the
extra pass and the shader repermute the web build was spared. The threshold also gates
*encoded* values — full feedback spans linear ≈ 1–13, and the cap is unreachable under the
4.0-encoded storage ceiling — so what glow the web gets is dimmer and differently shaped than
Forward+'s even where it works. (In a transparent render target the format is RGBA8, the
headroom trick is off, and glow is inert while the post pass still runs.) All of which is why
the pass earns its keep here only for the extended sources the quad system does not reach; the
*Renderer parity* numbers are measured with it off, and are that much better than the shipped
configuration on dim content. Recovering most of the crush would take a third display mode
that pre-inverts the bracket twice — not the bottom few codes, each pass's encode having a
hard zero floor — or extending the quad system to every body with a computable magnitude,
which would shrink the pass's remaining role to spacecraft parts.

**And the one lever is inert there, which is why the far sun reads as an ordinary star.**
The glow buffers are allocated in the render target's own format
(`RenderSceneBuffersGLES3::check_glow_buffers`), so they are RGB10_A2 like the scene buffer,
and the filter pass writes `luminance_multiplier × color` — 0.25 × a value capped at
`glow_hdr_luminance_cap`. Anything above **4.0 clamps on store**, so the effective cap is
4.0 whatever the property says, and raising it changes nothing. The scene buffer clamps at
the same 4.0 encoded (≈ 27.5 linear), so the sun's ~1e9 and a bright field star's ~1e3 are
*already the same number* before glow samples them. On Forward+ they survive to the pass and
are flattened by the 12.0 cap instead — the same outcome by a different route, and the
reason the far sun did not stand out from the brightest stars on either renderer. What
separates them is footprint alone: the above-threshold radius of a point grows as
`sqrt(ln I)`, which is 3.2 px for the sun against 1.8 px for Sirius, an area ratio of about
3. That was never going to be enough, and it is what the shader glare above replaces: the
lever a capped pass cannot offer is one the shader does not need.

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
| body tables | `albedo` | V-band geometric albedo: the asset-level target (a map's sphere mean) and, unless overridden, the metering albedo. |
| | `meter_albedo` | Metering albedo where what the camera sees is not the map alone — a body whose shells add light over it. Earth only. |
| | `emission_luminance_scale` | Luminance of a full-white emission texel at multiplier 1.0. |
| | `ambient_starlight_illuminance` | Integrated starlight: ambient level and the metering floor. |
| | `auto`, `manual_exposure_ev`, `exposure_adjustment_ev` | Runtime overrides for a GUI: hold the metered result, replace it with a stated EV, or offset either. The defaults (auto, no adjustment) apply the metered result itself. |
| | `auto_exposure_ev` (read-only) | The metered and adapted result, in EV relative to the authored sky look. Live every frame whether or not `auto` is set, so a control can display it and hand it to manual without a jump. |

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
  - **Fixed: the shells were lit plane-parallel, so nothing was lit past the terminator.**
    Every shell took `albedo x max(mu0, 0) x atm_sun_transmittance`: flux entering the column
    goes as mu0, so illumination was pinned to zero at the geometric terminator WITH A CORNER,
    and surface and deck stopped at the same line while the glow ran on to mu0 -0.13. On a
    sphere the air above a point at mu0 = 0 is still fully lit and shines down; nothing put
    that light anywhere. New `atm_sky_flux` / `atm_sky_slope` / `atm_sky_bend` carry the
    twilight curve `flux x exp(mu0 (slope + mu0 bend))`, fitted per body and channel by
    `limb_model.py --fit-skylight` against a hemisphere integral of the same layers, columns
    and shadow rule the limb uses; `atm_sky_excess` adds it as EMISSION, as the excess over
    the plane-parallel diffuse the shell already gets. Measured with the limb hidden, Earth's
    body at its terminator goes **0.11 rendered codes -> 5.25** and carries light **8.6 deg
    past the line** where it carried exactly none; band contrast rises 40 %, band level 4-5 %
    (Mars 19 %, Titan 42 %, Venus 2.8x). The subtraction is what makes the day side identical
    rather than close: term-on against term-off in ONE app run measured **0.0000 codes**
    above 3.4 deg of solar elevation.
  - **A BRDF's BEAM FACTOR IS NOT ITS ANSWER TO DIFFUSE LIGHT, and the mismatch renders as
    a SHELF.** The twilight first shipped riding whatever disc law the shader had already
    applied to ALBEDO -- `mu0^(k-1) mu^(k-1)` for Minnaert -- which is an answer about one
    incidence angle applied to light that has none. On Venus (k = 1.35) it collapsed the
    twilight toward the terminator exactly where it takes over, and the rendered slope went
    449 / 222 / 88 / **0.7** / 173 across mu0 0.045 -> 0.005: a flat plateau inside a steep
    gradient, which is a Mach band, and it was reported as a lighter band before the night
    side. The illumination itself has no shelf -- its slope rises monotonically from the
    terminator outward (Venus 0.29 -> 0.94 over mu0 0 -> 0.09), with the fitted curve or with
    the raw integral -- so the band was never in the twilight. Isolated in one app run with
    only `minnaert_k` differing: at 1.0 the shelf is simply gone. The fix is the law's
    hemisphere integral (`*_isotropic_response` in `_photometry.gdshaderinc`), which takes
    that minimum slope to 57.5 with the day side at ratio 1.0000. Note what it does NOT
    remove: near a terminator the surface really is lit by its sky and not by the beam
    (Venus's skylight is 3.4x the beam at 1.15 deg of sun elevation and 22x by 0.3 deg), so
    a flattening there is correct and some of it survives.
  - **MOVING LIGHT BETWEEN ALBEDO AND EMISSION IS NOT NEUTRAL, WHICH RULES OUT THE TIDIER
    FIX.** The obvious restructure -- beam on ALBEDO with the beam factor, the whole diffuse
    half on EMISSION with the isotropic response -- is algebraically an identity on a Lambert
    body and measured **25 % dark** on Mars. ALBEDO rides the engine's N.L through the NORMAL
    MAP, so it carries per-texel relief shading; EMISSION rides nothing. Routing the
    day-side diffuse through EMISSION therefore strips relief from 70-99 % of the
    illumination. That is also the physical answer: the two-stream's diffuse half is largely
    FORWARD-scattered and keeps the beam's directionality, so it belongs on the beam's
    footing. Only the twilight, which really does arrive from the whole sky, moves to the
    isotropic response.
  - **A shipped table cell was deciding where that handover happens.** `atm_haze_multiple` is
    a boost on a layer's RADIANCE, tuned by eye for a limb, and the plane-parallel two-stream
    the curve hands over to ignores it -- so with Titan's 2.0 in the fit, its sky beat the
    two-stream out to a solar elevation of **15 deg** and brightened half its disc 1.7x,
    against 2.4-4.2 deg for the other three bodies. Two estimates of one quantity have to
    stand on the same footing. Excluded; Titan lands at 5.3 deg. Found the same way:
    `limb_model.py` had **drifted from the table**, carrying 1.0 for Earth's shipped
    `atm_gas_multiple` of 1.3 -- the recurring failure that its own `--verify` cannot see,
    being a comparison of two integrals over the same body.
  - **What is left is the DECK, and it is now well posed.** A cloud is a scattering layer, not
    a horizontal Lambertian sheet, so its radiance carries no mu0 projection -- which is
    exactly why this model's own glow survives to mu0 -0.13 while the deck inside it does not.
    At mu0 = 0 the deck's sun ray is tangent at its own 10.19 km, where Earth's tangent optical
    depth is **2.23, i.e. 10.7 % of the beam still arrives**, and a layer law would collect it
    where the N.L projection throws all of it away. That is what makes real sunset cloud tops
    glow, and it is deck-only: the ground IS a horizontal surface and its mu0 projection is
    right. It needs the shadow graded through the deck's own thickness rather than cut at a
    line (a cutoff law only moves the wall -- rejected above), and both halves need the deck's
    optical depth separated from its coverage, which `Earth.clouds.albedo.512.png` cannot
    supply. Also unresolved and unrelated: at mu0 < 0.06 Earth's ocean cannot compete on
    albedo at all -- 0.05 against a glow that is 65-80 % of the pixel.
  - **The twilight curve runs 2.3x over Earth's observed illuminance, and that is the expected
    sign.** 927 lx at sunset against ~400 measured. Single scattering with no ozone: the
    Chappuis band is what takes real twilight down, over a horizontal path through the ozone
    layer, and this model has no ozone anywhere -- the limb's own glow included, so the two
    stay on one footing. Worth checking the veil's twilight width against full-disc imagery
    (EPIC, Himawari) in the same pass, since both are one calibration.
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
- **Glow follow-ups.** The bloom pass the disc/point co-calibration anticipated has landed
  as `Environment.glow_enabled` in `ivoyager_environment.tres`, judged good in-app on
  Forward+ at the engine defaults (see *Glow: the bloom pass* for the audit). Still open:
  - **The nonphysical sun handoff.** With physical light off, the disc's
    `_SUN_DISC_BRIGHTNESS` (3.0, `IVShellsModel`) meets a point holding the f16 cap, so the
    halo pops off at the top of the disc/point crossfade instead of carrying through — a
    long-standing gap made visible by its first consumer. Fix by
    co-leveling the nonphysical disc with the point at the cap (one constant; both halves
    already clip to identical white without glow, so nothing else moves), minding
    `IVBody2DCapturer`'s sun preview, which writes its own brightness for RGBA8 readback
    and must keep it. The stale "future glow pass" wording left in
    `stars.gdshader` goes with that change.
  - **Night-side metering re-judgment** (see *Night-side emission*): clipped city cores now
    spread instead of being contained. Judge in-app; the 0.3 cd/m² anchor and Earth's
    `exposure_ceiling` are the knobs if the blowout stops reading correctly.
  - **`glow_hdr_luminance_cap` A/B** if the brightest stars' halos read too uniform: the
    cap (12.0) is where bloom stops being proportional to flux, and raising it trades the
    bright-end size hierarchy and firefly damping for honest wing energy. Less pressing
    since the star glare landed — the flux hierarchy the cap flattens is carried in the
    shader now — but the pass still governs every OTHER clipped source (a blown limb,
    overexposed cloud tops, city cores, the near-opposition ring face). In-app judgment;
    the default is defensible.
  - **The star glare's two constants** (see *Glow: the bloom pass*): `glare_scale` 0.0126
    and `glare_gamma` 0.286 are anchored so the far sun reproduces the Forward+ glow halo
    they replace, and the growth law is a stated representation, not a measurement — the
    physical amplitude is unrenderable at any exposure a star field can use. Candidates at
    0.5x and 2x scale, and gamma 0.20 and 0.40, are rendered and measured; the sweep is
    reproducible in one app run through the probe suite's `set_psf_settings`. An in-app
    judgment, at Earth (the largest halo, 102-122 px at 32 codes) as well as at Pluto.
- **Anchor refinement**: the 20.0 mag/arcsec² anchor is good to a few tenths against
  LMC/SMC levels in the shipped map; a tighter cross-check against published integrated
  photometry is possible.
- **Sun surface tuning**: in-app judgment of the procedural photosphere (every parameter
  is a uniform) and granulation time evolution, which is static by decision rather than
  oversight — a granule lives ~10 minutes, so the time input belongs on the sim clock.
