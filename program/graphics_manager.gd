# graphics_manager.gd
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
class_name IVGraphicsManager
extends Node

## Applies user graphics settings (antialiasing, shadow resolution, atmosphere
## quality, 3D render scale and frame rate cap) and the screen's display scale to
## the engine, the rendering server, the main window viewport and the local shadow
## maps, records the renderer for the next start, and publishes the renderer's
## colour-space convention to shaders.
##
## Added by [IVCoreInitializer]. Settings [code]atmosphere_quality[/code],
## [code]render_scale[/code], [code]msaa_3d[/code], [code]fxaa[/code],
## [code]use_taa[/code], [code]shadow_resolution[/code] and
## [code]frame_rate_cap[/code] are defined in [IVSettingsManager] and exposed in
## [IVOptionsPopup]; this node applies them at startup and re-applies them live on
## change. [member atmosphere_quality_settings], [member render_scale_settings],
## [member msaa_settings], [member shadow_resolution_settings], [member
## frame_rate_cap_settings], [member renderer_settings] and [member
## star_catalog_settings] are the enumerations backing the seven dropdowns.
## [IVStarsVisual] applies setting [code]star_catalog[/code] itself, when it loads
## the catalog at startup.[br][br]
##
## Setting [code]renderer[/code] cannot apply live: Godot fixes the renderer at
## engine start. On change, and at startup when that file still names a renderer
## the setting no longer does (as after a settings cache reset), this node writes
## it to the file the project names in ProjectSettings
## [code]application/config/project_settings_override[/code] (e.g.
## [code]user://override.cfg[/code]), which the engine reads at the next start. A
## project that names no such file, a project whose [member
## IVSettingsManager.graphics_target] is [code]MODERN_GPU[/code], and any
## non-desktop build get no Renderer option; see [method can_set_renderer]. A
## Forward+ run also records the GPU's type in that file, which a Compatibility run
## cannot read for itself; see [member IVGlobal.video_adapter_type]. A project that
## switches a run to a renderer other than the one it started in must restart it
## before the rest of init; [method write_rendering_method] and [method
## get_rendering_method] serve a preinitializer that does so.[br][br]
##
## [method get_graphics_tier] rates what this machine's GPU and screen can carry,
## and [method get_fitted_defaults] gives the graphics defaults that suit it, which
## [IVSettingsManager] applies when a project sets [member
## IVSettingsManager.graphics_target]. See [i]Fitted defaults[/i] in
## [code]GRAPHICS_PROFILING.md[/code] for why each tier gives up what it does.[br][br]
##
## Renderer support differs: MSAA, atmosphere quality and frame rate cap work in
## all renderers; render scale works everywhere but on ANGLE's Direct3D 11 path,
## where a reduced scale costs frame time (see [method can_scale_render]); FXAA is
## unavailable in the Compatibility renderer (including web exports); TAA is
## Forward+ only; and directional shadows on Compatibility depend on [member
## IVCoreSettings.apply_gl_compatibility_shadows] (see [IVDynamicLight]).
## Unsupported settings are skipped here and hidden by [IVOptionsPopup].[br][br]
##
## Frame rate cap sets [member Engine.max_fps]. None leaves in place the cap the
## engine started with, from ProjectSettings [code]application/run/max_fps[/code] or
## the [code]--max-fps[/code] command-line argument; 60 or 30 replaces it.[br][br]
##
## Render scale sets the main viewport's [member Viewport.scaling_3d_scale],
## upscaling with FSR 1 on Forward+ and bilinear elsewhere; the 2D GUI keeps the
## window's resolution. Where [method can_scale_render] is false it holds the scale
## at 100%, whatever is cached. A change emits [signal IVGlobal.viewport_size_changed].
## Which pixel decisions must follow the scaled buffer is in the settings summary of
## [code]VISUAL_MODEL.md[/code].[br][br]
##
## With [member IVCoreSettings.apply_display_scale], the screen's own scale becomes
## the main window's [member Window.content_scale_factor], so the 2D GUI and every
## mouse position are in logical pixels, and a window still at the project's size
## opens that much larger. The 3D view keeps rendering at the screen's pixels, so
## [method Viewport.get_visible_rect] is no longer the render size: use [method
## get_render_size]. See [i]Pixel spaces[/i] in [code]VISUAL_MODEL.md[/code].[br][br]
##
## Atmosphere quality writes the [code]iv_atm_*[/code] shader globals that
## [code]shaders/_atmosphere.gdshaderinc[/code] reads. Normal and Reduced are one
## shader program, so a change between them costs no compile and takes effect on
## the next frame. Min and Off each bind other programs, which [IVAssetPreloader]
## chooses when bodies are built ([member is_atmosphere_min_session], [member
## is_atmosphere_off_session]), so a change into or out of either waits for a
## restart, and [method IVSettingsManager.is_restart_pending] says so. See
## [i]Atmospheres[/i] in [code]PHOTOMETRIC_MODEL.md[/code] for what each tier gives
## up and [code]GRAPHICS_PROFILING.md[/code] for what it buys back.[br][br]
##
## It also writes the [code]iv_display_encode[/code] shader global once at startup:
## the Compatibility renderer is display-referred at both ends of a shader — a
## source_color texture arrives still encoded, and what a shader writes is taken
## as encoded too — so a shader must decode what it samples, do its colour
## arithmetic in linear, and encode what it writes. Every colour-handling shader
## does so through [code]shaders/_display.gdshaderinc[/code]; see that file for
## what the global means and what it does not cover.

