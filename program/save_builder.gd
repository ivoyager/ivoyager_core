# saver_builder.gd
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
class_name IVSaveBuilder
extends RefCounted

## Generates a compact game-save data structure from properties specified in
## object constants. Sets properties and rebuilds procedural parts of the scene
## tree on game load.
##
## IVSaveBuilder can persist Godot built-in types (including arrays and
## dictionaries) and four kinds of objects:[br][br]
##    
##    1. 'Non-procedural' Node - May have persist data but is not freed.[br]
##    2. 'Procedural' Node - Freed and rebuilt on game load.[br]
##    3. 'Procedural' RefCounted - Freed and rebuilt on game load.[br]
##    4. WeakRef to any of above.[br][br]
##
## Arrays and dictionaries containing persisted non-object data can be nested
## at any level of complexity (array types are also persisted). However, see
## 'Special rules for persist objects' below for arrays and dictionaries that
## contain persisted objects.[br][br]
##
## A Node or RefCounted is identified as a 'persist' object by the presence of
## any one of the following:[br][br]
##
##    [code]const PERSIST_MODE := IVEnums.PERSIST_PROPERTIES_ONLY[/code][br]
##    [code]const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL[/code][br]
##    [code]var persist_mode_override := [/code] <either of above two values>[br][br]
##
## Lists of properties to persists must be named in constant arrays:[br][br]
##    [code]const PERSIST_PROPERTIES: Array[StringName] = [][/code][br]
##    [code]const PERSIST_PROPERTIES2: Array[StringName] = [][/code][br]
##    (These list names can be modified in static member [code]properties_arrays[/code].
##    The extra numbered lists can be used in subclasses to add persist properties.)[br][br]
##
## To reconstruct a scene, the base node's gdscript must have one of:[br][br]
##
##    [code]const SCENE := "<path to .tscn file>"[/code][br]
##    [code]const SCENE_OVERRIDE := "<as above; override may be useful in subclass>"[/code][br][br]
##
## Special rules for persist objects:[br][br]
##    1. Arrays containing persist objects must be typed with
##       [code]get_typed_builtin() == TYPE_OBJECT[/code]. Objects can't be
##       nested in containers in an array.[br]
##    2. Dictionaries keys or values can be persist objects. But dictionary
##       keys and values cannot be containers of persist objects.[br]
##    3. Nodes must be in the tree.[br]
##    4. All ancester nodes up to and including [code]save_root[/code] must also be persist
##       nodes.[br]
##    5. Non-procedural Nodes (i.e., [code]PERSIST_PROPERTIES_ONLY[/code]) cannot
##       have any ancestors that are [code]PERSIST_PROCEDURAL[/code].[br]
##    6. Non-procedural Nodes must have stable node path.[br]
##    7. Inner classes can't be persist objects.[br]
##    8. A persisted RefCounted can only be [code]PERSIST_PROCEDURAL[/code].[br]
##    9. Persist objects cannot have required args in their [code]_init()[/code]
##       method.[br][br]
##
## Warnings:[br][br]
##    1. Godot does not allow us to index arrays and dictionaries by reference rather
##       than content (see proposal #874 to fix this). Therefore, a single array
##       or dictionary persisted in two places (i.e., listed in [code]PERSIST_PROPERTIES[/code]
##       in two files) will become two separate arrays or dictionaries on load.[br]
##    2. Be sure to call [code]free_all_procedural_objects()[/code] before calling
##       [code]build_tree()[/code]. It's advised to wait a few frames between
##       to make sure freeing nodes are really gone and not still responding to
##       signals. (They do and it is a nightmare to troubleshoot!)[br][br]


const files := preload("res://addons/ivoyager_core/static/files.gd")

enum {
	NO_PERSIST,
	PERSIST_PROPERTIES_ONLY,
	PERSIST_PROCEDURAL,
}

const DPRINT := false # true for debug print
const DDPRINT := false # prints even more debug info

# debug printing/logging - these allow verbose writing to user://logs/debug.log
var debug_log_persist_nodes := false
var debug_log_all_nodes := false
var debug_print_stray_nodes := false
var debug_print_tree := false

