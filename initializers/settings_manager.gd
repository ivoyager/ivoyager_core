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
class_name IVSettingsManager
extends RefCounted

## Defines and manages user settings that are persisted in a cache file.
##
## Make all changes to static [member defaults] before _init()![br][br]
##
## Many (but not necessarily all) user settings are settable in [IVOptionsPopup].


static var defaults: Dictionary[StringName, Variant] = {
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
	&"language" : 0,
	&"gui_size" : IVGlobal.GUISize.GUI_MEDIUM,
	&"viewport_names_size" : 15,
	&"viewport_symbols_size" : 25,
	&"point_size" : 3,
	&"hide_hud_when_close" : true, # restart or load required

	# graphics/performance
	&"starmap" : IVGlobal.StarmapSize.STARMAP_16K,

	# misc
	&"mouse_action_releases_gui_focus" : true,

	# cached but not in IVOptionsPopup
	# FIXME: Obsolete below?
	&"save_dir" : "",
	&"pbd_splash_caption_open" : false,
	&"mouse_only_gui_nav" : false,

}

var file_name := "settings.ivbinary"
var file_version := "0.0.23" # update when old cache file might be problematic
var cache_handler: IVCacheHandler

var _current := IVGlobal.settings


func _init() -> void:
	cache_handler = IVCacheHandler.new(defaults, _current, file_name, file_version)
	cache_handler.current_changed.connect(_on_current_changed)


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func change_current(key: StringName, value: Variant, suppress_caching := false) -> void:
	cache_handler.change_current(key, value, suppress_caching)


func cache_now() -> void:
	cache_handler.cache_now()


func is_default(key: StringName) -> bool:
	return cache_handler.is_default(key)


func is_defaults() -> bool:
	return cache_handler.is_defaults()


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func restore_default(key: StringName, suppress_caching := false) -> void:
	cache_handler.restore_default(key, suppress_caching)


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func restore_defaults(suppress_caching := false) -> void:
	cache_handler.restore_defaults(suppress_caching)


func is_cache_current() -> bool:
	return cache_handler.is_cache_current()


func restore_from_cache() -> void:
	cache_handler.restore_from_cache()


func _on_current_changed(key: StringName, new_value: Variant) -> void:
	IVGlobal.setting_changed.emit(key, new_value)