## What a machine's GPU and screen can carry; see [method get_graphics_tier].
enum GraphicsTier {
	FULL, ## A discrete GPU driving a screen of ordinary pixel count.
	REDUCED, ## A discrete GPU driving a screen past [constant REDUCED_TIER_SCREEN_PIXELS].
	LOW, ## Any other GPU, including one of unknown type, as in every browser.
}

## Godot's rendering method for each value of setting [code]renderer[/code].
const RENDERING_METHODS: Array[String] = ["forward_plus", "gl_compatibility"]
## The 3D render scale for each value of setting [code]render_scale[/code].
const RENDER_SCALES: Array[float] = [1.0, 0.85, 0.7, 0.5]
## Physical screen pixels past which a discrete GPU rates [constant GraphicsTier.REDUCED].
const REDUCED_TIER_SCREEN_PIXELS := 6_000_000
## 3D render pixels that [constant GraphicsTier.REDUCED] fits its render scale within.
const REDUCED_TIER_RENDER_PIXELS := 4_700_000
## 3D render pixels that [constant GraphicsTier.LOW] fits its render scale within.
const LOW_TIER_RENDER_PIXELS := 2_700_000


## True if this session draws every atmosphere with the Min tier's shaders (THE MIN VARIANT
## in [code]shaders/_atmosphere.gdshaderinc[/code]): setting [code]atmosphere_quality[/code]
## was Min when this node entered the tree. [IVAssetPreloader] reads it later, when it builds
## the bodies' shell specs, so it holds for the session. False without this node.
static var is_atmosphere_min_session := false
## True if this session draws every atmosphere with the Off tier's shaders and no limb shell
## (THE OFF VARIANT in [code]shaders/_atmosphere.gdshaderinc[/code]): setting
## [code]atmosphere_quality[/code] was Off when this node entered the tree. Held for the
## session, as [member is_atmosphere_min_session] is. False without this node.
static var is_atmosphere_off_session := false

## Enumeration backing the [code]atmosphere_quality[/code] dropdown in
## [IVOptionsPopup]. Normal and Reduced are mapped to the quadrature rule and ring tap
## cap in [method _apply_atmosphere_quality]; Min and Off each to shaders of their own,
## bound at startup ([member is_atmosphere_min_session], [member
## is_atmosphere_off_session]). Insertion order must equal value order (the popup uses
## the setting value as the dropdown item index).
var atmosphere_quality_settings: Dictionary[StringName, int] = {
	ATMOSPHERE_NORMAL = 0,
	ATMOSPHERE_REDUCED = 1,
	ATMOSPHERE_MIN = 2,
	ATMOSPHERE_OFF = 3,
}

