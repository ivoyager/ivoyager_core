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

## Generates a compact data structure for game save from properties specified
## in object constants. Sets properties and rebuilds procedural scene tree on
## game load.
##
## IVSaveBuilder can persist Godot built-in types, including dictionaries and
## arrays (typed or untyped) at any level of nesting, and four kinds of objects:[br][br]
##    
##    1. 'Non-procedural' Node (may have persist data but is not freed)[br]
##    2. 'Procedural' Node (freed and rebuilt on game load)[br]
##    3. 'Procedural' RefCounted (freed and rebuilt on game load)[br]
##    4. WeakRef to any of above[br][br]
##
## A Node or RefCounted is identified as a 'persist' object by the presence of
## any of the following:[br][br]
##
##    [code]const PERSIST_MODE := IVEnums.PERSIST_PROPERTIES_ONLY[/code][br]
##    [code]const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL[/code][br]
##    [code]var persist_mode_override := [/code] <either of above two values>[br][br]
##
## Lists of properties to persists must be named in constant arrays:[br][br]
##    [code]const PERSIST_PROPERTIES: Array[StringName][/code][br]
##    [code]const PERSIST_PROPERTIES2: Array[StringName][/code][br]
##    (These list names can be modified in static member [code]properties_arrays[/code].
##    The extra numbered lists can be used in subclasses to add persist properties.)[br][br]
##
## To reconstruct a scene, the base node's gdscript must have one of:[br][br]
##
##    [code]const SCENE := "<path to .tscn file>"[/code][br]
##    [code]const SCENE_OVERRIDE := "<as above; override may be useful in subclass>"[/code][br][br]
##
## Additional rules for persist objects:[br][br]
##    1. Nodes must be in the tree.[br]
##    2. All ancester nodes up to and including [code]save_root[/code] must also be persist
##       nodes.[br]
##    3. Non-procedural Nodes (i.e., [code]PERSIST_PROPERTIES_ONLY[/code]) cannot
##       have any ancestors that are [code]PERSIST_PROCEDURAL[/code].[br]
##    4. Non-procedural Nodes must have stable node path.[br]
##    5. Inner classes can't be persist objects.[br]
##    6. A persisted RefCounted can only be [code]PERSIST_PROCEDURAL[/code].[br]
##    7. Persist objects cannot have required args in their [code]_init()[/code]
##       method.[br][br]
##
## Warnings:[br][br]
##    1. Godot does not allow us to index arrays and dictionaries by reference rather
##       than content (see proposal #874 to fix this). Therefore, a single array
##       or dictionary persisted in two places (i.e., listed in [code]PERSIST_PROPERTIES[/code]
##       in two files) will become two separate arrays or dictionaries on load.[br]
##    2. Be sure to free existing procedural nodes before calling [code]build_tree()[/code].
##       It's advised to wait a few frames after freeing to make sure nodes are
##       really gone and not responding to signals.[br][br]


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
# FileAccess.store_var() & get_var() doesn't save or recover array type as of Godot 4.2.dev6
var _gs_n_objects := 1
var _gs_serialized_nodes := [] # can't type as of Godot 4.2.dev6!
var _gs_serialized_references := [] # can't type as of Godot 4.2.dev6!
var _gs_script_paths := [] # can't type as of Godot 4.2.dev6!
var _gs_dict_keys := [] # can't type as of Godot 4.2.dev6!

# save processing
var _save_root: Node
var _path_ids := {} # indexed by script paths
var _object_ids := {} # indexed by objects
var _key_ids := {} # indexed by dict keys

# load processing
var _scripts: Array[Script] = [] # indexed by script_id
var _objects: Array[Object] = [null] # indexed by object_id (0 has a special meaning)

