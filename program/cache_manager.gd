# cache_manager.gd
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
class_name IVCacheManager
extends RefCounted

## Abstract base class for managing user cached items.
##
## Subclasses include [IVSettingsManager] and [IVInputMapManager].

# project vars - set in subclass _init(); project can modify at init
var cache_file_name := "generic_item.ivbinary" # change in subclass
var cache_file_version := 1 # change in subclass; non-current is overwritten
var defaults: Dictionary # subclass defines in _init()
var current: Dictionary # subclass makes or references an existing dict

# private
var _io_manager: IVIOManager
var _file_path: String
var _cached := {} # exact replica of disk cache notwithstanding I/O delay
var _missing_or_bad_cache_file := true


# *****************************************************************************

func _init() -> void:
	IVGlobal.project_objects_instantiated.connect(_on_project_objects_instantiated)


func _on_project_objects_instantiated() -> void:
	_io_manager = IVGlobal.program["IOManager"]
	var cache_dir: String = IVCoreSettings.cache_dir
	_file_path = cache_dir.path_join(cache_file_name)
	# TEST34
	if !DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)
	for key: StringName in defaults:
		var default: Variant = defaults[key]
		var type := typeof(default)
		if type == TYPE_DICTIONARY or type == TYPE_ARRAY:
			@warning_ignore("unsafe_method_access")
			current[key] = default.duplicate(true)
		else:
			current[key] = default
	_read_cache()
	if _missing_or_bad_cache_file:
		_write_cache.call_deferred()


# *****************************************************************************

func change_current(key: StringName, value: Variant, suppress_caching := false) -> void:
	# If suppress_caching = true, then be sure to call cache_now() later.
	_about_to_change_current(key)
	var type := typeof(value)
	if type == TYPE_DICTIONARY or type == TYPE_ARRAY:
		@warning_ignore("unsafe_method_access")
		current[key] = value.duplicate(true)
	else:
		current[key] = value
	_on_change_current(key)
	if !suppress_caching:
		cache_now()


func cache_now() -> void:
	_write_cache()


func is_default(key: StringName) -> bool:
	return current[key] == defaults[key]


func is_all_defaults() -> bool:
	return current == defaults


func get_cached_value(key: StringName, cached_values: Dictionary) -> Variant: # unknown type
	# If cache doesn't have it, we treat default as cached
	if cached_values.has(key):
		return cached_values[key]
	return defaults[key]


func is_cached(key: StringName, cached_values: Dictionary) -> bool:
	if cached_values.has(key):
		return current[key] == cached_values[key]
	return current[key] == defaults[key]


func get_cached_values() -> Dictionary:
	return _cached


func restore_default(key: StringName, suppress_caching := false) -> void:
	if !is_default(key):
		change_current(key, defaults[key], suppress_caching)


func restore_all_defaults(suppress_caching := false) -> void:
	for key: StringName in defaults:
		restore_default(key, true)
	if !suppress_caching:
		cache_now()


func is_cache_current() -> bool:
	var cached_values := get_cached_values()
	for key: StringName in defaults:
		if !is_cached(key, cached_values):
			return false
	return true


func restore_from_cache() -> void:
	var cached_values := get_cached_values()
	for key: StringName in defaults:
		if !is_cached(key, cached_values):
			var cached_value: Variant = get_cached_value(key, cached_values)
			change_current(key, cached_value, true)


# *****************************************************************************

func _about_to_change_current(_item_name: StringName) -> void:
	# subclass logic
	pass


func _on_change_current(_item_name: StringName) -> void:
	# subclass logic
	pass


func _write_cache() -> void:
	_cached.clear()
	for key: StringName in defaults:
		if current[key] != defaults[key]: # cache only non-default values
			_cached[key] = current[key]
	_cached[&"__version__"] = cache_file_version
	_io_manager.store_var_to_file(_cached.duplicate(true), _file_path)


func _read_cache() -> void:
	# This happens on 'project_objects_instantiated' only. We want this on the
	# main thread so it blocks until completed.
	var file := FileAccess.open(_file_path, FileAccess.READ)
	if !file:
		prints("Creating new cache file", _file_path)
		return
	var file_var: Variant = file.get_var() # untyped for safety
	# test for version and type consistency (no longer used items are ok)
	if typeof(file_var) != TYPE_DICTIONARY:
		prints("Overwriting obsolete cache file", _file_path)
		return
	var file_dict: Dictionary = file_var
	if file_dict.get("__version__", -1) != cache_file_version:
		prints("Overwriting obsolete cache file", _file_path)
		return
	for key: StringName in file_dict:
		if current.has(key):
			if typeof(current[key]) != typeof(file_dict[key]):
				prints("Overwriting obsolete cache file:", _file_path)
				return
	# file cache ok
	_cached = file_dict
	for key: StringName in _cached:
		if current.has(key): # possibly old verson obsoleted key
			current[key] = _cached[key]
	_missing_or_bad_cache_file = false