## Enumeration backing the [code]render_scale[/code] dropdown in
## [IVOptionsPopup]. Mapped to a 3D render scale by [constant RENDER_SCALES].
## Insertion order must equal value order (the popup uses the setting value as
## the dropdown item index).
var render_scale_settings: Dictionary[StringName, int] = {
	RENDER_SCALE_100 = 0,
	RENDER_SCALE_85 = 1,
	RENDER_SCALE_70 = 2,
	RENDER_SCALE_50 = 3,
}

## Enumeration backing the [code]msaa_3d[/code] dropdown in [IVOptionsPopup].
## Values match [enum Viewport.MSAA]. Insertion order must equal value order
## (the popup uses the setting value as the dropdown item index).
var msaa_settings: Dictionary[StringName, int] = {
	MSAA_DISABLED = 0,
	MSAA_2X = 1,
	MSAA_4X = 2,
	MSAA_8X = 3,
}

## Enumeration backing the [code]shadow_resolution[/code] dropdown in
## [IVOptionsPopup]. Mapped to a shadow atlas resolution in [method
## _apply_shadow_resolution]; Off switches the maps off through [member
## IVDynamicLight.shadow_maps_enabled] and frees the atlas. Insertion order must
## equal value order (the popup uses the setting value as the dropdown item index).
var shadow_resolution_settings: Dictionary[StringName, int] = {
	SHADOW_OFF = 0,
	SHADOW_2048 = 1,
	SHADOW_4096 = 2,
	SHADOW_8192 = 3,
}

## Enumeration backing the [code]frame_rate_cap[/code] dropdown in [IVOptionsPopup].
## Mapped to [member Engine.max_fps] in [method _apply_frame_rate_cap]. Insertion
## order must equal value order (the popup uses the setting value as the dropdown
## item index).
var frame_rate_cap_settings: Dictionary[StringName, int] = {
	FRAME_RATE_CAP_NONE = 0,
	FRAME_RATE_CAP_60 = 1,
	FRAME_RATE_CAP_30 = 2,
}

## Enumeration backing the [code]renderer[/code] dropdown in [IVOptionsPopup].
## Mapped to a rendering method by [constant RENDERING_METHODS]. Insertion order
## must equal value order (the popup uses the setting value as the dropdown item
## index).
var renderer_settings: Dictionary[StringName, int] = {
	RENDERER_FORWARD_PLUS = 0,
	RENDERER_COMPATIBILITY = 1,
}

## Enumeration backing the [code]star_catalog[/code] dropdown in [IVOptionsPopup].
## Mapped to a magnitude cutoff by [constant IVStarsVisual.STAR_CATALOG_CUTOFFS].
## Insertion order must equal value order (the popup uses the setting value as the
## dropdown item index).
var star_catalog_settings: Dictionary[StringName, int] = {
	STAR_CATALOG_ALL = 0,
	STAR_CATALOG_MAG_11 = 1,
	STAR_CATALOG_MAG_9_5 = 2,
}

var _startup_max_fps := Engine.max_fps # from the project settings or the command line

@onready var _window := get_tree().get_root()


## Returns the size in pixels of [param viewport]'s 3D render buffer, which its shaders
## read as [code]VIEWPORT_SIZE[/code]: the window's own pixels times [member
## Viewport.scaling_3d_scale]. Make any decision about what the render can resolve in
## these, never in [method Viewport.get_visible_rect], which a display scale makes the
## 2D GUI's logical size.
static func get_render_size(viewport: Viewport) -> Vector2:
	var window := viewport as Window
	var sub_viewport := viewport as SubViewport
	var pixels := Vector2(window.size) if window else Vector2(sub_viewport.size)
	return (pixels * viewport.scaling_3d_scale).floor() # the engine truncates too


