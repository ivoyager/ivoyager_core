# settings_manager.gd
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
extends Node

## Singleton [IVSettingsManager] defines and manages user settings that are
## persisted in a cache file.
##
## A preinitializer script can make changes to default settings or add new
## cached settings using [method set_default]. This must happen [i]before[/i]
## cache init. Changes to public properties must also happen before cache init.[br][br]
##
## Settings are initialized and valid before "program" objects are instantiated.[br][br]
##
## Many settings are settable in [IVOptionsPopup]. Other settings can be added
## that are "hidden" from user Options and managed by code.[br][br]
##
## A project that runs on a range of hardware sets [member graphics_target], and
## its graphics defaults are then fitted to each machine rather than applied as
## written.[br][br]
##
## A setting that takes effect only at startup can register the value the running
## session actually uses with [method set_running_value]. [method
## is_restart_pending] then tells whether the current settings need a restart, and
## [method is_restart_pending_for] whether one setting does.[br][br]
##
## With [member IVCoreSettings.enable_graphics_rescue], a start that crashes, freezes or is
## killed before it finishes has the next start restore [member graphics_settings] to their
## defaults, and [member graphics_reset] says so. User argument [constant
## RESET_GRAPHICS_ARGUMENT] asks for the same on any start. See [i]A setting the machine can't
## carry[/i] in [code]GRAPHICS_PROFILING.md[/code].[br][br]



## Emitted when settings are initialized and valid. This happens before
## "program" objects are instantiated.
signal initialized()
## Emitted after any setting change.
signal changed(setting: StringName, value: Variant)


## The hardware a project supports, which decides whether its graphics defaults are
## fitted to each machine. See [member graphics_target].
enum GraphicsTarget {
	## Graphics defaults apply as written, on every machine.
	NONE,
	## Anything from integrated graphics and browsers up. The Renderer option offers
	## Compatibility where the project allows it (see [method
	## IVGraphicsManager.can_set_renderer]).
	BROAD_HARDWARE,
	## GPUs that run Forward+, the only renderer: the Renderer option is hidden.
	MODERN_GPU,
}

## Why this start restored [member graphics_settings] to their defaults; see [member
## graphics_reset].
enum GraphicsReset {
	## It didn't, or none differed from its default.
	NONE,
	## The last start never finished; see [member IVCoreSettings.enable_graphics_rescue].
	FAILED_START,
	## The command line asked, with [constant RESET_GRAPHICS_ARGUMENT].
	REQUESTED,
}

## A command-line user argument (after [code]--[/code]) that has this start restore [member
## graphics_settings] to their defaults.
const RESET_GRAPHICS_ARGUMENT := "--reset-graphics"
## Seconds of running simulator after which a start counts as finished. A start that ends sooner,
## other than by quitting, counts as failed; see [member IVCoreSettings.enable_graphics_rescue].
const START_CHECK_TIME := 10.0


## Name of the settings cache file.
var file_name := "settings.ivbinary"
## Name of the file, beside the settings cache, that records whether the last start finished.
var start_marker_file_name := "start_marker.ivbinary"
## A new value obsoletes existing cache files. Update only when old cache files
## might be problematic.
var file_version := "0.0.23"
## Set in a preinitializer. Any target but [constant GraphicsTarget.NONE] replaces
## graphics defaults at cache init with those [method
## IVGraphicsManager.get_fitted_defaults] gives for this machine, so a weaker GPU or a
## denser screen starts with lighter settings; Forward+ stays the default renderer
## wherever it runs. A setting the project gives its own default with [method
## set_default] keeps it on every machine.
var graphics_target := GraphicsTarget.NONE
## Settings that decide what the GPU draws each frame: the ones [method
## restore_graphics_defaults] restores, as does a start after a failed one. A project that adds
## such a setting with [method set_default] should append it here.
var graphics_settings: Array[StringName] = [&"atmosphere_quality", &"glow", &"render_scale",
		&"msaa_3d", &"fxaa", &"use_taa", &"shadow_resolution", &"star_catalog", &"renderer"]
## Why this start restored [member graphics_settings] to their defaults, if it did. Valid after
## [signal initialized].
var graphics_reset := GraphicsReset.NONE


