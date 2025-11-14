# settings_manager.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2025 Charlie Whitfield
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



## Emitted when settings are initialized and valid. This happens before
## "program" objects are instantiated.
signal initialized()
## Emitted after any setting change.
signal changed(setting: StringName, value: Variant)


## Name of the settings cache file.
var file_name := "settings.ivbinary"
## A new value obsoletes existing cache files. Update only when old cache files
## might be problematic.
var file_version := "0.0.23"


var _defaults: Dictionary[StringName, Variant] = {
	# save/load (only matters if Save pluin is enabled)
	&"save_base_name" : "I Voyager",
	&"append_date_to_save" : true,
	&"pause_on_load" : false,
	&"autosave_time_min" : 10,

	# camera
	&"camera_transfer_time" : 1.0,
	&"camera_mouse_in_out_rate" : 1.0,
	&"camera_mouse_move_rate" : 1.0,
	&"camera_mouse_pitch_yaw_rate" : 1.0,
	&"camera_mouse_roll_rate" : 1.0,
	&"camera_key_in_out_rate" : 1.0,
	&"camera_key_move_rate" : 1.0,
	&"camera_key_pitch_yaw_rate" : 1.0,
	&"camera_key_roll_rate" : 1.0,

	# UI & HUD display
	&"language" : 0, # see IVLanguageManager
	&"gui_size" : IVGlobal.GUISize.GUI_MEDIUM,
	&"label3d_names_size_percent" : 100,
	&"label3d_symbols_size_percent" : 100,
	&"point_size" : 3,
	&"hide_hud_when_close" : true, # restart or load required

	# graphics/performance
	&"starmap" : IVGlobal.StarmapSize.STARMAP_16K,
}

var _settings: Dictionary[StringName, Variant] = {}
var _cache_handler: IVCacheHandler


func _ready() -> void:
	IVStateManager.core_init_preinitialized.connect(_on_core_init_preinitialized)


## For preinitializer script only! Defaults become read-only at cache init.
## Supply [param value] = null to remove a setting.
func set_default(key: StringName, value: Variant) -> void:
	assert(!_defaults.is_read_only(), "Call set_default() before cache init")
	if value == null:
		_defaults.erase(key)
	else:
		_defaults[key] = value


## If calling with [param suppress_caching] = true, call [method cache_now]
## after changes.
func change_setting(key: StringName, value: Variant, suppress_caching := false) -> void:
	_cache_handler.change_current(key, value, suppress_caching)


func get_setting(key: StringName) -> Variant:
	return _settings[key]


func get_default(key: StringName) -> Variant:
	return _defaults[key]


func cache_now() -> void:
	_cache_handler.cache_now()


func is_default(key: StringName) -> bool:
	return _cache_handler.is_default(key)


func is_defaults() -> bool:
	return _cache_handler.is_defaults()


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func restore_default(key: StringName, suppress_caching := false) -> void:
	_cache_handler.restore_default(key, suppress_caching)


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func restore_defaults(suppress_caching := false) -> void:
	_cache_handler.restore_defaults(suppress_caching)


func is_cache_current() -> bool:
	return _cache_handler.is_cache_current()


func restore_from_cache() -> void:
	_cache_handler.restore_from_cache()


func _on_core_init_preinitialized() -> void:
	assert(!_cache_handler)
	_defaults.make_read_only()
	_cache_handler = IVCacheHandler.new(_defaults, _settings, file_name, file_version)
	_cache_handler.current_changed.connect(_on_current_changed)
	initialized.emit()


func _on_current_changed(key: StringName, new_value: Variant) -> void:
	changed.emit(key, new_value)