## Returns what this machine's GPU and screen can carry, judged from the GPU's type ([member
## IVGlobal.video_adapter_type]) and the physical pixel count of the screen the main window is
## on. Only a discrete GPU rates above [constant GraphicsTier.LOW]; a browser, and a
## Compatibility run that no Forward+ run has recorded the GPU for, cannot know the type.
static func get_graphics_tier() -> GraphicsTier:
	if IVGlobal.video_adapter_type != RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return GraphicsTier.LOW
	if _get_screen_pixels() > REDUCED_TIER_SCREEN_PIXELS:
		return GraphicsTier.REDUCED
	return GraphicsTier.FULL


## Returns the graphics defaults that suit this machine, keyed by setting, which
## [IVSettingsManager] applies when a project sets [member IVSettingsManager.graphics_target]. It
## holds only what differs from Core's defaults. [constant GraphicsTier.REDUCED] takes atmosphere
## quality to Reduced, shadow resolution to 2048 and render scale within [constant
## REDUCED_TIER_RENDER_PIXELS]; [constant GraphicsTier.LOW] also takes MSAA off and the star
## catalog to V 11, fits render scale within [constant LOW_TIER_RENDER_PIXELS], and has
## atmospheres at Min where [method is_angle_d3d11]. Forward+ stays the default renderer wherever
## it runs, but where the engine fell back from it, or the command line chose another, the
## running renderer is the default.
static func get_fitted_defaults() -> Dictionary[StringName, Variant]:
	var fitted_defaults: Dictionary[StringName, Variant] = {}
	match get_graphics_tier():
		GraphicsTier.REDUCED:
			fitted_defaults[&"atmosphere_quality"] = 1 # reduced
			fitted_defaults[&"shadow_resolution"] = 1 # 2048
			if can_scale_render():
				fitted_defaults[&"render_scale"] = _get_fitted_render_scale(
						REDUCED_TIER_RENDER_PIXELS)
		GraphicsTier.LOW:
			fitted_defaults[&"atmosphere_quality"] = 2 if is_angle_d3d11() else 1 # min, reduced
			fitted_defaults[&"shadow_resolution"] = 1 # 2048
			fitted_defaults[&"msaa_3d"] = 0 # disabled
			fitted_defaults[&"star_catalog"] = 1 # to V 11
			if can_scale_render():
				fitted_defaults[&"render_scale"] = _get_fitted_render_scale(LOW_TIER_RENDER_PIXELS)
	var running_renderer := RENDERING_METHODS.find(RenderingServer.get_current_rendering_method())
	if running_renderer != -1 and !_is_configured_renderer_running():
		fitted_defaults[&"renderer"] = running_renderer
	return fitted_defaults


## Returns true if setting [code]renderer[/code] can take effect in this build: a
## desktop build whose project names a settings override file for the engine to
## read at startup, and whose [member IVSettingsManager.graphics_target] is not
## [code]MODERN_GPU[/code]. Otherwise [IVOptionsPopup] hides the Renderer option.
static func can_set_renderer() -> bool:
	if !OS.has_feature("pc"):
		return false
	if IVSettingsManager.graphics_target == IVSettingsManager.GraphicsTarget.MODERN_GPU:
		return false
	var is_override_disabled: bool = ProjectSettings.get_setting(
			"application/config/disable_project_settings_override")
	var override_path: String = ProjectSettings.get_setting(
			"application/config/project_settings_override")
	return !is_override_disabled and !override_path.is_empty()


## Returns true where the Compatibility renderer runs through ANGLE's Direct3D 11 path: a
## Windows desktop build on the [code]opengl3_angle[/code] driver, and any browser on Windows.
static func is_angle_d3d11() -> bool:
	if OS.has_feature("web"):
		return OS.has_feature("web_windows")
	return (OS.get_name() == "Windows"
			and RenderingServer.get_current_rendering_driver_name() == "opengl3_angle")


## Returns false where a reduced 3D render scale costs frame time rather than saving it, which
## is wherever [method is_angle_d3d11]. There setting [code]render_scale[/code] is ignored, the
## scale holds at 100%, and [IVOptionsPopup] hides the 3D Render Scale option. See [i]3D render
## scale[/i] in [code]GRAPHICS_PROFILING.md[/code].
static func can_scale_render() -> bool:
	return !is_angle_d3d11()