var _defaults: Dictionary[StringName, Variant] = {
	# save/load (only matters if Save pluin is enabled)
	&"save_base_name" : "I Voyager",
	&"append_date_to_save" : true,
	&"pause_on_load" : false,
	&"autosave_time_min" : 10,

	# camera
	&"physical_light" : true, # row appears only if IVCoreSettings.enable_physical_light
	&"camera_transfer_time" : 1.0,
	&"camera_mouse_in_out_inverse" : false,
	&"camera_mouse_in_out_rate" : 1.0,
	&"camera_mouse_move_rate" : 1.0,
	&"camera_mouse_pitch_yaw_rate" : 1.0,
	&"camera_mouse_roll_rate" : 1.0,
	&"camera_key_in_out_rate" : 1.0,
	&"camera_key_move_rate" : 1.0,
	&"camera_key_pitch_yaw_rate" : 1.0,
	&"camera_key_roll_rate" : 1.0,

	# screenshots
	&"screenshot_width" : 1200, # px; height follows from screenshot_aspect
	&"screenshot_aspect" : 0, # see IVScreenshotManager.aspects (0 = preserve window aspect)
	&"screenshot_file_dialog" : true, # false saves quietly to the last-used directory

	# UI & HUD display
	&"language" : 0, # see IVLanguageManager
	&"gui_size" : 1, # see IVCoreSettings.gui_size_settings
	&"gui_fade_while_dragging" : true, # see IVControlModFade
	&"gui_fade_when_idle" : true, # see IVControlModFade
	&"label3d_names_size_percent" : 100,
	&"body_symbol_size_percent" : 100, # % of IVThemeManager GUI-scaled symbol_base_size (IVBodyPositionVisual)
	&"small_bodies_symbol_size_percent" : 40, # % of IVThemeManager GUI-scaled symbol_base_size (shaped symbols)
	&"small_bodies_point_size" : 3, # render px for plain points (symbol_type -1)
	&"hide_hud_when_close" : true, # restart or load required
	
	# graphics/performance
	&"atmosphere_quality" : 0, # 0,1,2,3 = normal,reduced,min,off; see IVGraphicsManager
	&"glow" : true, # Compatibility at restart; see IVGraphicsManager
	&"render_scale" : 0, # 0,1,2,3 = 100,85,70,50%; see IVGraphicsManager
	&"msaa_3d" : 1, # 0,1,2,3 = disabled,2x,4x,8x (== Viewport.MSAA_*)
	&"fxaa" : false, # not available in Compatibility renderer (incl. web)
	&"use_taa" : false, # Forward+ only; ghosts vertex-shader-positioned orbit lines
	&"shadow_resolution" : 2, # 0,1,2,3 = off,2048,4096,8192
	&"frame_rate_cap" : 0, # 0,1,2 = none,60,30 fps; see IVGraphicsManager
	&"renderer" : 0, # 0,1 = forward_plus,gl_compatibility (at restart); see IVGraphicsManager
	&"star_catalog" : 0, # 0,1,2 = all,to V 11,to V 9.5 (at restart); see IVStarsVisual
}

var _settings: Dictionary[StringName, Variant] = {}
var _running_values: Dictionary[StringName, Variant] = {}
var _project_default_keys: Dictionary[StringName, bool] = {}
var _cache_handler: IVCacheHandler


func _ready() -> void:
	IVStateManager.core_init_preinitialized.connect(_on_core_init_preinitialized)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		mark_start_finished()


## Add or change a default setting.
## For preinitializer script only! Defaults become read-only at cache init.
## Supply [param value] = null to remove a setting. A default set here holds on
## every machine, whatever [member graphics_target] would fit.
func set_default(key: StringName, value: Variant) -> void:
	assert(!_defaults.is_read_only(), "Call set_default() before cache init")
	_project_default_keys[key] = true
	if value == null:
		_defaults.erase(key)
	else:
		_defaults[key] = value


## Returns true if [param key] is a registered setting (whether or not the
## current value differs from the default).
func has_setting(key: StringName) -> bool:
	return _defaults.has(key)


## If calling with [param suppress_caching] = true, call [method cache_now]
## after changes.
func change_setting(key: StringName, value: Variant, suppress_caching := false) -> void:
	_cache_handler.change_current(key, value, suppress_caching)


## Returns the current value of setting [param key]. Errors if [param key] is
## not a registered setting.
func get_setting(key: StringName) -> Variant:
	return _settings[key]


## Returns the default value of setting [param key]. Errors if [param key] is
## not a registered setting.
func get_default(key: StringName) -> Variant:
	return _defaults[key]


## Writes the current settings to the cache file. Useful after a batch of
## [method change_setting] calls made with [param suppress_caching] = true.
func cache_now() -> void:
	_cache_handler.cache_now()


## Returns true if [param key] currently equals its default value.
func is_default(key: StringName) -> bool:
	return _cache_handler.is_default(key)


## Returns true if [i]all[/i] settings currently equal their defaults.
func is_defaults() -> bool:
	return _cache_handler.is_defaults()


