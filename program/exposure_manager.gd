# exposure_manager.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield
# I, Voyager is a registered trademark of Charlie Whitfield in the US
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *****************************************************************************
class_name IVExposureManager
extends Node

## Physical light with a software compensating camera: per-frame CPU metering
## drives a relative exposure so bodies filling a significant screen fraction
## are correctly exposed while stars and the Milky Way dim (or vanish) exactly
## as a real camera's image would.
##
## The photometric frame is the star field's: catalog V magnitudes through the
## camera PSF model ([IVStarSettings]), anchored by
## [constant IVAstronomy.MAG0_ILLUMINANCE]. One member welds everything else to
## that frame - [member background_peak_magnitude_per_arcsec2], the surface
## brightness of the background panorama's brightest texel - from which this
## node derives [member sky_energy] (the panorama's physical energy_multiplier)
## and [member gain] (rendered units per unit luminance). Sunlight, the sun
## disc, ambient and emission then follow from catalog data with no per-source
## tuning.[br][br]
##
## [member exposure] is RELATIVE: 1.0 is the authored empty-sky look, and the
## camera RESTS fully dark-adapted at 2^[member exposure_max_ev] above it -
## the empty-sky and deep-night state. Metering only ever pulls exposure DOWN
## from that rest: sunlit bodies pull hardest (stars vanish over inner-system
## bodies), dim outer bodies less, starlit night terrain barely or not at all.
## The lit and dark portions of a body meter as separate candidates, each with
## its own surface luminance weighted by its own share of screen area, so
## adaptation responds to how much lit surface is in the view - not to phase
## geometry, and not to the star, whose disc clips white at any scene exposure
## and so meters only when it grows into the subject.[br][br]
##
## Metering and adaptation produce [member auto_exposure_ev]; what is applied
## is 2^([member auto_exposure_ev] or [member manual_exposure_ev], per
## [member auto], plus [member exposure_adjustment_ev]). The defaults - auto,
## no adjustment - make [member exposure] the metered result itself.[br][br]
##
## Writers and readers, one frame-consistent set per frame:[br]
## - Writes the [code]iv_exposure[/code] shader global, which every photometric
##   shader multiplies into its self-luminous output (stars, sun point and
##   disc, sky panorama) - and [code]iv_emission_luminance_scale[/code]
##   ([member exposure] x [member gain]), which renders an emission map at the
##   cd/m^2 its shells.tsv emission_luminance column asserts, paired with
##   [code]iv_emission_energy_scale[/code] (0.0 while active), which retires
##   the by-eye emission_energy_multiplier channel, and [code]iv_limb_scale[/code]
##   (0.0 while active, 1.0 otherwise), the gate on the atmosphere shells' by-eye
##   taste multipliers: the physical parameters alone render under physical light.[br]
## - Drives the Environment ambient energy per frame (starlight level x
##   [member exposure]): engine ambient then compensates StandardMaterial3D
##   craft models, and [IVSunOcclusionManager]'s ambient_light feed hands the
##   same value to the custom body shaders, which rebuild it with no further
##   exposure factor.[br]
## - [IVDynamicLight] reads the statics to carry exposure in
##   [code]light_energy[/code], so lit surfaces need no shader term (and
##   unshaded HUD elements are untouched by construction).[br]
## - [IVShellsModel] sun-mode reads the statics for the disc's physical
##   surface brightness and the disc/point handoff.[br]
## - On activation this node captures and replaces the by-eye scene values it
##   supersedes (starmap energy, Environment ambient, and the Compatibility
##   tonemap_exposure offset, which post-multiplies HUD and is retired while
##   active); deactivation restores the captured values.[br][br]
##
## Processes at priority -1, BEFORE the camera, lights and body visuals (0):
## metering consumes only camera-relative distances (origin-shift invariant),
## and this ordering hands lights, sun visuals, and the shader global one
## consistent exposure for the same rendered frame. The cost is metering on the
## previous frame's settled geometry - the same one-frame-lag convention as
## [IVDynamicLight]'s occlusion factor.[br][br]
##
## Gating: [member IVCoreSettings.enable_physical_light] false (default) erases
## this node from [IVCoreInitializer] - zero cost, statics stay inert. When the
## node exists, the cached user setting [code]&"physical_light"[/code] toggles
## the system at runtime. Activation requires
## [member IVCoreSettings.dynamic_lights].[br][br]
##
## Caveat, single star: metering illuminates every body from the camera's
## star, consistent with the one-star limit documented in
## [code]_sun_occlusion.gdshaderinc[/code].[br][br]
##
## Caveat, icon capture: [code]iv_exposure[/code] is a rendering-server global,
## so [IVBody2DCaptureManager] SubViewport captures are exposed by it too.
## Toggle the physical_light user setting off before capturing icons (dev tool;
## inert outside source runs).

## Current relative exposure; the value written to the [code]iv_exposure[/code]
## shader global. 1.0 whenever inactive. Read-only.
static var exposure := 1.0
## The metered and adapted auto exposure, in EV relative to the authored sky
## look (log2 of the exposure it alone would apply): rests at
## [member exposure_max_ev] fully dark-adapted and falls as metering pulls
## exposure down. Updated every frame while active, whether or not
## [member auto] is true. Read-only.
static var auto_exposure_ev := 0.0
## True while the system is applied (core setting + user setting + activation
## requirements all satisfied). Read-only.
static var physical_active := false
## Rendered units per unit internal luminance, derived from [IVStarSettings]
## and the anchor; 0.0 until first activation. Read-only.
static var gain := 0.0
## The background panorama's physical energy_multiplier (at exposure 1.0),
## derived from [IVStarSettings] and the anchor; 0.0 until first activation.
## Read-only.
static var sky_energy := 0.0

## If false, [member manual_exposure_ev] replaces the metered result. Metering
## runs either way, so [member auto_exposure_ev] stays live and a return to
## auto resumes without a settling delay.
var auto := true
## The exposure applied while [member auto] is false, in EV relative to the
## authored sky look; ignored otherwise. A GUI taking manual control should
## seed this from [member auto_exposure_ev] so the view does not jump.
var manual_exposure_ev := 0.0
## Added to whichever of [member auto_exposure_ev] or [member manual_exposure_ev]
## is in force. This is the viewer's exposure compensation rather than something
## the camera adapts to, so it applies instantly.
var exposure_adjustment_ev := 0.0

