# view_manager.gd
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
class_name IVViewManager
extends Node

## Manages [IVView] instances that are persisted via gamesave or cache.

const files := preload("res://addons/ivoyager_core/static/files.gd")

const PERSIST_MODE := IVEnums.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_gamesave_views",
]

var ViewScript: Script
var file_path := IVCoreSettings.cache_dir.path_join("views.ivbinary")

var _gamesave_views: Dictionary[StringName, IVView] = {}
var _cached_views: Dictionary[StringName, IVView] = {}
var _io_manager: IVIOManager
var _missing_or_bad_cache_file := true


func _init() -> void:
	IVGlobal.project_objects_instantiated.connect(_on_project_objects_instantiated)


func _on_project_objects_instantiated() -> void:
	ViewScript = IVGlobal.procedural_classes[&"View"]
	_io_manager = IVGlobal.program[&"IOManager"]
	DirAccess.make_dir_recursive_absolute(IVCoreSettings.cache_dir)
	_read_cache()
	if _missing_or_bad_cache_file:
		_write_cache()


# public

func save_view(view_name: StringName, collection_name: StringName, is_cached: bool, flags: int,
		allow_threaded_cache_write := true) -> void:
	var key := view_name + "." + collection_name
	var view := get_view_object(view_name, collection_name, is_cached)
	if view:
		view.reset()
	else:
		@warning_ignore("unsafe_method_access")
		view = ViewScript.new()
	view.save_state(flags)
	if is_cached:
		_cached_views[key] = view
		_write_cache(allow_threaded_cache_write)
	else:
		_gamesave_views[key] = view


func set_view(view_name: StringName, collection_name: StringName, is_cached: bool,
		is_camera_instant_move := false) -> void:
	var key := view_name + "." + collection_name
	var view: IVView
	if is_cached:
		view = _cached_views.get(key)
	else:
		view = _gamesave_views.get(key)
	if !view:
		return
	view.set_state(is_camera_instant_move)


func save_view_object(view: IVView, view_name: StringName, collection_name: StringName, is_cached: bool,
		allow_threaded_cache_write := true) -> void:
	var key := view_name + "." + collection_name
	if is_cached:
		_cached_views[key] = view
		_write_cache(allow_threaded_cache_write)
	else:
		_gamesave_views[key] = view


func get_view_object(view_name: StringName, collection_name: StringName, is_cached: bool) -> IVView:
	var key := view_name + "." + collection_name
	if is_cached:
		return _cached_views.get(key)
	return _gamesave_views.get(key)


func has_view(view_name: StringName, collection_name: StringName, is_cached: bool) -> bool:
	var key := view_name + "." + collection_name
	if is_cached:
		return _cached_views.has(key)
	return _gamesave_views.has(key)


func remove_view(view_name: StringName, collection_name: StringName, is_cached: bool) -> void:
	var key := view_name + "." + collection_name
	if is_cached:
		_cached_views.erase(key)
		_write_cache()
	else:
		_gamesave_views.erase(key)
	

func get_names_in_collection(collection_name: StringName, is_cached: bool) -> Array[StringName]:
	var group: Array[StringName] = []
	var suffix := "." + collection_name
	var dict := _cached_views if is_cached else _gamesave_views
	for key: StringName in dict:
		if key.ends_with(suffix):
			group.append(key.trim_suffix(suffix))
	return group


# private

func _read_cache() -> void:
	# Populate _cached_views once at project init on main thread.
	var file := FileAccess.open(file_path, FileAccess.READ)
	if !file:
		prints("Creating new cache file", file_path)
		return
	var file_var: Variant = file.get_var() # untyped for safety
	file.close()
	if typeof(file_var) != TYPE_DICTIONARY:
		prints("Overwriting obsolete cache file", file_path)
		return
	var dict: Dictionary = file_var
	if !dict.is_typed():
		prints("Overwriting obsolete cache file", file_path)
		return
	var bad_cache_data := false
	for key: StringName in dict:
		var data: Array = dict[key]
		@warning_ignore("unsafe_method_access") # possible replacement class
		var view: IVView = ViewScript.new()
		if !view.set_data_from_cache(data): # may be prior version
			bad_cache_data = true
			continue
		_cached_views[key] = view
	if !bad_cache_data:
		_missing_or_bad_cache_file = false


func _write_cache(allow_threaded_cache_write := true) -> void:
	# Unless this is app exit, no one is waiting for this and we can do the
	# file write on i/o thread. At app exit, we want the main thread to wait.
	var dict := {}
	for key: StringName in _cached_views:
		var view: IVView = _cached_views[key]
		var data := view.get_data_for_cache()
		dict[key] = data
	if allow_threaded_cache_write:
		_io_manager.callback(_write_cache_maybe_on_io_thread.bind(dict))
	else:
		_write_cache_maybe_on_io_thread(dict)
	

func _write_cache_maybe_on_io_thread(dict: Dictionary) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if !file:
		print("ERROR! Could not open ", file_path, " for write!")
		return
	file.store_var(dict)
	file.close()
