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

## Defines and manages user settings.
##
## Non-default settings are persisted in a cache file.[br][br]
##
## Many (but not necessarily all) user settings are settable in [IVOptionsPopup].


var file_name := "settings.ivbinary"
var file_version := "0.0.23" # update when obsoleted
var current := IVGlobal.settings
var defaults := IVCoreSettings.default_cached_settings
var cache_handler: IVCacheHandler


func _init() -> void:
	cache_handler = IVCacheHandler.new(defaults, current, file_name, file_version)
	cache_handler.current_changed.connect(_on_current_changed)


## If suppress_caching = true, be sure to call cache_now() later.
func change_current(key: StringName, value: Variant, suppress_caching := false) -> void:
	cache_handler.change_current(key, value, suppress_caching)


func cache_now() -> void:
	cache_handler.cache_now()


func is_default(key: StringName) -> bool:
	return cache_handler.is_default(key)


func is_all_defaults() -> bool:
	return cache_handler.is_all_defaults()


func get_cached_values() -> Dictionary[StringName, Variant]:
	return cache_handler.get_cached_values()


## If suppress_caching = true, be sure to call cache_now() later.
func restore_default(key: StringName, suppress_caching := false) -> void:
	cache_handler.restore_default(key, suppress_caching)


## If suppress_caching = true, be sure to call cache_now() later.
func restore_all_defaults(suppress_caching := false) -> void:
	cache_handler.restore_all_defaults(suppress_caching)


func is_cache_current() -> bool:
	return cache_handler.is_cache_current()


func restore_from_cache() -> void:
	cache_handler.restore_from_cache()


func _on_current_changed(key: StringName, new_value: Variant) -> void:
	IVGlobal.setting_changed.emit(key, new_value)
