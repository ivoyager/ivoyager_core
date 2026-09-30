# world_environment.gd
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
class_name IVWorldEnvironment
extends WorldEnvironment

## I, Voyager's WorldEnvironment for scene tree construction.
##
## This node uses default Environment and CameraAttributes resources from
## res://addons/ivoyager_core/resources.[br][br]
##
## Renderer-conditional Environment setup happens here at [method Node._ready]: the
## Compatibility brightness offset ([member gl_compatibility_exposure]) there, and the
## adjustment stage that [IVScreenshotManager] dims with everywhere else.[br][br]
##
## If [member add_starmap] is true (default), this node adds a low-resolution
## background panorama (the diffuse Milky Way / nebula sky) from the assets
## directory to the Environment's sky at startup, discovered by file prefix (see
## [member starmap_background_file_prefix]) and oriented by [member sky_rotation].
## The default Environment omits it because the Core plugin is stand-alone without
## assets; a missing file simply leaves the black clear-color background. Discrete
## stars are drawn separately by [IVStarsVisual].[br][br]
##
## Glow halos keep the share of the frame they are authored for at any render height
## (window size, 3D render scale or capture): this node reads the Environment's glow
## level weights at [method Node._ready] as authored for a render
## [code]iv_reference_viewport_height[/code] tall, and shifts them to the current height.
## Change them at runtime with [method set_glow_levels], not on the Environment, which
## this node overwrites whenever the height changes. Inert under Compatibility, whose
## glow has no levels. See [i]Glow: the bloom pass[/i] in PHOTOMETRIC_MODEL.md.[br][br]

## If true, a background panorama discovered under [member starmaps_search] by
## [member starmap_background_file_prefix] is added to the Environment's sky as a
## [PanoramaSkyMaterial] at startup. A missing file leaves the clear-color background.
@export var add_starmap := true
## File prefix (see [IVFiles]) of the background sky panorama in [member
## starmaps_search]; e.g. [code]milkyway_galaxies_nebulea[/code] matches
## [code]milkyway_galaxies_nebulea.4096.exr[/code], so the asset resolution can
## change without a code edit. A panorama must be equirectangular and drawn to the
## astronomical convention (longitude 0 centered and increasing leftward, +latitude
## up); set [member sky_rotation] for the frame it is drawn in.
@export var starmap_background_file_prefix := "milkyway_background"
## Directories searched for the background panorama. Prepend a directory to
## prioritize a custom override.
var starmaps_search: Array[String] = ["res://addons/ivoyager_assets/starmaps"]
## Scales the background sky's energy multiplier. 1.0 is
## [method IVExposureManager.compute_sky_energy], the level at which the panorama
## and the star field are one photometric system: both are then the same camera's
## image of the same sky, so toggling physical light moves the two together instead
## of changing their ratio. Raising it is a taste call about the Milky Way alone.
## Physical light supersedes it, as it does every by-eye value it replaces.
@export_range(0.0, 4.0, 0.01, "or_greater") var starmap_background_energy_scale := 1.0
## Euler angles assigned to [member Environment.sky_rotation], which rotates the background
## panorama out of the frame it is drawn in and into the simulator's ecliptic frame. Zero
## means the panorama is already ecliptic. The default suits the galactic-coordinate
## panorama named by [member starmap_background_file_prefix]: it decomposes the ecliptic
## basis whose x-axis points at the galactic center (ICRS RA 266.40510, dec -28.936175) and
## z-axis at the north galactic pole (ICRS RA 192.85948, dec +27.12825), the IAU galactic
## frame as referred to ICRS by Hipparcos (ESA SP-1200, sect. 1.5.3).
@export var sky_rotation := Vector3(0.000351590, -1.050488534, -1.682016221)
## Multiplies all scene radiance (emission + lit surfaces + sky) before tonemapping;
## applied only under the Compatibility renderer to offset its dimmer output. Tune by eye.
@export var gl_compatibility_exposure := 1.2
## Stops drawing the background panorama while the compensating camera has metered it
## below one display code. Relief with no visual change rather than a quality setting: in
## any lit-body view the panorama is already black, yet the sky pass is 10-17% of an
## integrated-GPU frame. Inert without physical light, where exposure rests at
## [constant IVExposureManager.INACTIVE_EXPOSURE] and the sky's brightest texel sits near
## display code 117. Set false to render (and measure) against the sky always drawn.
## Requires [member Environment.background_color] to be black, which it is by default and
## which nothing reads while the sky is drawn. See [i]Skipping what the camera has metered
## away[/i] in PHOTOMETRIC_MODEL.md.
@export var skip_invisible_starmap := true

## Share of [constant IVPhotometry.ONE_DISPLAY_CODE_LINEAR] the sky must fall below to be
## skipped, against the whole code it must reach to be drawn again. Half a code is the
## 8-bit rounding boundary and so the real "cannot move a pixel" line; the gap to a whole
## code is the hysteresis, which exposure glides through in 1 EV -- without it the pass
## would flip on and off every frame while it sat on the line. Matches
## [constant IVStarsVisual.HIDE_THRESHOLD_FRACTION], the same decision for the stars.
const HIDE_THRESHOLD_FRACTION := 0.5