## The absolute anchor: V surface brightness (mag/arcsec^2) represented by the
## background panorama's brightest texel (value 1.0). Initial value from
## photographic photometry of the brightest extended bulge patches (Sgr/Sct
## star clouds, ~19.5-20.5) pending measured refinement against LMC/SMC/M31
## levels in the shipped map.
var background_peak_magnitude_per_arcsec2 := 20.0
## Rendered value a fully-metered body's mean luminance lands at (mid-exposure
## target, in [0, 1] display terms).
var metering_key := 0.5
## Screen-area fraction at which a body begins to influence metering. The
## weight ramp runs in LOG fraction space between here and
## [member meter_fraction_full], so the transition spreads evenly across the
## decades between the two edges (approach distance factor
## sqrt(full/start)) rather than bunching against the upper edge.
var meter_fraction_start := 1e-5
## Screen-area fraction at which a body fully drives metering (this is the
## "how much screen before the camera fully compensates" knob).
var meter_fraction_full := 0.005
## Screen-area fraction at which the star's disc begins to influence metering
## (with [member star_meter_fraction_full], a much later ramp than the body
## one). The star's disc clips white at any scene exposure, so it is never
## "lit surface" to adapt to; it meters only once it grows into the subject
## of the view. Without the later onset, a sun speck in (or near) frame
## black-crushes the scene: Mercury's day side metered ~5 EV under its own
## target, and night-side approaches stayed dark until the sun crossed the
## limb, then jumped.
var star_meter_fraction_start := 0.005
## Screen-area fraction at which the star's disc fully drives metering (a
## deliberate close approach; VIEW_ZOOM framing is ~0.2).
var star_meter_fraction_full := 0.2
## Screen-area fraction at which an atmosphere limb begins to hold its shell's
## [code]limb_exposure_ceiling[/code] (with [member limb_meter_fraction_full],
## a far later ramp than the body one). The fraction is the limb shell's own
## on-screen area scaled by the share of the limb that is sunlit, forward-scattering
## and inside the frame, so what it measures is the LIMB as a subject and not the
## body: zoom inside the ring, pan it out of frame, or swing round to where the sun
## is behind the camera, and the ceiling releases entirely.
## The late ramp is the "how much more readily than a disc may a limb clip"
## knob - the camera compensates for a limb only where the limb is the view.
var limb_meter_fraction_start := 0.05
## Screen-area fraction at which an atmosphere limb fully holds its shell's
## [code]limb_exposure_ceiling[/code]; see [member limb_meter_fraction_start].
## Roughly the body framed at the default view zoom with its lit limb in frame.
var limb_meter_fraction_full := 0.5
## The screen-edge gate on every candidate's metering weight: a body influences
## exposure only while its disc is actually inside the frame, ramping from zero
## as the disc crosses the frame edge to full influence when its center is this
## fraction of the frame dimension inside. Panning toward a bright body, it
## enters the frame still overexposed and compensation completes as it moves
## in; a body just OUT of frame never meters (it can't - the same gate is what
## keeps an off-frame sun from black-crushing the view).
var meter_edge_fraction := 0.15
## The screen-edge gate on the limb ring's own samples (taken at the limb's
## foot), standing in for
## [member meter_edge_fraction] on that one candidate: how far inside the frame
## a piece of lit limb must sit to count in full. Wider than the body gate
## because it does a second job - centrality, which is half of what makes a
## limb the subject of a view rather than something at its corner. At 0.5 only
## a ring through the middle of the frame counts at all.
var limb_meter_edge_fraction := 0.25
## Exposure adaptation rate (EV/s) when darkening (a bright body entering).
## In WALL-CLOCK seconds, not [IVUnits]: an adaptation rate describes the
## viewer's eye, not the simulation, so [method _process] divides its delta by
## [member Engine.time_scale] and this rate is measured against that. Scaling it
## by [constant IVUnits.SECOND] would be the bug, not the fix.
var adapt_darken_ev_per_second := 16.0
## Exposure adaptation rate (EV/s) when brightening (bright body leaving); see
## [member adapt_darken_ev_per_second] for why this is not an [IVUnits] quantity.
var adapt_brighten_ev_per_second := 8.0
## Target jumps larger than this (EV) apply instantly - camera teleports and
## view restores snap rather than adapt.
var snap_ev_threshold := 6.0
## Albedo assumed for bodies without an [code]albedo[/code] table value.
var default_albedo := 0.3
## The ring metering candidate's base reflectance: the bright-ring level
## (area-weighted 90th percentile x transparency) of the lit-side backscatter
## profile, BEFORE the shader's phase boost, which the candidate mirrors per
## frame - the boosted product near opposition well exceeds any Lambert
## sphere's albedo, which is why lit rings clip white when only the globe
## meters. Anchored at the bright-ring level rather than the ring mean so
## metering protects the B-ring highlights; the fainter rings then render
## mid-dim, as real photographs show them. Measured from the shipped Saturn
## assets.
var ring_meter_albedo := 0.55
## The camera's fully dark-adapted exposure, in EV above the authored sky
## look (exposure 1.0): the RESTING exposure with nothing metered - the empty
## sky far from any body - and the bound that night-side metering rides to,
## so deep night and deep space are one continuous state. Metering only ever
## pulls exposure DOWN from here. 0.0 rests at the authored sky look (night
## sides stay black); the physical camera would keep adapting until starlit
## terrain is mid-exposed (~9-11 EV depending on albedo), blowing out the
## Milky Way on the way.
var exposure_max_ev := 3.0
## Shapes the exposure path across the metering weight ramp: 1.0 spends EV
## uniformly across the (log-space) screen-fraction ramp, which reads as
## instant saturation on zoom-out - a fully-metered body has only ~1 EV of
## headroom before clipping white while the stars need the last several EV, so
## the body blows out in a tick of the wheel and stars then crawl in. Higher
## values hold near the metered exposure longer (a gradual climb into
## overexposure) and spend the star-revealing EV quickly at the small-fraction
## end.
var meter_transition_exponent := 2.0
## Visible lit disc fraction below which night adaptation begins. With more
## lit surface than this in view, the lit surface fully holds its daylight
## exposure; below it, the hold releases (in log space) down to
## [member nightside_full_lit_fraction], so exposure responds to how much lit
## surface remains in view and dark-side terrain and stars emerge while the
## sun is still well above the limb. The default begins the walk into night
## right past half phase.
var nightside_onset_lit_fraction := 0.5
## Visible lit disc fraction below which the camera is fully dark-adapted (at
## [member exposure_max_ev]) and the remaining crescent overexposes freely.
## The default reaches full night while the sun is still a few degrees above
## the limb at low altitude.
var nightside_full_lit_fraction := 0.05
## Angular width of the horizon fade on a body's visible lit area: close in,
## the lit crescent sinks behind the horizon just past the terminator, and
## this is how much orbital travel spans that geometric cutoff. It trims the
## tail of the night transition - most of the adaptation comes earlier, from
## the lit fraction falling through the ramp above.
var nightside_twilight_angle := 20.0 * IVUnits.DEG
## Integrated starlight illuminance for ambient, in internal units
## (~2e-4 lux; sky-integrated V-band starlight). Also the illuminance floor of
## body metering: a fully dark body meters as starlit terrain, which is what
## exposure rides toward (up to [member exposure_max_ev]) on a night side.
var ambient_starlight_illuminance := 2e-4 * IVUnits.CANDELA / IVUnits.METER ** 2