# project settings
var progress_multiplier := 95 # so prog bar doesn't sit for a while at 100%

static var properties_arrays: Array[StringName] = [
	&"PERSIST_PROPERTIES",
	&"PERSIST_PROPERTIES2",
]

# gamesave contents
# Note: FileAccess.store_var() & get_var() doesn't save or recover array type
# as of Godot 4.2.dev6. So we can't type these arrays.
var _gamesave_n_objects := 0
var _gamesave_serialized_nodes := []
var _gamesave_serialized_refs := []
var _gamesave_script_paths := []
var _gamesave_indexed_values := []

# save processing
var _save_root: Node
var _path_ids := {} # indexed by script paths
var _object_ids := {} # indexed by objects
var _indexed_string_ids := {} # indexed by String values
var _indexed_nonstring_ids := {} # indexed by non-String values (incl StringName)

# load processing
var _scripts: Array[Script] = [] # indexed by script_id
var _objects: Array[Object] = [] # indexed by object_id

# logging
var _log_count := 0
var _log_count_by_class := {}
var _log := ""

# static processing
static var _nulling_dict := {}


## Frees all 'procedural' Node and RefCounted instances starting from
## [code]root_node[/code] (which may or may not be procedural). This method
## first nulls all references to procedural objects everywhere, then frees the
## base procedural Nodes.[br][br]
## WARNING: We assume that all references to procedural RefCounteds are listed
## in PERSIST_PROPERTIES arrays. Any other references must be nulled by some
## other code.
static func free_all_procedural_objects(root_node: Node) -> void:
	null_procedural_references_recursive(root_node)
	free_procedural_nodes_recursive(root_node)


## Nulls all property and container references to 'procedural' objects
## recursively.
static func null_procedural_references_recursive(object: Object) -> void:
	
	# Don't process circular references.
	var is_root_call := _nulling_dict.is_empty()
	if _nulling_dict.has(object):
		return
	_nulling_dict[object] = true
	
	# Recursive call to all nodes. All procedural nodes must be in the tree!
	if object is Node:
		var root_node: Node = object
		for child in root_node.get_children():
			if is_persist_object(child):
				null_procedural_references_recursive(child)
	
	# Null all procedural object references with recursive calls to RefCounteds
	for properties_array_name in properties_arrays:
		if not properties_array_name in object:
			continue
		var properties_array: Array = object.get(properties_array_name)
		for property: StringName in properties_array:
			var value: Variant = object.get(property)
			var type := typeof(value)
			if type == TYPE_OBJECT:
				var property_object: Object = value
				null_procedural_references_recursive(property_object)
				object.set(property, null)
			elif type == TYPE_ARRAY:
				# test elements if Object-typed only
				var array: Array = value
				if array.get_typed_builtin() == TYPE_OBJECT:
					for i in array.size():
						var array_object: Object = array[i]
						null_procedural_references_recursive(array_object)
						array[i] = null
			elif type == TYPE_DICTIONARY:
				# test all keys and values
				var dict: Dictionary = value
				for key: Variant in dict.keys():
					var dict_value: Variant = dict[key]
					if typeof(dict_value) == TYPE_OBJECT:
						var value_object: Object = dict_value
						null_procedural_references_recursive(value_object)
						dict[key] = null
					if typeof(key) == TYPE_OBJECT:
						var key_object: Object = key
						null_procedural_references_recursive(key_object)
						dict.erase(key)
	
	if is_root_call:
		_nulling_dict.clear()


## Frees all 'procedural' Nodes at or below [code]root_node[/code]. Note: It's
## usually better to call [code]free_all_procedural_objects()[/code] instead! 
static func free_procedural_nodes_recursive(root_node: Node) -> void:
	if is_procedural_persist(root_node):
		root_node.queue_free() # children will also be freed!
		return
	for child in root_node.get_children():
		if is_persist_object(child):
			free_procedural_nodes_recursive(child)