## Returns Godot's rendering method for [param renderer_setting], a value of
## setting [code]renderer[/code].
static func get_rendering_method(renderer_setting: int) -> String:
	# A stale cached index past the end takes the last method, as the popup shows it.
	return RENDERING_METHODS[clampi(renderer_setting, 0, RENDERING_METHODS.size() - 1)]


## Writes [param rendering_method] to the project's settings override file, for the
## engine to start with next time. Anything else the file holds is kept. Call only
## if [method can_set_renderer].
static func write_rendering_method(rendering_method: String) -> Error:
	return _write_override_file(rendering_method)


# Also records the GPU's type whenever this run can read it.
static func _write_override_file(rendering_method := "") -> Error:
	var override_path: String = ProjectSettings.get_setting(
			"application/config/project_settings_override")
	var config := ConfigFile.new()
	if FileAccess.file_exists(override_path):
		var error := config.load(override_path)
		if error != OK:
			return error # don't clobber a file we can't read
	if rendering_method:
		config.set_value("rendering", "renderer/rendering_method", rendering_method)
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		# No section: the engine loads a key outside any section as its full path.
		config.set_value("", IVGlobal.VIDEO_ADAPTER_TYPE_SETTING,
				RenderingServer.get_video_adapter_type())
	return config.save(override_path)


# False where the command line, or the engine's fallback from a renderer it can't run, chose the
# renderer rather than the project settings and their override file.
static func _is_configured_renderer_running() -> bool:
	var configured_method: String = ProjectSettings.get_setting_with_override(
			&"rendering/renderer/rendering_method")
	return RenderingServer.get_current_rendering_method() == configured_method


static func _get_fitted_render_scale(max_render_pixels: int) -> int:
	var screen_pixels := _get_screen_pixels()
	for setting in RENDER_SCALES.size():
		var render_scale := RENDER_SCALES[setting]
		if screen_pixels * render_scale * render_scale <= max_render_pixels:
			return setting
	return RENDER_SCALES.size() - 1


static func _get_screen_pixels() -> int:
	var screen_size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	return screen_size.x * screen_size.y


func _ready() -> void:
	IVSettingsManager.changed.connect(_settings_listener)
	# The renderer cannot change without a restart, so this is written once and never again.
	RenderingServer.global_shader_parameter_set(&"iv_display_encode",
			1.0 if IVGlobal.is_gl_compatibility else 0.0)
	var atmosphere_quality: int = IVSettingsManager.get_setting(&"atmosphere_quality")
	is_atmosphere_min_session = _is_tier(atmosphere_quality, &"ATMOSPHERE_MIN")
	is_atmosphere_off_session = _is_tier(atmosphere_quality, &"ATMOSPHERE_OFF")
	_apply_atmosphere_quality()
	_apply_render_scale()
	_apply_msaa()
	_apply_fxaa()
	_apply_taa()
	_apply_shadow_resolution()
	_apply_frame_rate_cap()
	if can_set_renderer():
		IVSettingsManager.set_running_value(&"renderer",
				RENDERING_METHODS.find(RenderingServer.get_current_rendering_method()))
		_update_override_file()
	set_process(false)
	if !IVCoreSettings.apply_display_scale:
		return
	_scale_project_sized_window() # first, so the GUI never lays out in a window too small for it
	_apply_display_scale()
	_window.dpi_changed.connect(_apply_display_scale)
	# A browser changes devicePixelRatio with zoom and raises no event for it; the canvas
	# keeps its pixel count, so there is no resize to catch either.
	set_process(OS.has_feature("web"))


func _process(_delta: float) -> void:
	_apply_display_scale()


func _apply_display_scale() -> void:
	var display_scale := _get_display_scale()
	if display_scale <= 0.0 or is_equal_approx(display_scale, _window.content_scale_factor):
		return
	_window.content_scale_factor = display_scale


# Godot is only system-DPI-aware on Windows and reports no scale there. A system-aware
# window is drawn at the system DPI on every screen, and that is the primary screen's.
func _get_display_scale() -> float:
	if OS.has_feature("windows"):
		return DisplayServer.screen_get_dpi(DisplayServer.SCREEN_PRIMARY) / 96.0
	return DisplayServer.screen_get_scale()