# logging
var _log_count := 0
var _log_count_by_class := {}
var _log := ""


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
	# persist node itelf with const PERSIST_MODE = PERSIST_PROPERTIES_ONLY.
	# Data in the result array includes the save_root and the continuous tree
	# of persist nodes below that.
	assert(is_persist_object(save_root))
	assert(!is_procedural_persist(save_root))
	_save_root = save_root
	assert(!DPRINT or IVDebug.dprint("* Registering tree for gamesave *"))
	_register_tree(save_root)
	assert(!DPRINT or IVDebug.dprint("* Serializing tree for gamesave *"))
	_serialize_tree(save_root)
	var gamesave := [
		_gs_n_objects,
		_gs_serialized_nodes,
		_gs_serialized_references,
		_gs_script_paths,
		_gs_dict_keys,
		]
	print("Persist objects saved: ", _gs_n_objects, "; nodes in tree: ",
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
	# using IVUtils.free_procedural_nodes(). It is recommended to delay a few
	# frames after that so old freeing objects are no longer recieving signals.
	_save_root = save_root
	_gs_n_objects = gamesave[0]
	_gs_serialized_nodes = gamesave[1]
	_gs_serialized_references = gamesave[2]
	_gs_script_paths = gamesave[3]
	_gs_dict_keys = gamesave[4]
	_load_scripts()
	_locate_or_instantiate_objects(save_root)
	_deserialize_all_object_data()
	_build_procedural_tree()
	print("Persist objects loaded: ", _gs_n_objects)
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
	_gs_n_objects = 1
	_gs_serialized_nodes = []
	_gs_serialized_references = []
	_gs_script_paths = []
	_gs_dict_keys = []
	_save_root = null
	_path_ids.clear()
	_object_ids.clear()
	_key_ids.clear()
	_objects.resize(1) # 1st element is always null
	_scripts.clear()


# Procedural save

func _register_tree(node: Node) -> void:
	# Make an object_id for all persist nodes by indexing in _object_ids.
	# Initial call is the save_root which must be a persist node itself.
	_object_ids[node] = _gs_n_objects
	_gs_n_objects += 1
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
	for script_path: String in _gs_script_paths:
		var script: Script = load(script_path)
		_scripts.append(script) # indexed by script_id


func _locate_or_instantiate_objects(save_root: Node) -> void:
	# Instantiates procecural objects (nodes & references) without data.
	# Indexes root and all persist objects (procedural and non-procedural).
	assert(!DPRINT or IVDebug.dprint("* Registering(/Instancing) Objects for Load *"))
	_objects.resize(_gs_n_objects)
	_objects[1] = save_root
	for serialized_node: Array in _gs_serialized_nodes:
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
			assert(!DPRINT or IVDebug.dprint(object_id, node, script_id, _gs_script_paths[script_id]))
		assert(node)
		_objects[object_id] = node
	for serialized_reference: Array in _gs_serialized_references:
		var object_id: int = serialized_reference[0]
		var script_id: int = serialized_reference[1]
		var script: Script = _scripts[script_id]
		@warning_ignore("unsafe_method_access")
		var ref: RefCounted = script.new()
		assert(ref)
		_objects[object_id] = ref
		@warning_ignore("unsafe_call_argument")
		assert(!DPRINT or IVDebug.dprint(object_id, ref, script_id, _gs_script_paths[script_id]))


func _deserialize_all_object_data() -> void:
	assert(!DPRINT or IVDebug.dprint("* Deserializing Objects for Load *"))
	for serialized_node: Array in _gs_serialized_nodes:
		_deserialize_object_data(serialized_node, true)
	for serialized_reference: Array in _gs_serialized_references:
		_deserialize_object_data(serialized_reference, false)


func _build_procedural_tree() -> void:
	for serialized_node: Array in _gs_serialized_nodes:
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
		assert(!DPRINT or IVDebug.dprint(object_id, node, script_id, _gs_script_paths[script_id]))
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
	_gs_serialized_nodes.append(serialized_node)


func _register_and_serialize_reference(ref: RefCounted) -> int:
	assert(is_procedural_persist(ref)) # must be true for RefCounted
	var object_id := _gs_n_objects
	_gs_n_objects += 1
	_object_ids[ref] = object_id
	var serialized_reference := []
	serialized_reference.append(object_id) # index 0
	var script: Script = ref.get_script()
	var script_id := _get_script_id(script)
	@warning_ignore("unsafe_call_argument")
	assert(!DPRINT or IVDebug.dprint(object_id, ref, script_id, _gs_script_paths[script_id]))
	serialized_reference.append(script_id) # index 1
	_serialize_object_data(ref, serialized_reference)
	_gs_serialized_references.append(serialized_reference)
	return object_id


func _get_script_id(script: Script) -> int:
	var script_path := script.resource_path
	assert(script_path)
	var script_id: int = _path_ids.get(script_path, -1)
	if script_id == -1:
		script_id = _gs_script_paths.size()
		_gs_script_paths.append(script_path)
		_path_ids[script_path] = script_id
	return script_id


func _serialize_object_data(object: Object, serialized_object: Array) -> void:
	assert(object is Node or object is RefCounted)
	# serialized_object already has 3 elements (if Node) or 2 (if Reference).
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
		if n_properties > 0:
			var array := []
			for property in properties:
				array.append(object.get(property))
			var encoded_array := _get_encoded_array(array)
			serialized_object.append(encoded_array)


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
		var serialized_array: Array = serialized_object[index]
		index += 1
		var decoded_array := _get_decoded_array(serialized_array) # may or may not be content-typed
		var properties: Array = object.get(properties_array)
		var property_index := 0
		while property_index < n_properties:
			var property: String = properties[property_index]
			# fill existing arrays & dicts in place; everything else is set
			var type := typeof(decoded_array[property_index])
			if type == TYPE_ARRAY:
				var saved_array: Array = decoded_array[property_index]
				var object_array: Array = object.get(property)
				var size := saved_array.size()
				object_array.resize(size)
				for i in size:
					object_array[i] = saved_array[i]
			elif type == TYPE_DICTIONARY:
				var saved_dict: Dictionary = decoded_array[property_index]
				var object_dict: Dictionary = object.get(property)
				object_dict.clear()
				for key: Variant in saved_dict:
					object_dict[key] = saved_dict[key]
			else:
				object.set(property, decoded_array[property_index])
			property_index += 1


func _get_encoded_array(array: Array) -> Array:
	var n_items := array.size()
	var encoded_array := []
	encoded_array.resize(n_items)
	var index := 0
	while index < n_items:
		var item: Variant = array[index]
		var type := typeof(item)
		if type == TYPE_OBJECT:
			var item_object: Object = item
			encoded_array[index] = _get_encoded_object(item_object)
		elif type == TYPE_ARRAY:
			var item_array: Array = item
			encoded_array[index] = _get_encoded_array(item_array)
		elif type == TYPE_DICTIONARY:
			var item_dict: Dictionary = item
			encoded_array[index] = _get_encoded_dict(item_dict)
		else: # built-in type
			encoded_array[index] = item
		index += 1
	
	# append array type to the encoded array
	if array.is_typed():
		var script: Script = array.get_typed_script()
		var script_id := _get_script_id(script) if script else -1
		encoded_array.append(script_id)
		encoded_array.append(array.get_typed_class_name())
		encoded_array.append(array.get_typed_builtin()) # last element
	else:
		encoded_array.append(-1) # last element
	
	return encoded_array


func _get_encoded_dict(dict: Dictionary) -> Dictionary:
	# Very many dicts will have shared keys, so we index these rather than
	# packing the gamesave with many redundant key strings.
	# All keys of type String are converted to StringName!
	var encoded_dict := {}
	for key: Variant in dict:
		if typeof(key) == TYPE_STRING:
			var key_str: String = key
			key = StringName(key_str)
		var key_id: int = _key_ids.get(key, -1)
		if key_id == -1:
			key_id = _key_ids.size()
			_key_ids[key] = key_id
			_gs_dict_keys.append(key)
		var item: Variant = dict[key]
		var type := typeof(item)
		if type == TYPE_OBJECT:
			var item_object: Object = item
			encoded_dict[key_id] = _get_encoded_object(item_object)
		elif type == TYPE_ARRAY:
			var item_array: Array = item
			encoded_dict[key_id] = _get_encoded_array(item_array)
		elif type == TYPE_DICTIONARY:
			var item_dict: Dictionary = item
			encoded_dict[key_id] = _get_encoded_dict(item_dict)
		else: # built-in type
			encoded_dict[key_id] = item
	return encoded_dict


func _get_decoded_array(encoded_array: Array) -> Array: # may or may not be content-typed
	var array := []
	
	# pop array type from the encoded array
	var typed_builtin: int = encoded_array.pop_back()
	if typed_builtin != -1:
		var typed_class_name: StringName = encoded_array.pop_back()
		var script_id: int = encoded_array.pop_back()
		var script: Script
		if script_id != -1:
			script = _scripts[script_id]
		array = Array(array, typed_builtin, typed_class_name, script)
	
	var n_items := encoded_array.size()
	array.resize(n_items)
	var index := 0
	while index < n_items:
		var item: Variant = encoded_array[index]
		var type := typeof(item)
		if type == TYPE_ARRAY:
			var item_array: Array = item
			array[index] = _get_decoded_array(item_array)
		elif type == TYPE_DICTIONARY:
			var item_dict: Dictionary = item
			if item_dict.has("r"):
				var object := _get_decoded_object(item_dict)
				array[index] = object
			else: # it's a dictionary w/ int keys only
				array[index] = _get_decoded_dict(item_dict)
		else: # other built-in type
			array[index] = item
		index += 1
	return array


func _get_decoded_dict(encoded_dict: Dictionary) -> Dictionary:
	var dict := {}
	for key_id: int in encoded_dict:
		var key: Variant = _gs_dict_keys[key_id] # untyped (any String was converted to StringName)
		var item: Variant = encoded_dict[key_id] # untyped
		var type := typeof(item)
		if type == TYPE_ARRAY:
			var item_array: Array = item
			dict[key] = _get_decoded_array(item_array)
		elif type == TYPE_DICTIONARY:
			@warning_ignore("unsafe_cast")
			var item_dict := item as Dictionary
			if item_dict.has("r"):
				var object := _get_decoded_object(item_dict)
				dict[key] = object
			else: # it's a dictionary w/ int keys only
				dict[key] = _get_decoded_dict(item_dict)
		else: # other built-in type
			dict[key] = item
	return dict


func _get_encoded_object(object: Object) -> Dictionary:
	# Encoded object is a dictionary with key "_" = sign-coded object_id.
	var is_weak_ref := false
	if object is WeakRef:
		@warning_ignore("unsafe_method_access")
		object = object.get_ref()
		if object == null:
			return {r = 0} # object_id = 0 represents a weak ref to dead object
		is_weak_ref = true
	assert(is_persist_object(object), "Can't persist a non-persist obj")
	var object_id: int = _object_ids.get(object, -1)
	if object_id == -1:
		assert(object is RefCounted, "Nodes are already registered")
		var refcounted: RefCounted = object
		object_id = _register_and_serialize_reference(refcounted)
	if is_weak_ref:
		return {r = -object_id} # negative object_id for WeakRef
	return {r = object_id} # positive object_id for non-WeakRef


func _get_decoded_object(encoded_object: Dictionary) -> Object:
	var object_id: int = encoded_object.r
	if object_id == 0:
		return WeakRef.new() # weak ref to dead object
	var object: Object
	if object_id < 0: # weak ref
		object = _objects[-object_id]
		return weakref(object)
	object = _objects[object_id]
	return object