static func clone_persist_properties(origin: Object, clone: Object) -> void:
	# Not used by IVSaveBuilder but uses same persist properties.
	for properties_array in properties_arrays:
		if not properties_array in origin:
			continue
		var properties: Array[StringName] = origin.get(properties_array)
		for property in properties:
			var value: Variant = origin.get(property)
			var type := typeof(value)
			if type == TYPE_ARRAY:
				var origin_array: Array = value
				value = origin_array.duplicate(true)
			elif type == TYPE_DICTIONARY:
				var origin_dict: Dictionary = value
				value = origin_dict.duplicate(true)
			clone.set(property, value)


static func get_persist_properties(origin: Object) -> Array:
	# Not used by IVSaveBuilder but uses same persist properties.
	var array := []
	for properties_array in properties_arrays:
		if not properties_array in origin:
			continue
		var properties: Array[StringName] = origin.get(properties_array)
		for property in properties:
			var value: Variant = origin.get(property)
			var type := typeof(value)
			if type == TYPE_ARRAY:
				var origin_array: Array = value
				value = origin_array.duplicate(true)
			elif type == TYPE_DICTIONARY:
				var origin_dict: Dictionary = value
				value = origin_dict.duplicate(true)
			array.append(value)
	return array


static func set_persist_properties(clone: Object, array: Array) -> void:
	# Set properties in 'clone' using 'array' from get_persist_properties().
	var i := 0
	for properties_array in properties_arrays:
		if not properties_array in clone:
			continue
		var properties: Array[StringName] = clone.get(properties_array)
		for property in properties:
			clone.set(property, array[i])
			i += 1


static func get_persist_mode(object: Object) -> int:
	if &"persist_mode_override" in object:
		return object.get(&"persist_mode_override")
	if &"PERSIST_MODE" in object:
		return object.get(&"PERSIST_MODE")
	return NO_PERSIST


static func is_persist_object(object: Object) -> bool:
	if &"persist_mode_override" in object:
		return object.get(&"persist_mode_override") != NO_PERSIST
	if &"PERSIST_MODE" in object:
		return object.get(&"PERSIST_MODE") != NO_PERSIST
	return false


static func is_procedural_persist(object: Object) -> bool:
	if &"persist_mode_override" in object:
		return object.get(&"persist_mode_override") == PERSIST_PROCEDURAL
	if &"PERSIST_MODE" in object:
		return object.get(&"PERSIST_MODE") == PERSIST_PROCEDURAL
	return false
	


func generate_gamesave(save_root: Node) -> Array:
	# "save_root" may or may not be the main scene tree root. It must be a
	# persist node itself with const PERSIST_MODE = PERSIST_PROPERTIES_ONLY.
	# Data in the result array includes the save_root and the continuous tree
	# of persist nodes below that.
	# TODO: We could recode to allow save_root to be a 'detatched' procedural node.
	assert(_debug_is_persist_object(save_root))
	assert(!is_procedural_persist(save_root), "save_root must be PERSIST_PROPERTIES_ONLY")
	_save_root = save_root
	assert(!DPRINT or IVDebug.dprint("* Registering tree for gamesave *"))
	_register_tree(save_root)
	assert(!DPRINT or IVDebug.dprint("* Serializing tree for gamesave *"))
	_serialize_tree(save_root)
	var gamesave := [
		_gamesave_n_objects,
		_gamesave_serialized_nodes,
		_gamesave_serialized_refs,
		_gamesave_script_paths,
		_gamesave_indexed_values,
		]
	print("Persist objects saved: ", _gamesave_n_objects, "; nodes in tree: ",
			save_root.get_tree().get_node_count())
	_reset()
	return gamesave


func build_tree(save_root: Node, gamesave: Array) -> void:
	# "save_root" must be the same non-procedural persist node specified in
	# generate_gamesave(save_root).
	#
	# To call this function on another thread, save_root can't be part of the
	# current scene.
	#
	# If building for a loaded game, be sure to free the old procedural tree
	# using free_all_procedural_objects(). It is recommended to delay a few
	# frames after that so old freeing objects are no longer recieving signals.
	_save_root = save_root
	_gamesave_n_objects = gamesave[0]
	_gamesave_serialized_nodes = gamesave[1]
	_gamesave_serialized_refs = gamesave[2]
	_gamesave_script_paths = gamesave[3]
	_gamesave_indexed_values = gamesave[4]
	_load_scripts()
	_locate_or_instantiate_objects(save_root)
	_deserialize_all_object_data()
	_build_procedural_tree()
	print("Persist objects loaded: ", _gamesave_n_objects)
	_reset()