# The project's window size is room for the GUI, so it grows with the display scale. A
# size that came from the command line, the OS or the editor's game view is left alone.
func _scale_project_sized_window() -> void:
	if (OS.has_feature("web") or Engine.is_embedded_in_editor()
			or _window.mode != Window.MODE_WINDOWED or _window.size != _get_project_window_size()):
		return
	var usable_rect := DisplayServer.screen_get_usable_rect(_window.current_screen)
	var decorations := _window.get_size_with_decorations() - _window.size
	var max_size := usable_rect.size - decorations
	if usable_rect.size == DisplayServer.screen_get_size(_window.current_screen):
		# Godot on Windows reports a window whose outer rect is the whole screen as fullscreen.
		max_size.y -= 1
	var scaled_size := Vector2i((Vector2(_window.size) * _get_display_scale()).round())
	var new_size := scaled_size.min(max_size)
	if new_size == _window.size:
		return
	var client_offset := _window.position - _window.get_position_with_decorations()
	# Position first: a size set first grows the window past the screen edge until it moves.
	@warning_ignore("integer_division")
	_window.position = (usable_rect.position + (usable_rect.size - new_size - decorations) / 2
			+ client_offset)
	_window.size = new_size


# The size Godot opens the window at when no command-line size overrides it.
func _get_project_window_size() -> Vector2i:
	var width: int = ProjectSettings.get_setting("display/window/size/viewport_width")
	var height: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	var width_override: int = ProjectSettings.get_setting(
			"display/window/size/window_width_override", 0)
	var height_override: int = ProjectSettings.get_setting(
			"display/window/size/window_height_override", 0)
	return Vector2i(width_override if width_override > 0 else width,
			height_override if height_override > 0 else height)


func _apply_atmosphere_quality() -> void:
	var setting: int = IVSettingsManager.get_setting(&"atmosphere_quality")
	# The session's shader programs decide what a change can reach: only a tier that runs on
	# them applies now, and any other waits for a restart.
	if (_is_tier(setting, &"ATMOSPHERE_MIN") == is_atmosphere_min_session
			and _is_tier(setting, &"ATMOSPHERE_OFF") == is_atmosphere_off_session):
		IVSettingsManager.set_running_value(&"atmosphere_quality", setting)
	# The packed table in _atmosphere.gdshaderinc holds the 6-node rule at 0 and the 4-node
	# rule at 6. Normal below is also where a stale cached index past the end lands, and Min,
	# whose shaders read only the ring cap, keeps Normal's; Off's read none of these.
	var gl_first := 0
	var gl_nodes := 6
	var ring_max_taps := 8
	match setting:
		1:
			gl_first = 6
			gl_nodes = 4
			ring_max_taps = 2
	RenderingServer.global_shader_parameter_set(&"iv_atm_gl_first", gl_first)
	RenderingServer.global_shader_parameter_set(&"iv_atm_gl_nodes", gl_nodes)
	RenderingServer.global_shader_parameter_set(&"iv_atm_ring_max_taps", ring_max_taps)


func _is_tier(atmosphere_quality: int, tier: StringName) -> bool:
	return atmosphere_quality == atmosphere_quality_settings.get(tier, -1)


func _apply_render_scale() -> void:
	# A cached reduced scale from a run that could scale is ignored where this one cannot.
	var setting: int = IVSettingsManager.get_setting(&"render_scale") if can_scale_render() else 0
	var render_scale := 1.0 # also the scale for a stale cached index past the end
	if setting > 0 and setting < RENDER_SCALES.size():
		render_scale = RENDER_SCALES[setting]
	# Only Forward+ has FSR 1. The engine would fall back to bilinear elsewhere anyway,
	# but with a warning.
	var is_forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	_window.scaling_3d_mode = (Viewport.SCALING_3D_MODE_FSR if is_forward_plus
			else Viewport.SCALING_3D_MODE_BILINEAR)
	if is_equal_approx(_window.scaling_3d_scale, render_scale):
		return
	_window.scaling_3d_scale = render_scale
	# The viewport raises no signal for this, and HUD sizes in render pixels must follow it.
	IVGlobal.viewport_size_changed.emit(_window.get_visible_rect().size)


