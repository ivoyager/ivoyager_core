# Changelog

This file documents changes to [ivoyager_core](https://github.com/ivoyager/ivoyager_core).

File format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

See cloning and downloading instructions [here](https://www.ivoyager.dev/developers/).


## [v0.2.1] - UNRELEASED

Under development using Godot 4.7.2.

Requires ivoyager_assets v0.2.1.dev.20260909. The Core plugin editor will offer to download this for you.

**Project Notes:**
1. Physical light is opt-in: set `IVCoreSettings.enable_physical_light = true` to instantiate the system and surface its "Physical Light" user Option (user can toggle it on/off at runtime). It requires `dynamic_lights`.
2. The shader warm-up is opt-in; see IVShaderWarmup addition below. This forces shader compilation under the boot or splash screen rather than mid-flight when visiting a body for the first time at runtime. These times can be significant, especially for Compatibility renderer; see *Compiling shaders* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).
3. Hardware-fitted graphics defaults are opt-in: set `IVSettingsManager.graphics_target` so that integrated graphics, browsers and dense screens start with lighter settings.


### Added
* Physical light with a compensating camera (new IVExposureManager, gated by new `IVCoreSettings.enable_physical_light`; off by default and costless when off). Sunlight becomes true 1/r² and ambient becomes integrated starlight, while per-frame CPU metering drives a relative exposure — new shader global `iv_exposure`, also carried into `light_energy` — so a body in view exposes correctly while stars and the Milky Way dim or vanish, exactly as a camera would. Everything derives from catalog data plus one absolute anchor: the background panorama's peak surface brightness in mag/arcsec². New static class IVPhotometry holds the V-band anchors and the magnitude, illuminance and luminance conversions. See [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md). New table columns support it:
	* shells.tsv `emission_luminance` states a night-side emission map in cd/m² (Earth's city lights).
	* shells.tsv `exposure_ceiling` and `limb_exposure_ceiling` cap the exposure while a shell is in view. What a rendered atmosphere or city-light layer should cost the rest of the frame is a taste decision rather than a photometric one, so the level is asserted per shell instead of metered.
	* Body-table `meter_albedo` is the albedo metering divides by where that is not the body's catalog `albedo`. Only Earth needs one, its air and clouds adding light over its cloudless map.
* Point-spread quads for bright bodies (new IVBodyPSF, `shaders/body_psf.gdshader`, new `IVCoreSettings.apply_body_psf`). The sun plus the 26 planetary-mass bodies with a geometric albedo now draw the camera's PSF response to their own flux, so a body becomes a point when its disc goes sub-pixel instead of vanishing at the old distance cull — framed to Iapetus' orbit, Saturn's whole retinue used to disappear while still far brighter than any star. A body's magnitude follows its albedo, phase and eclipse state through the same photometry as the star field, and the disc/point handoff is solved rather than tuned, so the trade is flux-continuous. The glare wing sits toward the lit limb rather than centred on the body and carries the flux this camera receives rather than a distant observer's, so it follows a crescent and dies with it when a close body's sun sets behind its own disc. With physical light off, only a star keeps its glare over a resolved disc; a planet or moon glares as a point and loses it as its disc resolves. This also replaces `sun_point.gdshader` and `sun_glare.gdshader`: two draws are two adds in a blend, and on the display-referred renderer a blend runs on encoded values, where a sum is not a sum. New body-table column `color_b_v` supplies catalog colour indices. See [VISUAL_MODEL.md](VISUAL_MODEL.md).
* Glare on every point source: the wide `r^-2` wing a real camera PSF has outside its Gaussian core, drawn in the shader and shared by the star field and by in-scene sources through one IVPSFSettings. The engine's glow pass cannot carry it — its per-texel feed is capped, so bloom stops being proportional to flux above the cap, and on Compatibility there is no halo at all — which is why the far sun read as an ordinary bright star. New IVPSFSettings values `glare_scale`, `glare_gamma` and `glare_max_px`, exported on IVStarsVisual; `glare_scale` 0 turns it off.
* Glow (bloom) is on by default in `resources/ivoyager_environment.tres`. It composites pre-tonemap in linear light and keys on `glow_hdr_threshold`, so under the compensating camera it blooms only what the camera has *not* exposed for — the sun, bright star cores, a blown limb, clipped city cores — while a correctly metered surface sits below the threshold. What it buys is the extended sources an IVBodyPSF quad doesn't cover: spacecraft parts, small moons and asteroids. A new *Glow: the bloom pass* section in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) records which of Godot's glow properties a project may change, which carry the contract, and what the Compatibility renderer does differently.
* [Table breaking] Physically based atmospheres. The seven hand-tuned `limb_*` shells.tsv columns are replaced by 17 `atm_*` columns authored on a body's limb row, and `atmosphere_limb.gdshader` now draws an atmosphere as single scattering along the view ray through a Rayleigh gas, a haze and an optional detached layer (new `shaders/_atmosphere.gdshaderinc`). One integral gives the thin band beyond the limb, the veil brightening a full disc toward its edge, sunset-coloured twilight, the cusps of a backlit crescent, and Titan's stacked haze shells. The surface, cloud and band shaders take their sunlight and their extinction through the same atmosphere, so a cloud deck at the limb turns the colour of sunset and the ground is lit past the geometric terminator rather than cut off dead at it. Earth, Venus, Mars and Titan have one, which moved Venus, Titan and Mars from top-of-atmosphere to surface reflectance. A project with its own limb rows must restate them in the new terms; with physical light off, `atm_intensity` and `atm_thickness` remain for by-eye tuning. See [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md).
* Disc photometry: brightness now falls toward a body's limb the way the real body's does. The engine shades a sphere with a steady falloff from the sun-facing point to the terminator, but an airless rocky or icy body is nearly flat across its disc at full phase — the Moon, Mercury and the icy moons had been rendering their outer quarter about 2x too dark. New `shaders/_photometry.gdshaderinc` adds two adjustable laws to the surface, cloud shell and band pattern shaders, set per shell in shells.tsv: `lunar_lambert` flattens the disc toward what a regolith does, and `minnaert_k` deepens the falloff for a cloud-covered body such as Venus or Titan. Both default to rendering a body exactly as before, and a cloud deck must repeat its surface's value or the two disagree wherever the deck is thin. Note that `minnaert_k` couples law and level through the disc factor `F = 2/(2k+1)`, so a body adopting it must re-derive its map level against `A x F = p`.
* Range tags: a texture may be stored packed into its own reflectance range, with the range named in its file (`l`/`h` digit groups in units of 1e-4, optionally narrowed to one channel — `Triton.albedo.1024.l02462.png`). This gives the reflectance a body actually has all 256 of its codes, and is what lets a level above white be stored at all. The surface and cloud shell shaders unpack with one affine step; an untagged asset renders exactly as before.
* GUI widget IVExposureControl (`ui_widgets/exposure_control.tscn`), an "EV Auto" row showing the metered exposure in EV relative to the authored sky look. Unchecking Auto swaps the readout for a SpinBox seeded from the live value, so taking manual control does not itself change the view; a second SpinBox adjusts on top of whichever is in force. Inert, and hidden by default, unless physical light is active (`hide_when_nonphysical_light`).
* GUI component IVEdgeContainer (`ui_components/edge_container.gd`), a Container that holds its children against its edges and corners by their size flags and never lets them overlap, capping the height of any that would. Its class doc says how to build a panel that scrolls once capped.
* GUI component IVControlModFade (`ui_components/control_mod_fade.gd`), which fades its parent Control while the user drags the 3D view and when the user leaves it idle, under new user settings `gui_fade_while_dragging` and `gui_fade_when_idle` for a project to offer in Options.
* GUI widgets IVPanelButton, a toggle that shows and hides a panel, one panel at a time for buttons that share a ButtonGroup, with an optional hotkey; and IVHideGUIButton and IVShowGUIButton, on-screen counterparts to the Show/Hide All GUI hotkey.
* IVOptionsPopup and IVHotkeysPopup export `modal`, true by default, which keeps the rest of the GUI and the view from responding while the popup is open, as before. False leaves them usable, and a second `IVGlobal.options_requested` or `hotkeys_requested` then closes the popup (new `toggle()` on each), as its hotkey does.
* IVOptionsPopup and IVHotkeysPopup scroll their content once the popup reaches new export `max_screen_proportion` of the view, 70% by default.
* User Option "Invert Mouse Wheel" (setting `camera_mouse_in_out_inverse`), which flips the wheel's zoom direction.
* [shader/gdshaderinc breaking] [Project breaking] User Option "Atmosphere Quality" (setting `atmosphere_quality`, new `IVGraphicsManager.atmosphere_quality_settings`): Normal; Reduced, a shorter along-ray quadrature and fewer beyond-limb ring taps in the same shader program, applied live through three new shader globals (`iv_atm_gl_first`, `iv_atm_gl_nodes`, `iv_atm_ring_max_taps`) that replace the `atm_gl6_nodes` and `atm_ring_max_taps` uniforms and the `ATM_GL6_T` / `ATM_GL6_W` tables; Minimum, the same model in closed form in each atmosphere shader's new `.min` twin (`_atmosphere.min.gdshaderinc`, new `IVAssetPreloader.min_shader_variants`); and Off, which draws no limb shell and each disc's air in a cheap closed form in its new `.off` twin (`_atmosphere.off.gdshaderinc`, new `IVAssetPreloader.off_shader_variants`). Minimum and Off apply at the next start. See *Atmospheres* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) and *Atmosphere quality* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).
* User Option "Glow" (setting `glow`), which switches the bloom pass, live on Forward+ and at the next start on Compatibility. See *Glow* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).
* Airless variants of the surface, cloud and band shaders (`surface.airless.gdshader` and the rest, new `IVAssetPreloader.airless_shader_variants`), which a body with no atmosphere now binds: the same shader with `_atmosphere.gdshaderinc` compiled down to no-ops, rendering the body identically and faster, most of all on an Intel iGPU. Each disc shader's body moves into an include (`_surface.gdshaderinc` and the rest) that both variants share. See *Airless shaders* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).
* User Option "3D Render Scale" (setting `render_scale`, new `IVGraphicsManager.render_scale_settings`): the 3D view at 100, 85, 70 or 50% of the window's resolution, upscaled with FSR 1 on Forward+ and bilinear elsewhere, while the GUI keeps full resolution. It is hidden, and the scale held at 100%, where the renderer runs through ANGLE's Direct3D 11 path, where a reduced scale costs frame time instead (new `IVGraphicsManager.can_scale_render()`). See *3D render scale* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).
* User Option "Renderer" (setting `renderer`, new `IVGraphicsManager.renderer_settings`), desktop only: Forward+ or Compatibility, written to the file a project names in `application/config/project_settings_override` for the engine to start with next time; a project that names none gets no option. IVOptionsPopup now hides a section with nothing to show, and while a setting registered through new `IVSettingsManager.set_running_value()` differs from what the running session uses, it marks that option (new `IVSettingsManager.is_restart_pending_for()`) and warns that a restart is needed. New `IVGlobal.video_adapter_type` lets a project choose defaults by GPU, in either renderer: Compatibility can't read the GPU's type, so a Forward+ run records it in the same file.
* User Option "Star Catalog" (setting `star_catalog`, new `IVGraphicsManager.star_catalog_settings`): all 2.6 million catalog stars, or the brightest 940,000 (to V 11) or 220,000 (to V 9.5), which IVStarsVisual loads at the next start. See *Star catalog* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).
* User Option "Frame Rate Cap" (setting `frame_rate_cap`, new `IVGraphicsManager.frame_rate_cap_settings`): None, 60 or 30 fps, applied live as `Engine.max_fps`; None leaves in place whatever `application/run/max_fps` or `--max-fps` started the engine with. See *FXAA, TAA and Frame rate cap* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).
* Graphics defaults fitted to each machine's GPU and screen, opt-in through new `IVSettingsManager.graphics_target` (new `IVGraphicsManager.get_graphics_tier()`, `get_fitted_defaults()` and `is_angle_d3d11()`): `BROAD_HARDWARE` for a project that runs from integrated graphics and browsers up, and `MODERN_GPU` for one that requires Forward+, which also hides the Renderer option. The default, `NONE`, applies Core's defaults as written. See *Fitted defaults* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).
* Graphics rescue, on by default outside editor builds (new `IVCoreSettings.enable_graphics_rescue`, new IVGraphicsRescue): a start that crashes or freezes has the next one restore the graphics settings to their defaults (new `IVSettingsManager.graphics_settings`, `restore_graphics_defaults()` and `graphics_reset`), a session whose frames crawl is offered the same, and user argument `--reset-graphics` asks for it. A restart or page reload that bypasses `IVStateManager.quit()` should call new `IVSettingsManager.mark_start_finished()` first. See *A setting the machine can't carry* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).
* IVConfirmationDialog shows a notice, with no Cancel button, for an `IVGlobal.confirmation_required` with an empty `cancel_txt`.
* Tooltips on every user Option (new `IVOptionsPopup.option_tooltips`), with Core's texts in `text/hints_text.csv`. A graphics option's tooltip states its GPU cost under the running renderer (new `option_compatibility_tooltips` for Compatibility).
* Three design documents. [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) is the logic and science of the physical light system: the one-anchor calibration chain, the compensating camera, surface/shell/ring/star/background handling, renderer parity and the settings. [VISUAL_MODEL.md](VISUAL_MODEL.md) is its spatial companion: how a double-precision simulation renders through a float32 pipeline (parenting cancellation, origin shifting, farwarp compression, the ~2^24 near:far ceiling), the shadow systems, culling and lifecycle, orbit-line tiers, point fields and mouse picking. [PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) is the objective simulation underneath both: bodies, orbits as an element coordinate system and why that does not limit thrust or perturbations, trajectories, rotation, time, scale, the small-body groups, the persisted state and what a multiplayer sync would need, and the three kinds of project the model serves — including a game whose action is local, where a project's own scene, camera and Godot physics sit inside the simulation. Each carries its own TODO list, and each says what a project may bring of its own: *A game whose action is local*, *The render frame anchor and local scenes*, *A project's own lighting*.
* [IVBody_REDESIGN_v0.3.md](IVBody_REDESIGN_v0.3.md), the living plan for the v0.3 IVBody rework: positioner / rotator / geometry composition, surface anchors, fixed positioners, the proximity service replacing camera-parented sleep and lazy triggers, and a body that answers its own surface geometry. Its §2 adds anchor-relative placement — every body `top_level`, placed from f64 against a frame anchor, which subsumes origin shifting and is what lets a project hang a scene of its own inside the simulation. [PHYSICAL_MODEL.md](PHYSICAL_MODEL.md) and [VISUAL_MODEL.md](VISUAL_MODEL.md) link to it where a section describes a v0.2 mechanism it replaces.
* IVShaderWarmup (`program/shader_warmup.gd`), opt-in through `IVCoreInitializer.program_nodes`: it draws spatial shaders on quads in front of the camera, at the planet-scale and the shadow-casting craft-scale layers, so the Compatibility renderer's per-shader compiles land under a loading or splash screen instead of on the first visit to a body. It warms what the project will actually draw rather than every shader in `IVGlobal.resources`: a body's shell shaders come from the specs IVAssetPreloader has already resolved, and Core's remaining shaders from the same conditions IVBodyFinisher and IVSBGFinisher apply when they add the node that binds one. It also draws the materials of each body's packed model, such as a spacecraft's (`warm_packed_models`). A shader no such condition can decide is not warmed — `stars_shader` is the one Core shader in that position, IVStarsVisual being a scene node — so name it, and any of your own, in `extra_shader_names`; `warm_core_shaders` = false turns the automatic selection off entirely. Its `trigger` suits either boot sequence: `SIMULATOR_STARTED` for a project that boots straight in, where the real scene supplies the specializations bodies use, or `ASSETS_PRELOADED` for a splash-screen project (`wait_for_start` == true), where no system tree exists yet and the warm-up adds its own camera and light to compile the scene-independent part. It runs once per session, holding `IVStateManager.show_splash_screen` or `ok_to_start` until it finishes (new `IVStateManager.hold_splash_screen()` and `hold_start()`), so a splash or boot screen that follows them covers it; `progress_changed` lets that screen report it.
* A shadow-mapped IVDynamicLight switches its map off while nothing within its reach would draw into it or read it, under new opt-in `IVCoreSettings.apply_empty_shadow_pass_skip` — renderer-neutral, and worth 7-22 % of an integrated-GPU Forward+ frame. It is opt-in because each shadowed-light count a session reaches compiles its own programs for every lit shader: see *Local shadow maps* in [VISUAL_MODEL.md](VISUAL_MODEL.md), and *Empty shadow passes* and *The light configuration* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md). An IVBodyVisual declares itself while it holds `IVGlobal.LOCAL_SHADOW_CASTER`; a project's own local scene does so through new `IVDynamicLight.add_local_shadow_geometry()`.
* [Project breaking] Hi-DPI support: IVGraphicsManager applies the screen's own scale (Windows display scaling, or the browser's devicePixelRatio) as the root window's `content_scale_factor`, so the GUI, body names and symbols, asteroid symbols and the hover probe keep their size on a hi-DPI screen (Small Bodies Point Size stays in screen pixels), a window still at the project's size opens larger to match, and GUI Size scales on top (new `IVCoreSettings.apply_display_scale`, on by default). See *Pixel spaces* in [VISUAL_MODEL.md](VISUAL_MODEL.md). `Viewport.get_visible_rect()` is now logical pixels, so code that took it for render pixels must use new `IVGraphicsManager.get_render_size()`.
* [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md): what the graphics cost a weak machine, measured in the [Planetarium](https://github.com/ivoyager/planetarium) on an Intel UHD iGPU and a GTX 1650 Ti through each render path they give — per frame, option by option and for each saving that needs no option, and once, in the shaders a first run compiles, with the rules for writing a shader that compiles quickly.

### Changed
* [API breaking] A body with no mesh of its own now picks its shared sphere per frame by on-screen size, from a ladder of rungs halving down from the finest (`IVShellsModel`, built by `IVResourceInitializer.get_sphere_lod_resolutions()`). A rung serves every body whose silhouette sag stays within 0.15 px, so a close body keeps the detail it had while a distant one stops drawing 65,536 triangles into a few pixels. `IVCoreSettings.sphere_radial_segments` and `sphere_rings` are replaced by one `max_sphere_resolution` (256), rings being half the segments at every rung; a project that set either must restate it as the one value. See *The sphere LOD ladder* in [VISUAL_MODEL.md](VISUAL_MODEL.md) and *Level of detail, and shells nobody can see* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).
* [API breaking] A body's shells now cull, and a body's own mesh takes its LODs, on their own bounds wherever the camera's far plane allows, keeping the farwarp box only while the body may reach past a quarter of it (new `IVFarwarpManager.true_bounds_far_fraction` and `IVBodyVisual.set_farwarp_box()`), which also lets a body without a PSF quad take its 4000-radii distance cull as intended; and a body handed off to its PSF point stops drawing its shells, as its rings now do at their own handoff in place of a distance cull that never fired (new `IVShellsModel.cull_handed_off` and `IVRings.cull_handed_off`). Together they return 2-7 ms, or 2-16 %, of an integrated-GPU frame through ANGLE, most of it Ceres's and the moons' own meshes drawn off screen; see *Farwarp* in [VISUAL_MODEL.md](VISUAL_MODEL.md) and *Level of detail, and shells nobody can see* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md). A shader a project registers in `IVShellsModel.shader_meshes` must now place its vertices within the shell's unit sphere.
* Under physical light, the background panorama and each star magnitude bin stop being drawn once the compensating camera has metered them below half a display code (`IVWorldEnvironment.skip_invisible_starmap`, `IVStarsVisual.cull_invisible_bins`, both on by default and both inert with the system off). To make the second possible the star field is now one mesh per bin under `IVStarsVisual` rather than one merged surface, so the node itself no longer holds a `mesh`. Half a code is the 8-bit rounding boundary, which bounds the change at one display code by construction; see *Skipping what the camera has metered away* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) and *Point fields* in [VISUAL_MODEL.md](VISUAL_MODEL.md).
* Updated asset download pointer to v0.2.1.dev.20260909.
* [Asset breaking][API breaking] The catalog star field is rebuilt from Hipparcos **and Tycho-2** — 2,551,210 stars against 117,955, complete to V 11.0 rather than about V 7.5 — which is what fills a narrow field of view that used to look thin. A new packed binary format carries it in 19.6 MiB, in half-magnitude bins, so a project rendering at one fixed fov can ship only the buckets that fov can use; the ivoyager_assets README tabulates where each bin stops mattering. `IVStarsVisual.BINARY_FILE_MAGNITUDES` and `stars_binary_path` change with it (`starmaps/stars.*.ivbinary`), and the field's integrated starlight rises 1.77x — the light the background panorama subtracts as Tycho stars and that nothing had put back.
* [Project breaking] The background panorama takes its level from the star field's own photometry with physical light OFF as well as on, so the Milky Way and the stars sit on one brightness scale either way and toggling the setting moves them together; the authored value it replaces was about 6x too bright against the stars. `IVWorldEnvironment.starmap_background_energy` becomes `starmap_background_energy_scale`, a multiplier on the derived level defaulting to 1.0, so a project that set the old absolute value must restate it as a ratio; the new static `IVExposureManager.compute_sky_energy()` is the one producer, and this node re-applies it on `IVPSFSettings.changed` like every other consumer of those values.
* [Asset breaking][API breaking][Table breaking] Saturn's rings are rebuilt end to end. `rings.gdshader` renders a single-scattering slab, so the rings answer to their opening angle and phase, the unlit face renders at all, and they stop snapping off as they go edge-on; past the size at which a plane can be rasterized they hand their light to the body's own point source instead of vanishing. Their level, their colour, their phase function and their optical depth are measured now rather than set by eye — the phase function from Dones et al.'s observed Voyager phase curve, the depth from Cassini UVIS stellar occultations in place of a Voyager profile that saturated over the B ring. The asset is one imported `CompressedTexture2DArray`, built by the new `build_saturn_rings.py` in the [tools](https://github.com/ivoyager/tools) submodule, in place of 27 PNGs on nine hand-built LOD levels — so `IVAssetPreloader.get_rings_texture_arrays()` becomes `get_rings_texture_array()`. rings.tsv gains ten photometric columns, which is what makes the shader generic to any real or invented ring system, and IVRings and IVExposureManager gain the point-source handoff and the per-face metering that go with them. See [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md).
* [Asset breaking] [Table breaking] [shader breaking] Earth's cloud deck is rebuilt from two days of MODIS and VIIRS with its COVERAGE and its OPTICAL THICKNESS measured apart, and the cloud shell shaders now light a deck as the layer it is rather than as a painted sheet: from that pair the shell evaluates the deck's reflectance and both of its transmittances at each fragment's own sun and view angles, so a deck is no longer limb-darkened like a Lambert surface and the sunlight it removes is graded through its own thickness instead of cut at a line. That, the new `clouds_relief` cell and a shadow cast at the displaced place the sun ray really crosses the deck (`clouds_sun_transmittance()`) end the wall of white cloud at Earth's terminator. New shells.tsv columns `clouds_two_stream_map` and `clouds_relief`; a deck built the old way (Neptune's) leaves both blank and renders bit-identically. The deck ships at face 2048, and the shaders' domain warp and five-octave detail are DELETED rather than tuned down -- they stood in for a map four times coarser than the surface beneath it and cost 4.2 % of a frame the deck fills, where the map's own size costs nothing. That retires the uniforms `clouds_warp_scale/strength`, `clouds_detail_scale/strength/floor` and `clouds_edge_gamma` and the shells.tsv columns `clouds_detail_strength` and `clouds_warp_strength`; a body still setting one is ignored, as any unknown column is. See [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md).
* [shader/gdshaderinc breaking] `shaders/_sun_occlusion.gdshaderinc` takes each occluder's pole-stretched sun direction fed per frame (new `occluder_data_c`, written by IVSunOcclusionManager) rather than deriving it per fragment, which was a normalize and a divide per occluder on every lit pixel of every shader that includes it. A project calling `sun_occlusion_spheroid_fraction()` directly must update the call; one calling only `sun_occlusion_visible_fraction()` needs no change.
* IVSunOcclusionManager no longer feeds receivers that draw nothing, and writes a receiver's ring-shadow texture only when it changes rather than every frame (each write rebuilt the material's uniform set).
* [Project breaking] `IVCoreInitializer.tree_program_nodes` now lists `WorldEnvironment`, which IVSunOcclusionManager and IVExposureManager read from `IVGlobal.program` rather than searching the scene tree — every frame, in the occlusion manager's case, wherever none existed. A project whose WorldEnvironment node has another name must rename it; one without any can remove the entry to silence the startup warning.
* [Project breaking] New shader globals `iv_exposure`, `iv_emission_energy_scale`, `iv_emission_luminance_scale`, `iv_limb_scale`, `iv_display_encode`, `iv_psf_sigma`, `iv_atm_gl_first`, `iv_atm_gl_nodes` and `iv_atm_ring_max_taps`, which the Core editor plugin writes into your project.godot from ivoyager_core.cfg on editor load. Core shaders require these with or without physical light; the default values tell a shader that physical light is inactive, `iv_exposure` also carrying the fixed exposure such a project renders at (2.0, the dark-adapted rest `exposure_max_ev` names, so the sky, the stars and every body's point source sit at one level either way), and `iv_psf_sigma` carries IVPSFSettings.psf_sigma to the shaders that image a body's rim.
* [API breaking] IVStarSettings is renamed IVPSFSettings (`program/psf_settings.gd`, `IVGlobal.program` key `PSFSettings`), and IVStarsVisual's "Star Appearance" export group is now "Point Spread Function". No member, method or signal changed name. The class was never star-specific: it is the camera every source images through, and it now has a second consumer in every body's PSF quad.
* [Project breaking] An "id" shader must write its fragment id through the new `id_broadcast()` in `shaders/_fragment_id.gdshaderinc` rather than assigning the encoded vector to ALBEDO raw, and must draw in the opaque pass, which is all the probe now reads; an id is 30 bits rather than 33. A raw broadcast writes values far above the glow threshold into the buffer the glow pass reads, which blooms a blob at the cursor; `id_broadcast()` carries each channel in [0.5, 1.0] instead, at a cost of one bit per channel. A project that only calls `IVFragmentIdentifier.get_new_id()` / `get_new_id_as_vec3()` needs no change.
* [Table breaking] file_adjustments.tsv is retired. Its last live column was a packed model's scale, which a model name now states directly — `Eros.1_10.glb` is 10 m per glb unit, an untagged model 1 m — read by the new `IVAssetPreloader.parse_model_scale()`. This also fixed Arrokoth, which had no row and so rendered 3 km long instead of 36 km. The other two columns go with it: `map_offset` and its engine plumbing, an equirectangular map having to be centred on the prime meridian anyway; and `disable_auto_visual_range`, replaced by a self-describing rule — a model that wants its own cull distance authors `visibility_range_end` on its own GeometryInstance3D nodes, which now holds in the 2D icon rig as well as in-sim. `IVAssetPreloader.get_body_disable_auto_visual_range()` is removed with it.
* [API breaking] `IVWorldController.mouse_wheel_turned` gained a `factor` argument and now emits once per wheel turn rather than twice (it had fired on both the press and the release of each wheel event). Zoom follows the wheel's reported turn amount, so a trackpad scrolls smoothly instead of in whole notches; one event is capped at a notch, that amount being a platform detail rather than a notch count, and turns accumulate over a frame rather than overwriting. `IVCameraHandler.mouse_wheel_adj` is retuned from 7.5 to 0.125 because wheel zoom no longer scales by frame time; a project that sets it must rescale by the same factor.
* [API breaking] A shell spec from `IVAssetPreloader.get_body_shell_specs()` now carries the shader that will really be bound, the swap to a `cube_shader_variants` entry having moved there from IVShellsModel — which is what lets IVShaderWarmup warm a body's real shaders without re-deriving the asset format. The warning for a cubemap channel whose shader has no cube variant is raised at load rather than on the body's first visit.
* [API breaking] The cubemap variant of the star's surface shader is retired, with the `sun_surface_cube_shader` resource key and its `IVAssetPreloader.cube_shader_variants` entry, and `photosphere.gdshader` drops its `emission` uniform. A star's photosphere is drawn procedurally and no shipped star has a surface map, so both existed only to modulate it with one; a star that ever ships a map needs a shader of its own.
* [API breaking] [Table breaking] `sun_surface.gdshader` is renamed `photosphere.gdshader`, its `IVGlobal.resources` key `sun_surface_shader` becomes `photosphere_shader`, and the `G_STAR` row of shells.tsv names the new key — what the shader draws is a photosphere, and none of it is specific to our own star. A project naming the old key in its own tables or code must update it.
* Attribution docs restructured. IVOYAGER_WORKS.md is retired and replaced by IVOYAGER_ASSETS.md, which documents every distributed asset individually — I, Voyager's own and third-party alike — with what it is, what it was made from, what we did to it, and its own copyright and license, organized by content type rather than by owner. 3RD_PARTY.md keeps the license texts and becomes a clean list by copyright holder and license, each file carrying one short line naming which aspect of it is third-party. These plus CREDITS.md are mirrored here, in our project shells (Planetarium and Project Template), at our [distribution repository](https://github.com/ivoyager/asset_downloads), and within any distribution download itself.
* The near light's shadow reach is tightened in dynamic_lights.tsv: `shadow_max_floor` from 1 to 0.1 km and `shadow_max_target_plus` from 1 to 0.25 km. Reach sets the shadow-map texel size, and a 109 m spacecraft framed from 90 m was getting 1090 m of it, leaving craft self-shadowing several screen pixels soft; the cost is that self-shadowing now fades out past roughly 1 km of camera distance rather than 4 km.
* `IVBody.get_camera_radius()` returns `get_perspective_radius()`, so a body whose visible extent exceeds its radius can set `perspective_radius` in its table row and keep the camera's 1.2-radius floor and near plane clear of its shells. Titan does, for its haze. IVShellsModel also hands every shader shell its geometry (`body_radius_km`, `shell_scale`, `surface_scale`) as uniforms.
* Body-table albedo values: the planets now follow Mallama et al. (2017) V-band geometric albedos and Pluto is corrected from 0.3 to 0.52. Spacecraft and the previously empty asteroid rows (Itokawa, Arrokoth) carry albedos derived from their shipped models' measured render response, so a craft exposes correctly instead of blowing out white. `albedo` is now the published catalog value on every body, exposure metering having been given its own column.
* Exposure fix for the four bodies that ship no surface map. Venus, Titan, Uranus and Neptune had their `albedo_color` set by the asset convention "sphere mean = geometric albedo", which is exact only under Lommel-Seeliger, so all four rendered at the wrong brightness — Titan clipping white over most of its disc. All are relevelled against measured renders. `band_pattern.gdshader` gains the `albedo_ceiling` and `albedo_scale` uniforms this required, since a level above 1.0 is physical here but an sRGB Color cannot hold one.
* Uranus and Neptune gain their own measured limb darkening, each fitted from its own disc in Irwin et al. (2024). `band_pattern.gdshader` carries `lunar_lambert` as well as `minnaert_k`, for the k < 1 direction Minnaert cannot serve.
* Moon surface classes. Ganymede, Callisto, Mimas and Miranda move from `ROCKY_WORLD` to `ICE_WORLD`, and 61 previously unclassified moons gain a class wherever the table's own density or albedo settles it. The 97 with neither stay generic. Side effect worth knowing: surface_classes.tsv's `fallback_triaxial_size` had been reaching zero bodies, and now shapes 28 small moons that have no measured figure of their own.
* Mimas ships as a mesh plus albedo and normal cubemaps, like the other custom-mesh bodies, which is what lets its geometric albedo of 0.962 be stored at all.
* The 2D body-icon rig (IVBody2DCapturer, driving IVBody2DCaptureDialog) renders a staged body the way the simulator does, which an atmosphere made a requirement rather than a nicety. Its camera is perspective instead of orthographic — a shader takes VIEW from the view-space position, so an orthographic projection hands a disc-photometry law a `mu` that reaches zero inside the drawn silhouette, and hands an atmosphere a ray from a point the rasterizer is not looking from. The rig's key light is now also the staged body's sun, which IVSunOcclusionManager otherwise feeds only to bodies in the live scene. `stage_visual()` takes the body's reference radius; pass 0 for a packed craft model, whose table radius is a placeholder.
* [API breaking] Asteroid binaries have a new format, and are now built by `build_asteroid_binaries.py` in the [tools](https://github.com/ivoyager/tools) submodule rather than by the external `ivbinary_maker` project — the whole pipeline, source-data instructions included, is public and scriptable. The files carry a magic number, version and count where the old Godot `store_var` layout carried no validation at all, and load as bulk float blocks plus one name blob instead of one decoded Variant string per asteroid, at 15% fewer bytes per asteroid. Binaries predating this format are skipped with one warning per directory, so an older `ivoyager_assets` yields no asteroids rather than an error. `IVSmallBodiesGroup.s_g_mag_de` is renamed `s_g_mag`, having dropped the eccentricity libration amplitude — AstDyS publishes that amplitude but neither the frequency nor the phase, so nothing could ever have rendered it — which also narrows the CUSTOM2 vertex attribute to `RGB_FLOAT`. A project persisting groups through `ivoyager_save` should rebuild rather than load old saves, the arrays being persisted verbatim with no version gate.
* Asteroid names now come from the JPL Small-Body Database, replacing a PDS file frozen in 2008 whose names stopped at minor planet 175629. 22.5% of the shipped set is named, against 15.7% before.
* Tooltip backgrounds are opaque (new `TooltipPanel` style in `resources/ivoyager_theme.tres`); the engine default is half-transparent black.
* [API breaking] The Shadow Resolution option gains Off, which clears every local shadow map (new static `IVDynamicLight.shadow_maps_enabled`) and frees the atlas's memory, drops 16384 and defaults to 4096 rather than 8192. Its setting `directional_shadow_size` is renamed `shadow_resolution`, and `IVGraphicsManager.shadow_size_settings` becomes `shadow_resolution_settings`, so a choice cached before the change returns to the default rather than being misread. A project that names the setting anywhere must use the new key, where index 0 is Off.
* [Project breaking] Glow halos keep their share of the frame at any render height — window size, 3D render scale or screenshot — on Forward+ and Mobile, where they had been fixed in render pixels: IVWorldEnvironment shifts the Environment's glow levels, as authored for the 1080 reference height, to the render height. Compatibility's glow has no levels to shift. A project that changes glow levels at runtime must call the new `IVWorldEnvironment.set_glow_levels()`; a write to the Environment is overwritten at the next height change. See *Glow: the bloom pass* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md).
* [shader breaking] The atmosphere limb stops paying for the disc interior, where every fragment it drew was discarded: `atmosphere_limb.gdshader` now draws only a camera-facing annulus of its shell around the silhouette, on the new shared `limb_annulus_mesh` that new `IVShellsModel.shader_meshes` pairs with it (rows set by new `IVCoreSettings.limb_annulus_rows`), and renders are unchanged. A project drawing that shader on a mesh of its own must use `limb_annulus_mesh`. See [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md).
* A shell's `process` method is now called once as the shell is built, with a `delta` of 0.0, so nothing reads a shell that has not been posed (`IVShellsModel.process_methods`).
* The GUI Size ladder steps down one (`IVCoreSettings.gui_size_multipliers`): Medium, the default, is what Small was (0.75 of the base sizes), Large is what Medium was, and a new smaller Small (0.625) sits below them, so a `gui_size` already in a user's settings cache names one size smaller than it did. GUI Size now scales the whole GUI rather than its fonts alone — the theme's icons, stylebox content margins and pixel constants (new `IVThemeManager.scale_icons_and_spacing`), and Core's fixed-size buttons and spacers — where check boxes and spacing had stayed one size at every step. A project's own `theme_override_constants` follow it under a new IVControlModSpacing child, and an icon, stylebox or constant it sets on the main theme after init is replaced at the next size change.
* `IVDebug` opens its debug log on the first `dlog()` call rather than at startup, so a run that never logs no longer empties `user://logs/debug.log`, and parallel instances of a project leave it alone.
* IVFullScreenButton, IVOptionsButton and IVHotkeysButton name their hotkey in a tooltip (new static `IVInputMapManager.append_action_key()`), and IVFullScreenButton can be an icon button (new `full_screen_icon` and `minimize_icon`).

### Fixed
* The catalog star field drew only its nearest 4 % of stars, at every fov. `farwarp()` measured distance with `length()`, which sums squares, so it needed the SQUARE of a view-space coordinate to fit float32 — a ceiling of about 345 pc in metre units. Every star beyond it returned `+inf`, the compression then handed back `position * (inf / inf)` = NaN, and the rasterizer dropped the vertex in silence. Since a star without a usable parallax sits on a 1 kpc shell, that was 98 % of the catalog: the field rendered its 49,454 Hipparcos parallax stars and nothing else, which is why it thinned as you zoomed in and why deepening the catalog changed nothing. New `farwarp_length()` divides by the largest component before squaring, which is exact to within a float32 ULP at every distance from 1 m to 1e19 m and costs two `max()`es in a vertex shader. Measured at a 100 mm focal length, the field goes from 441 rendered stars to 25,668.
* Bodies rendered wrong under the Compatibility renderer (including the web export): high-albedo moons blew out to flat white, Saturn came out over-saturated, and an atmosphere lost most of its limb and all of its lit-side softening. That renderer is display-referred at both ends of a shader where Forward+ and Mobile are linear at both, and the two conventions agree only for a value that is merely sampled and multiplied by light. New `shaders/_display.gdshaderinc` is the fix and the only place that decides any of it: a shader decodes what it samples, works in linear, and writes through `display_write()`, gated by the new `iv_display_encode` global and the identity on a renderer that handles its own colour space, so Forward+ and Mobile render bit-identically to before. Saturn's rings and the background panorama take the same treatment, retiring the IVRings Compatibility boost overrides that had been tuned against the old broken pipeline. *Renderer parity* in [PHOTOMETRIC_MODEL.md](PHOTOMETRIC_MODEL.md) carries the measurements and records what the blend still costs — it runs after a shader returns, which is why the air in front of a disc is now composited by the disc's own shaders rather than blended over them.
* Core input handlers no longer push an engine error when an InputMap action is missing. `InputEvent.is_action_pressed()` errors on an unknown action, and every action IVInputMapManager defines is absent until IVCoreInitializer instantiates it — and stays absent in a project that removes or renames one, so a keystroke could error on every press. New IVInputMapManager statics `is_action_pressed()` and `is_action_released()` return false for an unknown action, which also makes `IVShowHideUI.user_toggle_action = &""` disable the toggle as documented rather than error.
* Zooming could throw the camera through its target and out the far side. Distance to target was scaled linearly, so an accumulated zoom-in past 1.0 took the multiplier to zero or negative and flipped the camera's position vector. Scaling is now exponential, which cannot reach zero and also makes zoom in and out exact inverses.
* Every custom-mesh body rendered mirrored in v0.2 — Ceres, Charon, Iapetus, Miranda, Phoebe, Phobos, Deimos and Vesta. The mesh asset pipeline placed longitude as the mirror image of the spheroid pipeline's, which shows on a tidally locked body as a landmark on the wrong side of the sub-planet point (Iapetus' dark face trailed, where Cassini Regio must lead). Corrected in the shipped assets and their builders. IVBodyVisual now also builds one reference basis for both surface paths, and a body mesh is authored as the displaced SphereMesh, so the two frames agree and their maps are interchangeable.
* Every tidally locked moon rendered rotated about its axis — two stacked errors in the lock. The anchor was applied twice: the table builder passed a full anchor as `rotation_at_epoch`, which `create_from_astronomy_specs()` stashes as the offset term `_update_rotations()` adds back on top. And the anchor was measured from the wrong zero: the orbit's raw mean longitude is referenced to the reference plane's node on the ICRF equator (the JPL satellite-elements convention the positions correctly use), while the rotation basis is built from the vernal equinox — a per-plane constant, 131° for Saturn's inner moons. Summed, the sub-parent meridian pointed away from the parent by as much as 150°. The builder now passes only the offset, and the new `IVOrbit.get_vernal_referenced_mean_longitude_at_epoch()` bridges the two frames.
* `substellar_longitude_at_epoch` was applied with the wrong sign, so every planet's spin phase rendered the substellar point at longitude −S instead of S: Earth's clock ran ~10 minutes off, Mars' local time ~5 hours. Moons were unaffected, having no such column.
* Captured 2D body icons carried a dark fringe at every silhouette, and could not show an atmosphere at all. A transparent-background SubViewport hands back premultiplied colour — a partly covered edge texel is the resolve of covered samples against nothing, and an atmosphere limb draws with `blend_premul_alpha` outright — and the readback saved it straight into a PNG, which means straight alpha, so every partly transparent texel composited at `alpha` times its true colour. `IVBody2DCapturer.unpremultiply_alpha()` converts the readback, raising alpha rather than clipping the colour where a thin bright ring's straight colour would exceed white, and the dialog composites its live preview with `BLEND_MODE_PREMULT_ALPHA`. The icon fit also now measures alpha at or above 8/255 rather than any nonzero alpha, so a body is no longer sized by how far its own invisible air reaches.
* Body name labels and symbols washed out under a body's cloud or atmosphere shell — the case that shows is a moon's HUD over its planet's cloud deck. Transparent surfaces sort by `render_priority` before depth, and a HUD sat at the default 0 while IVShellsModel ranks shells upward from it; both the symbol and the name (outline included) now sit at `IVBodyPositionVisual.HUD_RENDER_PRIORITY`, clear of the shell range.
* Body name labels and symbols drew over the sun, labelling bodies that were behind it. `photosphere.gdshader` writes ALPHA for the disc/point crossfade, which puts it in the transparent pass, where its `depth_draw_opaque` wrote no depth at all and left occlusion to paint order — so the disc covered the orbit lines and bodies below it but nothing at a higher `render_priority`, which is where HUDs have sat since the fix below. It now draws depth (`depth_draw_always`); the IVBodyPSF quad it hands off to is unaffected.
* IVControlModResizable resolved anchors against the viewport, so a Control whose parent doesn't fill the screen — one under a persistent menu bar, say — was repositioned out of bounds by the parent's own offset. `Control.position` is parent-relative, so a Control parent's size is now the reference; the viewport remains the fallback.
* A body's rim came apart wherever the lit sliver was thinner than a pixel: points and broken dashes with the sun within a radius or so of the limb, full-brightness pixels speckling a backlit rim and trailing off a crescent's tips as glow-amplified dashes, and an atmosphere's beyond-limb ring breaking into coloured fragments on Earth or Titan from a few tens of radii out. One shading sample per pixel decided that sliver by where the sample happened to land — the shading RATE is what is short, not coverage, which is why no MSAA setting touched it. The surface, cube-surface, band-pattern and cloud-shell shaders now image each rim pixel through the camera's own PSF (`limb_mean_incidence()` in `shaders/_photometry.gdshaderinc`), `atm_limb()` averages the beyond-limb ring over each pixel's own altitude footprint, and the body's PSF quad carries the outward half of that spread, which a surface has no fragment for — so a bright rim reads as a continuous line of the width the size law gives it, a faint one trails off through intermediate values, a backlit one gets no light at all, and a crescent hands off to the body's distant point source without a step.
* Shader compile times cut for the atmosphere and sun shaders under the Compatibility renderer, and above all in the web export on Windows, where Chrome's shader compiler inlines every call. `_atmosphere.gdshaderinc` now reaches each heavy function from one call site, and its loop bounds, with `photosphere.gdshader`'s and `_photometry.gdshaderinc`'s limb kernel's, are `uniform int`s the GL compiler cannot unroll (`iv_atm_gl_first`, `iv_atm_gl_nodes`, `atm_shell_nodes`, `iv_atm_ring_max_taps`, `spot_cell_reach`, `limb_kernel_cells`). Renders are unchanged; see *What drives the cost* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).
* Every asteroid's mean longitude ran fast by its own perihelion precession rate. AstDyS publishes `n` as the rate of the mean *longitude*, but `orbiting_positions_id.gdshader` advanced mean anomaly at `n` while also precessing the longitude of perihelion at `g`, so each asteroid gained `g` per unit time. The visible casualty was the Hildas, whose published `g` is not a secular precession at all but the rate that holds the 3:2 resonance stationary — they drifted 1344° over 3000 BC – 3000 AD where they should drift 5° — and a blanket ÷3 on every group's `s` and `g` in `IVSmallBodiesGroup.append_data`, marked in code as working for an unknown reason, had been hiding it: dividing `g` by three is the same correction, but only for a 3:2 resonance, and it left the other ~78,000 asteroids precessing at a third of their catalog rate. The divisor is gone, the shader uses `n - g`, and `get_mean_anomaly_rate()` is the CPU-side equivalent.
* Jupiter Trojan libration phase was a random number. `θ₀` is now solved per member from its own osculating semi-major axis and mean longitude at the source epoch, which oscillate in quadrature about Jupiter's, so each Trojan renders at its true mean longitude instead of somewhere on its libration cycle.
* `IVSBGPositionsVisual` pushed an engine error for a group with no members, `add_surface_from_arrays()` rejecting a zero-vertex surface. It now warns and draws no points, which is what an asset set older than the current binary format leaves behind.
* Repeated `bad comparison function; sorting will be broken` errors in debug builds, and an arbitrary draw order among farwarp items. Godot takes an instance's sort depth from the centre of its transformed AABB, and the always-pass `custom_aabb` every farwarp consumer sets collapses that centre to a constant in f32 — shells models, rings, path visuals, SBG points and orbit lines, the star field and the PSF quads were all reporting one identical depth, which for the transparent ones is an arbitrary blend order and for the opaque ones a lost front-to-back pass. Each now pairs its `custom_aabb` with `sorting_use_aabb_center = false`; see the farwarp obligations in [VISUAL_MODEL.md](VISUAL_MODEL.md).
* IVDynamicLight printed Godot's `Target and up vectors are colinear` warning every frame the camera sat on its star's ±y axis, and now and then at startup. It aimed with the default up vector, +y, which lies in the ecliptic plane most views share with their star; it now takes ecliptic north, falling back to +y only in a view straight down the star's pole.
* IVCamera printed the same warning every frame it sat exactly over a pole of its reference frame, which a view or `move_to` can ask for though the up-locked camera's own motion stops short of it. Near a pole it now takes its up from its own meridian, which rolls it exactly as north does elsewhere.
* Earth did not render identically in two sessions at the same date, and a cloud deck's shadow drifted away from the cloud casting it. `IVShellsModel._rotate` integrated per-frame deltas into the shell's basis, so a deck's phase was the session's frame history rather than the clock — `set_time` left the deck behind, and the surface's shadow lookup carried no phase term at all, so at Earth's drift rate the shadow fell 26° further behind per sim day, unbounded. Both sides now resolve the phase through the one closed form `IVShellsModel.get_spin()`, the shader through the new `clouds_shadow_spin` uniform, which also means a deck sits at the longitude its date gives it rather than the one it was built at; see *The cloud deck's phase* in [VISUAL_MODEL.md](VISUAL_MODEL.md).
* Mouse-over identification of orbit lines and asteroids (IVFragmentIdentifier) looked in the wrong place, or found nothing, whenever the 3D render scale was below 100%, and missed any line or point seen through a transparent draw, such as an atmosphere limb or a ring, or through Environment fog. See *Mouse picking* in [VISUAL_MODEL.md](VISUAL_MODEL.md).
* Headless runs before Godot 4.8 corrupted the dummy renderer's mesh and material RIDs, printing `Attempting to initialize the wrong RID` errors and RIDs leaked at exit, more of them the more games a run built. IVBodyFinisher now finishes bodies on the main thread there, since that renderer can't create RIDs on two threads at once ([godotengine/godot#121949](https://github.com/godotengine/godot/issues/121949)).
* IVSaveManager permitted a gamesave load before `IVStateManager.ok_to_start`, as early as during asset preloading; it now waits for it.
* [ivoyager_assets] Five packed models — Hubble, the ISS, Hyperion, Bennu and Arrokoth — compiled a shader that drew nothing: each carried a glTF `emissiveFactor` of `[0, 0, 0]`, which Godot's importer takes as emission on, giving their materials a key of their own and a Compatibility first run 3.3 s more to compile through ANGLE. The zero factors are dropped from the models, which takes effect with the next asset release. See *What a first run costs* in [GRAPHICS_PROFILING.md](GRAPHICS_PROFILING.md).

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