# *****************************************************************************
# Debug logging

func debug_log(save_root: Node) -> String:
	# Call before and after all external save/load stuff completed. Wrap in
	# in assert to compile only in debug builds, e.g.:
	# assert(print(save_manager.debug_log(get_tree())) or true)
	_log += "Number tree nodes: %s\n" % save_root.get_tree().get_node_count()
	# This doesn't work: OS.dump_memory_to_file(mem_dump_path)
	if debug_print_stray_nodes:
		print("Stray Nodes:")
		save_root.print_orphan_nodes()
		print("***********************")
	if debug_print_tree:
		print("Tree:")
		save_root.print_tree_pretty()
		print("***********************")
	if debug_log_all_nodes or debug_log_persist_nodes:
		_log_count = 0
		var last_log_count_by_class: Dictionary
		if _log_count_by_class:
			last_log_count_by_class = _log_count_by_class.duplicate()
		_log_count_by_class.clear()
		_log_nodes(save_root)
		if last_log_count_by_class:
			_log += "Class counts difference from last count:\n"
			for class_: String in _log_count_by_class:
				if last_log_count_by_class.has(class_):
					_log += "%s %s\n" % [class_, _log_count_by_class[class_] - last_log_count_by_class[class_]]
				else:
					_log += "%s %s\n" % [class_, _log_count_by_class[class_]]
			for class_: String in last_log_count_by_class:
				if !_log_count_by_class.has(class_):
					_log += "%s %s\n" % [class_, -last_log_count_by_class[class_]]
		else:
			_log += "Class counts:\n"
			for class_: String in _log_count_by_class:
				_log += "%s %s\n" % [class_, _log_count_by_class[class_]]
	var return_log := _log
	_log = ""
	return return_log


func _log_nodes(node: Node) -> void:
	_log_count += 1
	var class_ := node.get_class()
	if _log_count_by_class.has(class_):
		_log_count_by_class[class_] += 1
	else:
		_log_count_by_class[class_] = 1
	var script_identifier := ""
	if node.get_script():
		@warning_ignore("unsafe_method_access")
		var source_code: String = node.get_script().get_source_code()
		if source_code:
			var split := source_code.split("\n", false, 1)
			script_identifier = split[0]
	_log += "%s %s %s %s\n" % [_log_count, node, node.name, script_identifier]
	for child in node.get_children():
		if debug_log_all_nodes or is_procedural_persist(child):
			_log_nodes(child)


# *****************************************************************************

func _reset() -> void:
	_gamesave_n_objects = 0
	_gamesave_serialized_nodes = []
	_gamesave_serialized_refs = []
	_gamesave_script_paths = []
	_gamesave_indexed_values = []
	_save_root = null
	_path_ids.clear()
	_object_ids.clear()
	_indexed_string_ids.clear()
	_indexed_nonstring_ids.clear()
	_objects.clear()
	_scripts.clear()


# Procedural save

func _register_tree(node: Node) -> void:
	# Make an object_id for all persist nodes by indexing in _object_ids.
	# Initial call is the save_root which must be a persist node itself.
	_object_ids[node] = _gamesave_n_objects
	_gamesave_n_objects += 1
	for child in node.get_children():
		if is_persist_object(child):
			_register_tree(child)


func _serialize_tree(node: Node) -> void:
	_serialize_node(node)
	for child in node.get_children():
		if is_persist_object(child):
			_serialize_tree(child)


# Procedural load

func _load_scripts() -> void:
	for script_path: String in _gamesave_script_paths:
		var script: Script = load(script_path)
		_scripts.append(script) # indexed by script_id