var _camera: Camera3D
var _star: IVBody
var _world_environment: WorldEnvironment # persistent scene node; found lazily
var _starmap_material: ShaderMaterial # exists only after assets_preloaded
var _transition_dirty := true # settings are cached before _ready; apply on first frame
var _snap_next := false
var _warned_off_nominal := false
var _captured_starmap_energy := NAN
var _captured_ambient_energy := NAN
var _captured_tonemap_exposure := NAN
var _ambient_energy_base := 0.0 # Environment ambient at exposure 1.0; x exposure per frame
var _ring_meter_data: Dictionary[StringName, Vector2] = {} # body name -> (inner, outer) radius
var _ring_meter_data_built := false
var _limb_geometry: Dictionary[StringName, Vector2] = {} # body name -> (disc, shell) radius
var _exposure_ceilings: Dictionary[StringName, Array] = {} # body name -> [(shell radius, ceiling)]
var _limb_ceilings: Dictionary[StringName, float] = {} # body name -> limb_exposure_ceiling
var _shell_meter_data_built := false
var _ring_litside_phase_boost := 3.0 # rings.gdshader default


func _ready() -> void:
	process_priority = -1 # before camera/lights/visuals (0); see class doc
	IVGlobal.current_camera_changed.connect(_on_current_camera_changed)
	IVGlobal.camera_tree_changed.connect(_on_camera_tree_changed)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVStateManager.assets_preloaded.connect(_on_assets_preloaded)
	IVSettingsManager.changed.connect(_settings_listener)
	var star_settings := _get_star_settings()
	if star_settings:
		star_settings.changed.connect(_on_star_settings_changed)


func _exit_tree() -> void:
	if physical_active:
		_restore_scene_values()
		physical_active = false
	exposure = 1.0
	auto_exposure_ev = 0.0
	_neutralize_shader_globals()


func _process(delta: float) -> void:
	# Activation/deactivation applies here rather than in the settings listener:
	# a toggle while a PAUSABLE-universe project is paused must not write into a
	# scene whose lights and visuals are frozen.
	if _transition_dirty:
		_apply_transition()
	if !physical_active:
		return
	var time_scale := Engine.time_scale
	if time_scale > 0.0:
		delta /= time_scale # adaptation rates are wall-clock
	_update_auto_exposure(_get_metering_target(), delta)
	_apply_exposure()


# *****************************************************************************
# Transitions & derived photometry


func _apply_transition() -> void:
	_transition_dirty = false
	var activate: bool = IVSettingsManager.get_setting(&"physical_light")
	if activate == physical_active:
		return
	if activate:
		if !IVCoreSettings.dynamic_lights:
			push_warning("IVExposureManager: physical light requires IVCoreSettings.dynamic_lights"
					+ "; staying inactive")
			return
		if !_recompute_photometry():
			return
		_build_ring_meter_data()
		_build_shell_meter_data()
		_capture_and_apply_scene_values()
		# The atmosphere's output is I/F riding light_energy like a surface; no rebase. The
		# global only gates the shells' nonphysical taste multipliers off (see _atmosphere.gdshaderinc).
		RenderingServer.global_shader_parameter_set(&"iv_limb_scale", 0.0)
		RenderingServer.global_shader_parameter_set(&"iv_emission_energy_scale", 0.0)
		_snap_next = true
		physical_active = true
	else:
		_restore_scene_values()
		physical_active = false
		exposure = 1.0
		auto_exposure_ev = 0.0
		_neutralize_shader_globals()


## Returns false (with warning) if prerequisites are missing.
func _recompute_photometry() -> bool:
	var star_settings := _get_star_settings()
	if !star_settings:
		push_warning("IVExposureManager: no StarSettings in IVGlobal.program; staying inactive")
		return false
	if !_warned_off_nominal and (star_settings.intensity_gamma != 1.0
			or star_settings.fov_compensation != 1.0):
		_warned_off_nominal = true
		push_warning("IVExposureManager: IVStarSettings intensity_gamma/fov_compensation differ "
				+ "from 1.0; the physical calibration assumes the photometric values")
	# The star chain's fov/resolution compensation is exactly the inverse pixel
	# solid angle of the PSF (a fixed-f-number camera), so the panorama's level
	# reduces to the star photometry evaluated at the map's per-texel equivalent
	# magnitude - the anchor minus 2.5*log10 of the reference pixel's arcsec^2.
	# omega_ref uses the same reference fov and viewport height the star
	# shaders compensate against, which is what makes the result view-invariant.
	var reference_height := _get_reference_viewport_height()
	var arcsec_per_pixel := star_settings.fov_reference_deg * 3600.0 / reference_height
	var omega_ref := arcsec_per_pixel * arcsec_per_pixel
	var psf_area := TAU * star_settings.psf_sigma * star_settings.psf_sigma
	sky_energy = (star_settings.intensity_scale * psf_area * omega_ref
			* 10.0 ** (0.4 * (star_settings.intensity_faint_mag
			- background_peak_magnitude_per_arcsec2)))
	var anchor_luminance := IVAstronomy.get_luminance_from_surface_brightness(
			background_peak_magnitude_per_arcsec2)
	gain = sky_energy / anchor_luminance
	return true


func _capture_and_apply_scene_values() -> void:
	_find_world_environment()
	if _world_environment and _world_environment.environment:
		var environment := _world_environment.environment
		if is_nan(_captured_ambient_energy):
			_captured_ambient_energy = environment.ambient_light_energy
		if IVGlobal.is_gl_compatibility and is_nan(_captured_tonemap_exposure):
			# The by-eye Compatibility brightness offset is a post-tonemap stage
			# that also brightens HUD; the physical chain replaces it.
			_captured_tonemap_exposure = environment.tonemap_exposure
			environment.tonemap_exposure = 1.0
		_apply_ambient()
	_apply_starmap_energy()


