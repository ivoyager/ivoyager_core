# Changelog

This file documents changes to [ivoyager_core](https://github.com/ivoyager/ivoyager_core).

File format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

See cloning and downloading instructions [here](https://www.ivoyager.dev/developers/).


## [v0.2.1] - UNRELEASED

Under development using Godot 4.7.2.

Requires ivoyager_assets v0.2.1.dev.20260901. The Core plugin editor will offer to download this for you.

**Project Notes:**
1. Physical light is opt-in: set `IVCoreSettings.enable_physical_light = true` to instantiate the system and surface its "Physical Light" user Option (user can toggle it on/off at runtime). It requires `dynamic_lights`.


### Added
* Physical light with a compensating camera (new IVExposureManager, gated by new `IVCoreSettings.enable_physical_light`; off by default and costless when off). Sunlight becomes true 1/r² and ambient becomes integrated starlight, while per-frame CPU metering drives a relative exposure — new shader global `iv_exposure`, also carried into `light_energy` — so a body in view exposes correctly while stars and the Milky Way dim or vanish, exactly as a camera would. Everything derives from catalog data plus one absolute anchor: the background panorama's peak surface brightness in mag/arcsec². New static class IVPhotometry holds the V-band anchors and the magnitude, illuminance and luminance conversions. See [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md). New table columns support it:
	* shells.tsv `emission_luminance` states a night-side emission map in cd/m² (Earth's city lights).
	* shells.tsv `exposure_ceiling` and `limb_exposure_ceiling` cap the exposure while a shell is in view. What a rendered atmosphere or city-light layer should cost the rest of the frame is a taste decision rather than a photometric one, so the level is asserted per shell instead of metered.
	* Body-table `meter_albedo` is the albedo metering divides by where that is not the body's catalog `albedo`. Only Earth needs one, its air and clouds adding light over its cloudless map.
* Point-spread quads for bright bodies (new IVBodyPSF, `shaders/body_psf.gdshader`, new `IVCoreSettings.apply_body_psf`). The sun plus the 26 planetary-mass bodies with a geometric albedo now draw the camera's PSF response to their own flux, so a body becomes a point when its disc goes sub-pixel instead of vanishing at the old distance cull — framed to Iapetus' orbit, Saturn's whole retinue used to disappear while still far brighter than any star. A body's magnitude follows its albedo, phase and eclipse state through the same photometry as the star field, and the disc/point handoff is solved rather than tuned, so the trade is flux-continuous. This also replaces `sun_point.gdshader` and `sun_glare.gdshader`: two draws are two adds in a blend, and on the display-referred renderer a blend runs on encoded values, where a sum is not a sum. New body-table column `color_b_v` supplies catalog colour indices. See [VISUAL_MODEL.md](VISUAL_MODEL.md).
* Glare on every point source: the wide `r^-2` wing a real camera PSF has outside its Gaussian core, drawn in the shader and shared by the star field and by in-scene sources through one IVPSFSettings. The engine's glow pass cannot carry it — its per-texel feed is capped, so bloom stops being proportional to flux above the cap, and on Compatibility there is no halo at all — which is why the far sun read as an ordinary bright star. New IVPSFSettings values `glare_scale`, `glare_gamma` and `glare_max_px`, exported on IVStarsVisual; `glare_scale` 0 turns it off.
* Glow (bloom) is on by default in `resources/ivoyager_environment.tres`. It composites pre-tonemap in linear light and keys on `glow_hdr_threshold`, so under the compensating camera it blooms only what the camera has *not* exposed for — the sun, bright star cores, a blown limb, clipped city cores — while a correctly metered surface sits below the threshold. What it buys is the extended sources an IVBodyPSF quad doesn't cover: spacecraft parts, small moons and asteroids. A project that wants it off can author its own Environment. A new *Glow: the bloom pass* section in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) records which of Godot's glow properties a project may change, which carry the contract, and what the Compatibility renderer does differently.
* [Table breaking] Physically based atmospheres. The seven hand-tuned `limb_*` shells.tsv columns are replaced by 17 `atm_*` columns authored on a body's limb row, and `atmosphere_limb.gdshader` now draws an atmosphere as single scattering along the view ray through a Rayleigh gas, a haze and an optional detached layer (new `shaders/_atmosphere.gdshaderinc`). One integral gives the thin band beyond the limb, the veil brightening a full disc toward its edge, sunset-coloured twilight, the cusps of a backlit crescent, and Titan's stacked haze shells. The surface, cloud and band shaders take their sunlight and their extinction through the same atmosphere, so a cloud deck at the limb turns the colour of sunset and the ground is lit past the geometric terminator rather than cut off dead at it. Earth, Venus, Mars and Titan have one, which moved Venus, Titan and Mars from top-of-atmosphere to surface reflectance. A project with its own limb rows must restate them in the new terms; with physical light off, `atm_intensity` and `atm_thickness` remain for by-eye tuning. See [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md).
* Disc photometry: brightness now falls toward a body's limb the way the real body's does. The engine shades a sphere with a steady falloff from the sun-facing point to the terminator, but an airless rocky or icy body is nearly flat across its disc at full phase — the Moon, Mercury and the icy moons had been rendering their outer quarter about 2x too dark. New `shaders/_photometry.gdshaderinc` adds two adjustable laws to the surface, cloud shell and band pattern shaders, set per shell in shells.tsv: `lunar_lambert` flattens the disc toward what a regolith does, and `minnaert_k` deepens the falloff for a cloud-covered body such as Venus or Titan. Both default to rendering a body exactly as before, and a cloud deck must repeat its surface's value or the two disagree wherever the deck is thin.
* Range tags: a texture may be stored packed into its own reflectance range, with the range named in its file (`l`/`h` digit groups in units of 1e-4, optionally narrowed to one channel — `Triton.albedo.1024.l02462.png`). This gives the reflectance a body actually has all 256 of its codes, and is what lets a level above white be stored at all. The surface and cloud shell shaders unpack with one affine step; an untagged asset renders exactly as before.
* GUI widget IVExposureControl (`ui_widgets/exposure_control.tscn`), an "EV Auto" row showing the metered exposure in EV relative to the authored sky look. Unchecking Auto swaps the readout for a SpinBox seeded from the live value, so taking manual control does not itself change the view; a second SpinBox adjusts on top of whichever is in force. Inert, and hidden by default, unless physical light is active (`hide_when_nonphysical_light`).
* User Option "Invert Mouse Wheel" (setting `camera_mouse_in_out_inverse`), which flips the wheel's zoom direction.
* Two design documents. [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) is the logic and science of the physical light system: the one-anchor calibration chain, the compensating camera, surface/shell/ring/star/background handling, renderer parity and the settings. [VISUAL_MODEL.md](VISUAL_MODEL.md) is its spatial companion: how a double-precision simulation renders through a float32 pipeline (parenting cancellation, origin shifting, farwarp compression, the ~2^24 near:far ceiling), the shadow systems, culling and lifecycle, orbit-line tiers, point fields and mouse picking. Each carries its own TODO list.

### Changed
* Updated asset download pointer to v0.2.1.dev.20260901.
* [Project breaking] New shader globals `iv_exposure`, `iv_emission_energy_scale`, `iv_emission_luminance_scale`, `iv_limb_scale` and `iv_display_encode`, which the Core editor plugin writes into your project.godot from ivoyager_core.cfg on editor load. Core shaders require these with or without physical light; the default values tell a shader that physical light is inactive.
* [API breaking] IVStarSettings is renamed IVPSFSettings (`program/psf_settings.gd`, `IVGlobal.program` key `PSFSettings`), and IVStarsVisual's "Star Appearance" export group is now "Point Spread Function". No member, method or signal changed name. The class was never star-specific: it is the camera every source images through, and it now has a second consumer in every body's PSF quad.
* [Project breaking] An "id" shader must write its fragment id through the new `id_broadcast()` in `shaders/_fragment_id.gdshaderinc` rather than assigning the encoded vector to ALBEDO raw, and an id is 30 bits rather than 33. A raw broadcast writes values far above the glow threshold into the buffer the glow pass reads, which blooms a blob at the cursor; `id_broadcast()` carries each channel in [0.5, 1.0] instead, at a cost of one bit per channel. A project that only calls `IVFragmentIdentifier.get_new_id()` / `get_new_id_as_vec3()` needs no change.
* [Table breaking] file_adjustments.tsv is retired. Its last live column was a packed model's scale, which a model name now states directly — `Eros.1_10.glb` is 10 m per glb unit, an untagged model 1 m — read by the new `IVAssetPreloader.parse_model_scale()`. This also fixed Arrokoth, which had no row and so rendered 3 km long instead of 36 km. The other two columns go with it: `map_offset` and its engine plumbing, an equirectangular map having to be centred on the prime meridian anyway; and `disable_auto_visual_range`, replaced by a self-describing rule — a model that wants its own cull distance authors `visibility_range_end` on its own GeometryInstance3D nodes, which now holds in the 2D icon rig as well as in-sim. `IVAssetPreloader.get_body_disable_auto_visual_range()` is removed with it.
* [API breaking] `IVWorldController.mouse_wheel_turned` gained a `factor` argument and now emits once per wheel turn rather than twice (it had fired on both the press and the release of each wheel event). Zoom follows the wheel's reported turn amount, so a trackpad scrolls smoothly instead of in whole notches; one event is capped at a notch, that amount being a platform detail rather than a notch count, and turns accumulate over a frame rather than overwriting. `IVCameraHandler.mouse_wheel_adj` is retuned from 7.5 to 0.125 because wheel zoom no longer scales by frame time; a project that sets it must rescale by the same factor.
* Attribution docs restructured. IVOYAGER_WORKS.md is retired and replaced by IVOYAGER_ASSETS.md, which documents every distributed asset individually — I, Voyager's own and third-party alike — with what it is, what it was made from, what we did to it, and its own copyright and license, organized by content type rather than by owner. 3RD_PARTY.md keeps the license texts and becomes a clean list by copyright holder and license, each file carrying one short line naming which aspect of it is third-party. These plus CREDITS.md are mirrored here, in our project shells (Planetarium and Project Template), at our [distribution repository](https://github.com/ivoyager/asset_downloads), and within any distribution download itself.
* `IVBody.get_camera_radius()` returns `get_perspective_radius()`, so a body whose visible extent exceeds its radius can set `perspective_radius` in its table row and keep the camera's 1.2-radius floor and near plane clear of its shells. Titan does, for its haze. IVShellsModel also hands every shader shell its geometry (`body_radius_km`, `shell_scale`, `surface_scale`) as uniforms.
* Body-table albedo values: the planets now follow Mallama et al. (2017) V-band geometric albedos and Pluto is corrected from 0.3 to 0.52. Spacecraft and the previously empty asteroid rows (Itokawa, Arrokoth) carry albedos derived from their shipped models' measured render response, so a craft exposes correctly instead of blowing out white. `albedo` is now the published catalog value on every body, exposure metering having been given its own column.
* Exposure fix for the four bodies that ship no surface map. Venus, Titan, Uranus and Neptune had their `albedo_color` set by the asset convention "sphere mean = geometric albedo", which is exact only under Lommel-Seeliger, so all four rendered at the wrong brightness — Titan clipping white over most of its disc. All are relevelled against measured renders. `band_pattern.gdshader` gains the `albedo_ceiling` and `albedo_scale` uniforms this required, since a level above 1.0 is physical here but an sRGB Color cannot hold one.
* Uranus and Neptune gain their own measured limb darkening, each fitted from its own disc in Irwin et al. (2024). `band_pattern.gdshader` carries `lunar_lambert` as well as `minnaert_k`, for the k < 1 direction Minnaert cannot serve.
* Moon surface classes. Ganymede, Callisto, Mimas and Miranda move from `ROCKY_WORLD` to `ICE_WORLD`, and 61 previously unclassified moons gain a class wherever the table's own density or albedo settles it. The 97 with neither stay generic. Side effect worth knowing: surface_classes.tsv's `fallback_triaxial_size` had been reaching zero bodies, and now shapes 28 small moons that have no measured figure of their own.
* Mimas ships as a mesh plus albedo and normal cubemaps, like the other custom-mesh bodies, which is what lets its geometric albedo of 0.962 be stored at all.
* The 2D body-icon rig (IVBody2DCapturer, driving IVBody2DCaptureDialog) renders a staged body the way the simulator does, which an atmosphere made a requirement rather than a nicety. Its camera is perspective instead of orthographic — a shader takes VIEW from the view-space position, so an orthographic projection hands a disc-photometry law a `mu` that reaches zero inside the drawn silhouette, and hands an atmosphere a ray from a point the rasterizer is not looking from. The rig's key light is now also the staged body's sun, which IVSunOcclusionManager otherwise feeds only to bodies in the live scene. `stage_visual()` takes the body's reference radius; pass 0 for a packed craft model, whose table radius is a placeholder.

### Fixed
* Bodies rendered wrong under the Compatibility renderer (including the web export): high-albedo moons blew out to flat white, Saturn came out over-saturated, and an atmosphere lost most of its limb and all of its lit-side softening. That renderer is display-referred at both ends of a shader where Forward+ and Mobile are linear at both, and the two conventions agree only for a value that is merely sampled and multiplied by light. New `shaders/_display.gdshaderinc` is the fix and the only place that decides any of it: a shader decodes what it samples, works in linear, and writes through `display_write()`, gated by the new `iv_display_encode` global and the identity on a renderer that handles its own colour space, so Forward+ and Mobile render bit-identically to before. Saturn's rings and the background panorama take the same treatment, retiring the IVRings Compatibility boost overrides that had been tuned against the old broken pipeline. *Renderer parity* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) carries the measurements and records what the blend still costs — it runs after a shader returns, which is why the air in front of a disc is now composited by the disc's own shaders rather than blended over them.
* Core input handlers no longer push an engine error when an InputMap action is missing. `InputEvent.is_action_pressed()` errors on an unknown action, and every action IVInputMapManager defines is absent until IVCoreInitializer instantiates it — and stays absent in a project that removes or renames one, so a keystroke could error on every press. New IVInputMapManager statics `is_action_pressed()` and `is_action_released()` return false for an unknown action, which also makes `IVShowHideUI.user_toggle_action = &""` disable the toggle as documented rather than error.
* Zooming could throw the camera through its target and out the far side. Distance to target was scaled linearly, so an accumulated zoom-in past 1.0 took the multiplier to zero or negative and flipped the camera's position vector. Scaling is now exponential, which cannot reach zero and also makes zoom in and out exact inverses.
* Every custom-mesh body rendered mirrored in v0.2 — Ceres, Charon, Iapetus, Miranda, Phoebe, Phobos, Deimos and Vesta. The mesh asset pipeline placed longitude as the mirror image of the spheroid pipeline's, which shows on a tidally locked body as a landmark on the wrong side of the sub-planet point (Iapetus' dark face trailed, where Cassini Regio must lead). Corrected in the shipped assets and their builders. IVBodyVisual now also builds one reference basis for both surface paths, and a body mesh is authored as the displaced SphereMesh, so the two frames agree and their maps are interchangeable.
* Every tidally locked moon rendered rotated about its axis — two stacked errors in the lock. The anchor was applied twice: the table builder passed a full anchor as `rotation_at_epoch`, which `create_from_astronomy_specs()` stashes as the offset term `_update_rotations()` adds back on top. And the anchor was measured from the wrong zero: the orbit's raw mean longitude is referenced to the reference plane's node on the ICRF equator (the JPL satellite-elements convention the positions correctly use), while the rotation basis is built from the vernal equinox — a per-plane constant, 131° for Saturn's inner moons. Summed, the sub-parent meridian pointed away from the parent by as much as 150°. The builder now passes only the offset, and the new `IVOrbit.get_vernal_referenced_mean_longitude_at_epoch()` bridges the two frames.
* `substellar_longitude_at_epoch` was applied with the wrong sign, so every planet's spin phase rendered the substellar point at longitude −S instead of S: Earth's clock ran ~10 minutes off, Mars' local time ~5 hours. Moons were unaffected, having no such column.
* Captured 2D body icons carried a dark fringe at every silhouette, and could not show an atmosphere at all. A transparent-background SubViewport hands back premultiplied colour — a partly covered edge texel is the resolve of covered samples against nothing, and an atmosphere limb draws with `blend_premul_alpha` outright — and the readback saved it straight into a PNG, which means straight alpha, so every partly transparent texel composited at `alpha` times its true colour. `IVBody2DCapturer.unpremultiply_alpha()` converts the readback, raising alpha rather than clipping the colour where a thin bright ring's straight colour would exceed white, and the dialog composites its live preview with `BLEND_MODE_PREMULT_ALPHA`. The icon fit also now measures alpha at or above 8/255 rather than any nonzero alpha, so a body is no longer sized by how far its own invisible air reaches.
* Body name labels and symbols washed out under a body's cloud or atmosphere shell — the case that shows is a moon's HUD over its planet's cloud deck. Transparent surfaces sort by `render_priority` before depth, and a HUD sat at the default 0 while IVShellsModel ranks shells upward from it; both the symbol and the name (outline included) now sit at `IVBodyPositionVisual.HUD_RENDER_PRIORITY`, clear of the shell range.
* IVControlModResizable resolved anchors against the viewport, so a Control whose parent doesn't fill the screen — one under a persistent menu bar, say — was repositioned out of bounds by the parent's own offset. `Control.position` is parent-relative, so a Control parent's size is now the reference; the viewport remains the fallback.


## [v0.2] - 2026-08-01

Released using Godot 4.7.1.

Requires ivoyager_assets v0.2. The Core plugin editor will offer to download this for you.

**Project Notes:**
1. **Why are the stars missing?!** Add the new IVStarsVisual (tree/stars_visual.tscn) to your main scene "Universe" node (or whatever you call it) to see the new shader-rendered stars. You'll also need assets v0.2.dev.20260711, which the Editor will prompt you to download.
2. The new Screenshots feature has a file dialog `ui/screenshot_dialog.tscn` — add it under IVTopUI or wherever you add your popups.
3. Light and shadows no longer appear to be finicky about IVUnit.METER, at least over the range I've tested. Previous recommendation was 1e-3. I've set Planetarium back to 1.0 and everything seems fine.


### Added
* Textureless banded atmospheres. New `shaders/band_pattern.gdshader` generates a body's surface — zonal bands, streaks, a planetary wave and true color — from parameters alone, so Venus, Titan, Uranus and Neptune ship no surface map. Not for Jupiter or Saturn, whose named features no parameter set reproduces. 23 new shells.tsv columns drive it; `band_contrast` scales the whole pattern, 0 giving a flat body in its true color. Non-zonal features go to an overlay shell instead: Neptune's Great Dark Spot and clouds are now `SHELL_PLANET_NEPTUNE_CLOUDS`.
* Cubemap body maps. A body's channels (albedo, normal, roughness, emission) may be supplied as direction-sampled cubemaps instead of equirectangular maps, removing the pole pinch, the ±180° seam, and sliver-triangle shading (see [discussion #22](https://github.com/orgs/ivoyager/discussions/22)). This covers surfaces, shell overlays such as a cloud deck, and in-scene stars, each with its own cubemap shader variant so the tables never encode "cube vs. equirect". The equirectangular path is untouched and the two coexist per channel: a cubemap wins where both exist. Each is a 6-face strip importing as a `CompressedCubemap`, so nothing is decoded or recompressed at load; normal maps reproject to object space. Bake strips with the new `bake_cubemap.py` in the tools submodule, or — for projects without its Python toolchain — the new Project > Tools > "Map Convert…" dialog, which reprojects on the GPU.
* Screenshots. New IVScreenshotManager renders the sim to an off-screen SubViewport at the chosen output size, so a capture is the same picture as the screen at its own resolution. *This is especially helpful for any image with stars!* Adds IVScreenshotDialog, a `take_screenshot` hotkey (F12; changeable in Hotkeys popup), and a new Options section "Screenshots": `Width`, `Aspect` and `File Dialog`. With the dialog off it saves quietly to the last-used directory or `user://screenshots`, dimming the world briefly to acknowledge the save. Every non-"Preserve" aspect is a crop.
* At great distance, Sun visual is provided by a shader so that it is accurate relative to background stars — the far point images through the same photometry as the star field (shared via new IVStarSettings, so the two cannot drift), and the handoff to the close-in 3D model is solved rather than hand-tuned. Removed "grow" model hack that had kept Sun visible before. See [this commit](https://github.com/charliewhitfield/ivoyager_core/commit/e24dfe23ba6fd2670f68883154a14e64882f07b9) and subsequent commits.
* Stars as shaders. ~200,000 Hipparcos Catalog stars (thank you ESA) are now pin-sharp at any FOV rather than looking like a magnified jpeg at narrow FOV (even with 16K image). Each images as a fixed camera PSF with blackbody color, calibrated against NASA's starmap_2020, so the field is photometric out of the box and is the same picture at any render resolution (new shader global `iv_reference_viewport_height`, default 1080). Tune via IVStarsVisual's "Star Appearance" exports. Bonus: the new system is substantially lighter in GPU footprint and export size than the previous use of 8K or 16K images. Background Milky Way and nebulae are provided by a 4K image (de-pixelated via a sky shader). See [this commit](https://github.com/charliewhitfield/ivoyager_core/commit/09ed1c0bd4d44eec20f35b74842814a8d1a6f391) and subsequent commits.
* Analytic sun-occlusion system replaces shadow maps for astronomical-scale shadows. Four bonuses: 1) Resolution of Saturn rings shadow is  10000x higher (limited only by zoom level and rings resolution) and penumbra are mathematically modeled and correct. 2) The system is much ligher on the GPU than cranking shadow map up to 16K (which didn't help anyway). 3) It works in Compatibility renderer, so we can have shadows in our Planetarium web app. 4) It works with our "farwarp" system (see below). See [commit](https://github.com/charliewhitfield/ivoyager_core/commit/25e0b04f763265e1e966875efc844d4b24b9eb70). Architecture:
	* Shadows among large bodies and ring systems (astronomical-scale) are provided by material shaders only (surface.gdshader, cloud_shell.gdshader and rings.gdshader; all using _sun_occlusion.gdshaderinc).
	* Astronomical shadows on *distant* small objects are represented by mathematically modeled uniform light changes.
	* (Retained from before:) Local shadows among small objects or, say, a crater rim on a small object, are rendered via Godot's normal shadow system using two directional lights and a light mask to handle > and <= 100m radius objects separately.
* [#18](https://github.com/ivoyager/ivoyager_core/issues/18) "Farwarp" compression keeps large and distant objects visible when zoomed in to small spacecraft. Affects "visual" nodes and vertex shaders. Managed by IVFarwarpManager and IVBody, but does not affect IVBody itself. Opt-out available in IVCoreSetting. See [commit](https://github.com/charliewhitfield/ivoyager_core/commit/b9e5731b3521c8494290356b052752de8794f32e).
* Add IVOrbit.replacement_subclass to enable project-wide replacement (e.g., for [this proposal](https://github.com/orgs/ivoyager/discussions/25)).
* [#16](https://github.com/ivoyager/ivoyager_core/issues/16) Added spacecraft pointing methods. These can be specified by name in body tables (e.g., see `process` and `process_args` in [spacecrafts.tsv](https://github.com/ivoyager/ivoyager_core/blob/master/tables/spacecrafts.tsv)). The methods are in IVBody and can be added to by extending IVBody. (TODO: Move these to a static Callable dictionary to make it possible to add without subclassing.)

### Changed
* [Table breaking] spheroids.tsv is absorbed into [shells.tsv](https://github.com/ivoyager/ivoyager_core/blob/master/tables/shells.tsv), where a row is now either a body row (`SHELL_<body>_<tag>`) or a surface-class row supplying the default surface for its class. Two things that were shells-only now work for a default surface: it needs no texture, and it can carry a `scale` (what we see of Venus is its cloud top, ~65 km up). New table [surface_classes.tsv](https://github.com/ivoyager/ivoyager_core/blob/master/tables/surface_classes.tsv) replaces the body-table column `spheroid_type` with `surface_class`, which every body now needs, and defines each class's fallback mesh and color. This retires the `blank_grid.jpg` fallback model: an untextured body is now plain grey, and the `*_TYPE_BODY` classes shape the shared sphere by `fallback_triaxial_size` — the median axis ratios of the small bodies whose figure has been measured — so an unresolved small body reads as irregular rather than round.
* [API breaking] New optional moons.tsv column `triaxial_size` gives a small moon its measured semi-axes, scaling the shared sphere the way `equatorial_radius`/`polar_radius` already did for oblate bodies; thirteen moons have one, and `IVBody.get_equatorial_radius()`/`get_polar_radius()` now read it. `IVBodyVisual._init` takes a single `triaxial_size` Vector3 in place of the two radii, so projects setting `replacement_body_visual_class` must match.
* [API breaking] `IVSpheroidModel` is renamed `IVShellsModel` (`tree/shells_model.gd`) and no longer takes a surface class in `_init`; neither does `IVBodyVisual`, nor `IVBody.make_body_visual()`. `IVBody.get_spheroid_type()` is now `get_surface_class()`. Projects setting `IVBodyVisual.replacement_shells_model_class` or `IVBody.replacement_body_visual_class` must match the new signatures.
* Update ivoyager_core.cfg asset pointer to v0.2.dev.20260728. Sync 3RD_PARTY.md and IVOYAGER_WORKS.md for asset changes.
* [shader/gdshaderinc usage breaking] Many shader renames. The general pattern now is to name a `gdshader` file for its user if it is doing >1 function (e.g., surface.gdshader) or its single generic function (e.g., farwarp_vertex.gdshader), and `gdshaderinc` files for the function(s) that they provide.
* IVDynamicLights and defining table dynamic_lights.tsv restructured: the 4 semi-opaque far lights collapse into one unshadowed light that handles astronomical objects (see Analytic sun-occlusion system above). This takes pressure off of Godot's shadow map so should improve "local" shadows.
* IVRings no longer creates a whole bunch of shadow caster nodes for semi-transparent shadows. This is all handled by Analytic sun-occlusion system above.
* Renamed "IVPhysicalBody" to "IVBodyVisual". Rename motivated by new "farwarp" system, which further disassociates an IVBody from its visual representation.
* [API Breaking] Fully support 64-bit in IVOrbit and formalize a new 64-/32-bit API idiom. New idiom: "Vector" = 32-bit = "for graphics use". New methods `get_translation()` and `get_state()` return PackedFloat64Array. Old methods renamed `get_position_vector()` and `get_state_vectors()` return Vector3 and PackedVector3Array. New static utility IVMath64 supports 64-bit rotations, etc. See [commit](https://github.com/charliewhitfield/ivoyager_core/commit/55f18cebdd7b7ec4804c5e1a4311fac9f1fd5287).
* [Feature](https://github.com/orgs/ivoyager/discussions/24): New and better symbols can be shown with or without body names, and set by group similar to color. See [preview](https://github.com/orgs/ivoyager/discussions/24#discussioncomment-17525851). Core provides a default symbol atlas resources/ivoyager_symbol_atlas.png, which can be replaced by setting "symbol_atlas_" values in IVCoreSettings.

### Fixed
* [API Breaking] Oblate bodies were rendered slightly too flat. IVBodyVisual derived the polar radius as `3 * mean_radius - 2 * equatorial_radius`, which inverts an *arithmetic* mean, but the tables carry the published *volumetric* mean — and carry `polar_radius` itself, the value `IVBody.get_polar_radius()` returns and the analytic shadows already use. The derivation was both redundant and wrong, over-flattening Jupiter by 105 km and Saturn by 204 km (~3% of Saturn's flattening). `IVBodyVisual._init()` now takes `polar_radius`, so a project setting `IVBody.replacement_body_visual_class` must match the new signature.
* The editor asset updater now removes an existing `ivoyager_assets` file by file, notifying EditorFileSystem of each removal, instead of sending the whole directory to the trash. Replacing it wholesale stranded cached imports under `res://.godot/imported`, so the next install skipped reimporting and model scenes never re-extracted their textures (required for 20260728+ asset downloads which don't include extractable resources).
* [#17](https://github.com/ivoyager/ivoyager_core/issues/17) Fixed jagged and offset orbit/trajectory lines at Neptune and beyond.


## [v0.1.2] - 2025-06-29

Released using Godot 4.7.

**Project Breaking note:** IVFragmentIdentifier is no longer a SubViewport added in your scene tree! It's now a regular program node added by IVCoreInitializer. Suggested project update:
1. Remove node "FragmentIdentifier" in your scene tree, if present (it was optional).
2. Close editor and update `ivoyager_core`.
3. Open editor and go into Project Settings / Globals / Shader Globals. Delete the now-orphaned "iv_fragment_id_cycler", if present.


### Added
* IVOYAGER_WORKS.md now documents *our* derived works (compliments existing 3RD_PARTY.md).
* IVBody signal `parent_changed` (emitted on parent change for bodies with an IVTrajectory).
* Directional shadow resolution is now a user graphics option (IVOptionsPopup), applied live via RenderingServer by IVGraphicsManager. Options 2048/4096/8192/16384; default 8192. Hidden on the Compatibility renderer where directional shadows are disabled.
* User antialiasing options (MSAA, FXAA, TAA) in IVOptionsPopup, applied live to the main viewport by new program node IVGraphicsManager. MSAA defaults to 2x. FXAA and TAA are hidden in the Compatibility renderer (including web exports) where they are unsupported; TAA is exposed as experimental (it ghosts orbit lines, which are positioned in the vertex shader). The IVFragmentIdentifier probe now reads the unresolved multisampled color buffer under MSAA, so mouse-over identification of orbit lines and asteroid points survives antialiasing.
* "Shells" configuration via table [shells.tsv](https://github.com/ivoyager/ivoyager_core/blob/master/tables/shells.tsv) for full customization of surface and atmospheric effects on spheroid models. 
* Body 2D icon capture tool for generating the 256 PNG alpha flat images in ivoyager_assets/bodies_2d/. It runs *in the simulator* (new IVBody2DCaptureManager; Ctrl+Shift+B, and only in a run from source) and stages a throwaway IVBodyVisual, so an icon is the body exactly as the sim draws it — cloud deck, atmospheric limb, cube shaders and all — rather than a separate approximation that has to be kept in step. A checkbox per shell drops any of them; Earth's additive limb in particular reads as a dark rim against a transparent background, so you'll usually want it off. Opens on whatever body is selected. Captures are written to `user://body_icons`; copy each `.png` with its `.import` into the assets directory. Supporting API: `IVBody.make_body_visual()`, `IVBodyVisual.set_static_preview()` / `get_model()`, `IVAssetPreloader.get_body_file_prefix()`, and a `tag` key in each `get_body_shell_specs()` spec.
* Patched conics via new [IVTrajectory](https://github.com/ivoyager/ivoyager_core/blob/master/tree_components/trajectory.gd). Allows construction of complex flight paths with planet flybys. It's essentially a scheduler that specifies a series of IVOrbit instances and parent bodies. Can be defined in data tables or built by code in running game. Demonstrated with additions: Voyager 1 & 2, Pioneer 10, and New Horizons.
* IVBody signal `sleep_changed(is_sleeping: bool)`.
* IVSleepManager `hide_on_sleep` setting. Set false to prevent IVSleepManager from toggling `IVBody.visible`.
* IVCoreSettings `radius_multiplier_visibility_range_end` applied in IVBodyVisual and IVRings.
* IVCoreSettings `gui_size_settings` for project customization. (Replaces IVGlobal enum.) 
* IVStateManager signal `about_to_free_for_quit`. Emits before `about_to_free_procedural_nodes` when quitting.
* IVStateManager signal `threads_state_changed(thread_state: ThreadsState)`. Supplements existing threads signals.
* IVStateManager signal `procedural_nodes_freed`. Emits an arbitrary 5 frames after `about_to_free_procedural_nodes`.
* IVStateManager signal `game_loaded`. Unlike the IVSave signal, this signal is guarateed to emit before system_tree_built.
* Several IVArrays utility functions.
* IVAstronomy constant `CELESTIAL_NORTH` and function `get_basis_from_z_axis_and_icrf_equator_node()` (the reference basis convention for JPL satellite mean elements).

### Changed
* [shader/gdshaderinc breaking] Modified/standardized names of orbit and id shaders and gdshaderinc.
* [Possibly project breaking] Orbit parameters have been taken out of body tables (planets.tsv, moons.tsv, etc.) and moved to their own [orbits.tsv](https://github.com/ivoyager/ivoyager_core/blob/master/tables/orbits.tsv). This was necessary to implement the new trajectory system, but it's also a much cleaner data representation.
* [Project breaking] Rebuilt IVFragmentIdentifier system to use a CompositorEffect and a probe compute shader that writes an SSBO (Shader Storage Buffer Object). Previous SubViewport system was a very expensive hack that needed to be replaced. Now only functions with Forward+ or Mobile renderer (cleanly removes itself if Compatibility renderer). The system is very cheap now so added to projects by default. Performance is noticeably better than the older hack. (The new system is still a hack: it'll be much simplified when [this proposal](https://github.com/godotengine/godot-proposals/issues/7916) is fully implemented. Our shaders will then write their ids directly to CUSTOM_BUFFER0, CUSTOM_BUFFER1, etc.)
* [#13](https://github.com/ivoyager/ivoyager_core/issues/13) Decoupled the orbit-line "id" shaders from appearance: they are now appearance-agnostic overlays attached via `material_overlay`. Renamed `orbit.id.gdshader` → `uniform_id.gdshader` and `orbits.id.gdshader` → `instance_id.gdshader` (IVGlobal.resources keys `uniform_id_shader` and `instance_id_shader`). The visible orbit now comes from a base material, so arbitrary appearance shaders work without baking in id logic. For IVSBGOrbitsVisual subclasses, `_shader_override` now sets base appearance only and the id overlay is added independently (`_bypass_fragment_identifier` suppresses it).
* Scrapped `IVBody._process()` distance culling code. Instead, IVBodyVisual and IVRings set `visibility_range_end` on all GeometryInstance3Ds. Since this is intrusive on project models, there is an "opt-out" option provided by field `disable_auto_visual_range` in table `file_adjustments.tsv`.
* [API breaking] Removed IVGlobal enum `GUISize`. (Replaced by settable IVCoreSettings `gui_size_settings`.)
* [API breaking] Renamed IVStateManager threads allowed/stop signals; now: `threads_allowed` and `threads_required_to_stop`.
* Complete doc comments in all files.
* Emit signal about_to_quit closer to actual SceneTree.quit().
* IVSelectionManager "body" functions return Object rather than IVBody.

### Fixed
* [#15](https://github.com/ivoyager/ivoyager_core/issues/15) Mouse-over tooltip stuck on screen after the cursor moved from an orbit line or body directly onto a GUI panel. IVWorldController updates its mouse position only from `_gui_input`, which a GUI panel drawn on top suppresses once it takes over hover, so the frozen position kept resolving the last target. IVWorldController now tracks `is_mouse_in_world` via its `mouse_entered`/`mouse_exited` signals (dropping the world target on exit), and IVMouseTargetLabel hides whenever the mouse is not in the world.
* [#11](https://github.com/ivoyager/ivoyager_core/issues/11) Phantom camera drag after closing a dialog. A mouse press in the 3D view behind a popup could leave IVWorldController's drag state latched, so the camera panned with the mouse once the dialog closed. Mouse drag is now driven by `InputEventMouseMotion.relative` gated on the live `button_mask`, so a drag cannot outlive its physical button release. Admin popups (including IVConfirmationDialog) are now modal (`exclusive`) so clicks can't fall through to the world behind them.
* [#12](https://github.com/ivoyager/ivoyager_core/issues/12) Mouse-over target identification now requires body to have minimum visual separation from parent (same logic that show/hides visual HUD element).
* [#7](https://github.com/ivoyager/ivoyager_core/issues/7) Moon positions diverged from ephemeris (e.g., Earth's Moon ~120° ahead at 2026-01-01). IVTableOrbitBuilder misinterpreted two values from the JPL satellite mean elements source data: table `mean_motion` is the sidereal rate (dL/dt), not the mean anomaly rate; and `apsidal_period` (JPL "Pw") is the cycle period of the argument of periapsis ω measured from the moving node, not of the longitude of periapsis ϖ. Together these made mean longitude drift ahead by 360°/Pw per year (~60°/year for Earth's Moon).
* IVTableOrbitBuilder shifted Ω₀ and ω₀ in the wrong direction when converting orbit elements from a non-J2000 table epoch (`epoch_jd`) to internal J2000 epoch (affected Mars, Jupiter, Saturn & Uranus moons with 1950/1997 epochs).
* Orbit reference basis for EQUATORIAL and LAPLACE reference planes now has x-axis at the ascending node of the reference plane on the ICRF equator, matching the JPL convention for the longitude of the ascending node ("measured from the node of the reference plane on the ICRF equator"). Was the direction nearest the vernal equinox, causing static in-plane offsets (e.g., ~40° for Phobos/Deimos, ~126° for Titan, ~174° for Charon).
* IVRealPlanetOrbit (real planet positions) advanced mean anomaly at the table `mean_motion`, which per the JPL approximation is the mean longitude rate dL/dt. With the longitude of periapsis precessing, mean anomaly must advance at dM/dt = dL/dt − dϖ/dt (JPL computes M = L − ϖ). Planets therefore drifted ahead of ephemeris by dϖ/dt per unit time — negligible near J2000 but a few degrees toward the edges of the 3000 BC–3000 AD validity range (e.g., Mars ~3.4° and Earth ~3.0° at year 2900). Now uses the corrected rate for mean motion, time of periapsis, GM and specific energy.

## [v0.1.1] - 2026-02-09

Released using Godot 4.6.

### Added
* Added ease curve option for game speed changes.
* Added optional "stroboscope" properties in IVCoreSettings. These create an artificial stroboscope effect for fast rotating bodies that is more stable and pleasing then the effect you might see from frame updates. 

### Changed
* Set root Window.mode = MODE_WINDOWED on OS.shell_open(url) call by default.
* Changed default game speeds and speed names.
* [API breaking] Removed property IVSpeedManager.speed_name. Use method IVSpeedManager.get_speed_name()
* [API breaking] Removed IVGlobal.speeds and changed IVGlobal.times indexing.
* Removed unneeded/unmaintained website text in README.md.

### Fixed
* Fixed setter type bug in IVSpeedManager that prevented reverse color in IVDateTimeLabel.
* Fixed push_warning() text error in IVCoreInitializer.


## [v0.1] - 2025-12-13

Beta release!

Released using Godot 4.5.1.

### Added
* Lots of documentation! The main entry point for plugin documentation is [IVUniverseTemplate](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/universe_template.gd).
* Many replacement GUI widgets that are much more modular than older widgets. New foldable widgets using the new FolableContainer.
* IVTimekeeper can generate "clock time" as Terrestrial Time (TT) or simulated Universal Time (UT; default). TT is true simulator "time" but diverges from Earth rotation. UT stays synchronous with Earth rotation over long time scales.
* IVLanguageManager and "Language" as a user option. **We're ready for translations!**

### Changed
* Recoded IVSelectionManager to handle any Object type as selection (yay duck-typing!).
* Recoded IVCamera & IVCameraHanlder to handle any Node3D as target (yay more duck-typing!). 
* Renamed top-level directories. Removed all subdirectories.
* [API breaking] Moved all utils.gd static methods to new utility files: arrays.gd, conversions.gd, widgets.gd, etc.
* [Project breaking] Massive overhaul of how the scene tree works. See doc in [IVUniverseTemplate](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/universe_template.gd).
* [API breaking] Moved game speed code in IVTimekeeper into the new IVSpeedManager.
* IVStateManager is now an autolaod singleton.
* [API breaking] Many signals previously in IVGlobal have been removed, renamed and/or moved to IVStateManager (now a singleton).
* [Project GUI breaking] Removed many obsoleted GUI widgets.
* [Project GUI breaking] Removed "gui_mods" directory and contents. These have been replaced by new "gui_components": IVControlModResizable, IVControlModDraggable, etc.
* User can now edit "View" buttons.
* Improved the EditorPlugin's asset loader UI.
* Replaced 3RD_PARTY.txt with updated and more human-readable 3RD_PARTY.md, and updated CREDITS.md.
* [API breaking] Removed IVFontManager and overhauled IVThemeManager to work correctly with Godot's theme system.
* Recoded IVLinkLabel widget to either open external URL or pass to IVWikiManager.open_page().
* Recoded IVWikiManager to facilitate use of external or internal wiki.
* IVBodyLabel visual size now compensates for camera fov and viewport height.
* [Project breaking] Renamed many data table columns. Renamed table field "en.wiki" to "en.wikipedia" (these are Wikipedia.org page titles).
* [API breaking] Ranamed some IVBody.BodyFlags enums. Removed unused BodyFlags.EXISTS.
* [API breaking] Many other things not listed here... (Breaking API everywhere now so it won't happen after beta 0.1.)

### Fixed
* Graphic glitch on the frame that IVCamera hands off to a new parent body.
* Tidally locked body not rotating w/out orbit update.


## [v0.0.25] - 2025-06-12

Released using Godot 4.4.1

### Added
* IVOrbit can now handle parabolic and hyperbolic trajectories.
* IVOrbitVisual (replaces IVBodyOrbit) can display parabolic and hyperbolic trajectories.
* IVAstronomy centralizes astronomy related constants (G, etc.) and static methods.
* IVBodyFinisher class for adding non-procedural nodes from table data (to help declutter IVBody).
* IVLazyModelInitializer for initing lazy models. (Replaces overly complicated IVLazyManager.)
* Implemented nodal and apsidal precessions for asteroid orbits (points only).

### Changed
* [API breaking] Total code overhaul for [IVOrbit](https://github.com/ivoyager/ivoyager_core/blob/master/tree_refs/orbit.gd).
* [API breaking] Total code overhaul for [IVBody](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/body.gd).
* [API breaking] Renamed and reorganized enums in IVBody.BodyFlags.
* [API breaking] Removed procedural class dictionaries from IVGlobal and IVCoreInitializer. These classes can still be subclassed or replaced, but this happens in the class itself (member "replacement_subclass") or in "builder" classes.
* Unabbreviated field names in body tables for orbit parameters.
* De-cluttered code in various TableXxxxBuilder classes.
* Consolidated debug code in various places into IVDebug (static/debug.gd).

### Fixed
* Fixed errors caused by loading resources simultaneously on different threads.
* Fixed nodal and apsidal precessions for retrograde oribits.
* Hilda asteroids now maintain aphelion inside Jupiter's L3, L4, L5 points from 3000 BC - 3000 AD. (Due to precessions implementation.)
* Tadpole orbits for Jupiter Trojans now have propper distal "tails".


## [v0.0.24] - 2025-03-31

Released using Godot 4.4.

NOTE: For the shadows fix to work, project must have scale METER ~ 1e3 (see  
[comments](https://github.com/ivoyager/planetarium/blob/master/planetarium/units.gd)). For
good quality shadows you also need ProjectSettings:
* Rendering/Lights and Shadows/Directional Shadow/Size = 16384 (or as high as possible).
* Rendering/Lights and Shadows/Directional Shadow/16 Bits = false.
* Rendering/Anti Aliasing/Use TAA = true.

### Added
* SHADOWS!!!! Dynamic lights system added to support shadows over vast scale differences and also semi-transparancy. See [IVDynamicLight](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/dynamic_light.gd) and [dynamic_lights.tsv](https://github.com/ivoyager/ivoyager_core/blob/master/data/solar_system/dynamic_lights.tsv).
* Inner class IVRings/IVRingsShadowCaster and rings_shadow_caster.shader to cast semi-transparent shadows from Saturn Rings (in conjunction with above system).

### Changed
* To support shadows, all VisualInstance3D's have `layers` set. Large bodies have value 0b0001, but smaller have different values determined by IVCoreSettings.size_layers. A "semi-transparancy" mask (bits 8 to 11) is also applied to support Saturn Rings' shadows.

### Fixed
* v0.0.23 regression where IVMouseTargetLabel failed to display shader targets (asteroids and orbit lines).


## [v0.0.23] - 2025-03-20

Released using Godot 4.4.

### Added
* New data table views.tsv from which we build default IVView instances. (Removed class IVViewsDefaults.)

### Changed
* [API breaking] Type dictionaries where possible.
* [API breaking] Replace IVCacheManager inheritance w/ IVCacheHandler as component.
* [API breaking] Moved & renamed resource containers between IVProjectSettings and IVGlobal.
* [API breaking] Moved several "catalog" containers from IVGlobal to static var in the respective class files. E.g., 'bodies', 'small_bodies_groups' and 'selections'.
* [API breaking] Standardized many enum names for global table usage (e.g., added "BODYFLAGS_", "CAMERAFLAGS_" prefixes).
* [API breaking] Removed IVEnums and moved all enums to appropriate class files or IVGlobal singleton.
* Assets downloader uses OS.get_temp_dir() for the temp zip file.

### Fixed
* Nav button and view save bugs related to 'pressed', 'button_pressed' misuse.


## [v0.0.22] - 2025-03-07

Released using Godot 4.3. **We will update to 4.4 in the next release!**

### Changed
* [API breaking] Recoded IVSaveManager and other classes to work with the new (optional) [Save](https://github.com/ivoyager/ivoyager_save) plugin.
* [Project breaking] Removed save/load related GUI (moved to the plugin).

## [v0.0.21] - 2025-01-07

Released using Godot 4.3.

### Changed
* Now requires plugins 'ivoyager_tables' and 'ivoyager_units'. (These resulted from splitting the now-depreciated 'ivoyager_table_importer' plugin.)


## [v0.0.20] - 2024-12-20

Released using Godot 4.3.

### Fixed
* Export breaking reference to EditorInterface outside of EditorPlugin.


## [v0.0.19] - 2024-12-16

Released using Godot 4.3.

Requires plugin [ivoyager_table_reader](https://github.com/ivoyager/ivoyager_table_importer) v0.0.8.

Requires ivoyager_assets-v0.0.19. The editor plugin will add or update assets if you agree at the prompt.

### Added
* API support for adding IVSmallBodiesGroup data by code (not just tables/binaries).
* IVBody.remove_and_disable_model_space()
* Shader global 'iv_sun_global_positions' that can track up to 3 suns for shader effects. Used for phase angle in Saturn's Rings.

### Changed
* Improved the plugin's EditorPlugin, including waiting for required plugins to load first.
* [API breaking] Improved builder class names with "source" and "what": "BinaryAsteroidsBuilder", "TableBodyBuilder", "TableOrbitBuilder", etc.
* [Project breaking] Removed fake virtual function _ivcore_init().
* [Project breaking] IVCoreInitializer no longer adds admin popups (save dialog, options popup, etc.). Projects can now add these in a more Godot-like manner by constructing a control scene tree.
* Tables specified in IVCoreSettings.body_tables no longer need to be top-down ordered.
* [API breaking] Changed IVCamera fov/focal-length API. Replaced widgets FocalLengthButtons and FocalLengthLabel with new and better better FocalLengthControl.

### Fixed
* Our rings "1D" texture mipmaps are broken in Godot 4.3. This is fixed by explicit LOD coding using separate LOD textures. **Requires asset update!**


## [v0.0.18] - 2024-03-15

Released using Godot 4.2.1. _Has backward breaking changes!_

Requires plugin [ivoyager_table_reader](https://github.com/ivoyager/ivoyager_table_importer) v0.0.7.

Requires **ivoyager_assets-0.0.18**. **_NEW! The plugin will update this for you! Just press 'Download' at the dialog prompt._** (Alternatively, download [here](https://github.com/ivoyager/non_release_assets/releases/tag/2024-01-29).)

### Added
* Assets download & version management! The editor plugin checks presence and version of ivoyager_assets, and offers to download and add (or replace) as appropriate.
* Class documentation using Godot ## tags (work-in-progress).
* IVWorldEnvironment scene with default Environment and CameraAttributes. Project can specify data tables to override properties in Environment and CameraAttributes.

### Changed
* [ivoyager_assets] Major Neptune color adjustment (and minor Uranus) to match newly published true color estimations.
* [ivoyager_assets] New Titan images to show true atmospheric view rather than radar image.
* Unlocked the time setter widget so year can be set outside of 3000 BC to 3000 AD. The widget now displays a text warning telling user that planet positions are valid in that range. (Widget used in Planetarium.)
* Improved IVSaveBuilder Dictionary handling: a) Persist objects can be keys. b) String versus StringName types are correctly distinguished and persisted as keys.
* [Possibly breaking] Optimized IVSaveBuilder with new rules for Objects in containers: Objects can be in object member Arrays (which must be Object-typed) or object member Dictionaries (as keys or values), but cannot be in nested Arrays or Dictionaries inside of Arrays or Dictionaries. (Pure "data" containers can still be nested at any level.)
* IVSaveBuilder: Improved debug asserts at game save. Throws errors on rule violations that could lead to load problems.
* [API breaking] Removed `IVUtils.free_procedural_nodes()`. Replaced usage with `IVSaveBuilder.free_all_procedural_objects()`. The new function nulls all references to procedural objects (so frees RefCounted instances having circular references) and then frees the Nodes.
* Use static vars for localized class items.
* For loop typing and error fixes for Godot 4.2.
* Removed functions `_on_init()`, `_on_ready()`, `_on_process()`, etc. These were needed in Godot 3.x because virtual functions could not be overridden by subclasses. This is no longer the case.
* Removed number & unit names from translation (now added in ivoyager_table_importer).

### Removed
* IVSaveBuilder class. Save/load functionality has been removed from core and is now added by the [Tree Saver](https://github.com/ivoyager/ivoyager_tree_saver) plugin.

### Fixed
* [Migration regression] Fixed array type error causing crash in `IVTimekeeper.is_valid_gregorian_date()`.


## v0.0.17 - 2023-10-03

Released using Godot 4.1.1.

Requires non-Git-tracked **ivoyager_assets-0.0.17**; find in ivoyager_core [releases](https://github.com/ivoyager/ivoyager_core/releases).    
Requires plugin [ivoyager_table_reader](https://github.com/ivoyager/ivoyager_table_importer) v0.0.5.

### Added
* Core submodule content previously in [ivoyager](https://github.com/ivoyager/ivoyager) v0.0.16.

### Changed
* ivoyager_core works as an editor plugin!
* All autoload singletons, shader globals, project settings, and class definitions can be modified by editing res://ivoyager_overrides.cfg.
* Previous project settings in IVGlobal have been moved to IVCoreSettings.
* Previous class definitions in IVProjectBuilder have been moved to IVCoreInitializer.


##
I, Voyager projects v0.0.16 and earlier used a different core submodule [ivoyager](https://github.com/ivoyager/ivoyager) (now depreciated); see previous changelog [here](https://github.com/ivoyager/ivoyager/blob/master/CHANGELOG.md).

[v0.2.1]: https://github.com/ivoyager/ivoyager_core/compare/v0.2...HEAD
[v0.2]: https://github.com/ivoyager/ivoyager_core/compare/v0.1.2...v0.2
[v0.1.2]: https://github.com/ivoyager/ivoyager_core/compare/v0.1.1...v0.1.2
[v0.1.1]: https://github.com/ivoyager/ivoyager_core/compare/v0.1...v0.1.1
[v0.1]: https://github.com/ivoyager/ivoyager_core/compare/v0.0.25...v0.1
[v0.0.25]: https://github.com/ivoyager/ivoyager_core/compare/v0.0.24...v0.0.25
[v0.0.24]: https://github.com/ivoyager/ivoyager_core/compare/v0.0.23...v0.0.24
[v0.0.23]: https://github.com/ivoyager/ivoyager_core/compare/v0.0.22...v0.0.23
[v0.0.22]: https://github.com/ivoyager/ivoyager_core/compare/v0.0.21...v0.0.22
[v0.0.21]: https://github.com/ivoyager/ivoyager_core/compare/v0.0.20...v0.0.21
[v0.0.20]: https://github.com/ivoyager/ivoyager_core/compare/v0.0.19...v0.0.20
[v0.0.19]: https://github.com/ivoyager/ivoyager_core/compare/v0.0.18...v0.0.19
[v0.0.18]: https://github.com/ivoyager/ivoyager_core/compare/v0.0.17...v0.0.18