func _locate_or_instantiate_objects(save_root: Node) -> void:
	# Instantiates procecural objects (Node and RefCounted) without data.
	# Indexes root and all persist objects (procedural and non-procedural).
	assert(!DPRINT or IVDebug.dprint("* Registering(/Instancing) Objects for Load *"))
	_objects.resize(_gamesave_n_objects)
	_objects[0] = save_root
	for serialized_node: Array in _gamesave_serialized_nodes:
		var object_id: int = serialized_node[0]
		var script_id: int = serialized_node[1]
		var node: Node
		if script_id == -1: # non-procedural node; find it
			var node_path: NodePath = serialized_node[2] # relative
			node = save_root.get_node(node_path)
			assert(!DPRINT or IVDebug.dprint(object_id, node, node.name))
		else: # this is a procedural node
			var script: Script = _scripts[script_id]
			node = files.make_object_or_scene(script)
			@warning_ignore("unsafe_call_argument")
			assert(!DPRINT or IVDebug.dprint(object_id, node, script_id, _gamesave_script_paths[script_id]))
		assert(node)
		_objects[object_id] = node
	for serialized_ref: Array in _gamesave_serialized_refs:
		var object_id: int = serialized_ref[0]
		var script_id: int = serialized_ref[1]
		var script: Script = _scripts[script_id]
		@warning_ignore("unsafe_method_access")
		var ref: RefCounted = script.new()
		assert(ref)
		_objects[object_id] = ref
		@warning_ignore("unsafe_call_argument")
		assert(!DPRINT or IVDebug.dprint(object_id, ref, script_id, _gamesave_script_paths[script_id]))


func _deserialize_all_object_data() -> void:
	assert(!DPRINT or IVDebug.dprint("* Deserializing Objects for Load *"))
	for serialized_node: Array in _gamesave_serialized_nodes:
		_deserialize_object_data(serialized_node, true)
	for serialized_ref: Array in _gamesave_serialized_refs:
		_deserialize_object_data(serialized_ref, false)


func _build_procedural_tree() -> void:
	for serialized_node: Array in _gamesave_serialized_nodes:
		var object_id: int = serialized_node[0]
		var node: Node = _objects[object_id]
		if is_procedural_persist(node):
			var parent_save_id: int = serialized_node[2]
			var parent: Node = _objects[parent_save_id]
			parent.add_child(node)


# Serialize/deserialize functions

func _serialize_node(node: Node) -> void:
	var serialized_node := []
	var object_id: int = _object_ids[node]
	serialized_node.append(object_id) # index 0
	var script_id := -1
	var is_procedural := is_procedural_persist(node)
	if is_procedural:
		var script: Script = node.get_script()
		script_id = _get_script_id(script)
		@warning_ignore("unsafe_call_argument")
		assert(!DPRINT or IVDebug.dprint(object_id, node, script_id, _gamesave_script_paths[script_id]))
	else:
		assert(!DPRINT or IVDebug.dprint(object_id, node, node.name))
	serialized_node.append(script_id) # index 1
	# index 2 will be parent_save_id *or* non-procedural node path
	if is_procedural:
		var parent := node.get_parent()
		var parent_save_id: int = _object_ids[parent]
		serialized_node.append(parent_save_id) # index 2
	else:
		var node_path := _save_root.get_path_to(node)
		serialized_node.append(node_path) # index 2
	_serialize_object_data(node, serialized_node)
	_gamesave_serialized_nodes.append(serialized_node)


func _register_and_serialize_reference(ref: RefCounted) -> int:
	assert(is_procedural_persist(ref)) # must be true for RefCounted
	var object_id := _gamesave_n_objects
	_gamesave_n_objects += 1
	_object_ids[ref] = object_id
	var serialized_ref := []
	serialized_ref.append(object_id) # index 0
	var script: Script = ref.get_script()
	var script_id := _get_script_id(script)
	@warning_ignore("unsafe_call_argument")
	assert(!DPRINT or IVDebug.dprint(object_id, ref, script_id, _gamesave_script_paths[script_id]))
	serialized_ref.append(script_id) # index 1
	_serialize_object_data(ref, serialized_ref)
	_gamesave_serialized_refs.append(serialized_ref)
	return object_id


func _get_script_id(script: Script) -> int:
	var script_path := script.resource_path
	assert(script_path)
	var script_id: int = _path_ids.get(script_path, -1)
	if script_id == -1:
		script_id = _gamesave_script_paths.size()
		_gamesave_script_paths.append(script_path)
		_path_ids[script_path] = script_id
	return script_id


