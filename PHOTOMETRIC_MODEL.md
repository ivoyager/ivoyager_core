# The Photometric Model

This document describes how I, Voyager renders physically calibrated light: what the
numbers mean, where they come from, and which classes, shaders and settings carry them.
It is about the logic and the science; implementation detail lives in the class and
shader docs. It has two siblings. [VISUAL_MODEL.md](VISUAL_MODEL.md) covers where
everything is drawn and how big, what stands between it and the light, and how the mouse
finds it; a system with both a photometric and a spatial face (rings, the sun, the star
field) appears in both documents, split by concern and cross-referenced.
[PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) is the objective simulation underneath both —
bodies, orbits, rotation, time and scale — which light physics reads and never modifies.

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
  values darken self-luminous content (stars, the sky panorama, a body's PSF quad, a
  star's disc) as the camera stops down for a bright subject. Lit surfaces do not read
  it; they receive exposure baked into `light_energy` by `IVDynamicLight` (never both —
  that would double-expose). It is the one global that is not neutral with the system
  off: it holds `IVExposureManager.INACTIVE_EXPOSURE` (2.0, matching the
  `exposure_max_ev` default) so a project without the compensating camera renders every
  self-luminous source at the level this one rests at.
- `iv_emission_luminance_scale` — rendered units per cd/m² (exposure × gain), which
  renders an emission map (city lights) at the physical luminance its `shells.tsv`
  `emission_luminance` column asserts. 0.0 while the system is off.
- `iv_emission_energy_scale` — gates the by-eye emission channel, `shells.tsv`
  `emission_energy_multiplier`: 1.0 while the system is off, 0.0 while it runs. The two
  emission globals are never both nonzero, so a shell authors both columns and the shader
  sums the channels rather than branching.
- `iv_limb_scale` — rebases the atmosphere-limb glow while the system is active
  (see *Atmosphere limbs* below).

The other three are neutral whenever physical light is off — 1.0 where one multiplies an
authored value, 0.0 where one gates a channel the authored look does not use — so every
shader renders the authored look, at the fixed exposure `iv_exposure` names.

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

The same three answer a project that wants to bring them; see *A project's own lighting*.

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
identical at every exposure. Nor does anything outside the candidate set above meter at all:
the set is bodies and the two asserted shell ceilings, so a project's own local scene is
invisible to the meter however much of the frame it fills (*A project's own lighting*).

What metering decides is also what need not be drawn at all: see *Skipping what the camera
has metered away*.

## A project's own lighting

A project that hangs a scene of its own inside the simulation
([VISUAL_MODEL.md](VISUAL_MODEL.md) *The render frame anchor and local scenes*) brings its own
lights, its own materials and possibly its own ideas about exposure. There are three ways that
can go, and only the middle one needs anything from this document.

**1. Nonphysical, and the default.** With `enable_physical_light` false every global here is
neutral — 1.0 where one multiplies an authored value, 0.0 where one gates a channel — and every
shader renders the authored look at the fixed exposure `iv_exposure` names. The project lights
its scene however it likes and hand-tunes our items to taste (the `nonphysical_*` settings, the
shell `energy_multiplier` columns). Integration cost is zero, and for a game whose subject is
the local scene this is usually the right answer.

**2. Our physical light, with the project joining the scale.** Everything the project adds must
then speak the same units, and every join already exists:

- *Which light reaches it.* `IVCoreSettings.size_layers` sorts content into the far / middle /
  near domains by radius, and a project's local scene is near-domain content — lit by the near
  light, which carries shadow maps and scales its energy by `camera_sun_visible_fraction`, so a
  base goes dark in an eclipse with nothing written for it
  ([VISUAL_MODEL.md](VISUAL_MODEL.md) *Local shadow maps*).
- *The project's own lights.* Convert as `IVDynamicLight` does:
  `light_energy = illuminance × IVExposureManager.gain / π × exposure`, with `IVPhotometry`
  holding the conversions and `gain` a public static. A lamp stated in lux then sits on the same
  scale as sunlight at Saturn and stays right as the camera adapts.
- *Emission.* Anything authored in cd/m² multiplies `iv_emission_luminance_scale`; the by-eye
  channel is `iv_emission_energy_scale`, and the two are never both nonzero.
- *Custom shaders.* `_display.gdshaderinc`, without exception. A project shader that does colour
  arithmetic on a sampled value and writes the result raw is correct under Forward+ and wrong
  under Compatibility by the whole transfer curve (*Renderer parity*).

The gap is **metering.** Candidates are bodies and shell ceilings, so a project's scene
contributes none and a lit interior filling the frame meters at the dark-adapted rest and blows
out. Two existing outs: hold the metered value (`auto = false`, `manual_exposure_ev`) or offset
it (`exposure_adjustment_ev`). One designed extension — a local-scene ceiling candidate on the
`exposure_ceiling` pattern — is TODO.

**3. Godot's own physical light and auto exposure: one exposure authority, and it cannot be
both.** *Overview* gives three reasons we do not use `CameraAttributesPhysical`, and none of
them changes when it is the project asking. Ours folds exposure into `light_energy` and the
emission globals, all of it before tonemapping; the engine's applies after, to the finished
image, and takes the HUD and every overlay with it. Run both and the scene is exposed twice. Two
smaller couplings follow from the same place: `Light3D.light_intensity_lumens` / `_lux` take
effect only while a `CameraAttributesPhysical` is present, so photometric units for a project's
own lamps are not separable from that camera — convert through `gain` instead, which is the same
physics against our anchor rather than the engine's; and `CameraAttributesPhysical` sets FOV
from focal length, which the star field's own FOV and resolution compensation assumes it owns.
So the choice is tier 2 or tier 1, made once per project rather than per scene.

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

A cloud deck (e.g. Earth's) is an overlay shell whose map carries the deck's reflectance in
rgb and its coverage in alpha. What that pair MEANS is set by `clouds_two_stream_map`, and
the difference is the difference between a deck built from one number per texel and one
built from two.

**Without it (Neptune's), the two channels are already composited and go straight through.**
A source cloud map supplies one number per texel, so the conservative two-stream relates
them, `A = 1 − (1 − R)²` and `C = R / A`, giving `A·C = R` identically — the deck's own
light is the source's, and what the split fixes is the surface beneath it. A texel half
covered by opaque cloud and one wholly covered by thin cloud arrive as the same middling
value, which is why nothing about such a deck can depend on the sun's angle.

**With it (Earth's), the two are independent measurements and the shell composites them at
each fragment's own geometry.** Alpha is the geometric cloud FRACTION `f`; rgb is the
cloud's own conservative two-stream albedo, which is a monotone encoding of the scaled
optical depth `τ* = (1 − g)τ` at a reference `µ = 1/2`, so the shell recovers
`τ* = R / (1 − R)` — that reference is fixed at 1/2 for exactly this inverse and the build
script must agree. Then each leg of the light's path takes its own cosine,

    R(µ) = τ* / (τ* + 2µ)          T(µ) = 1 − R(µ)

and matching `ALPHA·ALBEDO + (1 − ALPHA)·surface` against
`f (R(µ0) + surface·T(µ0)·T(µ)) + (1 − f)·surface` gives the deck's albedo `R(µ0)` and its
opacity `f (1 − T(µ0) T(µ))`. The two channels do not arrive at the same resolution and the
build does not pretend they do: a cloud mask reports coverage everywhere, while an optical
thickness is retrieved only on a confidently overcast pixel and so reaches 82 % of the cloudy
area even with four satellites — so the shell's rgb is a regional field with the retrieved
detail faded in over it, and a viewer sees measured thickness where there is one and its
neighbourhood's level where there is not. Two things follow that a composited pair cannot say. The
deck's own **layer law**: its albedo rises toward the limb the way a cloud's does instead of
sitting at one value, which measured on Earth is 0.86× the disc at phase 20 and 1.08× at
phase 90, with clipping more than halved (4.3 % → 2.0 %) — a cloud deck is much less
limb-darkened than a Lambert surface. And the **graded shadow**: the covered fraction's sun
leg goes as `T(µ0)` and shuts off as the sun grazes, while the clear fraction passes full
sunlight at any incidence. That is the shadow graded through the deck's own thickness rather
than cut at a line, and it is the half that needed the fraction and the thickness apart.

**`clouds_relief` carries the deck past the body's own terminator, and it is the one
judgment here.** A plane-parallel layer takes `F µ0` and so goes dark at `µ0 = 0` however
thick it is — right for the ground, which *is* a horizontal surface, and wrong for a cloud
field, whose sides are what a low sun lights. The cell is that side area per unit ground,
and `sqrt(µ0² + relief²)` reaches it smoothly: at Earth's 0.15 it is worth 1.3 % of a
near-full disc and nothing measurable on a crescent. What bounds it is geometry, not taste:
a deck stands above the disc, so it stays sunlit out to `µ0 = −sqrt(1 − (surface/shell)²)`
— 3.2° past the ground's terminator for Earth's 10.19 km — and it enters that shadow across
its own height rather than at a line, the same lit-height grading the limb exposure ceiling
uses. Past that cut the term is exactly zero and reliefs of 0, 0.08 and 0.15 render
bit-identically. Measured on the terminator band's surviving feature contrast, its minimum
across `µ0 ∈ [−0.06, +0.13]` goes 0.059 at relief 0 to 0.078 at 0.08 and 0.099 at 0.15,
against 0.054 before any of this work. The term is delivered as EMISSION, because the
engine's N·L has already thrown this light away, and it takes the disc law's isotropic
response, because light on a vertical face is not light at the layer's own incidence. One
approximation is stated rather than modelled: the sun-path transmittance is `atm_sun_
transmittance`, which clamps its column at `µ0 = 0`, so across the last 3.2° the beam is
reddened as it is at the tangent and no further; the lit-height ramp dominates that band.

**The deck's shadow lands where it falls, not underneath the cloud (2026-09-08).** The sun ray
from a surface point crosses the deck at a horizontally displaced place, so the shadow belongs
there — `clouds_sun_transmittance()` in `_clouds.gdshaderinc`, fed the deck's own map by
`IVShellsModel._propagate_cloud_shadow` and folded into the surface's sun leg, while the deck's
alpha keeps only its view leg so nothing is counted twice. It is a REDISTRIBUTION and the
render says so: over a lit disc the mean moves 0.998–1.001× while 10–19 % of the frame changes,
and from ISS altitude 44 %. Solved against the deck's sphere rather than as `h tan(z)`, which
diverges at a grazing sun. **Whether it can be SEEN was a question about the deck's
resolution, not about the term**, and the answer moved with the deck: at Earth's 10.19 km
shell the displacement is 5.9 km at a 30° solar zenith, 17.6 at 60 and 56 at 80, which
against the retired 19.5 km texel put most of the lit disc's shadow inside the texel casting
it — and against the shipped 4.89 km one puts it 1.2, 3.6 and 11 texels away. Measured at
face 2048 from 1900 km up, the term moves 38–51 % of the lit disc, p99 1 DN at phase 35 and
8 DN at phase 75, and costs nothing outside run-to-run drift. Nothing about it changed; the
map did. Bodies without a two-stream deck are untouched — Mars and Neptune render
bit-identically.

**The deck's resolution is the map's, and it carries no procedural stand-in (2026-09-08).**
Both cloud shaders had a domain warp and five octaves of fbm to hide a map four times coarser
than the surface it sat on; they were deleted, with `clouds_warp_*`, `clouds_detail_*` and
`clouds_edge_gamma`, when Earth's deck went to face 2048 — the surface's own 4.89 km texel,
and essentially the cloud fraction's own limit. Measured with the deck filling the frame, the
procedural path cost **139 µs, 4.2 % of the frame**, where going from face 512 to 2048 cost
**2 µs against 3 µs of run-to-run drift**: a modern GPU pays per fragment for the ALU whether
it is wanted or not, and pays nothing for a bigger texture that is mipmapped and cache-
coherent under magnification. So a deck that looks coarse magnified wants a finer map, and
this is where to reach for one. Two consequences, both wanted: a deck and its shadow now read
ONE map and line up by construction, where a procedural field the shadow lookup did not share
could never be shadowed correctly; and the deck's coverage stops spreading, so real gaps open
and the ground shows through them. One map is necessary and was not sufficient: a deck that
drifts is also read at a PHASE, and the lookup got the deck's only from 2026-09-19 (*The cloud
deck's phase* in [VISUAL_MODEL.md](VISUAL_MODEL.md)). The `.gdshader` files are the interface here — a body
overriding a retired uniform through a `shells.tsv` column of the same name is silently
ignored, as any unknown column is.

A deck is lit by the same light as the surface, so under an exposure metered for the
*cloudless* surface albedo, cloud tops overexpose by a factor of a few — bright, occasionally
clipped white, which matches real orbital photography. No separate cloud compensation exists,
deliberately: compensating for clouds would crush the surface. The build and its measurements
are in `records/Earth.md` in the assets build tree.

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
- **Nor does it rasterize the rest of its shell, only a camera-facing annulus of it.** Every
  ray meeting the disc farther inside its silhouette than the handoff band and the ring
  filter's half-width, `b < min(R(1 − ATM_RIM_HANDOFF), R − 1.25 px)`, returns nothing and
  discards — and on an integrated GPU a discarded fragment costs most of a drawn one: a limb
  shader discarding at its first statement measured 249 ms at Earth-fill on an Intel UHD
  under Compatibility, against 116 ms with the limb hidden. So `IVShellsModel.shader_meshes`
  gives the limb row the shared `limb_annulus_mesh` in place of the sphere, a ring of
  triangles whose vertices carry an azimuth and a row, and `limb_annulus_vertex()` places each
  where the camera ray it names enters the shell, from two pixels inside that bound out to the
  shell's own silhouette. On the shell rather than on a flat billboard, each fragment keeps the
  depth the sphere gave it — a flat annulus through the silhouette stands behind the disc
  across the handoff band, where the depth test would drop the fragments it exists to draw —
  and reads the same ray, which is all the fragment stage uses. The rows
  (`IVCoreSettings.limb_annulus_rows`) are spaced by arc on the shell for farwarp's sake (see
  *Farwarp* in [VISUAL_MODEL.md](VISUAL_MODEL.md)). Against the whole sphere only single
  pixels on the silhouette's rim move, and no more of them than rotating the sphere itself
  about its pole moves, which changes nothing but where its facets fall: the rim is sensitive
  to the last bits of the interpolated ray, whatever mesh supplies it. Measured on that Intel
  UHD under Compatibility, Earth-fill fell from 481 to 304 ms (−37 %), Venus close by 54 % and
  Titan and Mars close by 19–20 %, where the annulus's own fragments are most of what the limb
  still costs; on a GTX 1650 Ti, 3–16 %.
- **The air in front of the disc is composited by the disc's own shaders** (2026-08-30,
  `atm_disc_air()`): each surface, band and cloud fragment evaluates the veil, the
  twilight glow and the far half of an optical-limb ray for its own ray, adds the path
  over everything it renders and multiplies the luma of the disc's view transmittance
  into all of it — lit albedo, emission, and the specular lobe as its square root — with
  the tint from `atm_receiver_light()` still carrying the chromatic complement, which is exact
  and lets a cloud deck 10 km up escape the air beneath it. In linear light this is algebraically
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
  slot multiplies its sunlight by the sun transmittance `atm_receiver_light()` returns — the
  column above that shell's own altitude along the sun ray. This is what turns a cloud deck at
  the limb the colour of sunset. A body with no such row carries none of it: its shells bind
  the airless variant of each shader (`IVAssetPreloader.airless_shader_variants`), which
  renders it identically and runs faster (*Addendum: the atmosphere's structure, at runtime* in
  [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)).
- **That factor is the TOTAL illumination, direct plus diffuse, and not `exp(-column)`**
  (2026-08-28). Absorbed light is gone and takes the exponential; scattered light is not, and
  the sun leg is the one place nothing else accounts for it — a view ray's scattered light IS
  the path radiance, which the model adds separately, so the view tint and the limb's alpha
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
  `atm_view_tint` (both of which lost an argument, and are now `atm_receiver_light()`'s
  outputs). Removing it re-rendered all four bodies
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
- **The shell must outrun the profile.** The shader draws only within the limb shell's own
  silhouette, so a ray whose tangent altitude clears the shell gets no fragment: the atmosphere
  is cut off there, and if it is still rendering at that altitude the cut is a hard edge
  against the sky.
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
  the whole warm inner band of the backlit ring. The far half is now integrated too, as a
  segment of `atm_ray_path()`, at the ray's own tangent altitude *below* the disc and floored at
  the disc, which makes its view extinction `tangent column − own column above z` exactly as for
  the ring — (down to the far surface) + (the sub-disc chord) + (the near half) — with no new
  term. Rendered, the rim is continuous at every phase, and Earth and Mars are
  **bit-identical** while Venus gains at most 3 DN over 204 pixels of its rim.
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

#### Atmosphere quality, and what Reduced and Min give up

The limb shell is 75–95 % of an integrated-GPU frame in any view with air
([GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)), which is why the user setting
`atmosphere_quality` exists. Its first two tiers are the same shader:

- **Normal** — the six-node along-ray quadrature and up to eight ring taps described above.
  This is the rule `limb_model.py` verifies, and the contract in the include binds it.
- **Reduced** — a four-node rule and two ring taps. The quadrature is a valid
  Gauss–Legendre rule of its own, packed into the same table, so it is a coarser evaluation
  of the same model rather than a different one.
- **Min** — the same model integrated in closed form, in shaders of its own (*The Min tier*,
  below).

What moves on screen is small and confined to the limb: at most 2 display codes on Earth and
up to 15 on 0.4 % of Titan's pixels, 1.2–1.8 % of pixels past 2 codes. The surface and cloud
shaders take the air in front of themselves through the same quadrature, so twilight and the
sunset-reddened beam shift with it — that is where Earth's 2 codes are.

`IVGraphicsManager` writes the tier as three shader globals, `iv_atm_gl_first`,
`iv_atm_gl_nodes` and `iv_atm_ring_max_taps`. **Only their values differ between tiers, not
the shader source**, so no program is recompiled and the change lands on the next frame —
which is what lets this be a live setting on a renderer where a compile costs seconds
([SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md)). A project whose
`IVGraphicsManager` never writes them renders at Normal, those being the defaults the Core
editor plugin puts in `project.godot`.

##### The Min tier

Min is a different program rather than a coarser rule: each atmosphere shader's `.min` twin,
compiled with `ATM_MIN` so that `_atmosphere.min.gdshaderinc` stands in for the quadrature.
Everything else is shared — the layers and their columns, `atm_receiver_light()`, the twilight,
the entry points — so **a surface's own colour is Normal's exactly** (the entry-point probe reads
0.000 % on the receiver light, the sky excess and the luma), and what is approximated is the air
in front of it and beyond the limb.

Each segment of a view ray is integrated in closed form from its columns at a few points,
instead of at quadrature nodes:

- **The lit part in front of a disc.** Its radiance is the source per unit optical depth times
  the integral of e^−(T + S) over the view column T, S the sun's column. Taking the layers'
  mixture as uniform in optical depth along the segment, and S as proportional to T — the
  plane-parallel identity, carried to the sphere by the Chapman slants — makes the exponent
  linear in T and the integral exact. Where the sun is low along the segment, or the segment is
  capped or starts above the disc, S does not fall with T; a second point one upper scale height
  along measures how it runs, and the exponent is taken piecewise linear through the points.
- **Two exponential layers are not a mixture.** Earth's gas (8.4 km) over its haze (1.5 km) is
  two stacked slabs, and the uniform-mixture form fails on it by 14–20 % at the 99th percentile.
  The integral is blended between that MIXED form and a STACKED one — each layer's own run, the
  lower layer's light crossing the whole upper — with weight (r − 1)/(r + 1), r the ratio of the
  two scale heights: the thin limit of the exact two-layer integral, within ~2 % along Earth's
  and Venus' real curves.
- **A tangent half-ray** holds half its ray's column, spread from the tangent point as
  erf(√(Δz / H)), so its lit part lies between two fractions of it; the sun's column is held at
  the point that halves what the camera sees of that part, and the same blend stacks the layers.
  The thin layer — Mars' water-ice haze, Titan's detached layer — takes the mixed form, its
  columns from the shared Abel tables, so Titan's blue shell is drawn.

What moves on screen, in the app on the GTX at the 18 atmosphere poses against Normal: day sides
and the limb band hold to 3 display codes at the 99th percentile (Earth close up 5), Titan's
shell included, and the error gathers at high phase. **Earth's crescent cusps turn yellow**, by
up to 180 codes, 0.2 % of the frame past 8: one sun point per tangent half cannot follow a sun
column that grows toward the camera. **Mars' twilight is too bright**, by up to 14 codes at the 99th percentile over
3 % of a crescent frame, half of it the thin layer's mixed treatment. Reduced moves 31 codes at
most. The probe puts Min's limb and disc air within 3.4 % of the image maximum at the 99th
percentile on all four bodies, against Reduced's 5.0 % on Earth's limb.

Being its own program, Min is chosen when bodies are built: `IVAssetPreloader` binds the `.min`
shaders (`min_shader_variants`) for every body with air, the shader warm-up compiles those
instead of the full ones, and a change into or out of Min waits for a restart, which the Options
popup says. What it costs and saves is *Addendum: the Min tier, built* in
[GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).

## The Sun

The sun disc's surface brightness is derived from its absolute magnitude and radius
(`IVPhotometry.get_star_disc_luminance` — ~1.8×10⁹ cd/m²) times gain and exposure, so
approaching it, the metering dims the scene until granulation and sunspots resolve
instead of a white blowout. The disc and the star's PSF quad are co-calibrated and
crossfade by apparent size (`IVShellsModel`'s disc LOD against the handoff `IVBodyPSF`
solves), both capped at the shared half-float-safe constant that also bounds the star
field. As a metering subject the sun
uses its own late screen-fraction ramp (see above).

What resolves is generated, not sampled: `photosphere.gdshader` draws limb
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
umbral brightness-size relation — are cited in the shader.

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
the panorama had been ~6× too bright relative to the stars it sits behind.
`IVWorldEnvironment` authors the sky from that same expression
(`IVExposureManager.compute_sky_energy()`, static so it is reachable with this node
erased), so the correction holds with physical light OFF as well and the two modes
differ by exposure alone — toggling the setting moves the sky and the stars together.
At rest exposure the whole sky rides `exposure_max_ev` above the authored look.

## Skipping what the camera has metered away

Metering's output is also a visibility decision. Once the camera has stopped down for a
sunlit body, most of what this document calibrates renders below the darkest code a display
can show, and the GPU is still drawing every bit of it — in a lit-body view the background
panorama is 10–17 % of an integrated-GPU frame and the star field 13–28 %, for nothing. Two
consumers act on that: `IVWorldEnvironment` stops drawing the panorama
(`skip_invisible_starmap`), and `IVStarsVisual` stops submitting each magnitude bin the
exposure has taken under (`cull_invisible_bins`). Both poll the `IVExposureManager` statics
from their own `_process`, as `IVDynamicLight` and `IVBodyPSF` do, and the manager gains
nothing: a per-frame visibility decision is not a value it supersedes, and a consumer that
owns its own decision restores itself on deactivation through the same branch a project
running without physical light takes anyway.

### One display code, and why it is not 1/255

`IVPhotometry.ONE_DISPLAY_CODE_LINEAR` is the linear radiance that encodes to 1/255 on the
sRGB toe — `(1/255) / 12.92`, about 3.04e-4. Nothing sits between a shader's linear value
and that transfer: `tonemap_mode` is LINEAR, and `tonemap_exposure` is pinned to 1.0 under
Compatibility while physical light is active.

**`psf_visible_size()` cuts at a LINEAR 1/255, which is a different threshold for a
different job.** That value is about 13 display codes, some 1800x brighter. It is the right
cut for a sprite's outer edge, where the question is where a Gaussian stops being worth
rasterizing; it is the wrong one for asking whether a source renders at all.

**The glare wing binds at the faint end, not the core.** A star at intensity 1/255 has a
core size law that already returns zero, while its wing still peaks at
`glare_scale * (1/255)^glare_gamma`, about 2.6e-3 linear — eight or nine codes. With the
shipped PSF the wing puts the one-code cut near intensity 2.2e-6, about 8.1 magnitudes
fainter than the core criterion would. A predicate built on the size law alone would delete
stars that are plainly visible, so the test is the peak of core plus wing
(`IVPSFSettings.get_peak_light()`).

### Half a code, and the bound that buys

A drawn layer is dropped below **half** a code and is not restored until it reaches a whole
one. The lower figure is the 8-bit rounding boundary — below it the layer alone cannot round
to anything — and the gap between the two is hysteresis, one EV of exposure glide, without
which a layer sitting on the line would flip every frame.

Half a code is also what makes the guarantee provable rather than measured. In the toe the
encode is linear at 12.92, so removing a contribution under half a code moves an encoded
value by under half a code and the rounded result **by at most one**, at any pose, over any
content. Bit-identity is not available at any positive threshold: what is removed is added
light, and added light can carry a pixel across a rounding boundary however small it is.
Measured at a frozen exposure with HUDs hidden, Earth at 3 radii (13 bins hidden, sky
skipped) and Saturn at 45 degrees (4 bins, sky skipped) came back bit-identical, while
Jupiter's moon system — where the sky sat at 0.099 of a code, just under the threshold —
moved 337 pixels of 2.07 M by exactly one code, faint star pixels the removed sky had been
tipping over a boundary.

### The panorama

Its rendered radiance is bounded by `energy_multiplier * iv_exposure`: a decoded 8-bit texel
cannot exceed 1.0, and 1.0 is precisely what `background_peak_magnitude_per_arcsec2` asserts
the brightest texel to be. Nothing else is view-dependent — an extended source sampled per
pixel holds its surface brightness across fov and resolution — so this is the one skip with
no capture hazard and no geometry in it. With the shipped anchor the sky goes at exposure
1.75e-3, 10.2 EV below the dark-adapted rest, which an EV sweep confirms to the stop.

Skipping is `background_mode = BG_COLOR`, so `environment.sky` survives for
`IVExposureManager._find_starmap_material()` and for the return. Ambient is unaffected
(`ambient_light_source` is COLOR, and the manager drives its energy). Reflections come from
the background, and a sky certified under half a code reflects under half a code — reflected
radiance cannot exceed incident.

### The star bins, and the two tests neither of which is sufficient

A star's rendered value falls with magnitude, so what the camera can show is always a prefix
of the bins and what it drops is always a suffix. Walking that suffix inward from the faint
end, a bin is dropped only if **both** hold:

- **Its brightest star is invisible on its own.** The bound is exact and free: the bins
  partition by magnitude, and `_build_bin_mesh()` records the brightest magnitude it actually
  decoded rather than trusting the file's tag.
- **The glow of every bin dropped so far is invisible together.** `blend_add` is a sum, and
  the faint bins are where the stars are — 1.1 M in `11.5` and `12.0` alone. Cutting to V 11
  was measured to dim a dark sky by about 7 codes over a third of it, which is entirely stars
  that are individually under one code. A per-bin test would drop four such bins and find
  each one innocent.

The summed term is a bin's mean added radiance per pixel: its sky density, times the screen
solid angle over the pixel count, times the light one sprite lays down. Two simplifications
are deliberate and both err toward drawing. The screen solid angle is the small-angle
`4 tan^2(fov/2)` form — the one `fov_compensation` is itself built on, so the fov terms
cancel as the star shader's header says they do, and it over-states a wide screen's share of
the sky. And every star in a bin is charged at its brightest member's peak, which over-states
by the bin's own half-magnitude width: a factor 1.14 in wing amplitude.

**Density is measured where the field is densest, not on average.** The catalog is a galaxy
seen from inside it: `11.5` and `12.0` run about 3x the mean density in the Milky Way band,
so a mean-density estimate would clear a bin for culling while its band was still glowing.
`_get_peak_sky_density()` takes the maximum over 96 equal-solid-angle cells — bands of equal
`sin(latitude)` by equal longitude — from a subsample of the decode loop.

The model reproduces the measured cut without being fitted to it: at Saturn's metered
exposure of 2.8e-5 it puts the boundary between the `11.5` bin (wing peak 1.58e-4, above the
half-code line) and the `12.0` bin (1.39e-4, below), which is where the running app puts it,
and which is the V 11 cut that [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md) certified as
changing zero pixels in lit-body views.

### Resolution, and the one place it is a correctness question

The per-star peak carries `resolution_scale^2` while the summed term is near
resolution-invariant, the two halves of the same law the star shader's header sets out. The
asymmetry has a consequence: an off-screen capture taller than the window renders every star
brighter, so a bin correctly hidden for the window would be *missing* from a 4K screenshot.
`IVScreenshotManager` therefore registers its render height in
`IVStarsVisual.capture_render_height` and waits a frame before building its viewport; a
hidden bin returns undamped, which is what makes one frame enough. Measured at a fixed
exposure, a 2x capture height restores three bins and a 4x height six.

### Renderer parity

One threshold serves both renderers, and it is conservative on the web one. `display_write()`
pre-inverts the Compatibility bracket so a linear radiance lands at the same code either way,
and with glow enabled Compatibility crushes the dim end further still (0.041x on 6-8 code
content, measured under *Renderer parity*). Nothing below 1.0 linear reaches the glow pass in
any case: `glow_hdr_threshold` is 1.0 and `glow_bloom` is 0.

## Rings

Saturn's rings (`rings.gdshader`, `rings.tsv`) render a **plane-parallel single-scattering
slab**, riding `light_energy` like a surface. The shader is generic -- every photometric
number is a `rings.tsv` cell -- so a different real or invented ring system is a new
texture and a new table row.

Their texture is one `CompressedTexture2DArray` of three radial profiles, built by
`addons/tools/build_saturn_rings.py` from Björn Jónsson's Voyager profiles. Its alpha is
`1 - exp(-tau_normal)` from the stellar occultation, and its rgb is **scattering
strength** -- the published brightness with the slab's geometry term DIVIDED OUT, so what
the file holds is a property of the particles rather than of one observing geometry. The
shader multiplies the term back at the angles it is actually rendering:

    lit    mu0/(mu+mu0) * (1 - T(1/mu + 1/mu0))
    unlit  mu0/(mu0-mu) * (T(1/mu0) - T(1/mu))

with mu and mu0 the sines of the camera's and the sun's elevation above the plane and
`T(rate) = (1 + rate tau / clumping)^-clumping` the layer's transmission -- optical depth
taken as gamma-distributed across the beam, self-gravity wakes being what makes it vary,
with the homogeneous slab as the large-`clumping` limit. That is what makes the rings answer
to their opening angle: as the camera drops toward the plane the optically thin rings
brighten toward the saturated value while the B ring, already saturated, barely moves.

**The reference geometry the build divides out is PINNED at the geometry the images were
taken at**, and that decides how much radial contrast every render carries. Jónsson's
profiles are Voyager, 1980-81, and Jónsson publishes none of that geometry -- so it is
measured from the spacecraft's own trajectories in the running simulation
(`voyager_ring_elevation.py` in the assets build tree, which parks the camera on the craft
and reads `get_rings_geometry`). Voyager 2's backscatter frames sit at camera 10.63 degrees
with the sun at 8.12, at the 6.8 degree lowest phase its lit side ever reaches; Voyager 1's
forwardscatter at 12.35 and 3.94, where its stated phase of 139 occurs; and Voyager 1's
unlit view at 39.4, the floor of the 22.7-hour dip below the ring plane that is the only
time it saw that face at all. The sun elevations are the check and were not fitted to
anything: a few degrees, as eight and sixteen months after Saturn's March 1980 ring-plane
crossing they must be, and the unlit profile's own sun leg is still FREE and lands at 3.94
against a measured 3.69-4.13.

A fit cannot supply that, and the two Voyager 1 profiles prove it between them:
`forwardscattered` and `unlitside` are the same spacecraft at the same encounter, a lit fit
determines only `k = 1/mu + 1/mu0`, and k can never be less than 1/mu0 -- yet forwardscatter
fits k = 7.20 where a sun at 3.94 degrees demands at least 14.55, and backscatter fits 3.24
against at least 7.08. Both are impossible. What the fit absorbs is the
RADIAL VARIATION OF PARTICLE ALBEDO, which the model has no term for.

Getting it wrong flattens the bands, since too wide a reference divides out too little
saturation. At the measured geometry the B ring against the C ring renders 8.10 at Saturn's
widest opening and 4.49 at 12 degrees, against published Cassini radial scans of 6 to 12 at
low phase. The independent check is the particle strength a reference implies: the C ring and
the Cassini Division are the known dark, contaminated regions, at roughly 0.2-0.5 of the A and
B rings' albedo, and this one puts them at 0.43 and 0.75 where a reference at Saturn's maximum
opening would put the Division brighter than the A ring.

**`clumping` is PINNED, and what pins it is now a confound rather than an absence of
leverage.** The UNLIT profile still measures nothing: its apparent leverage came from the
flat deep end, which is the source image's own background and not ring light, and scanned on
the live radii with that background removed its R2 moves **0.0079** across the whole family,
against a factor of forty in what the parameter actually does. The LIT profile is a different
story from what this document said until 2026-09-08. Its insensitivity (R2 moving 0.8733 to
0.8787) was measured at the 26.7 degree reference that shipped until 2026-09-06, and the
leverage grows sharply as the reference narrows -- span 0.0124 at 26.7 degrees, 0.0970 at 12,
**0.1483 at the measured geometry** -- with the fit preferring the most clumped end at every
one of them. That is not a measurement of clumping, because a low clumping shape flattens
saturation in exactly the way the radial variation of particle albedo does, which is the same
confound that makes a free lit fit return an impossible geometry two paragraphs above.

**What settles it is the transparency layer's own definition, and it is not a fit at all.**
The alpha channel stores what the archive calls a NORMAL OPTICAL DEPTH -- `-sin(B) ln(T)`
from a stellar occultation at one ring elevation, Cassini UVIS beta Centauri at 66.7 degrees.
For a layer whose depth varies across the beam that is by definition the APPARENT depth at
that elevation, so it already carries whatever clumping the ring has. Read through the
homogeneous law it reproduces the measured transmission exactly at the geometry it was
measured at and approximates it elsewhere; read through a clumped law it would count the same
inhomogeneity twice. The cell therefore stays at the homogeneous limit -- which is also the
family's darkest transmission, and the closest to what real unlit images show -- and moving
off it is not a one-cell change: it needs the mean depth re-derived from occultations
spanning elevation, and the ceiling scales as `sin(B)`, so a low-elevation set can only reach
the A ring, where the wakes are strongest and where one shape parameter shared with a
wake-free C ring is least defensible.

**There is no floor under the unlit face.** Jónsson's unlit profile stops falling at about
0.047 by tau 2.33 and is flat to 6 % from there to the profile's deepest 8.5 -- a factor of
nearly four in optical depth over which single scattering falls by 1e6 and even conservative
two-stream diffuse transmission, the most generous physical model there is, falls threefold.
(The threshold is measured rather than assumed, and it moves with the optical depth SCALE:
the same radii read 1.4 under the saturating Voyager profile.) That flat tail is the source
image's own background rather than ring light, and carried as a constant it would put a floor
under the unlit face that does not fall with tau at all, so an opaque ring would glow. The
build subtracts it, and where the subtraction leaves nothing takes the strength from the lit
layer, in a ratio the build measures on the densest material that still has signal (7.56x
layer 0). That ratio is NOT the constant this document once called it: it read flat only
while both references were fitted, because two fits absorb the same radial albedo variation
and it cancels in the quotient. Measured against pinned references it varies with radius,
p16-p84 5.0 to 10.2, which is a phase-function difference -- an unlit view is a high-phase
view, and the dusty C ring and Cassini Division forward-scatter more than the B ring. What that leaves out is stated plainly: real multiple scattering inside a dense layer is
not zero, and a truly opaque B ring renders black where a real one is merely very dark.

Phase carries the LEVEL and the texture carries only the shape, because all three profiles
are published independently peak-normalized: `forward_level` is the lit face's brightness at
`forward_phase` relative to `back_phase`, interpolated as a straight line in magnitudes,
with `opposition_surge` and `opposition_width` adding the narrow spike on top. Phase is
evaluated per fragment, so a close camera gets the local opposition spot under it. Which
face a fragment shows is also decided per fragment, from the signs of the two elevations,
so a camera near the plane sees the lit face on one side of itself and the unlit face on
the other.

**`forward_level` is 0.04, and it is a MEASURED phase ratio rather than the continuity
anchor it was until 2026-09-08.** The instrument is Dones, Cuzzi & Showalter's (1993)
Voyager phase curve for the inner A ring at 122500 km, plotted as scaled reflectivity
`I/F 4(mu+mu0)/mu0` -- which at one radius is exactly this quantity, the geometry and the
optical depth cancelling in the ratio. It gives **0.045 to 0.053** at 139 degrees against a
surge-free extrapolation to zero phase, and dividing by the 1.229 the asset's own two lit
layers differ by at that radius (they are peak-normalized independently, which is what this
cell exists to undo) puts the cell at 0.037 to 0.043. Two independent checks agree. The
published magnitude relation, which sees the cell only weakly through
`forward_level^(alpha/139)` over its 6.5 degree window, prefers lower monotonically: refitting
the surge at each candidate, the worst residual against the published curve falls from 3.2 %
at 0.25 to 1.9 % at 0.04. And the ring's brightness against Saturn's own globe in the
reference frames, which is the only image measurement available, put the old 0.25 between 15
and 32 times too bright at 138 and 152 degrees -- a bound rather than a value, its denominator
being a limb crescent, where the globe shader has no forward-scattering term of its own.
`scattering_scale`, `opposition_surge` and `opposition_width` are fitted WITH it and were
re-derived in the same pass (0.457 to 0.486, 0.515 to 0.418, 0.883 to 0.661 deg); the asset
itself is unchanged, all four being table cells.

What that number really carries is worth stating, because it is not the particles' own phase
function. Published values for those are far steeper -- the Dones power law at the index
Porco et al. (2008) fit to Cassini gives 0.021 at 139 degrees, and the index Salo & French
(2010) prefer for the B ring gives 0.010 -- and the gap is multiple scattering, which
dominates the lit face at high phase (27 times single scattering at 155 degrees in Dones'
own decomposition) and which this model has no term for. So 0.04 is an EFFECTIVE ratio:
particle phase function times the multiple scattering that is missing, calibrated on the
observed ring rather than on its particles. It is therefore geometry-dependent in principle,
the multiple-scattering share growing with albedo and optical depth, and one constant cannot
be exactly right everywhere.

**`forward_reddening` still has no cited source, and no available image can give it one.**
Its 1.05 is worth +2.8 % of rendered red-over-blue across the whole phase range (measured
1.585 at 15 degrees against 1.629 at 138), about four codes of 255 in blue. The eight RGB
"natural colour" frames in the reference set cannot resolve that: their ring red-over-blue
spans **0.68 to 3.31** with no relation to phase, two frames 8 degrees apart differing by
2.2 times, so they carry no common white balance and cannot arbitrate a few percent. The
asset's own colour comes from five-band disc-integrated photometry with no image anywhere in
the chain, which is the better instrument by far. The same measurement settles the
opposition surge's missing colour, which is real and tiny: the surge is stronger in blue
(C3 0.525 in B against 0.378 in V), so the rings run B-V 0.844 at exactly zero phase against
0.931 from 2 degrees out, and at a fixed luminance that whole spike is +4.3, -0.8 and -7.5
codes of 255 -- inside a window under two degrees wide, where the achromatic surge itself
moves the level by about 90. An achromatic `opposition_surge` is not a defect worth a
chromatic term.

**Both faces take that same phase term**, which is physics rather than convenience: the
phase angle is the sun-ring-observer angle, so a photon's scattering angle is `180 - phase`
whichever side the observer is on, and one phase function serves both. What differs is the
geometry term above. Without it the unlit face renders 1.8 to 2.8 times too bright at the
phases it can actually be seen at -- a low phase angle on the unlit side is geometrically
impossible, since reaching one means standing near the sun's direction and the sun is on the
other side of the plane. `unlit_level` is then DERIVED rather than chosen:
it is the reciprocal of the measured unlit/lit strength ratio, which is what puts both faces
on one scattering strength -- the two profiles are peak-normalized independently AND were
observed at different phase angles, and that one number undoes both at once. The build
prints the cell. That ratio is a ratio of PHASE FUNCTIONS, so it is not flat in radius: the
dustier C ring and Cassini Division forward-scatter more than the B ring, and it runs 17.7
at optical depth 0.02-0.1 down to 6.2 by 0.7-1.2. The build therefore measures it twice --
once over the whole live profile for the
level, and once on the densest tenth for the fallback that carries the deep B ring, which is
the material that fallback adjoins. It is derived because it CANNOT be measured the way the
lit level below is: Mallama & Hilton define their effective ring inclination as zero when the
Sun and the observer are on opposite sides of the plane, so the disc-integrated relation that
anchors the lit face says nothing whatever about this one.

**The lit face's level and its surge are anchored on SATURN'S OWN MAGNITUDE**, which is
disc-integrated photometry and therefore immune to the stretch on any image. Mallama &
Hilton (2018) publish the system (globe plus rings) and the globe alone as separate
equations, and their difference is the rings' own flux; adding back the 6.0 % of the globe
the rings occult (at zero phase the ring shadow hides behind that same silhouette, so it is
the whole loss) and dividing by the projected areas gives the rings' area-weighted mean I/F.
`scattering_scale`, `opposition_surge` and `opposition_width` are fitted to that relation
over its stated validity range and reproduce it to within 3.6 % from zero phase to 6
degrees. The published curve is much steeper than the source's own prose: a 40.3 % drop
from 0 to 6 degrees against Jónsson's stated "20-25 %".

That fit is at Saturn's WIDEST opening, and the model runs above the published relation as
the rings close: integrating the ring's whole flux against the globe's gives 1.007 of the
published value at a 26.7 degree opening and 1.11, 1.25 and 1.42 at 20, 12 and 6 degrees.
The sign is what single scattering has to do -- as the opening closes, the slab saturates
toward `mu0/(mu+mu0)` and the flux falls only as `sin(beta)`, where the real ring loses more
than that to mutual shadowing between its own particles, which this model has no term for.
That is an accepted deficiency and not an open question. Anchoring at the widest opening is
what makes it one-signed -- 0.48 EV by 6 degrees and 0.73 by 3, never negative -- and the
relation cannot calibrate the missing term anyway over the range where it would matter: its
phase coefficients hand the whole system's phase dimming to the rings, which at a small
opening, where the rings are a small part of the system, is numerically unstable (at 3
degrees of opening and 4 of phase it returns a ring mean I/F of 0.02).

At the far end of that range the rings go essentially black, and that too is the model rather
than a defect. Every term rides `mu0`, so a sun IN the ring plane takes the whole system to
about 1e-3 of its normal level and leaves only a shadow line on the globe. Real rings at
equinox were dramatically dark and not invisible, because a real layer has thickness and
vertical structure -- neither of which this models, by decision. A lit-side floor would be
the lever and the data does not ask for one: the lit fits reach R2 0.87 with no floor where
the unlit one needs 0.0985 to fit at all.

The fragment is **self-lit on both renderers** and its output is premultiplied: rgb is the
ring's own light over black sky and alpha is the SLANT occlusion `1 - (1-a)^(1/mu)`, so a
ring seen edge-on hides what is behind it however thin it is at normal incidence. Self-
lighting is not a stylistic choice -- the engine flips a double-sided primitive's normal, so
an engine-lit ALBEDO clamps N.L to zero on whichever face is turned away, which would leave
the unlit profile unreachable.

**A self-lit fragment must zero SPECULAR as well as ALBEDO.** A spatial shader that sets
neither gets Godot's defaults (SPECULAR 0.5, so F0 = 0.04), and the engine adds that lobe on
top of the self-lit EMISSION -- unshadowed, since the shader's own occlusion multiplies only
its own term, and Fresnel-amplified toward 1.0 at grazing incidence, which is exactly where
a ring is seen. Left in, it is an additive floor on every ring pixel (0.157 linear on an 8.3
degree view at phase 145, 29 % of the lit ansa), so what it costs is the radial contrast
everywhere and not only at grazing.

Their shadows -- on the planet and from the planet on them -- and all eclipse and transit
dimming come from the **analytic occlusion system** (`IVSunOcclusionManager` with
`_sun_occlusion.gdshaderinc`), which computes sun visibility per fragment instead of shadow
maps and applies the same slant law to the sun's own leg through the layer; the same system
supplies the eclipse factor metering uses, so an eclipsed moon meters dark and night
adaptation opens up inside a totality. The same term covers a spacecraft passing into its
planet's shadow, confirmed in-app.

**Going edge-on is a sampling problem, and it breaks in two places.** A pixel's cone meets
the ring plane in a segment that lengthens as `1/mu`, so the share of the pixel that is ring
falls as the sine of the opening angle -- that share is computed exactly (the segment's
radius is quadratic in its parameter, and its crossings of the two circles are closed form)
and scales the fragment's radiance and its occlusion together. It is the same quantity
`limb_mean_incidence()` calls coverage, one dimension lower: a fraction of the camera's own
aperture, derived rather than tuned.

That aperture is the pixel's own box CONVOLVED with the camera's point spread function --
`iv_psf_sigma`, the same Gaussian that images every star and every sunlit rim -- so the ring
goes through one camera model with everything else. It is taken as a single Gaussian of the
summed variance, which is within 0.002 of the true convolution at the shipped sigma, and
truncated at six of its own sigmas, where a Gaussian stops being representable at the worst
exposure this camera reaches (a metered ring left at the dark-adapted rest, ~15 stops, where
one 8-bit code is 1e-7 of the peak; the star field's `psf_visible_size()` cuts at 5.6 px
there against the 6.9 this draws). Two things follow, both measured against ray casts
convolved with the same Gaussian. It holds the sine law to 0.999-1.003 from a 4 degree
opening down to 0.02, where a plain pixel box under-integrates a band a pixel or two tall by
up to 16 % -- it samples at pixel centres a function it treats as flat across the pixel. And
at ~15 stops over **everything drawn clips**, so what a viewer sees is a count of rows: the
aperture floors that count at 8 across the ring's thin middle, nearly three times what a box
leaves, and its last row falls off through intermediate values rather than ending in a cliff
(ray-cast truth at a 1 degree opening ends 255, 148, 0 display codes and the aperture ends
255, 88, 0).

A convolution can only put light where the rasterizer made a fragment, so the plane is also
EXPANDED outward, to `plane_extent`, sized so the aperture's reach fits at the plane's own
far rim, where the footprint is largest. That expansion is bounded by the tilt below, and
that is the tilt's second job: the reach is measured in footprints, magnifying shrinks the
footprint, and both operations are exactly flux-neutral. Untilted, a camera at its floor
against a hairline ring would want a plane twenty times the ring's radius.

That aperture runs on BOTH screen axes. It is isotropic on the screen, so pulled back into
the plane it is `sigma x footprint` along the footprint axis and `sigma x pixel_angle x
distance` across it -- the second being `mu` times the first, hence negligible at grazing and
equal face on. Dropping it costs nothing while the ring is large, because its chord is then
almost linear in `across`; it costs everything once the ring is a few pixels wide, where a
blur along one screen axis draws a DASH across the ring's own long axis (measured at 700
plane radii, the drawn shape's aspect was 2.28 against a true 0.69). The across integral is
five-node Gauss-Hermite because what it has to resolve is a square root -- the chord through
a circle has infinite slope at the tangency, so the correction never becomes smooth however
small the sigma is. That tangency is also the ansa TIP, the one place the segment picture is
weak, and the same nodes carry it: whole-frame rms 0.0175, 0.0063, 0.0043 at one, three and
five nodes against the box's 0.0379.

**The texture read takes those same two axes**, its filter width being the radial span the
covered segment crosses. The segment measures that along the view ray, which at an ansa is
backwards: the ray runs tangent to a circle of constant radius there, so the along axis
carries almost none of the pixel's radial spread and the across axis carries all of it (on the
unlit face at a 13.4 degree opening, 2 km against 419 at worst, and `across > along` maps to
two lens-shaped patches covering 19 % of the ring and nothing else). Shifting the ray across
moves its whole closest approach with it, so what the second axis adds is the pixel's own
unforeshortened extent projected onto the radius, `dR/dc = c/R` -- combined with the first in
QUADRATURE, two extents of one aperture being variances rather than supports. Without it the
narrow gaps at each ansa comb into dashes, at 2.8 times the truth's own high-frequency content
against 1.2 with it.

What is left is the far field. Past roughly 300 plane radii the ring is smaller than the
camera's own PSF, and rasterizing a plane is the wrong instrument for it at all -- the drawn
shape's aspect and its flux both drift from the truth however many nodes are spent. What that
regime wants is a point-source quad like the body's own, which has no ring term.

The other half no coverage term can argue with. Without MSAA a fragment exists only where
the primitive covers a pixel CENTRE, so once the ring's image is thinner than a pixel the
line goes dashed and then, when it falls between two rows of centres, disappears whole
(measured at 1080p from six ring radii: the lit-pixel count went 996, 682, 408, 0 as the
projected minor axis passed 1.5, 1.2, 1.0 and 0.8 pixels). So the plane is TILTED about the
camera's own ground line until its projected minor axis reaches `MIN_SCREEN_THICKNESS`
pixels, and its light divided by exactly the factor it was thickened. A rigid tilt magnifies
the image by ONE number, so a pixel's footprint on the true plane shrinks by that same
number and the division conserves flux exactly: measured in the app, the rendered flux is
proportional to the sine of the opening angle to 0.3 % over a 24-fold range in angle, the
lit-pixel count is constant across it, and the brightest ring pixel falls 0.68, 0.46, 0.29,
0.17, 0.11, 0.057, 0.031 to nothing. `MIN_SCREEN_THICKNESS` is the one tuned number, and
what it buys is the sub-pixel middle of the ring, whose own band is a fifth of the minor
axis and dashes below the threshold. It is also the ceiling on the outward expansion above,
which is why the two live in one expression: the magnification taken is whichever of the two
demands is larger -- and then CAPPED at face on, because a ring is thin on screen for two
different reasons and the minor axis alone cannot tell them apart. Foreshortening is what the
tilt is for; distance is not, and magnifying past `major / minor` gives the ring a shape no
ring has (measured at 4000 plane radii, a 0.50 px ring held 3.5 px tall). The cap is
`1 / sin(elevation)`, so it diverges at grazing and bites only on a ring that is small in
both directions.

**The plane passes through its own planet, and the part inside must not draw.** A ring plane
is a disc through the globe's centre, so everything inside the globe's figure -- the circle
`r = R_equatorial`, which lies well inside the ring's own hole -- is somewhere no camera can
look at the ring from: every ray reaching it meets the globe first. The coverage term cannot
know that, because the aperture reaches `APERTURE_REACH` sigmas along the plane and at a
grazing view that is most of a plane radius, so a fragment buried in the planet still gathers
real ring light from outside it. So the shader discards on the occluder's own figure --
`sun_occlusion_inside_occluder()`, the same pole stretch the shadow term uses, so the figure
tested is exactly the one that casts the shadow, at one dot product per occluder. That guard
answers "at or inside the occluder" with ZERO sun, which is what a point inside an opaque body
should get; the manager's rule that a body is excluded from its own occluder list is true of a
surface and false of a ring, whose one occluder is the planet it circles.

**Past the point where a plane cannot be rasterized, the rings hand their light to the
body's own POINT SOURCE.** `IVBodyPSF` already draws a body's whole disc as one point of
light; the ring system is one more source in that magnitude, and about a magnitude of light
at a wide opening (-0.99 at zero phase and Saturn's own maximum). What the point needs is
the same integral the plane rasterizes, `sum S geometry(tau, mu, mu0) dA` over the annulus
times the phase level and the projection `mu` -- and far from the body every part of the ring
shares one phase and one pair of elevations, which is exactly the regime a point source is
for, so it reduces to a sum over radius. `IVRings` takes that sum at load time down to
optical-depth bins, geometry depending on radius ONLY through optical depth, and evaluates
the same slab model over them each frame; against the full 13177-texel profile, 64 bins hold
the flux to 0.9 % at worst and 0.03 % at the median. They are spaced in LOG optical depth,
because what the slab is sensitive to is tau against `1/rate` and the rate runs from 2 face
on to 2e4 at `MIN_MU`: the same count spaced linearly runs 76 % out and is no better at 128,
a grazing ray's whole answer being carried by material thinner than the first bin's own mean.

The two are a CROSSFADE, so the light is drawn exactly once at every distance: the plane
scales its coverage by `plane_light_fraction` (coverage being what a fragment holding part of
a ring already means, so the light and the occlusion fade together) and `IVRings` publishes
`1 - that` of the flux to `IVBody.rings_psf_flux_factor`, which `IVBodyPSF` adds before the
magnitude conversion -- flux sums where magnitude does not. The ramp is the ring system's own
projected outer radius, 8 px down to 3, and both ends are measured: against convolved ray
casts the drawn flux holds within 1 % of truth out to a 10 px outer radius, runs 5-10 % out
by 3 px, then swings 0.7 to 1.2 and collapses to nothing once the image falls off pixel
centres. Above the ramp a ring is a shape a viewer can see and must not become a dot; below
it, a plane that cannot be rasterized must not be what carries the light. Measured in the
app, the engine's sum reproduces the offline full-resolution integral to 0.9988-1.0001 on
both faces from 5 to 98 degrees of phase, and a render at the ramp's top is bit-identical to
one with none of this in it. The ramp is in render-buffer pixels, and a hi-res capture draws
these same nodes into a buffer of its own while one material and one published flux serve
both -- so `IVRings` decides for the greater of the window's render height and the one
`IVScreenshotManager` registers in `IVRings.capture_render_height`, the handshake it runs for
the star cull, the sphere LOD and glow. Its error is then only ever toward the plane: a capture
shorter than the window keeps the window's decision, and the window shows a taller capture's
for the few frames of the shot.

A ring's colour has to cross that handoff with its light. The quad draws a body in the tint
of its catalog `color_b_v`, and a ring system's is not its planet's -- Saturn's rings are
flux-weighted R/B 1.575 where its own index 1.04 draws its point at 1.812 -- so handing them
over without saying so recolours a third to a half of the system's light. rings.tsv carries
its own `color_b_v` (0.90 for Saturn, whose point-source tint is 99.5 % of the asset's own
red-over-blue, so the point matches the plane), and the two indices combine through their
FLUXES rather than by averaging. What the point still leaves out is small and is left out of
the body's own point
flux too: the planet's shadow on the rings, the rings' shadow on the planet, and the 6 % of
the globe the rings occult.

**That colour is measured in both halves, from two sources that share no instrument.** How red
the system is overall is B-V 0.93, from Mallama, Krobusek & Pavlov (2017)'s five-band magnitude
model by the same globe-minus-system difference the level is anchored on -- tan, and less red
than the planet it circles. How the colour varies with radius is Cassini VIMS: Hedman et al.
(2013) publish the two visible spectral slopes as radial profiles at 20 km, and a reflectance
spectrum built from each pair and integrated against the CIE functions gives every radius its
own colour. The two agree on the system's mean to 6 %. Both are applied as luma-neutral
per-channel gains on the built layers, so a colour change can never move the level:
`scattering_scale` and the magnitude anchor stand under either.

A ring face is brighter per unit area than any Lambert sphere near opposition, so a camera
metering the globe alone would clip the rings white. **Both faces** therefore meter as their
own candidate: a flat annulus whose screen fraction is its area foreshortened by the
camera's elevation, at `ring_meter_albedo` or `ring_meter_unlit_albedo` (the bright ring's
scattering strength times `scattering_scale`, derived per face) times CPU mirrors of the slab
geometry and the phase function. The unlit face is not the faint object it looks like from
the other side: an optically thin ring transmits nearly as much as it reflects, so at a low
opening angle the C ring and the Cassini Division come through bright while the B ring goes
dark.

The geometry mirror takes each face's slab term at **its own maximum over optical depth** --
the saturated limit `mu0/(mu+mu0)` on the lit face, where the term is monotone, and an
interior peak at `tau = ln(b/a)/(b-a)` on the unlit one. That keeps optical depth out of the
manager and makes the two branches MEET at the plane instead of switching (measured, 0.998
lit against 0.988 unlit at a 0.05 deg opening) -- a thin ring really does look the same from
either side.

**One anchor per face holds on the lit face and not quite on the unlit one, and both are
properties of the built FILE rather than of the rings.** Each stands in for a max over radius
the mirror cannot afford, so it is exact only at the opening it was derived at. On the lit
face there is nothing to drift: the implied anchor runs 1.103 to 1.138 across the whole range
the openness ramp below gives the candidate weight, worth 0.02 EV. On the unlit face the
term's peak sits at `tau = mu`, so as the rings close it walks out of the outer B ring and
into the C ring, and the anchor swings with it -- 1.424 at 26.7 deg, 0.844 at 16, about 1.0
from 12 down -- which one number costs 0.38 EV at worst, at full ramp weight rather than
where the ramp has released. That is a third of a stop on the fainter face against a per-mu
table as the alternative, and it is accepted; the cell takes the minimax rather than a
median. What is NOT acceptable is letting either go stale: they move with the asset and with
`scattering_scale` and `unlit_level`, and after the 2026-09-08 transparency re-source the
unlit anchor was a full stop out with nothing to announce it. Re-derive both with
`scratch/rings/meter_albedos.py` (in the assets build tree) whenever any of the three moves.

**The phase mirror uses the body's CENTRE where the shader uses each fragment's own**, so
close in the two disagree about the opposition surge. The error is bounded by the surge's own
amplitude and runs BOTH ways, contrary to what this document said until 2026-09-08: over
standoffs of 3 to 200 ring radii it reaches +0.27 EV where the centre sits inside the 0.883
deg window and no ring fragment does, and -0.51 EV where a ring fragment sits in the camera's
own shadow while the centre is degrees away. Neither shows. The metering key leaves a stop of
headroom above the metered subject, so even the worst under-metered case puts the surge spot
at 0.71 of full scale rather than clipping, and both directions converge beyond about 100
ring radii, where the ring subtends too little for a fragment's phase to differ from the
centre's.

**Neither face clips at any distance tested** -- 3.5 to 30 body radii, both faces, an 18 deg
opening: 0.00 % of every frame above 0.99, with p99.9 between 0.25 and 0.65. So a ring that
reads too bright is a level judgment and not an exposure failure. What follows from that is
that the ring candidate rarely WINS, now that the level is anchored on photometry: at the
photometric level the rings meter dimmer than Saturn's globe over most of the opening range,
so the globe's own candidate holds and the ring branch does nothing -- correctly, since
nothing clips. Measured, the lit face pulls at most 0.17 EV and the unlit face none at all,
against 0.53 and 0.28 at the pre-anchor level. The branch is live rather than dead code: it
produces a candidate at every geometry, the globe's is simply lower, and it would take
control for a brighter or a more open ring system.

**What holds that candidate is the ring's own geometry, in two parts** -- the same shape as
a body's lit candidate, which is held by its lit AREA and then again by its lit FRACTION.
The annulus is sampled in azimuth at radii spaced by equal area, and each sample counts by
how far inside the frame it lands (`meter_edge_fraction`); their share scales the annulus'
screen area. A ring is not a disc, so its body's screen position says little about whether
it is the view. That, with the disc's own gate no longer skipping a body whose ring or shell
reaches outside it, is what lets the rings meter with the rings filling the frame and the
globe panned off the side: measured over a yaw sweep at six body radii, the globe's disc
gate is exactly 0.000 from 50 to 60 degrees of yaw while the rings are still 19 % to 0.5 %
in frame and hold the exposure at -14.92 EV. Without it that whole window sits at the
dark-adapted rest, 15.9 stops brighter, with the rings blown white.

Then the **openness ramp**, `ring_meter_onset_openness` down to
`ring_meter_full_openness`, on the sine of the camera's elevation above the ring plane.
This is the shape term the area cannot supply: the area carries one power of the
foreshortening against a ramp that spans decades. Measured by disabling the ramp in the
same app run, area alone holds the exposure within half a stop of its metered value from a
12 deg opening all the way down to 0.5, and then dumps 13.9 stops between 0.2 deg and the
plane -- the rings hold the camera until they are almost exactly edge-on and then let go all
at once, which is the flash. With the ramp the release runs from 8 deg to 1.5 and spans 17.6
stops, symmetric about the plane. Purely a taste
setting, and the reason it is one: a ring at a low opening angle is a bright line, and this
is how readily the camera stops the whole frame down for one.

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
the display-referred branch. Since the ring texture became premultiplied the fragment's
colour is its whole term, so it goes through `display_write()` alone and the `display_mix`
pair is no longer needed; what stays approximate is the blend's own `(1 - alpha)`
attenuation of what lies behind, exact over the empty sky the ring stands on almost
everywhere. The fragment computes its own radiance from `sun_light_energy`, which
`IVSunOcclusionManager._feed_ring_material` passes beside the sun's direction, and decides
its own face per fragment, so the engine lights neither face on either renderer. The
`IVRings` Compatibility overrides of `litside_phase_boost` / `unlitside_phase_boost` are
retired along with the matching metering constant in `IVExposureManager`: tuned against the
old display-referred pipeline, where a boost `m` acted as `m^2.4`, they became a deliberate
divergence once that was corrected, and they had been quietly dimming every Compatibility
ring measurement by 0.88x.

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
| `glow_levels` | 2/3/4 at 0.8/0.4/0.1 | **Yes, as authored for the 1080 reference height.** Halo width and shape, not which pixels qualify. `IVWorldEnvironment` shifts them to the render height (*Render height*, below), so change them at runtime through its `set_glow_levels()`: a write to the Environment is overwritten at the next height change. |
| `glow_intensity`, `glow_strength`, `glow_mix`, `glow_map*` | 0.3, 1.0, 0.05, none | **Yes, freely.** Halo weight and shape. None of them touch which pixels qualify, only how their light is spread. |
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
- The blurred levels (defaults 2/3/4 at 0.8/0.4/0.1 — quarter- to sixteenth-resolution of
  the render buffer, shifted with its height: *Render height*, below)
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
panorama never reaches the threshold in either mode (peak ≈ 0.087 × 2^`exposure_max_ev` ≈ 0.17
at rest), so the Milky Way correctly does not bloom.

**The star PSF is not redundant with this, and could not be.** The PSF is the star's image —
the calibrated core-plus-skirt that carries photometric proportionality and the `sqrt(ln I)`
size law. Glow adds the wide scattering wings the Gaussian does not have, and its per-texel
energy caps at 12 while star peaks run to the 32768 f16 ceiling: bloom is proportional to
flux only between threshold and cap — roughly V 1.5 to 4 at the 1080 reference height,
reference fov and rest exposure, the band riding the same compensations as the field — and
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
  1100× saturation over the *whole frame* — a photograph exposed for the Milky Way cannot
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

The probe itself reads at `PRE_TRANSPARENT`, well before glow, so picking was never at risk
from glow — only the picture was.

**Render height: a halo keeps its share of the frame.** Every glow level is a blur of the
render buffer in that buffer's own texels, so left alone a halo is fixed in render pixels: a
taller window or a hi-res capture narrows it against the frame, and a 3D render scale below 1
widens it. Measured around the sun on Forward+, its light ran ×1.46 at 70 % render scale and
×1.98 at 50 %, and its reach nearly as much. `IVWorldEnvironment` therefore holds the
Environment's levels as authored for the 1080 reference height (`iv_reference_viewport_height`,
the height the PSF law is normalized to) and shifts them `log2(1080 / render height)` octaves,
finer below the reference and coarser above it. A weight that lands between two levels is
split to keep the halo's variance, level widths doubling per level: at 85 % and 70 % that held
the light to 1.02 and 1.03 of 100 %, where a split linear in octaves ran 1.09 and 1.17.
Verified in frame-height units against a 1080-tall render at 100 %: 85, 70 and 50 % render
scale, a 1440-tall window and 720- and 1440-tall screenshots all land within 0.94–1.03 of its
light and 2 px (1080-equivalent) of its reach. A capture gets its own height through
`IVWorldEnvironment.capture_render_height`, the handshake `IVScreenshotManager` already runs
for the star cull, the sphere LOD and the ring crossfade, so the live view shows the capture's
levels for the few frames of a shot. **Compatibility cannot do this**: its glow has no
levels, so a halo there stays fixed in render pixels (×1.60 of its light at 70 %, ×2.23 at
50 %).

**A tail too faint for the engine to compute draws garbage instead.** In 4.7.2 the glow pass
computes mips only through the last level weighted above 0.01 (`max_glow_index` in
`renderer_scene_render_rd.cpp`), but the tonemapper samples every level above 0.0001
(`gather_glow()` in `tonemap.glsl`). A trailing level weighted between the two is read from
a mip nothing wrote: uninitialized GPU memory, drawn as saturated red, green, blue and
magenta blobs and hard-edged black blocks, fixed on screen until the render buffers are next
reallocated. A split's coarse share runs down to zero, so the shift made such tails as a
matter of course. On a 3840×2400 screen, fullscreen put 0.0078 on level 6 and the scaled
startup window 0.0048, with level 5 the last level computed in both. Whether garbage
showed depended on what a released buffer had left in that memory, so it came and went
with fullscreen toggles. The built-in screenshot renders into its own buffers, so it never
showed the live view's garbage. `IVWorldEnvironment` therefore piles any trailing weight at
or below 0.011 (the engine's 0.01, with margin for its float32 copy) onto the last level the
pass computes, as the shift already does with weight past the end of the chain. Verified
2026-09-24 on the GTX 1650 Ti, reading back the root viewport over four fullscreen round
trips: in each windowed return that showed garbage, zeroing the tail removed all of it and
restoring it brought back the same image bit for bit; with the tail piled, every return
rendered bit-identical to the first frame.

**Captures.** Hi-res screenshots share the environment, so they get glow at their own height
(above), while stars stay pin-sharp — the PSF is absolute pixels — and a taller render pushes
fainter stars over the threshold, consistent with the fixed-f-number camera the star field
already implements. The 2D icon rig runs its own `World3D` on the default environment: **no
glow in icons**, which keeps transparent readbacks clean and costs the exact in-sim look of
overexposed content. Accepted.

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
| | `atmosphere_quality` | Normal, Reduced or Min. Normal and Reduced are applied live by `IVGraphicsManager` as the `iv_atm_*` globals, Reduced running a 4-node along-ray quadrature and 2 ring taps; Min is its own shaders, bound at startup, so it takes a restart. See *Atmospheres*. |
| `IVExposureManager` | `background_peak_magnitude_per_arcsec2` | The absolute anchor (mag/arcsec² of a full-white panorama texel). |
| | `metering_key` | Rendered value a fully metered surface lands at (mid-exposure target). |
| | `meter_fraction_start` / `meter_fraction_full` | Screen-fraction ramp: when a body begins to influence metering / fully drives it. |
| | `star_meter_fraction_start` / `_full` | The same ramp for the sun's disc (much later — the sun meters only as a subject). |
| | `limb_meter_fraction_start` / `_full` | The same ramp for an atmosphere limb's ceiling, on the sunlit, forward-scattering, in-frame share of its ring (later again — a limb may clip far more readily than a disc). |
| | `meter_edge_fraction` | Screen-edge gate width: compensation completes when a body's center is this fraction of the frame inside. |
| | `limb_meter_edge_fraction` | The same gate on the limb ring's own samples (taken at the limb's foot), wider: it is also the centrality test. |
| | `ring_meter_albedo` / `ring_meter_unlit_albedo` | The bright ring's scattering strength as each face meters it, before the phase level. Derived per face; see *Rings*. |
| | `ring_meter_onset_openness` / `ring_meter_full_openness` | Camera elevation sines where the rings begin to hand the meter back / hold none of it. The shape term beside their screen area, as the nightside lit fractions are beside a body's. |
| | `exposure_max_ev` | Dark-adapted resting exposure, in EV above the authored sky. The empty-sky and deep-night state. |
| | `meter_transition_exponent` | Shapes zoom-out: slower climb into overexposure, faster star arrival. |
| | `nightside_onset_lit_fraction` / `nightside_full_lit_fraction` | Lit-disc fractions where night adaptation begins / completes. |
| | `nightside_twilight_angle` | Horizon fade width on the last crescent sliver (close range). |
| | `adapt_darken_ev_per_second` / `adapt_brighten_ev_per_second`, `snap_ev_threshold` | Adaptation rates and the instant-jump threshold. The rates are in WALL-CLOCK seconds (they describe the viewer's eye), which is why they carry no `IVUnits` factor where `nightside_twilight_angle` and `ambient_starlight_illuminance` do. |
| | `default_albedo` | Metering albedo for bodies without a table value. |
| | `auto`, `manual_exposure_ev`, `exposure_adjustment_ev` | Runtime overrides for a GUI: hold the metered result, replace it with a stated EV, or offset either. The defaults (auto, no adjustment) apply the metered result itself. |
| | `auto_exposure_ev` (read-only) | The metered and adapted result, in EV relative to the authored sky look. Live every frame whether or not `auto` is set, so a control can display it and hand it to manual without a jump. |
| body tables | `albedo` | V-band geometric albedo: the asset-level target (a map's sphere mean) and, unless overridden, the metering albedo. |
| | `meter_albedo` | Metering albedo where what the camera sees is not the map alone — a body whose shells add light over it. Earth only. |
| | `emission_luminance_scale` | Luminance of a full-white emission texel at multiplier 1.0. |
| | `ambient_starlight_illuminance` | Integrated starlight: ambient level and the metering floor. |
| `IVWorldEnvironment` | `skip_invisible_starmap` | Stops drawing the background panorama once exposure has taken it under half a display code. False renders the sky always, which is the A/B an exposure-skip measurement diffs against. See *Skipping what the camera has metered away*. |
| | `set_glow_levels()` / `get_glow_levels()` | The glow level weights as authored for the 1080 reference height, which the node shifts to the render height; the runtime way to change them. See *Glow: the bloom pass*. |
| | `capture_render_height` (static) | Render height an off-screen capture is about to use, so its glow levels are shifted for it; `IVScreenshotManager` sets and clears it. Not a tunable. |
| `IVStarsVisual` | `cull_invisible_bins` | The same for each magnitude bin of the star field. False submits the whole catalog. |
| | `capture_render_height` (static) | Render height an off-screen capture is about to use; `IVScreenshotManager` sets and clears it. Not a tunable. |
| `IVRings` | `capture_render_height` (static) | Render height an off-screen capture is about to use, so the plane/point crossfade is decided for it; `IVScreenshotManager` sets and clears it. Not a tunable. |

## TODO

- **An atmosphere tier for the web's first visit** (2026-09-27). The v0.2.1.dev1 web export
  never loaded: through Chrome's ANGLE and D3D11 path one limb-shader program compiled for longer
  than Chrome's GPU watchdog allows. Restructuring the quadrature so each heavy function has one
  call site took every atmosphere program well inside it (*The atmosphere's structure* in
  [SHADER_COMPILE_PROFILING.md](SHADER_COMPILE_PROFILING.md)), but a first visit still compiles
  every shader the opening view and the warm-up draw, and the atmosphere is still most of that.
  What would shorten it is a tier that leaves the quadrature out of the limb and the disc shaders
  alike, chosen at restart. It needs Venus, Titan and Mars re-levelled (*Addendum: the limb ring
  and surface twilight* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)). Most of its
  machinery exists: the airless shader variants that bodies with no atmosphere already bind
  (*Addendum: the atmosphere's structure, at runtime*, there) would draw every body, and the
  limb shells would not be drawn. The Min tier (*The Min tier*, above) has since built the
  restart-bound tier this would be another value of, and takes about a fifth off an ANGLE
  first run by itself.
- **Saturn's rings do not draw through Intel's GL driver** (2026-09-28). On the profiling
  laptop's UHD (driver 31.0.101.2137) under Compatibility the ring plane renders nothing --
  either face, near or far, at 85 or 100 % render scale, with or without MSAA -- and logs no
  shader error. The same build through ANGLE on that GPU, and the GTX through its own GL and
  through ANGLE, agree to within a code, so the fault is the ring material on this one compiler.
  Bisect `rings.gdshader` there, starting with a flat `EMISSION` and `ALPHA` at the top of
  `fragment()` to learn whether any fragment reaches it. Moving these parts to ANGLE (*Open
  questions* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md)) would sidestep it; until then a
  project running Compatibility on such a part shows Saturn without rings.
- **Report the glow threshold mismatch upstream** (*Render height*, above): the pass computes
  levels above 0.01, the tonemapper samples levels above 0.0001. A 4.6 regression from
  godotengine/godot#110077; 4.5 computed every level above 0. Once Godot makes them agree,
  `IVWorldEnvironment._pile_uncomputed_tail()` can go.
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
- **Earth's terminator band on FORWARD+ — measured 2026-08-28 and CLOSED 2026-09-08. Kept
  here for the measurements and for the two candidates that were rejected on the way.**
  Measure it with `scratch/compat/termband.py` in the assets build tree, which poses the body
  at a solved phase 90 (so the terminator runs through the disc centre, where it is widest on
  screen, rather than wherever a guessed longitude put it) and reports against μ0 with a
  contrast metric — the illumination taken out as a median
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
    rejected 2026-08-28; the wall itself is FIXED 2026-09-08, below). Commenting out Earth's
    cloud row settles the Mars asymmetry: the features that survive inside the band are
    RELIEF, not albedo -- Mars has abundant relief to shade at grazing incidence and Earth's
    map has almost none, which is why Earth's contrast falls 0.214 -> 0.054 across the band
    while Mars' *rises* 0.066 -> 0.113. What reads as a defect is the abrupt end of the white
    clouds. Isolated by hiding the shell, the deck's own contribution falls
    0.0691 -> 0.0049 -> 0 over mu0 +0.065 -> -0.005, an e-folding length collapsing from 91
    pixels to 2. A `clouds_grazing_extent` carrying the deck to its own geometric shadow at
    mu0 = -0.0565 was rendered at k = 0/0.35/0.5/0.7/1.0 and **moved the wall without
    removing it** -- a linear ramp to a hard zero translates its corner but keeps its shape,
    and the deck is still 16 % of the pixel where it stops. What removes it is the falloff
    SHAPE, and both halves of that needed the deck's optical depth separated from its
    coverage, which the MODIS rebuild supplies and *Cloud shells* above describes. A range
    tag would still buy nothing: the deck spans half the scale and a tag is for a map that
    does not.
  - **Fixed: the shells were lit plane-parallel, so nothing was lit past the terminator.**
    Every shell took `albedo x max(mu0, 0) x sun transmittance`: flux entering the column
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
  - **FIXED 2026-09-08: the deck's own law, and the shadow graded through it.** See *Cloud
    shells* above for the mechanism. Three terms were missing and all three are in:
    `R(mu0)` and `T(mu0) T(mu)` evaluated at each fragment's own cosines, which is the layer
    law and the graded shadow and needed the map's coverage and thickness apart; and
    `clouds_relief`, which carries the deck past the GROUND's terminator to its own shadow
    entry at mu0 = -0.0565, graded across the deck's own height. The band's surviving feature
    contrast goes 0.054 before any of this work to 0.099, and past the geometric cut reliefs
    of 0, 0.08 and 0.15 render bit-identically. **One correction to what this item used to
    say:** a layer law does NOT simply drop the mu0 projection. A plane-parallel layer's
    reflected flux is `F mu0 R(mu0)` and, although R rises toward 1 at grazing incidence,
    the product still falls to zero linearly in mu0 -- the atmosphere's own glow survives
    past the terminator because its SHADOW is the domain boundary and it has no horizontal
    surface, and a cloud deck survives because its SIDES are lit, which is what
    `clouds_relief` states. Also unresolved and unrelated: at mu0 < 0.06 Earth's ocean
    cannot compete on albedo at all -- 0.05 against a glow that is 65-80 % of the
    pixel.
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
- **A project's local scene does not meter** (*A project's own lighting*, tier 2). The
  candidate set is bodies plus the two asserted shell ceilings, so a lit interior filling the
  frame leaves the camera at its dark-adapted rest and blows out; a project's only recourse
  today is to take exposure manually (`auto = false`) or offset it
  (`exposure_adjustment_ev`). The shape of the fix is already in the model: a ceiling
  candidate the scene asserts, weighted by its screen area on a ramp of its own, exactly as
  `exposure_ceiling` works for a shell — what a project's own room *should* cost the rest of
  the frame is a taste question, not a photometric one, which is the same reason that cell is
  asserted rather than derived. Wants an owner for the assertion (the frame anchor is the
  obvious place) and a decision on whether a project may register more than one.
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
- **Multiple stars: metering, star colour, and the star field from elsewhere.** Audited
  2026-09-05 for 3–6 light sources at a location and more than one system at once; the light
  rig, the engine's light budget and how occlusion reaches each light are the sibling
  document's entry. Nothing here is persisted, and `IVPhotometry`'s conversions are already
  star-parameterized — every call site is not.
  - **Metering lights every body from the camera's star.** `IVExposureManager._star` comes
    from `camera_tree_changed`; each body's illuminance, parent-shadow fraction, lit fraction,
    ring and limb candidates take that one star, and any other star is skipped as a candidate
    outright. Per body, over its fed stars (the sibling's selection): lit luminance sums
    `albedo × Σ Eᵢ × shadowᵢ / π`, each star's disc is its own candidate with its own
    camera-point fraction, and the ring and limb ceilings take the brightest star's geometry.
    The lit/dark split assumes one terminator: start with the dominant star driving the
    phase, night-side ramp and horizon cutoff, and secondaries adding their own visible-lit
    share to BOTH candidates — a 1 % companion lights the "dark" side ~7 EV under the day
    side, and the night ramp must not carry the camera past it to starlight. Exposure,
    `iv_exposure`, the emission globals and the ambient floor stay one scalar each.
  - **Nonphysical light cannot sum.** `nonphysical_energy_at_1_au / d^0.5` was tuned for one
    sun: two curves add to blowout, and a companion at 100 au reads at a tenth of the primary
    instead of 1e-4. Require physical light for multi-star, or normalize the curve to the
    dominant star and scale the others by their physical ratio.
  - **Star colour and white balance.** `light_color` is never set: every surface is lit white
    while discs, points and the catalog take `color_from_b_v()` (the Sun's 0.63 tints its
    disc, not its light). A per-star light colour wants the same ramp, luminance-normalized
    so V-band illuminance still meters, through a CPU mirror that cannot drift from the
    shader's. Then decide the white point: tinting the Sun's light shifts every calibrated
    map, so white-balance to the home star and let an M dwarf read red *relative* to it. The
    photosphere's limb darkening and Planck anchors are solar (5777 K) and stand as an
    approximation for other types.
  - **Per-star terms in the shell shaders.** The disc laws, `limb_mean_incidence()`, the sun
    transmittance, the twilight excess and the atmosphere's shadow cylinder each
    take one sun; the `atm_sky_*` curve is a function of µ₀ scaling linearly with
    illuminance, so it reuses per star with no refit. `IVBodyPSF` should sum reflected flux
    over stars, each through its own phase law, while its geometry — phase, wing offset, limb
    sun angles — is one star's: dominant-star geometry with summed flux is the starting
    approximation, and a binary's crescent glow is the view that tests it. Rings: per-star
    lit face and phase boost, no mesh flip.
  - **The star field is Earth-centric.** `CUSTOM0.x` is V at the Sun; from another system
    each catalog star shifts by `5 log10(d_camera / d_catalog)`, computable per vertex from
    the model-space position (f32 is fine at parsec magnitudes), but a star the catalog
    carries at a placeholder distance for want of a parallax shifts wrongly. The visited star
    must leave the catalog and the Sun must appear from there (its quad; sibling document).
    The panorama needs no parallax at these ranges.
  - **Cost.** Six stars in the uniform interface cost nothing; per-fragment cost is linear in
    the fed count under uniform loop bounds, and the atmosphere quadrature is the term that
    multiplies. The engine's directional-light count is the only hard limit (sibling).

- **Rings: a ring shadow renders truly black, and the real one is not.** What lights it is
  not Saturnshine off the lit hemisphere: a ring element inside the shadow sees the planet's
  NIGHT side by construction, the lit hemisphere being on the other side of the terminator,
  so the only planetary light reaching it is the thin crescent near the terminator's limb.
  The larger term is the rings' own -- the shadowed region is surrounded by brilliantly lit
  ring, and multiple scattering carries light into it. Neither is modelled and neither is
  estimated here. (The same term the other way, ringshine on the globe's night side, is what
  makes Saturn's dark hemisphere visible beside unlit rings in one exposure, as in PIA12590
  -- though that frame cannot constrain the ring LEVEL, ringshine being proportional to it.)
  Both need a light term rather than a ring-shader change.