## Render height an off-screen capture is about to use, or 0.0 for none. Set and cleared by
## [IVScreenshotManager], so the capture's glow is shifted for its own frame. Not a tunable.
static var capture_render_height := 0.0

var _starmap_material: ShaderMaterial # null until _add_starmap_sky() finds a panorama
var _starmap_skipped := false
var _glow_levels: Array[float] = [] # as authored for the reference height; empty = no shift
var _glow_render_height := 0.0 # the height the Environment's levels are shifted for


# Moves each weight octaves_finer levels finer (coarser if negative). A weight landing between
# two levels is split to keep the halo's variance, level widths doubling per level; weight
# past either end of the chain piles onto the end level.
static func _shift_glow_levels(levels: Array[float], octaves_finer: float) -> Array[float]:
	var shifted: Array[float] = []
	shifted.resize(levels.size())
	shifted.fill(0.0)
	var last_level := levels.size() - 1
	for level in levels.size():
		var weight := levels[level]
		if weight == 0.0:
			continue
		var position := level - octaves_finer
		var fine_level := floori(position)
		var coarse_share := (pow(4.0, position - fine_level) - 1.0) / 3.0
		shifted[clampi(fine_level, 0, last_level)] += weight * (1.0 - coarse_share)
		shifted[clampi(fine_level + 1, 0, last_level)] += weight * coarse_share
	return shifted


# Godot (4.7.2) computes glow only through the last level weighted above 0.01 but samples every
# level above 0.0001, so a trailing weight between the two draws a mip nothing wrote. See
# Render height in PHOTOMETRIC_MODEL.md.
static func _pile_uncomputed_tail(levels: Array[float]) -> void:
	const COMPUTED_ABOVE := 0.011 # Godot's 0.01, clear of rounding in its float32 copy
	var last_computed := 0 # the pass always writes the first level
	for level in levels.size():
		if levels[level] > COMPUTED_ABOVE:
			last_computed = level
	for level in range(last_computed + 1, levels.size()):
		levels[last_computed] += levels[level]
		levels[level] = 0.0


func _ready() -> void:
	if IVGlobal.is_gl_compatibility:
		environment.tonemap_exposure = gl_compatibility_exposure
		# Glow stays ON here, and it is a deliberate trade rather than a free win. It is
		# measurably worse than useless for a POINT source: the glow buffers inherit the
		# scene buffer's RGB10_A2 and store 0.25 x color, so the per-texel feed clamps at
		# 4.0 whatever glow_hdr_luminance_cap says (that property and glow_levels are
		# byte-for-byte inert), and the far sun's halo is the same 4 px with the pass on as
		# off. And it costs the dim end: enabling it moves tonemapping into a post pass that
		# re-runs the transfer bracket display_write() pre-inverts exactly once, measured at
		# 0.041x on 6-8 code content, 0.19x at 8-10, 0.66x at 12-18 and 0.84x over the whole
		# frame, where Forward+ measures 1.000x at every level. What buys it back is
		# EXTENDED sources: spacecraft parts, small moons and asteroids sit outside the
		# IVBodyPSF quad system, which draws its own wings (psf_glare_* in
		# _point_spread_function.gdshaderinc) for every source that has one, and the pass is the only
		# glow those others get. A project that wants it off can author its own Environment.
	else:
		# The adjustment stage, which [IVScreenshotManager] tweens for its capture dim. Kept
		# out of the Environment resource and off under Compatibility, where it is anything
		# but free: adjustments_enabled joins the gate that moves tonemapping out of the
		# scene shaders into a post pass, costing a full-resolution intermediate buffer, a
		# pass per frame, and a repermute of every scene shader -- a bill the web build would
		# pay always for an effect it wants for a moment. Forward+ folds it into a tonemap
		# pass that runs regardless, for a few ALU. Nothing here switches it back off, so a
		# project that wants it anyway can author it into its own Environment.
		environment.adjustment_enabled = true
		for level in RenderingServer.MAX_GLOW_LEVELS:
			_glow_levels.append(environment.get_glow_level(level))
	set_process(!_glow_levels.is_empty())
	IVStateManager.assets_preloaded.connect(_on_asset_preloader_finished)


func _process(_delta: float) -> void:
	if !_glow_levels.is_empty():
		_update_glow_levels()
	if _starmap_material:
		_update_starmap_skip()


## Returns the glow level weights as authored for a render
## [code]iv_reference_viewport_height[/code] tall, which this node shifts to the current
## render height. Empty under Compatibility.
func get_glow_levels() -> Array[float]:
	return _glow_levels.duplicate()


## Sets the glow level weights ([constant RenderingServer.MAX_GLOW_LEVELS] of them, as
## [method Environment.set_glow_level] takes them) for a render
## [code]iv_reference_viewport_height[/code] tall. Use this rather than the Environment to
## change glow levels at runtime. No effect under Compatibility, whose glow has no levels.
func set_glow_levels(levels: Array[float]) -> void:
	assert(levels.size() == RenderingServer.MAX_GLOW_LEVELS)
	if _glow_levels.is_empty():
		return
	_glow_levels = levels.duplicate()
	_glow_render_height = 0.0 # applied on the next frame


