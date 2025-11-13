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

## Builds [IVView] instances from table data (default views), and provides API
## for user-created views that are persisted via gamesave or cache.

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"gamesave_views",
]


## If true, manager will set view &"VIEW_HOME" at simulator start.
var move_home_at_start := true

var file_path := IVCoreSettings.cache_dir.path_join("views.ivbinary")

# read only!
var table_views: Dictionary[StringName, IVView]
var gamesave_views: Dictionary[StringName, IVView] = {}
var cached_views: Dictionary[StringName, IVView] = {}

var _missing_or_bad_cache_file := true



func _init() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVStateManager.core_init_program_objects_instantiated.connect(_on_program_objects_instantiated)
	IVStateManager.about_to_start_simulator.connect(_on_about_to_start_simulator)


func set_table_view(view_name: StringName, is_camera_instant_move := false) -> void:
	if !table_views.has(view_name):
		return
	var view: IVView = table_views[view_name]
	view.set_state(is_camera_instant_move)


func has_table_view(view_name: StringName) -> bool:
	return table_views.has(view_name)


func get_table_view_object(view_name: StringName) -> IVView:
	return table_views.get(view_name)


func get_table_view_flags(view_name: StringName) -> int:
	if table_views.has(view_name):
		return table_views[view_name].flags
	return 0


func save_view(view_name: String, collection_name: String, is_cached: bool, flags: int,
		allow_threaded_cache_write := true) -> void:
	var key := view_name + "." + collection_name
	var view := get_view_object(view_name, collection_name, is_cached)
	if view:
		view.reset()
	else:
		view = IVView.create()
	view.save_state(flags)
	if is_cached:
		cached_views[key] = view
		_write_cache(allow_threaded_cache_write)
	else:
		gamesave_views[key] = view


func set_view(view_name: String, collection_name: String, is_cached: bool,
		is_camera_instant_move := false) -> void:
	var key := view_name + "." + collection_name
	var view: IVView
	if is_cached:
		view = cached_views.get(key)
	else:
		view = gamesave_views.get(key)
	if !view:
		return
	view.set_state(is_camera_instant_move)


func save_view_object(view: IVView, view_name: String, collection_name: String, is_cached: bool,
		allow_threaded_cache_write := true) -> void:
	var key := view_name + "." + collection_name
	if is_cached:
		cached_views[key] = view
		_write_cache(allow_threaded_cache_write)
	else:
		gamesave_views[key] = view


func get_view_object(view_name: String, collection_name: String, is_cached: bool) -> IVView:
	var key := view_name + "." + collection_name
	if is_cached:
		return cached_views.get(key)
	return gamesave_views.get(key)


func get_view_flags(view_name: String, collection_name: String, is_cached: bool) -> int:
	var key := view_name + "." + collection_name
	var view: IVView = cached_views.get(key) if is_cached else gamesave_views.get(key)
	if view:
		return view.flags
	return 0


func get_view_edited_default(view_name: String, collection_name: String, is_cached: bool
		) -> StringName:
	var key := view_name + "." + collection_name
	var view: IVView = cached_views.get(key) if is_cached else gamesave_views.get(key)
	if view:
		return view.edited_default
	return &""


func set_view_edited_default(view_name: String, collection_name: String, is_cached: bool,
		edited_default: StringName) -> void:
	var key := view_name + "." + collection_name
	var view: IVView = cached_views.get(key) if is_cached else gamesave_views.get(key)
	if view:
		view.edited_default = edited_default


func has_view(view_name: String, collection_name: String, is_cached: bool) -> bool:
	var key := view_name + "." + collection_name
	if is_cached:
		return cached_views.has(key)
	return gamesave_views.has(key)


func remove_view(view_name: String, collection_name: String, is_cached: bool) -> void:
	# OK if doesn't exist
	var key := view_name + "." + collection_name
	if is_cached:
		if cached_views.has(key):
			cached_views.erase(key)
			_write_cache()
	else:
		gamesave_views.erase(key)
	

func get_names_in_collection(collection_name: String, is_cached: bool) -> Array[String]:
	var group: Array[String] = []
	var suffix := "." + collection_name
	var dict := cached_views if is_cached else gamesave_views
	for key: String in dict:
		if key.ends_with(suffix):
			group.append(key.trim_suffix(suffix))
	return group



func _clear_procedural() -> void:
	gamesave_views.clear()


func _on_program_objects_instantiated() -> void:
	# table read
	var table_view_builder: IVTableViewBuilder = IVGlobal.program[&"TableViewBuilder"]
	table_views = table_view_builder.build_all()
	# caching
	DirAccess.make_dir_recursive_absolute(IVCoreSettings.cache_dir)
	_read_cache()
	if _missing_or_bad_cache_file:
		_write_cache()


func _on_about_to_start_simulator(is_new_game: bool) -> void:
	if is_new_game and move_home_at_start:
		set_table_view(&"VIEW_HOME", true)


# This replicates some IVCacheHandler code, but it's really hard to generalize
# that class to handle objects.

func _read_cache() -> void:
	# Populate cached_views once at project init on main thread.
	var file := FileAccess.open(file_path, FileAccess.READ)
	if !file:
		prints("Creating new cache file", file_path)
		return
	
	# May have old cache file, so treat with care...
	var file_var: Variant = file.get_var() # untyped for safety
	if typeof(file_var) != TYPE_DICTIONARY:
		prints("Overwriting obsolete cache file", file_path)
		return
	var file_dict: Dictionary = file_var
	if file_dict.get_typed_key_builtin() != TYPE_STRING_NAME:
		prints("Overwriting obsolete cache file", file_path)
		return
	var bad_cache_data := false
	for key: StringName in file_dict:
		var data: Array = file_dict[key]
		var view := IVView.create()
		if !view.set_data_from_cache(data): # may be prior version
			bad_cache_data = true
			continue
		cached_views[key] = view
	if !bad_cache_data:
		_missing_or_bad_cache_file = false


func _write_cache(allow_threaded_cache_write := true) -> void:
	# Unless this is app exit, no one is waiting for this and we can do the
	# file write on thread. At app exit, we want the main thread to wait.
	var dict: Dictionary[StringName, Array] = {}
	for key in cached_views:
		var view: IVView = cached_views[key]
		var data := view.get_data_for_cache()
		dict[key] = data
	if allow_threaded_cache_write:
		WorkerThreadPool.add_task(_write_cache_file.bind(dict))
	else:
		_write_cache_file(dict)


func _write_cache_file(dict: Dictionary[StringName, Array]) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	var err := FileAccess.get_open_error()
	if err != OK:
		push_error("Could not open file for write: ", file_path)
		return
	file.store_var(dict)