func _serialize_object_data(object: Object, serialized_object: Array) -> void:
	assert(object is Node or object is RefCounted)
	# serialized_object already has 3 elements (if Node) or 2 (if RefCounted).
	# We now append the size of each persist array followed by data.
	for properties_array in properties_arrays:
		var properties: Array[StringName]
		var n_properties: int
		if properties_array in object:
			properties = object.get(properties_array)
			n_properties = properties.size()
		else:
			n_properties = 0
		serialized_object.append(n_properties)
		for property in properties:
			var value: Variant = object.get(property)
			assert(_debug_is_valid_persist_value(value))
			serialized_object.append(_get_encoded_value(value))


func _deserialize_object_data(serialized_object: Array, is_node: bool) -> void:
	# The order of persist properties must be exactly the same from game save
	# to game load. However, if a newer version (loading an older save) has
	# added more persist properties at the end of a persist array const, these
	# will not be touched and will not cause "data out of frame" mistakes.
	# There is some opportunity here for backward compatibility if the newer
	# version knows to init-on-load its added persist properties when loading
	# an older version save file.
	var index: int = 3 if is_node else 2
	var object_id: int = serialized_object[0]
	var object: Object = _objects[object_id]
	for properties_array in properties_arrays:
		var n_properties: int = serialized_object[index]
		index += 1
		if n_properties == 0:
			continue
		var properties: Array = object.get(properties_array)
		var property_index := 0
		while property_index < n_properties:
			var property: String = properties[property_index]
			var encoded_value: Variant = serialized_object[index]
			index += 1
			object.set(property, _get_decoded_value(encoded_value))
			property_index += 1


func _get_encoded_value(value: Variant) -> Variant:
	# Encoded values are ALWAYS of type Array, Dictionary or int.
	var type := typeof(value)
	if type == TYPE_DICTIONARY:
		var dict: Dictionary = value
		return _get_encoded_dict(dict) # dict
	if type == TYPE_ARRAY:
		var array: Array = value
		return _get_encoded_array(array) # array (1st element is never StringName)
	if type == TYPE_OBJECT:
		var object: Object = value
		return _get_encoded_object(object) # array of size 2 w/ first element StringName
	# Anything else is built-in type that we index. Indexing allows object encoding
	# above and optimizes for duplicate data (e.g., very many identical dict keys).
	var value_id: int
	if type == TYPE_STRING:
		# we have to index Strings separately from StringNames
		value_id = _indexed_string_ids.get(value, -1)
		if value_id == -1:
			value_id = _gamesave_indexed_values.size()
			_gamesave_indexed_values.append(value)
			_indexed_string_ids[value] = value_id
		return value_id
	value_id = _indexed_nonstring_ids.get(value, -1)
	if value_id == -1:
		value_id = _gamesave_indexed_values.size()
		_gamesave_indexed_values.append(value)
		_indexed_nonstring_ids[value] = value_id
	return value_id


func _get_decoded_value(encoded_value: Variant) -> Variant:
	# 'encoded_value' can only be an array, dictionary or int.
	var encoded_type := typeof(encoded_value)
	if encoded_type == TYPE_INT: # indexed built-in type
		var value_id: int = encoded_value
		return _gamesave_indexed_values[value_id]
	if encoded_type == TYPE_DICTIONARY:
		var encoded_dict: Dictionary = encoded_value
		return _get_decoded_dict(encoded_dict)
	var encoded_array_or_obj: Array = encoded_value
	if encoded_array_or_obj.size() == 2 and typeof(encoded_array_or_obj[0]) == TYPE_STRING_NAME:
		return _get_decoded_object(encoded_array_or_obj)
	return _get_decoded_array(encoded_array_or_obj)