func _restore_scene_values() -> void:
	if _world_environment and _world_environment.environment:
		var environment := _world_environment.environment
		if !is_nan(_captured_ambient_energy):
			environment.ambient_light_energy = _captured_ambient_energy
			_captured_ambient_energy = NAN
		if !is_nan(_captured_tonemap_exposure):
			environment.tonemap_exposure = _captured_tonemap_exposure
			_captured_tonemap_exposure = NAN
	if _starmap_material and !is_nan(_captured_starmap_energy):
		_starmap_material.set_shader_parameter(&"energy_multiplier", _captured_starmap_energy)
		_captured_starmap_energy = NAN


func _apply_ambient() -> void:
	# The Environment is the single ambient authority while active: the
	# occlusion manager re-reads it each frame and feeds the ambient_light
	# uniform to the custom body shaders, and engine ambient delivers the same
	# value to StandardMaterial3D craft models. The energy therefore carries
	# exposure itself (rewritten each frame in _update_exposure) - the fed
	# uniform is applied by receivers with NO further exposure factor. Color is
	# left as authored (a chromaticity choice, not a level).
	_ambient_energy_base = ambient_starlight_illuminance / PI * gain
	var environment := _world_environment.environment
	environment.ambient_light_energy = _ambient_energy_base * exposure


## Lazy: the starmap sky exists only after assets_preloaded, and only if the
## project adds one at all.
func _apply_starmap_energy() -> void:
	if !_starmap_material:
		_find_starmap_material()
		if !_starmap_material:
			return
	var current_var: Variant = _starmap_material.get_shader_parameter(&"energy_multiplier")
	if is_nan(_captured_starmap_energy) and typeof(current_var) == TYPE_FLOAT:
		var current: float = current_var
		_captured_starmap_energy = current
	_starmap_material.set_shader_parameter(&"energy_multiplier", sky_energy)


## Ring metering geometry from rings.tsv, built once on first activation
## (tables are fully postprocessed long before any runtime toggle).
func _build_ring_meter_data() -> void:
	if _ring_meter_data_built:
		return
	_ring_meter_data_built = true
	if !IVTableData.table_n_rows.has(&"rings"):
		return
	for row in IVTableData.get_n_rows(&"rings"):
		var inner_radius := IVTableData.get_db_float(&"rings", &"inner_radius", row)
		var outer_radius := IVTableData.get_db_float(&"rings", &"outer_radius", row)
		var ring_bodies: Array[StringName] = IVTableData.get_db_array(&"rings", &"bodies", row)
		for ring_body_name: StringName in ring_bodies:
			_ring_meter_data[ring_body_name] = Vector2(inner_radius, outer_radius)


func _build_shell_meter_data() -> void:
	# What the camera needs per shell, from one walk of the shells table (the tables, not
	# IVAssetPreloader, which holds a lazily modelled body's resources only once it is
	# seen): every shell's exposure_ceiling, and, for a body with an atmosphere limb shell,
	# its disc and shell radii and that shell's limb_exposure_ceiling, which rides on those
	# rather than on the body.
	if _shell_meter_data_built:
		return
	_shell_meter_data_built = true
	if !IVTableData.table_n_rows.has(&"shells"):
		return
	for table in IVCoreSettings.body_tables:
		for row in IVTableData.get_n_rows(table):
			var shell_tags: Array = IVTableData.get_db_array(table, &"shells", row)
			if shell_tags.is_empty():
				continue
			var body_name := IVTableData.get_db_entity_name(table, row)
			var mean_radius := IVTableData.get_db_float(table, &"mean_radius", row)
			if !(mean_radius > 0.0):
				continue
			var surface_scale := 1.0
			var limb_row := -1
			var limb_scale := 1.0
			var ceilings: Array[Vector2] = []
			for tag: String in shell_tags:
				var shell_row := IVTableData.get_row(StringName("SHELL_%s_%s" % [body_name, tag]))
				if shell_row == -1:
					continue
				var shell_scale := 1.0
				if IVTableData.db_has_value(&"shells", &"scale", shell_row):
					shell_scale = IVTableData.get_db_float(&"shells", &"scale", shell_row)
				if IVTableData.get_db_bool(&"shells", &"shell0", shell_row):
					surface_scale = shell_scale
				elif IVTableData.get_db_string_name(&"shells", &"shader", shell_row) == &"atmosphere_limb_shader":
					limb_row = shell_row
					limb_scale = shell_scale
				if IVTableData.db_has_value(&"shells", &"exposure_ceiling", shell_row):
					ceilings.append(Vector2(mean_radius * shell_scale,
							IVTableData.get_db_float(&"shells", &"exposure_ceiling", shell_row)))
			if ceilings:
				_exposure_ceilings[body_name] = ceilings
			if limb_row == -1:
				continue
			_limb_geometry[body_name] = Vector2(mean_radius * surface_scale,
					mean_radius * limb_scale)
			if IVTableData.db_has_value(&"shells", &"limb_exposure_ceiling", limb_row):
				_limb_ceilings[body_name] = IVTableData.get_db_float(&"shells",
						&"limb_exposure_ceiling", limb_row)


func _find_world_environment() -> void:
	if is_instance_valid(_world_environment):
		return
	_world_environment = null
	for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_world_environment = node as WorldEnvironment
		break


func _find_starmap_material() -> void:
	_find_world_environment()
	if !_world_environment or !_world_environment.environment:
		return
	var sky := _world_environment.environment.sky
	if !sky:
		return
	var sky_material := sky.sky_material
	if sky_material is ShaderMaterial:
		_starmap_material = sky_material


func _get_star_settings() -> IVStarSettings:
	var star_settings_var: Variant = IVGlobal.program.get(&"StarSettings")
	if star_settings_var is IVStarSettings:
		return star_settings_var
	return null


func _get_reference_viewport_height() -> float:
	# ProjectSettings, not RenderingServer.global_shader_parameter_get(): the
	# latter is editor-only and returns null in a running project.
	var setting_var: Variant = ProjectSettings.get_setting(
			"shader_globals/iv_reference_viewport_height")
	if typeof(setting_var) == TYPE_DICTIONARY:
		var setting_dict: Dictionary = setting_var
		var value_var: Variant = setting_dict.get("value")
		if typeof(value_var) == TYPE_FLOAT:
			var value: float = value_var
			return value
	return 1080.0


# *****************************************************************************
# Metering


