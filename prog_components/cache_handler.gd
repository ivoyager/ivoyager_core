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

## Program component for handling user cached items like game options, hotkeys
## and similar data.
##
## Cache data must be in the form [code]Dictionary[StringName, Variant][/code]. 
##
## All public methods are reference-safe in case cache values include arrays
## or dictionaries (this is likely the case for hotkeys).[br][br]
##
## The cache file is read once only at [method _init]. It is written (on thread if
## [code]IVCoreSettings.use_threads == true[/code]) when [method change_current] is
## called unless [param suppress_caching] is set. If many changes are to be made
## at once (or cache needs to be unchanged so [method restore_from_cache] can be
## used), use [param suppress_caching] = true and be sure to call [method cache_now]
## later.[br][br]
##
## Cache file will be stored in directory specified in
##   [property IVCoreSettings.cache_dir].[br][br]
##
## Note: Default values are not actually written to cache file. Default values
## are treated as "cached" for the purpose of [method get_cached_value],
## [method is_cached], etc. Only current values different than default are
## written to cache.[br][br]

signal current_changed(key: StringName, new_value: Variant)


var _defaults: Dictionary[StringName, Variant]
var _current: Dictionary[StringName, Variant]
var _cached: Dictionary[StringName, Variant] = {} # replica of disk cache
var _file_path: String
var _file_version: String # different version is ignored and overwritten
var _version_key: StringName


# *****************************************************************************

## Dictionary [param defaults] must have keys for all data to be cached.
## Dictionary [param current] is expected to be empty; it will be filled with file
## cached values or (where these don't exist) default values for all keys in
## [param defaults]. After init, [param current] is guaranteed to have the same
## exact keys as [param defaults].[br][br]
##
## If [param file_version] is specified, an existing cache file with a different
## version will be ignored and overwritten.
func _init(defaults: Dictionary[StringName, Variant], current: Dictionary[StringName, Variant],
		file_name: String, file_version := "", version_key := &"__version") -> void:
	assert(!defaults.is_empty())
	assert(current.is_empty())
	_defaults = defaults
	_current = current
	_file_version = file_version
	_version_key = version_key
	var cache_dir: String = IVCoreSettings.cache_dir
	_file_path = cache_dir.path_join(file_name)
	if !DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)
	for key in _defaults:
		_current[key] = _get_reference_safe(_defaults[key])
	if !_read_cache():
		_write_cache.call_deferred()


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func change_current(key: StringName, value: Variant, suppress_caching := false) -> void:
	_current[key] = _get_reference_safe(value)
	current_changed.emit(key, _current[key])
	if !suppress_caching:
		_write_cache()


func cache_now() -> void:
	_write_cache()


func is_default(key: StringName) -> bool:
	return _current[key] == _defaults[key]


func is_defaults() -> bool:
	return _current == _defaults


func get_cached_value(key: StringName) -> Variant:
	if _cached.has(key):
		return _get_reference_safe(_cached[key])
	return _get_reference_safe(_defaults[key])


func is_cached(key: StringName) -> bool:
	if _cached.has(key):
		return _current[key] == _cached[key]
	return _current[key] == _defaults[key]


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func restore_default(key: StringName, suppress_caching := false) -> void:
	if !is_default(key):
		change_current(key, _defaults[key], suppress_caching)


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func restore_defaults(suppress_caching := false) -> void:
	for key: StringName in _defaults:
		restore_default(key, true)
	if !suppress_caching:
		cache_now()


func is_cache_current() -> bool:
	for key in _defaults:
		if !is_cached(key):
			return false
	return true


## Restores [param current] values back to cached. This method only does
## anything if changes were made using [method change_current], [method restore_default]
## or [method restore_defaults] with [param suppress_caching] == true.
func restore_from_cache() -> void:
	for key in _defaults:
		if !is_cached(key):
			change_current(key, _get_cached_value(key), true)


# *****************************************************************************


func _get_cached_value(key: StringName) -> Variant:
	# WARNING: Return is NOT reference-safe! Use appropriately.
	if _cached.has(key):
		return _cached[key]
	return _defaults[key]


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


func _read_cache() -> bool:
	# This happens once at _init() only. We want this on the main thread so it
	# blocks until completed.
	var file := FileAccess.open(_file_path, FileAccess.READ)
	if !file:
		prints("Creating new cache file", _file_path)
		return false
	
	# May have old cache file, so treat with care...
	var file_var: Variant = file.get_var()
	if typeof(file_var) != TYPE_DICTIONARY:
		prints("Overwriting obsolete cache file", _file_path)
		return false
	var file_dict: Dictionary = file_var
	if file_dict.get_typed_key_builtin() != TYPE_STRING_NAME:
		prints("Overwriting obsolete cache file", _file_path)
		return false
	if file_dict.get(_version_key, "") != _file_version:
		prints("Overwriting obsolete cache file", _file_path)
		return false
	
	# Existing file cache ok to read. It may still have obsoleted keys or
	# wrongly typed values; we'll skip over those here (file will be overwriten
	# later).
	for key: StringName in file_dict:
		if !_defaults.has(key):
			continue
		if typeof(file_dict[key]) != typeof(_defaults[key]):
			continue
		if file_dict[key] == _defaults[key]:
			continue
		_cached[key] = file_dict[key]
		_current[key] = _get_reference_safe(file_dict[key]) # merge w/ defaults
	return true


func _write_cache() -> void:
	# It's safe to write file on thread, since we only read once at _init().
	for key in _defaults:
		# _cached only has keys for non-default _current
		if _current[key] == _defaults[key]:
			_cached.erase(key)
		elif !_cached.has(key) or _cached[key] != _current[key]:
			_cached[key] = _get_reference_safe(_current[key])
	_cached[_version_key] = _file_version
	if IVCoreSettings.use_threads:
		WorkerThreadPool.add_task(_write_cache_file.bind(_cached.duplicate(true)))
	else:
		_write_cache_file(_cached)


func _write_cache_file(cache_data: Dictionary[StringName, Variant]) -> void:
	var file := FileAccess.open(_file_path, FileAccess.WRITE)
	var err := FileAccess.get_open_error()
	if err != OK:
		push_error("Could not open file for write: ", _file_path)
		return
	file.store_var(cache_data)
