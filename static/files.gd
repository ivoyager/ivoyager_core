# files.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2023 Charlie Whitfield
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
class_name IVFiles
extends Object



static func config_exists(config_path: String) -> bool:
	var config := ConfigFile.new()
	return config.load(config_path) == OK


static func get_config(config_path: String) -> ConfigFile:
	# Returns null if doesn't exist.
	var config := ConfigFile.new()
	var err := config.load(config_path)
	if err == OK:
		return config
	return null


static func get_config_with_override(config_path: String, override_config_path: String,
		override_config_path2 := "") -> ConfigFile:
	var config := get_config(config_path)
	if !config:
		assert(false, "Failed to load config '%s'" % config_path)
		return null
	var override_config := get_config(override_config_path)
	if !override_config:
		return config
	for section in override_config.get_sections():
		for property in override_config.get_section_keys(section):
			config.set_value(section, property, override_config.get_value(section, property))
	if !override_config_path2:
		return config
	override_config = get_config(override_config_path2)
	if !override_config:
		return config
	for section in override_config.get_sections():
		for property in override_config.get_section_keys(section):
			config.set_value(section, property, override_config.get_value(section, property))
	return config


static func init_from_config(object: Object, config: ConfigFile, section: String) -> void:
	if !config.has_section(section):
		return
	for key in config.get_section_keys(section):
		var value: Variant = config.get_value(section, key)
		var slash_pos := key.find("/")
		var dot_pos := key.find(".")
		if slash_pos == -1 and dot_pos == -1: # not a dictionary or array
			if not key in object:
				push_warning("'%s' not in '%s'; check config file" % [key, object])
				continue
			object.set(key, value)
		elif slash_pos >= 0: # dictionary w/ key
			var dict_name := key.left(slash_pos)
			var dict_key := key.substr(slash_pos + 1)
			if not dict_name in object:
				push_warning("'%s' not in '%s'; check config file" % [dict_name, object])
				continue
			var dict: Dictionary = object.get(dict_name)
			if value == null:
				dict.erase(dict_key)
			else:
				dict[dict_key] = value
		elif dot_pos >= 0: # array w/ appends or erases
			var array_name := key.left(dot_pos)
			var array_cmd := key.substr(dot_pos + 1)
			if not array_name in object:
				push_warning("'%s' not in '%s'; check config file" % [array_name, object])
				continue
			if not value is Array:
				push_warning("Expected array after '%s'=" % key)
				continue
			var array: Array = object.get(array_name)
			var mod_array: Array = value
			if array_cmd == "append":
				for item in mod_array:
					array.append(item)
			elif array_cmd == "erase":
				for item in mod_array:
					array.erase(item)
			else:
				push_warning("'%s'. must be followed by 'append' or 'erase'" % key)
				continue
		else:
			push_warning("Bad config key '%s'" % key)
			continue


static func get_script_or_packedscene(path: String) -> Resource:
	if !path:
		assert(false, "Requires path")
		return null
	if path.ends_with(".tscn") or path.ends_with(".scn"):
		var packedscene: PackedScene = load(path)
		assert(packedscene, "Failed to load PackedScene at '%s'" % path)
		return packedscene
	var script: Script = load(path)
	assert(script, "Failed to load Script at '%s'" % path)
	return script


static func make_object_or_scene(arg: Variant) -> Object:
	# Returns intantiated Object or root node of instantiated scene.
	# 'arg' can be a Script, PackedScene, or String that is a path to a
	# PackedScene (*.tscn, *.scn) or Script resource.
	# If Script has const SCENE_OVERRIDE or SCENE, then that is used as path
	# to intantiate a scene. 
	var arg_type := typeof(arg)
	var packedscene: PackedScene
	var script: Script
	if arg_type == TYPE_OBJECT:
		if arg is Script:
			script = arg
		elif arg is PackedScene:
			packedscene = arg
		else:
			assert(false, "Unknown object class %s" % arg)
			return null
	else:
		assert(arg is String)
		var path: String = arg
		var script_or_packedscene := get_script_or_packedscene(path)
		if !script_or_packedscene:
			assert(false, "Could not load '%s' as Script or PackedScene" % path)
			return null
		if script_or_packedscene is Script:
			script = script_or_packedscene
		else:
			packedscene = script_or_packedscene
	
	if script:
		var scene_path: String
		if &"SCENE_OVERRIDE" in script:
			scene_path = script.get("SCENE_OVERRIDE")
		elif &"SCENE" in script:
			scene_path = script.get("SCENE")
		if scene_path:
			packedscene = load(scene_path)
			if !packedscene:
				assert(false, "Failed to load scene at '%s'" % scene_path)
				return null
		else:
			@warning_ignore("unsafe_method_access")
			return script.new()
	
	var root_node: Node = packedscene.instantiate()
	if root_node.get_script() != script: # root_node.script may be parent class!
		root_node.set_script(script)
	return root_node