# Every glow level is a blur of the render buffer in its own texels, so an unshifted halo is
# fixed in render pixels: narrower in a taller render, wider at a lower 3D render scale.
func _update_glow_levels() -> void:
	var render_height := capture_render_height
	if render_height <= 0.0:
		render_height = IVGraphicsManager.get_render_size(get_viewport()).y
	if render_height <= 0.0 or render_height == _glow_render_height:
		return
	_glow_render_height = render_height
	var octaves_finer := log(IVBodyPSF.get_reference_viewport_height() / render_height) / log(2.0)
	var levels := _shift_glow_levels(_glow_levels, octaves_finer)
	_pile_uncomputed_tail(levels)
	for level in levels.size():
		environment.set_glow_level(level, levels[level])


# What the sky pass costs is fixed -- a full-screen bicubic resample of the panorama --
# however little of it the exposure has left, so below one display code it is pure waste.
# The bound on its rendered radiance is energy_multiplier x exposure: a decoded 8-bit texel
# cannot exceed 1.0, and that ceiling is what background_peak_magnitude_per_arcsec2 states
# the panorama's brightest texel to be. energy_multiplier is read from the material rather
# than taken as IVExposureManager.sky_energy so that whatever last wrote it is what this
# answers to.
#
# WARNING: Under Compatibility, the first frame that draws the sky adds USE_RADIANCE_MAP to
# every scene shader's specialization for the rest of the session. The start sequence draws
# it before IVShaderWarmup runs, so the warm-up compiles with it. A skip that engaged before
# the sky's first draw would move a recompile of everything in view into flight. See
# Specializations in GRAPHICS_PROFILING.md.
func _update_starmap_skip() -> void:
	var skip := false
	if skip_invisible_starmap and IVExposureManager.physical_active:
		var energy_var: Variant = _starmap_material.get_shader_parameter(&"energy_multiplier")
		var energy_multiplier := 0.0
		if typeof(energy_var) == TYPE_FLOAT:
			energy_multiplier = energy_var
		var threshold := IVPhotometry.ONE_DISPLAY_CODE_LINEAR
		if !_starmap_skipped:
			threshold *= HIDE_THRESHOLD_FRACTION
		skip = energy_multiplier * IVExposureManager.exposure < threshold
	if skip == _starmap_skipped:
		return
	_starmap_skipped = skip
	environment.background_mode = Environment.BG_COLOR if skip else Environment.BG_SKY


# A fixed scene node's _ready() precedes core init, so IVGlobal.program is empty there
# (the same reason IVStarsVisual defers its build); this signal is well after it.
func _on_asset_preloader_finished() -> void:
	if !add_starmap:
		return
	_add_starmap_sky()
	# Only this node's own BG_SKY may be switched away and back: a project whose panorama
	# did not resolve keeps whatever background its Environment authored.
	_starmap_material = _get_starmap_material()
	set_process(!_glow_levels.is_empty() or _starmap_material != null)
	# The sky's level is IVPSFSettings photometry (see _get_starmap_energy), so this node
	# is a consumer of those values and re-applies on the signal like the rest of them.
	var psf_settings: IVPSFSettings = IVGlobal.program.get(&"PSFSettings")
	if psf_settings:
		psf_settings.changed.connect(_on_psf_settings_changed)


# IVExposureManager drives energy_multiplier itself while active, and restores what it
# captured when it stops, so writing here then would fight it over one parameter.
func _on_psf_settings_changed() -> void:
	if IVExposureManager.physical_active:
		return
	var sky_material := _get_starmap_material()
	if sky_material:
		sky_material.set_shader_parameter(&"energy_multiplier", _get_starmap_energy())


func _get_starmap_material() -> ShaderMaterial:
	if !environment or !environment.sky:
		return null
	return environment.sky.sky_material as ShaderMaterial


func _add_starmap_sky() -> void:
	var background: Texture2D = IVFiles.find_and_load_resource(starmaps_search,
		starmap_background_file_prefix)
	if !background:
		return

	# Depixelating sky shader (bicubic resample) that samples the background image as-is;
	# sky_rotation supplies the frame. See starmap_background.gdshader.
	var sky_material := ShaderMaterial.new()
	sky_material.shader = IVGlobal.resources[&"starmap_background_shader"]
	sky_material.set_shader_parameter(&"panorama", background)
	sky_material.set_shader_parameter(&"energy_multiplier", _get_starmap_energy())
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.sky_rotation = sky_rotation
	environment.background_mode = Environment.BG_SKY


# The anchor is IVExposureManager's when that node exists, so a project that moved it
# does not get one panorama level under physical light and another without.
func _get_starmap_energy() -> float:
	var exposure_manager: IVExposureManager = IVGlobal.program.get(&"ExposureManager")
	var sky_energy := (IVExposureManager.compute_sky_energy(
			exposure_manager.background_peak_magnitude_per_arcsec2) if exposure_manager
			else IVExposureManager.compute_sky_energy())
	return sky_energy * starmap_background_energy_scale