## Returns the target exposure for the current frame's view: the dark-adapted
## rest 2^exposure_max_ev with nothing metered, pulled down toward the
## strongest weighted candidate otherwise.
func _get_metering_target() -> float:
	var rest_exposure := 2.0 ** exposure_max_ev
	if !_camera or !_star:
		return rest_exposure
	var star_absolute_magnitude := _get_star_absolute_magnitude()
	if is_nan(star_absolute_magnitude) or gain <= 0.0:
		return rest_exposure
	var viewport := _camera.get_viewport()
	if !viewport:
		return rest_exposure
	var view_size := viewport.get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return rest_exposure
	var tan_half_fov := tan(deg_to_rad(_camera.fov) * 0.5)
	var aspect := view_size.x / view_size.y
	# Disc area over screen area: PI * theta^2 / (4 * tan^2(fov/2) * aspect).
	var fraction_per_theta_sq := PI / (4.0 * tan_half_fov * tan_half_fov * aspect)
	var star_position := _star.global_position
	var camera_position := _camera.global_position
	var log_rest := log(rest_exposure)
	var min_exposure := rest_exposure
	for body_name: StringName in IVBody.bodies:
		var body := IVBody.bodies[body_name]
		if !body.visible or body.mean_radius <= 0.0:
			continue
		var camera_vector := body.global_position - camera_position
		var camera_distance := camera_vector.length()
		if camera_distance <= 0.0:
			continue
		var angular_radius := minf(body.mean_radius / camera_distance, 1.0)
		var screen_fraction := fraction_per_theta_sq * angular_radius * angular_radius
		# Screen-edge gate (a weight factor on every candidate): metering
		# responds only to what is in the frame. A body behind the camera or
		# beyond a frame edge - the sun above and behind, most of all - must
		# not drag exposure, and a body panning IN arrives still overexposed,
		# completing compensation meter_edge_fraction inside the frame.
		var view_factor := _get_view_factor(body.global_position, angular_radius,
				view_size, tan_half_fov, aspect)
		if view_factor <= 0.0:
			continue
		if body.flags & IVBody.BodyFlags.BODYFLAGS_STAR:
			if body != _star:
				continue
			# A star hidden behind a body must not meter (on a night side the
			# sun is occluded by the planet itself); an area term (one-frame
			# lag, same convention as IVDynamicLight).
			screen_fraction *= IVSunOcclusionManager.camera_sun_visible_fraction
			var star_weight := view_factor * _get_ramp_weight(screen_fraction,
					star_meter_fraction_start, star_meter_fraction_full)
			if star_weight <= 0.0:
				continue
			var disc_luminance := IVAstronomy.get_star_disc_luminance(
					star_absolute_magnitude, body.mean_radius)
			min_exposure = minf(min_exposure, _get_candidate_exposure(disc_luminance,
					star_weight, log_rest, rest_exposure))
			continue
		var star_vector := star_position - body.global_position
		var star_distance := star_vector.length()
		if star_distance <= 0.0:
			continue
		# The lit and dark portions meter as separate candidates: each with
		# the luminance OF that surface (not a disc average diluted by phase)
		# weighted by ITS OWN screen area. Exposure therefore responds to how
		# much lit surface is in view: the lit candidate holds daylight
		# exposure only while lit area holds significant screen fraction, and
		# releases along the same ramp as any shrinking body - well before
		# the sun reaches the limb - while never overexposing a half-lit
		# face the way disc-average metering does.
		var lit_visible := _get_lit_visible_fraction(body, star_vector, star_distance,
				camera_vector, camera_distance)
		var albedo := _get_albedo(body)
		var apparent_magnitude := IVAstronomy.get_apparent_magnitude(
				star_absolute_magnitude, star_distance)
		var illuminance := IVAstronomy.get_illuminance_from_apparent_magnitude(
				apparent_magnitude)
		var shadow_fraction := _get_parent_shadow_fraction(body, star_vector, star_distance)
		# Ambient starlight is the floor of both candidates: eclipse shadow
		# removes sunlight, not starlight, matching the shaders.
		var lit_luminance := albedo * (illuminance * shadow_fraction
				+ ambient_starlight_illuminance) / PI
		# The lit candidate's hold weakens as the lit share of the disc falls
		# (the nightside_*_lit_fraction ramp): lit AREA alone collapses within
		# a few degrees of the terminator, which read as an abrupt plunge;
		# the lit disc FRACTION falls gradually across the whole back swing.
		var lit_hold := _get_ramp_weight(lit_visible, nightside_full_lit_fraction,
				nightside_onset_lit_fraction)
		var lit_weight := view_factor * lit_hold * _get_ramp_weight(
				screen_fraction * lit_visible, meter_fraction_start, meter_fraction_full)
		if lit_weight > 0.0 and lit_luminance > 0.0:
			min_exposure = minf(min_exposure, _get_candidate_exposure(lit_luminance,
					lit_weight, log_rest, rest_exposure))
		var dark_luminance := albedo * ambient_starlight_illuminance / PI
		var dark_weight := view_factor * _get_ramp_weight(screen_fraction * (1.0 - lit_visible),
				meter_fraction_start, meter_fraction_full)
		if dark_weight > 0.0 and dark_luminance > 0.0:
			min_exposure = minf(min_exposure, _get_candidate_exposure(dark_luminance,
					dark_weight, log_rest, rest_exposure))
		if _ring_meter_data.has(body_name):
			min_exposure = minf(min_exposure, _get_ring_candidate_exposure(body,
					_ring_meter_data[body_name], camera_vector, camera_distance, star_vector,
					star_distance, illuminance, shadow_fraction, fraction_per_theta_sq,
					view_size, tan_half_fov, aspect, log_rest, rest_exposure))
		if _exposure_ceilings.has(body_name):
			var ceilings: Array[Vector2] = _exposure_ceilings[body_name]
			for shell in ceilings:
				min_exposure = minf(min_exposure, _get_ceiling_candidate_exposure(body, shell,
						camera_distance, fraction_per_theta_sq, view_size, tan_half_fov,
						aspect, log_rest, rest_exposure))
		if _limb_ceilings.has(body_name):
			min_exposure = minf(min_exposure, _get_limb_ceiling_candidate_exposure(body,
					_limb_geometry[body_name], _limb_ceilings[body_name], camera_vector,
					camera_distance, star_vector, star_distance, fraction_per_theta_sq,
					view_size, log_rest, rest_exposure))
	return min_exposure