static func get_save_dir_path(is_modded: bool, override_dir: String = "") -> String:
	var save_dir := override_dir
	if save_dir:
		if is_modded:
			if !save_dir.ends_with("/modded_saves"):
				save_dir = ""
		else:
			if !save_dir.ends_with("/unmodded_saves"):
				save_dir = ""
	if save_dir:
		var dir := DirAccess.open(save_dir)
		if !dir:
			save_dir = ""
	if save_dir == "":
		save_dir = OS.get_user_data_dir() + "/saves"
		save_dir += "/modded_saves" if is_modded else "/unmodded_saves"
		DirAccess.make_dir_recursive_absolute(save_dir)
	return save_dir


static func get_base_file_name(file_name: String, save_file_extension: String) -> String:
	# Strips file type and date extensions
	file_name = file_name.replace("." + save_file_extension, "")
	var regex := RegEx.new()
	regex.compile("\\.\\d+-\\d\\d-\\d\\d") # "(\.\d+-\d\d-\d\d)"
	var search_result := regex.search(file_name)
	if search_result:
		var date_extension := search_result.get_string()
		file_name = file_name.replace(date_extension, "")
	return file_name


static func get_save_path(save_dir: String, base_name: String, save_file_extension: String,
		date_string := "", append_file_extension := false) -> String:
	var path := save_dir.path_join(base_name)
	if date_string:
		path += "." + date_string
	if append_file_extension:
		path += "." + save_file_extension
	return path


static func make_or_clear_dir(dir_path: String) -> void:
	if !DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
		return
	var dir := DirAccess.open(dir_path)
	dir.include_hidden = false
	dir.include_navigational = false
	dir.list_dir_begin() # TODOConverter3To4 fill missing arguments https://github.com/godotengine/godot/pull/40547
	var file_name := dir.get_next()
	while file_name:
		if !dir.current_is_dir():
			dir.remove(file_name)
		file_name = dir.get_next()


# loading assets & data files

# TODO34: Update debug func below for 4.x
#static func get_dir_files(dir_path: String, extension := "") -> Array:
#	# No period in extension, if provided.
#	# Useful for debugging. Export removes files & changes file names!
#	var dir := DirAccess.new()
#	if dir.open(dir_path) != OK:
#		print("Could not open dir: ", dir_path)
#		return []
#	var result := []
#	dir.list_dir_begin() # TODOConverter3To4 fill missing arguments https://github.com/godotengine/godot/pull/40547
#	var file_name := dir.get_next()
#	while file_name:
#		if !dir.current_is_dir():
#			if !extension or file_name.get_extension() == extension:
#				result.append(file_name)
#		file_name = dir.get_next()
#	return result


static func find_resource_file(dir_paths: Array[String], prefix: String,
		search_prefix_subdirectories := true) -> String:
	# Searches for file in the given directory path that begins with file_prefix
	# followed by dot. Returns resource path if it exists. We expect to
	# find file with .import extension (this is the ONLY file in an exported
	# project!), but ".import" must be removed from end to load it.
	# Search is case-insensitive.
	var prefix_dot := prefix + "."
	var match_size := prefix_dot.length()
	var dir: DirAccess
	for dir_path in dir_paths:
		dir = DirAccess.open(dir_path)
		if !dir:
			continue
		dir.include_hidden = false
		dir.include_navigational = false
		dir.list_dir_begin() # TODOConverter3To4 fill missing arguments https://github.com/godotengine/godot/pull/40547
		var file_name := dir.get_next()
		while file_name:
			if !dir.current_is_dir():
				if file_name.get_extension() == "import":
					if file_name.substr(0, match_size).matchn(prefix_dot):
						return dir_path.path_join(file_name).get_basename()
			elif search_prefix_subdirectories:
				if file_name.matchn(prefix):
					var subdir_path: String = dir_path + "/" + file_name
					var subdir_result := find_resource_file([subdir_path], prefix, false)
					if subdir_result:
						return subdir_result
			file_name = dir.get_next()
	return ""


static func find_and_load_resource(dir_paths: Array[String], prefix: String,
		search_prefix_subdirectories := true) -> Resource:
	var path := find_resource_file(dir_paths, prefix, search_prefix_subdirectories)
	if path:
		return load(path)
	return null


static func apply_escape_characters(string: String) -> String:
	string = string.replace("\\n", "\n")
	string = string.replace("\\t", "\t")
	return string