## Returns true if every one of [member graphics_settings] currently equals its default.
func is_graphics_defaults() -> bool:
	for key in graphics_settings:
		if _defaults.has(key) and !_cache_handler.is_default(key):
			return false
	return true


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func restore_default(key: StringName, suppress_caching := false) -> void:
	_cache_handler.restore_default(key, suppress_caching)


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func restore_defaults(suppress_caching := false) -> void:
	_cache_handler.restore_defaults(suppress_caching)


## Restores each of [member graphics_settings] to its default. If [param suppress_caching] ==
## true, be sure to call [method cache_now] later.
func restore_graphics_defaults(suppress_caching := false) -> void:
	for key in graphics_settings:
		if _defaults.has(key):
			_cache_handler.restore_default(key, true)
	if !suppress_caching:
		_cache_handler.cache_now()


## Returns true if the in-memory settings match the cache file (i.e., no
## un-cached changes are pending).
func is_cache_current() -> bool:
	return _cache_handler.is_cache_current()


## Reloads settings from the cache file, discarding any in-memory changes.
func restore_from_cache() -> void:
	_cache_handler.restore_from_cache()


## For setting [param key], one that takes effect only at startup, records
## [param value] as the value the running session actually uses. That can differ
## from the setting's value at startup, e.g. when the command line overrode it.
func set_running_value(key: StringName, value: Variant) -> void:
	assert(_defaults.has(key), "Setting '%s' doesn't exist" % key)
	_running_values[key] = value


## Returns true if any setting registered with [method set_running_value] now
## differs from the value the running session uses, so that it needs a restart
## to take effect. Valid after [signal initialized].
func is_restart_pending() -> bool:
	for key in _running_values:
		if _settings[key] != _running_values[key]:
			return true
	return false


## Returns true if setting [param key] is registered with [method set_running_value]
## and now differs from the value the running session uses. Valid after [signal
## initialized].
func is_restart_pending_for(key: StringName) -> bool:
	return _running_values.has(key) and _settings[key] != _running_values[key]


## Records this start as finished before [constant START_CHECK_TIME] s of running simulator, so
## the next start doesn't take it for a failed one. Call before a deliberate restart or page
## reload that doesn't go through [method IVStateManager.quit].
func mark_start_finished() -> void:
	if IVCoreSettings.enable_graphics_rescue and _cache_handler:
		_write_start_marker(false)


func _on_core_init_preinitialized() -> void:
	assert(!_cache_handler)
	if graphics_target != GraphicsTarget.NONE:
		_fit_graphics_defaults()
	_defaults.make_read_only()
	_cache_handler = IVCacheHandler.new(_defaults, _settings, file_name, file_version)
	_cache_handler.current_changed.connect(_on_current_changed)
	_check_last_start()
	initialized.emit()


func _check_last_start() -> void:
	if OS.get_cmdline_user_args().has(RESET_GRAPHICS_ARGUMENT):
		graphics_reset = GraphicsReset.REQUESTED
	elif (IVCoreSettings.enable_graphics_rescue and _is_last_start_unfinished()
			and !is_graphics_defaults()):
		graphics_reset = GraphicsReset.FAILED_START
	if graphics_reset != GraphicsReset.NONE:
		restore_graphics_defaults()
	if !IVCoreSettings.enable_graphics_rescue:
		return
	_write_start_marker(true)
	IVStateManager.simulator_started.connect(_on_simulator_started, CONNECT_ONE_SHOT)
	IVStateManager.about_to_quit.connect(mark_start_finished)


func _on_simulator_started() -> void:
	get_tree().create_timer(START_CHECK_TIME, true, false, true).timeout.connect(
			mark_start_finished)


func _is_last_start_unfinished() -> bool:
	var file := FileAccess.open(_get_start_marker_path(), FileAccess.READ)
	return file != null and file.get_var() == true


func _write_start_marker(is_unfinished: bool) -> void:
	var file := FileAccess.open(_get_start_marker_path(), FileAccess.WRITE)
	if !file:
		push_warning("Could not write %s: %s" % [_get_start_marker_path(),
				error_string(FileAccess.get_open_error())])
		return
	file.store_var(is_unfinished)


func _get_start_marker_path() -> String:
	return IVCoreSettings.cache_dir.path_join(start_marker_file_name)


func _fit_graphics_defaults() -> void:
	var fitted_defaults := IVGraphicsManager.get_fitted_defaults()
	for key in fitted_defaults:
		if _defaults.has(key) and !_project_default_keys.has(key):
			_defaults[key] = fitted_defaults[key]


func _on_current_changed(key: StringName, new_value: Variant) -> void:
	changed.emit(key, new_value)