## Weight ramp in LOG fraction space: candidate fractions span decades, so a
## linear smoothstep collapses the whole transition against the upper edge
## and deadens the start knob.
func _get_ramp_weight(screen_fraction: float, fraction_start: float,
		fraction_full: float) -> float:
	if screen_fraction <= fraction_start:
		return 0.0
	var log_span := log(fraction_full / fraction_start)
	if log_span <= 0.0:
		return 1.0
	return smoothstep(0.0, 1.0, log(screen_fraction / fraction_start) / log_span)


## Log-domain blend from the dark-adapted rest down to the candidate's full
## metering target, weighted by screen fraction; the transition exponent
## front-loads the hold near the metered exposure and releases the final
## (star-revealing) EV quickly; see meter_transition_exponent.
func _get_candidate_exposure(luminance: float, weight: float, log_rest: float,
		rest_exposure: float) -> float:
	return _blend_candidate_exposure(metering_key / (luminance * gain), weight, log_rest,
			rest_exposure)


## The blend itself, for a candidate whose fully-metered exposure is asserted rather than
## derived from a luminance (see [method _get_ceiling_candidate_exposure]).
func _blend_candidate_exposure(full_exposure: float, weight: float, log_rest: float,
		rest_exposure: float) -> float:
	full_exposure = minf(full_exposure, rest_exposure)
	var shaped_weight := 1.0 - (1.0 - weight) ** meter_transition_exponent
	return exp(lerpf(log_rest, log(full_exposure), shaped_weight))


## The screen-edge metering gate (see [member meter_edge_fraction]): 0.0 with
## the disc fully outside the frame, 1.0 once its center is
## meter_edge_fraction of the frame dimension inside. Positions come from the
## previous frame's camera (this node processes before it; the class-doc lag
## convention).
func _get_view_factor(global_position: Vector3, angular_radius: float, view_size: Vector2,
		tan_half_fov: float, aspect: float) -> float:
	if _camera.is_position_behind(global_position):
		return 0.0
	var screen_position := _camera.unproject_position(global_position)
	# The disc's angular radius (in frame-height and frame-width fractions;
	# small-angle, undistorted - a gate doesn't need edge-exact projection)
	# credits penetration, so a disc larger than the fade zone holds full
	# weight while any of it is in frame, and a small disc's limb crossing the
	# edge is what starts the ramp.
	var radius_fraction_y := angular_radius / (2.0 * tan_half_fov)
	var radius_fraction_x := radius_fraction_y / aspect
	var position_x := screen_position.x / view_size.x
	var position_y := screen_position.y / view_size.y
	var penetration_x := minf(position_x, 1.0 - position_x) + radius_fraction_x
	var penetration_y := minf(position_y, 1.0 - position_y) + radius_fraction_y
	var penetration := minf(penetration_x, penetration_y)
	if penetration <= 0.0:
		return 0.0
	return smoothstep(0.0, maxf(meter_edge_fraction, 1e-4), penetration)


## Metering candidate for a lit ring face (rings.tsv bodies): a flat annulus
## whose screen fraction is its area foreshortened by the camera's elevation
## from the ring plane, lit as a Lambert surface at the sun's elevation, with
## [member ring_meter_albedo] and a CPU mirror of the ring shader's
## backscatter phase boost carrying the map and phase response. A thin layer
## shows its bright face only from the sun's side of the plane, so the unlit
## side needs no candidate - it stays correctly exposed at the globe's own
## metering. Returns rest_exposure when the ring doesn't meter.
func _get_ring_candidate_exposure(body: IVBody, ring_radii: Vector2, camera_vector: Vector3,
		camera_distance: float, star_vector: Vector3, star_distance: float, illuminance: float,
		shadow_fraction: float, fraction_per_theta_sq: float, view_size: Vector2,
		tan_half_fov: float, aspect: float, log_rest: float, rest_exposure: float) -> float:
	const PHASE_EXPONENT := 6.0 # rings.gdshader
	var axis := body.rotation_axis
	var sin_camera_elevation := -camera_vector.dot(axis) / camera_distance
	var sin_sun_elevation := star_vector.dot(axis) / star_distance
	if sin_camera_elevation * sin_sun_elevation <= 0.0:
		return rest_exposure # camera on the unlit side
	var annulus_theta_sq := (ring_radii.y * ring_radii.y - ring_radii.x * ring_radii.x) \
			* absf(sin_camera_elevation) / (camera_distance * camera_distance)
	var ring_fraction := fraction_per_theta_sq * annulus_theta_sq
	var view_factor := _get_view_factor(body.global_position,
			minf(ring_radii.y / camera_distance, 1.0), view_size, tan_half_fov, aspect)
	var ring_weight := view_factor * _get_ramp_weight(ring_fraction,
			meter_fraction_start, meter_fraction_full)
	if ring_weight <= 0.0:
		return rest_exposure
	# Phase mirror of the shader's backscatter boost: phase_mix is 1.0 at zero
	# phase angle (sun straight behind the camera), where the boost peaks. The
	# boost value is per-renderer, which is why ring_meter_albedo is defined
	# before it.
	var to_sun := (star_vector + camera_vector).normalized() # camera -> sun
	var phase_mix_base := (to_sun.dot(-camera_vector / camera_distance) + 1.0) * 0.5
	var phase_mix := phase_mix_base ** PHASE_EXPONENT
	var phase_factor := _ring_litside_phase_boost * phase_mix + 1.0
	var ring_luminance := ring_meter_albedo * phase_factor * (illuminance * shadow_fraction
			* absf(sin_sun_elevation) + ambient_starlight_illuminance) / PI
	if ring_luminance <= 0.0:
		return rest_exposure
	return _get_candidate_exposure(ring_luminance, ring_weight, log_rest, rest_exposure)


## Metering candidate for a shell that asserts an [code]exposure_ceiling[/code] in
## shells.tsv: the exposure the camera may not exceed while that shell is in view, held
## by the shell's own screen area on the same ramp and screen-edge gate as every other
## candidate, and by nothing else - no phase, no lit fraction, no luminance. What a
## rendered atmosphere should cost the rest of the frame is not a photometric question
## (a real camera exposed for a body's disc DOES blow its limb out, and the reference
## photographs that show limb structure are exposed for the limb and show no stars), so
## the ceiling is asserted per shell rather than metered. Lower candidates still win:
## a ceiling never brightens a view its body's own disc has already metered down.
## Returns rest_exposure when the shell doesn't meter.
func _get_ceiling_candidate_exposure(body: IVBody, shell: Vector2, camera_distance: float,
		fraction_per_theta_sq: float, view_size: Vector2, tan_half_fov: float, aspect: float,
		log_rest: float, rest_exposure: float) -> float:
	var angular_radius := minf(shell.x / camera_distance, 1.0)
	var shell_fraction := fraction_per_theta_sq * angular_radius * angular_radius
	var view_factor := _get_view_factor(body.global_position, angular_radius, view_size,
			tan_half_fov, aspect)
	var weight := view_factor * _get_ramp_weight(shell_fraction, meter_fraction_start,
			meter_fraction_full)
	if weight <= 0.0:
		return rest_exposure
	return _blend_candidate_exposure(shell.y, weight, log_rest, rest_exposure)