func _get_encoded_array(array: Array) -> Array:
	# Encodes array type if applicable.
	#
	# As of Godot 4.2.beta5, godot file storage does not persist array types:
	# https://github.com/godotengine/godot/issues/76841
	# Therefore, we append type info so we can pop it in the decode method.
	#
	# TODO: When above issue is fixed, we can optimize here substantially by
	# duplicating non-object arrays. (We have many typed data arrays!)
	
	var encoded_array := []
	var array_type := array.get_typed_builtin()
	var size := array.size()
	encoded_array.resize(size)
	var index := 0
	while index < size:
		encoded_array[index] = _get_encoded_value(array[index])
		index += 1
	
	# Append array type info to the encoded array. Be careful: array[0] must
	# never by of type StringName or the ecoded array might be confused with
	# an encoded object. (An empty array here will get an id in position 0.)
	if array.is_typed():
		var script: Script = array.get_typed_script()
		var script_id := _get_script_id(script) if script else -1
		encoded_array.append(script_id)
		encoded_array.append(array.get_typed_class_name())
		encoded_array.append(array_type) # last element
	else:
		encoded_array.append(-1) # last element
	
	return encoded_array


func _get_decoded_array(encoded_array: Array) -> Array:
	# Return array may or may not be content-typed.
	var array := []
	
	# Pop array content-type info from the back of the encoded array, then
	# type the return array if applicable.
	var array_type: int = encoded_array.pop_back()
	if array_type != -1:
		var typed_class_name: StringName = encoded_array.pop_back()
		var script_id: int = encoded_array.pop_back()
		var script: Script
		if script_id != -1:
			script = _scripts[script_id]
		array = Array(array, array_type, typed_class_name, script) # last two often &"", null
	
	var size := encoded_array.size()
	array.resize(size)
	var index := 0
	while index < size:
		array[index] = _get_decoded_value(encoded_array[index])
		index += 1
	return array


func _get_encoded_dict(dict: Dictionary) -> Dictionary:
	var encoded_dict := {}
	for key: Variant in dict:
		var encoded_key: Variant = _get_encoded_value(key)
		encoded_dict[encoded_key] = _get_encoded_value(dict[key])
	return encoded_dict


func _get_decoded_dict(encoded_dict: Dictionary) -> Dictionary:
	var dict := {}
	for encoded_key: Variant in encoded_dict:
		var key: Variant = _get_decoded_value(encoded_key)
		dict[key] = _get_decoded_value(encoded_dict[encoded_key])
	return dict


func _get_encoded_object(object: Object) -> Array:
	# Encoded object is an array with 2 elements where the first element is a
	# StringName (&"r" or &"w") and the second is an int (object_id). This
	# can't be confused with an encoded array because an encoded array can only
	# have 1st element of type array, dictionary or int.
	var is_weak_ref := false
	if object is WeakRef:
		var wr: WeakRef = object
		object = wr.get_ref()
		if object == null:
			return [&"w", -1] # WeakRef to a dead object
		is_weak_ref = true
	assert(_debug_is_persist_object(object))
	var object_id: int = _object_ids.get(object, -1)
	if object_id == -1:
		var ref: RefCounted = object
		object_id = _register_and_serialize_reference(ref)
	if is_weak_ref:
		return [&"w", object_id] # WeakRef
	return [&"r", object_id] # Object


func _get_decoded_object(encoded_object: Array) -> Object:
	var object_id: int = encoded_object[1]
	if encoded_object[1] == -1:
		assert(encoded_object[0] == &"w")
		return WeakRef.new() # weak ref to dead object
	var object: Object = _objects[object_id]
	if encoded_object[0] == &"w":
		return weakref(object)
	return object


