# cache_handler.gd
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
class_name IVCacheHandler
extends RefCounted

## Program component for managing user cached items.
##
## Handles file caching for keyed values with defaults, intended for game
## options, hotkeys, or similar data. Init on project_objects_instantiated
## signal.

signal current_changed(key: StringName, new_value: Variant)


var _version_key: StringName

var _defaults: Dictionary[StringName, Variant]
var _current: Dictionary[StringName, Variant]
var _file_name: String
var _file_version: String # any change will force a cache overwrite

var _cached: Dictionary[StringName, Variant] = {} # replica of disk cache notwithstanding I/O delay
var _io_manager: IVIOManager
var _file_path: String
var _missing_or_bad_cache_file := true


# *****************************************************************************

func _init(defaults: Dictionary[StringName, Variant], current: Dictionary[StringName, Variant],
		file_name: String, file_version := "", version_key := &"__version") -> void:
	_defaults = defaults
	_current = current
	_file_name = file_name
	_file_version = file_version
	_version_key = version_key

	_io_manager = IVGlobal.program["IOManager"]
	var cache_dir: String = IVCoreSettings.cache_dir
	_file_path = cache_dir.path_join(_file_name)
	if !DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)
	for key: StringName in _defaults:
		_current[key] = _get_reference_safe(_defaults[key])
	_read_cache()
	if _missing_or_bad_cache_file:
		_write_cache.call_deferred()


## If suppress_caching = true, be sure to call cache_now() later.
func change_current(key: StringName, value: Variant, suppress_caching := false) -> void:
	_current[key] = _get_reference_safe(value)
	current_changed.emit(key, _current[key])
	if !suppress_caching:
		cache_now()


func cache_now() -> void:
	_write_cache()


func is_default(key: StringName) -> bool:
	return _current[key] == _defaults[key]


func is_all_defaults() -> bool:
	return _current == _defaults


func get_cached_value(key: StringName) -> Variant:
	# If cache doesn't have it, we treat default as cached.
	# WARNING: Return is NOT reference-safe!
	if _cached.has(key):
		return _cached[key]
	return _defaults[key]


func is_cached(key: StringName) -> bool:
	if _cached.has(key):
		return _current[key] == _cached[key]
	return _current[key] == _defaults[key]


func get_cached_values() -> Dictionary[StringName, Variant]:
	# WARNING: Return is NOT reference-safe!
	return _cached


func restore_default(key: StringName, suppress_caching := false) -> void:
	if !is_default(key):
		change_current(key, _defaults[key], suppress_caching)


func restore_all_defaults(suppress_caching := false) -> void:
	for key: StringName in _defaults:
		restore_default(key, true)
	if !suppress_caching:
		cache_now()


func is_cache_current() -> bool:
	for key: StringName in _defaults:
		if !is_cached(key):
			return false
	return true


func restore_from_cache() -> void:
	for key: StringName in _defaults:
		if !is_cached(key):
			change_current(key, get_cached_value(key), true)


# *****************************************************************************


func _get_reference_safe(value: Variant) -> Variant:
	var type := typeof(value)
	if type == TYPE_DICTIONARY:
		var dict: Dictionary = value
		return dict.duplicate(true)
	if type == TYPE_ARRAY:
		var array: Array = value
		return array.duplicate(true)
	assert(type != TYPE_OBJECT, "Unallowed Object value")
	return value


func _write_cache() -> void:
	_cached.clear()
	for key: StringName in _defaults:
		if _current[key] != _defaults[key]: # cache only non-default values
			_cached[key] = _get_reference_safe(_current[key])
	_cached[_version_key] = _file_version
	_io_manager.store_var_to_file(_cached.duplicate(true), _file_path)


func _read_cache() -> void:
	# This happens at _init() only. We want this on the main thread so it
	# blocks until completed.
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
	if !file_dict.is_typed_key():
		prints("Overwriting obsolete cache file", _file_path)
		return
		
	if file_dict.get(_version_key, "") != _file_version:
		prints("Overwriting obsolete cache file", _file_path)
		return
	for key: StringName in file_dict:
		if _current.has(key):
			if typeof(_current[key]) != typeof(file_dict[key]):
				prints("Overwriting obsolete cache file", _file_path)
				return
	# file cache ok
	_cached = file_dict
	for key: StringName in _cached:
		if _current.has(key): # possibly old verson obsoleted key
			_current[key] = _get_reference_safe(_cached[key])
	_missing_or_bad_cache_file = false