## Metering candidate for an atmosphere limb that asserts a
## [code]limb_exposure_ceiling[/code] in shells.tsv. Like
## [method _get_ceiling_candidate_exposure] the exposure itself is asserted rather than
## metered, for the same reason; what differs is what holds it. A limb is a ring, not a
## disc, so the camera compensates for one only while that ring is the view.[br][br]
##
## The ring is sampled in azimuth on the DISC's silhouette circle - the limb's own foot,
## which is where its light is and where a viewer sees it - and each sample carries the
## limb's whole height above that foot, up to the limb shell. A sample counts by three
## things.[br]
## - How much of that height is SUNLIT: the shadow is the disc's own cylinder, so at a foot
##   whose solar zenith is past 90 deg the shadow stands at radius
##   [code]disc / sin(zenith)[/code] and only the limb above it is still in daylight - full
##   credit at the terminator, falling to none where the shadow tops the shell.[br]
## - Whether the sample FORWARD-SCATTERS toward the camera, which is what makes a limb
##   bright enough to be a subject at all: the cosine of its scattering angle, the sun's
##   direction against the sample's own line to the camera, clamped at zero. A limb lit
##   from the camera's own side is not a ring anyone is looking at, and the body's disc
##   meters that view by itself.[br]
## - How far INSIDE THE FRAME the foot sits ([member limb_meter_edge_fraction]).[br]
## Their share of the ring scales the SHELL's screen area, on the limb's own late
## ramp.[br][br]
##
## The two physical terms are both needed and neither substitutes: a lit-height measure
## alone credits a twilight limb coming out of a night side exactly as it credits a blazing
## backlit one, because those are the same shadow geometry seen from opposite phases, and
## at fixed shadow the ring's own radiance runs about two orders of magnitude between them.
## A forward-scatter measure alone credits a fully shadowed limb at high phase. So zooming
## past the ring, or panning it out of frame, releases the ceiling and hands back the fully
## dark-adapted exposure; a backlit twilight limb holds it in proportion to the lit height
## that remains; and a limb that is either in the body's shadow or lit from behind the
## camera never held it at all. Returns rest_exposure when the limb doesn't meter.
func _get_limb_ceiling_candidate_exposure(body: IVBody, limb: Vector2, ceiling: float,
		camera_vector: Vector3, camera_distance: float, star_vector: Vector3,
		star_distance: float, fraction_per_theta_sq: float, view_size: Vector2,
		log_rest: float, rest_exposure: float) -> float:
	const RING_SAMPLES := 32
	var disc_radius := limb.x
	var shell_radius := limb.y
	var limb_height := shell_radius - disc_radius
	if limb_height <= 0.0 or camera_distance <= disc_radius:
		return rest_exposure
	var camera_position := body.global_position - camera_vector
	var to_camera := -camera_vector / camera_distance
	var to_star := star_vector / star_distance
	# A sphere's silhouette circle is smaller than the sphere and offset toward the camera,
	# and both terms run away close in - which is what takes the ring off screen, and the
	# ceiling with it, exactly where the camera is flying inside the limb's own annulus.
	var ring_radius := disc_radius * sqrt(maxf(1.0 - disc_radius * disc_radius
			/ (camera_distance * camera_distance), 0.0))
	var ring_center := body.global_position + to_camera * (disc_radius * disc_radius
			/ camera_distance)
	var sunward_axis := to_star - to_camera * to_star.dot(to_camera)
	if sunward_axis.length_squared() < 1e-12: # sun behind or ahead; the ring is symmetric
		sunward_axis = to_camera.cross(Vector3.UP if absf(to_camera.y) < 0.9 else Vector3.RIGHT)
	sunward_axis = sunward_axis.normalized()
	var crosswise_axis := to_camera.cross(sunward_axis)
	var visible_lit := 0.0
	for i in RING_SAMPLES:
		var azimuth := TAU * (i + 0.5) / RING_SAMPLES
		var point := ring_center + (sunward_axis * cos(azimuth)
				+ crosswise_axis * sin(azimuth)) * ring_radius
		var solar_cosine := (point - body.global_position).dot(to_star) / disc_radius
		var lit := 1.0
		if solar_cosine < 0.0: # past the terminator: the shadow rises into the limb
			var sin_zenith := sqrt(maxf(1.0 - solar_cosine * solar_cosine, 1e-12))
			lit = clampf((shell_radius - disc_radius / sin_zenith) / limb_height, 0.0, 1.0)
		# Per sample rather than from the body's phase: close in, the ring spans a wide range
		# of scattering angles, and the samples in frame are rarely the ones the phase names.
		var to_viewer := (camera_position - point).normalized()
		lit *= maxf(-to_star.dot(to_viewer), 0.0)
		if lit <= 0.0 or _camera.is_position_behind(point):
			continue
		var screen_position := _camera.unproject_position(point)
		var position_x := screen_position.x / view_size.x
		var position_y := screen_position.y / view_size.y
		var penetration := minf(minf(position_x, 1.0 - position_x),
				minf(position_y, 1.0 - position_y))
		if penetration <= 0.0:
			continue
		visible_lit += lit * smoothstep(0.0, maxf(limb_meter_edge_fraction, 1e-4), penetration)
	if visible_lit <= 0.0:
		return rest_exposure
	var angular_radius := minf(shell_radius / camera_distance, 1.0)
	var ring_fraction := fraction_per_theta_sq * angular_radius * angular_radius
	var limb_fraction := ring_fraction * visible_lit / RING_SAMPLES
	var weight := _get_ramp_weight(limb_fraction, limb_meter_fraction_start,
			limb_meter_fraction_full)
	if weight <= 0.0:
		return rest_exposure
	return _blend_candidate_exposure(ceiling, weight, log_rest, rest_exposure)