func _debug_is_valid_persist_value(value: Variant) -> bool:
	# Enforce persist property rules on save so we don't have more difficult
	# debugging on load. Wrap the function call in assert so it is only called
	# in editor and debug builds.
	var type := typeof(value)
	if type == TYPE_ARRAY:
		var array: Array = value
		var array_type := array.get_typed_builtin()
		if array_type == TYPE_NIL:
			# no objects in untyped arrays!
			return _debug_is_valid_data_array(array)
		if array_type == TYPE_ARRAY:
			# no nested objects allowed!
			for nested_array: Array in array:
				if !_debug_is_valid_data_array(nested_array):
					return false
			return true
		if array_type == TYPE_DICTIONARY:
			# no nested objects allowed!
			for nested_dict: Dictionary in array:
				if !_debug_is_valid_data_dictionary(nested_dict):
					return false
			return true
		if array_type == TYPE_OBJECT:
			return true # array object elements tested in _get_encoded_object()
		if array_type == TYPE_RID or array_type == TYPE_CALLABLE or array_type == TYPE_SIGNAL:
			assert(false, "Disallowed array type can't be persisted")
			return false
		return true # safe data-typed array
	if type == TYPE_DICTIONARY:
		var dict: Dictionary = value
		for key: Variant in dict:
			if !_debug_is_valid_dict_element(key):
				return false
			var dict_value: Variant = dict[key]
			if !_debug_is_valid_dict_element(dict_value):
				return false
		return true
	if type == TYPE_OBJECT:
		var object: Object = value
		return _debug_is_persist_object(object)
	if type == TYPE_RID or type == TYPE_CALLABLE or type == TYPE_SIGNAL:
		assert(false, "Disallowed type can't be persisted")
		return false
	return true


func _debug_is_persist_object(object: Object) -> bool:
	if !is_persist_object(object):
		assert(false, "Can't persist a non-persist object; see IVSaveBuilder doc")
		return false
	return true


func _debug_is_valid_dict_element(key_or_value: Variant) -> bool:
	# Object ok as key or value, but can't be nested.
	var type := typeof(key_or_value)
	if type == TYPE_OBJECT:
		var object: Object = key_or_value
		return _debug_is_persist_object(object)
	if type == TYPE_ARRAY:
		var array: Array = key_or_value
		return _debug_is_valid_data_array(array)
	if type == TYPE_DICTIONARY:
		var dict: Dictionary = key_or_value
		return _debug_is_valid_data_dictionary(dict)
	if type == TYPE_RID or type == TYPE_CALLABLE or type == TYPE_SIGNAL:
		assert(false, "Disallowed type can't be persisted")
		return false
	return true


func _debug_is_valid_data_array(array: Array) -> bool:
	# Untyped or nested arrays can't contain objects.
	for value: Variant in array:
		var type := typeof(value)
		if type == TYPE_OBJECT:
			assert(false, "Disallowed object in untyped or nested array; see IVSaveBuilder doc")
			return false
		if type == TYPE_RID or type == TYPE_CALLABLE or type == TYPE_SIGNAL:
			assert(false, "Disallowed type can't be persisted")
			return false
		elif type == TYPE_ARRAY:
			var array_value: Array = value
			if !_debug_is_valid_data_array(array_value):
				return false
		elif type == TYPE_DICTIONARY:
			var dict_value: Dictionary = value
			if !_debug_is_valid_data_dictionary(dict_value):
				return false
	return true


func _debug_is_valid_data_dictionary(dict: Dictionary) -> bool:
	# Nested dictionaries can't contain objects.
	for key: Variant in dict:
		var type := typeof(key)
		if type == TYPE_OBJECT:
			assert(false, "Disallowed object in nested dictionary; see IVSaveBuilder doc")
			return false
		if type == TYPE_RID or type == TYPE_CALLABLE or type == TYPE_SIGNAL:
			assert(false, "Disallowed type can't be persisted")
			return false
		elif type == TYPE_ARRAY:
			var array_key: Array = key
			if !_debug_is_valid_data_array(array_key):
				return false
		elif type == TYPE_DICTIONARY:
			var dict_key: Dictionary = key
			if !_debug_is_valid_data_dictionary(dict_key):
				return false
		var value: Variant = dict[key]
		type = typeof(value)
		if type == TYPE_OBJECT:
			assert(false, "Disallowed object in nested dictionary; see IVSaveBuilder doc")
			return false
		if type == TYPE_RID or type == TYPE_CALLABLE or type == TYPE_SIGNAL:
			assert(false, "Disallowed type can't be persisted")
			return false
		elif type == TYPE_ARRAY:
			var array_value: Array = value
			if !_debug_is_valid_data_array(array_value):
				return false
		elif type == TYPE_DICTIONARY:
			var dict_value: Dictionary = value
			if !_debug_is_valid_data_dictionary(dict_value):
				return false
	return true