func _apply_msaa() -> void:
	var setting: int = IVSettingsManager.get_setting(&"msaa_3d")
	match setting:
		1:
			_window.msaa_3d = Viewport.MSAA_2X
		2:
			_window.msaa_3d = Viewport.MSAA_4X
		3:
			_window.msaa_3d = Viewport.MSAA_8X
		_:
			_window.msaa_3d = Viewport.MSAA_DISABLED


func _apply_fxaa() -> void:
	if IVGlobal.is_gl_compatibility:
		return # FXAA unsupported in the Compatibility renderer (incl. web)
	var enable_fxaa: bool = IVSettingsManager.get_setting(&"fxaa")
	_window.screen_space_aa = (Viewport.SCREEN_SPACE_AA_FXAA if enable_fxaa
			else Viewport.SCREEN_SPACE_AA_DISABLED)


func _apply_taa() -> void:
	if IVGlobal.is_gl_compatibility:
		return # TAA is Forward+ only
	var enable_taa: bool = IVSettingsManager.get_setting(&"use_taa")
	_window.use_taa = enable_taa


func _apply_shadow_resolution() -> void:
	if IVGlobal.is_gl_compatibility and not IVCoreSettings.apply_gl_compatibility_shadows:
		return # single unshadowed light on Compatibility; no shadow map to size
	var setting: int = IVSettingsManager.get_setting(&"shadow_resolution")
	IVDynamicLight.shadow_maps_enabled = setting != 0
	var size := 8192 # also the size for a stale cached index past the end
	match setting:
		0:
			# Godot frees an atlas only when its size changes, not when the last map goes,
			# so Off parks it at the engine's minimum, a size no option uses.
			size = 256
		1:
			size = 2048
		2:
			size = 4096
	RenderingServer.directional_shadow_atlas_set_size(size, false)


func _apply_frame_rate_cap() -> void:
	var setting: int = IVSettingsManager.get_setting(&"frame_rate_cap")
	var max_fps := 30 # also the cap for a stale cached index past the end
	match setting:
		0:
			max_fps = _startup_max_fps
		1:
			max_fps = 60
	Engine.max_fps = max_fps


# A settings cache reset can leave the override file naming a renderer the setting no longer
# does, and a restart alone would never correct that.
func _update_override_file() -> void:
	var setting: int = IVSettingsManager.get_setting(&"renderer")
	if (get_rendering_method(setting) != RenderingServer.get_current_rendering_method()
			and _is_configured_renderer_running()):
		_write_renderer() # records the GPU's type too
		return
	_record_video_adapter_type()


func _record_video_adapter_type() -> void:
	if IVGlobal.is_gl_compatibility:
		return # can't read it
	var recorded: int = ProjectSettings.get_setting(IVGlobal.VIDEO_ADAPTER_TYPE_SETTING, -1)
	if recorded == IVGlobal.video_adapter_type:
		return
	var error := _write_override_file()
	if error != OK:
		push_error("Could not record the GPU's type in the project settings override: "
				+ error_string(error))


func _write_renderer() -> void:
	if !can_set_renderer():
		return
	var setting: int = IVSettingsManager.get_setting(&"renderer")
	var error := write_rendering_method(get_rendering_method(setting))
	if error != OK:
		push_error("Could not write the renderer to the project settings override: "
				+ error_string(error))


func _settings_listener(setting: StringName, _value: Variant) -> void:
	match setting:
		&"atmosphere_quality":
			_apply_atmosphere_quality()
		&"render_scale":
			_apply_render_scale()
		&"msaa_3d":
			_apply_msaa()
		&"fxaa":
			_apply_fxaa()
		&"use_taa":
			_apply_taa()
		&"shadow_resolution":
			_apply_shadow_resolution()
		&"frame_rate_cap":
			_apply_frame_rate_cap()
		&"renderer":
			_write_renderer()