## Fraction of the body's visible disc that is sunlit. camera_vector points
## camera -> body. A body with an atmosphere shell hands this its LIMB geometry:
## the fraction is still the surface's, but the horizon cutoff that ends it
## follows air that is lit past the terminator and seen from farther round.
func _get_lit_visible_fraction(body: IVBody, star_vector: Vector3, star_distance: float,
		camera_vector: Vector3, camera_distance: float) -> float:
	var phase_cos := -star_vector.dot(camera_vector) / (star_distance * camera_distance)
	var lit := (1.0 + phase_cos) * 0.5
	# Horizon correction: close in, the lit crescent sinks behind the horizon
	# just past the terminator, while the disc phase model above keeps
	# crediting sunlit surface no observer at this altitude can see. Lit
	# surface is geometrically visible only while the phase angle is under
	# 90 deg + the visible-cap half angle acos(radius / camera_distance)
	# (-> 180 deg far away, recovering the disc model; -> 90 deg at the
	# surface, where crossing the terminator is crossing into night).
	var phase_angle := acos(clampf(phase_cos, -1.0, 1.0))
	var lit_radius := body.mean_radius
	var terminator := PI / 2.0
	if _limb_geometry.has(body.name):
		# A body with an atmosphere is lit past its own terminator: the shadow is a cylinder
		# of the DISC's radius, so air at the limb shell's top keeps the sun until its foot
		# point's solar zenith angle reaches PI - asin(disc / shell). Dawn reaches the air
		# before the ground, and coming round from a night side that is what the camera sees
		# first - so the adaptation follows the atmosphere's geometry even though the
		# luminance it adapts TO is still the surface's albedo. Far away both terms saturate
		# and this is moot; from low altitude it starts the transition tens of degrees of
		# phase earlier.
		var limb: Vector2 = _limb_geometry[body.name]
		lit_radius = limb.y
		terminator = PI - asin(clampf(limb.x / limb.y, 0.0, 1.0))
	var lit_visible_cutoff := terminator + acos(clampf(lit_radius / camera_distance, 0.0, 1.0))
	lit *= 1.0 - smoothstep(lit_visible_cutoff - nightside_twilight_angle,
			lit_visible_cutoff, phase_angle)
	return clampf(lit, 0.0, 1.0)


## Satellite-in-parent-shadow term (e.g. the Moon in Earth's umbra), so an
## eclipsed body meters dark and exposure rises as an eye would. Parent only:
## other occluder geometries are negligible for metering.
func _get_parent_shadow_fraction(body: IVBody, star_vector: Vector3,
		star_distance: float) -> float:
	var parent := body.get_parent() as IVBody
	if !parent or parent == _star or !_star:
		return 1.0
	var parent_vector := parent.global_position - body.global_position
	var parent_distance := parent_vector.length()
	if parent_distance <= 0.0 or parent.mean_radius <= 0.0:
		return 1.0
	var star_angular_radius := _star.mean_radius / star_distance
	var parent_angular_radius := parent.mean_radius / parent_distance
	var cos_separation := star_vector.dot(parent_vector) / (star_distance * parent_distance)
	var separation := acos(clampf(cos_separation, -1.0, 1.0))
	return IVAstronomy.get_two_disc_visible_fraction(star_angular_radius, parent_angular_radius,
			separation)


func _get_star_absolute_magnitude() -> float:
	if !_star:
		return NAN
	var magnitude_var: Variant = _star.characteristics.get(&"absolute_magnitude")
	if typeof(magnitude_var) == TYPE_FLOAT:
		var magnitude: float = magnitude_var
		return magnitude
	return NAN


func _get_albedo(body: IVBody) -> float:
	# An empty table cell reaches characteristics as a non-positive float (not a
	# missing key), and a 0 albedo would zero the body's luminance and silently
	# remove it from metering - so only a positive value counts as known.
	var albedo_var: Variant = body.characteristics.get(&"albedo")
	if typeof(albedo_var) == TYPE_FLOAT:
		var albedo: float = albedo_var
		if albedo > 0.0:
			return albedo
	return default_albedo


# *****************************************************************************
# Exposure adaptation & apply


func _update_auto_exposure(target: float, delta: float) -> void:
	const LOG_2 := 0.6931471805599453
	var target_ev := log(target) / LOG_2
	if _snap_next or target_ev == auto_exposure_ev:
		_snap_next = false
		auto_exposure_ev = target_ev
		return
	var diff := target_ev - auto_exposure_ev
	if absf(diff) > snap_ev_threshold:
		auto_exposure_ev = target_ev
		return
	# Negative diff = darkening (exposure falling toward a bright body).
	var rate := adapt_darken_ev_per_second if diff < 0.0 else adapt_brighten_ev_per_second
	var step := rate * delta
	if absf(diff) <= step:
		auto_exposure_ev = target_ev
	else:
		auto_exposure_ev += signf(diff) * step


func _apply_exposure() -> void:
	var ev := (auto_exposure_ev if auto else manual_exposure_ev) + exposure_adjustment_ev
	exposure = 2.0 ** ev
	RenderingServer.global_shader_parameter_set(&"iv_exposure", exposure)
	RenderingServer.global_shader_parameter_set(&"iv_emission_luminance_scale",
			exposure * gain)
	# Ambient carries exposure in the Environment itself (see _apply_ambient),
	# reaching StandardMaterial3D craft models and the occlusion manager's
	# ambient_light feed alike. Ordering: this node runs at -1, the occlusion
	# manager at +100, so the feed reads this frame's value.
	if _world_environment and _world_environment.environment:
		_world_environment.environment.ambient_light_energy = _ambient_energy_base * exposure


# *****************************************************************************
# Signal handlers


func _on_current_camera_changed(camera: Camera3D) -> void:
	_camera = camera
	_snap_next = true


func _on_camera_tree_changed(_camera_node: Camera3D, _parent: Node3D, _star_orbiter: Node3D,
		star: Node3D) -> void:
	_star = star as IVBody


func _on_assets_preloaded() -> void:
	if physical_active:
		_apply_starmap_energy()


func _on_star_settings_changed() -> void:
	if !physical_active:
		return
	_recompute_photometry()
	_apply_ambient()
	_apply_starmap_energy()


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"physical_light":
		_transition_dirty = true


func _clear_procedural() -> void:
	_camera = null
	_star = null
	_snap_next = true
	exposure = 1.0
	auto_exposure_ev = 0.0
	_neutralize_shader_globals()


func _neutralize_shader_globals() -> void:
	RenderingServer.global_shader_parameter_set(&"iv_exposure", 1.0)
	RenderingServer.global_shader_parameter_set(&"iv_emission_energy_scale", 1.0)
	RenderingServer.global_shader_parameter_set(&"iv_emission_luminance_scale", 0.0)
	RenderingServer.global_shader_parameter_set(&"iv_limb_scale", 1.0)
