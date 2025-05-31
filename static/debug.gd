# debug.gd
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
class_name IVDebug
extends Object

## Provides debug static functions.
##
## Print & log functions return true so they can be wrapped in assert(). E.g.,[br]
##     [code]assert(IVDebug.dlog("debug print"))[/code][br]
##     [code]assert(!DPRINT or IVDebug.dprint("debug print"))[/code]
##
## TODO: Make this a self-contained singleton. Consolidate log_initializer.gd
## and related IVCoreSettings and IVGlobal members.

static var log_directory := "user://logs"


static func dprint(arg: Variant, arg2: Variant = "", arg3: Variant = "", arg4: Variant = ""
		) -> bool:
	# For >4 items, just use an array.
	prints(arg, arg2, arg3, arg4)
	return true


static func dlog(arg: Variant) -> bool:
	var file := IVGlobal.debug_log
	if !file:
		return true
	var line := str(arg)
	file.store_line(line)
	return true


static func dprint_orphan_nodes() -> bool:
	IVGlobal.print_orphan_nodes()
	return true


static func dprint_tree_pretty(node: Node = null) -> bool:
	if !node:
		node = IVGlobal.get_viewport()
	node.print_tree_pretty()
	return true


static func dprint_nodes_recursive(node: Node = null, include_internal: bool = true) -> bool:
	if !node:
		node = IVGlobal.get_viewport()
	print(node)
	for child in node.get_children(include_internal):
		dprint_nodes_recursive(child, include_internal)
	return true


static func dlog_nodes_recursive(node: Node = null, include_internal: bool = true) -> bool:
	if !node:
		node = IVGlobal.get_viewport()
	dlog(node)
	for child in node.get_children(include_internal):
		dlog_nodes_recursive(child, include_internal)
	return true



static func signal_verbosely(object: Object, signal_name: String, prefix: String) -> void:
	# Call before any other signal connections; signal must have <= 8 args.
	object.connect(signal_name, IVDebug._on_verbose_signal.bind(prefix + " " + signal_name))


static func signal_verbosely_all(object: Object, prefix: String) -> void:
	# See signal_verbosely. Prints all emitted signals from object.
	var signal_list := object.get_signal_list()
	for signal_dict in signal_list:
		var signal_name: String = signal_dict.name
		signal_verbosely(object, signal_name, prefix)


static func _on_verbose_signal(arg: Variant, arg2: Variant = null, arg3: Variant = null,
		arg4: Variant = null, arg5: Variant = null, arg6: Variant = null, arg7: Variant = null,
		arg8: Variant = null, arg9: Variant = null) -> void:
	# Expects signal_name as last bound argument.
	var args := [arg, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9]
	while args[-1] == null:
		args.pop_back()
	var debug_text: String = args.pop_back()
	prints(debug_text, args)


# *****************************************************************************
# leaked objects

static var _object_register: Dictionary[int, WeakRef] = {}


static func register_all_objects(root: Node, log_name := "objects.log") -> bool:
	_register_object_recursive(root)
	if log_name:
		dlog_object_register(log_name)
	return true


static func dlog_object_register(log_name := "objects.log") -> bool:
	var file := FileAccess.open(log_directory.path_join(log_name), FileAccess.WRITE)
	for id in _object_register:
		var object: Object = _object_register[id].get_ref()
		if !object:
			continue
		var script: Script = object.get_script()
		var class_file := script.resource_path.get_file() if script else ""
		var line := str(object) + " " + class_file
		file.store_line(line)
	return true


static func _register_object_recursive(object: Object) -> void:
	if !object or !is_instance_valid(object):
		return
	
	# Index this object (once).
	var id := object.get_instance_id()
	if _object_register.has(id):
		return
	_object_register[id] = weakref(object)
	
	# Check all properties.
	for property_dict in object.get_property_list():
		var property: StringName = property_dict.name
		var variant: Variant = object.get(property)
		if variant: # skip null or empty container
			_register_variant_recursive(variant)
	
	# Check all signal connections.
	for connection_dict in object.get_incoming_connections():
		var callable: Callable = connection_dict.callable
		var connected_object := callable.get_object()
		_register_object_recursive(connected_object)
	
	# Check all node children.
	if object is Node:
		var node: Node = object
		for child in node.get_children(true):
			_register_object_recursive(child)


static func _register_variant_recursive(variant: Variant) -> void:
	var type := typeof(variant)
	if type == TYPE_OBJECT:
		var object: Object = variant
		_register_object_recursive(object)
	elif type == TYPE_ARRAY:
		var array: Array = variant
		_register_array_recursive(array)
	elif type == TYPE_DICTIONARY:
		var dict: Dictionary = variant
		_register_dictionary_recursive(dict)


static func _register_array_recursive(array: Array) -> void:
	var array_type := array.get_typed_builtin()
	if array_type == TYPE_OBJECT:
		for object: Object in array:
			_register_object_recursive(object)
	elif array_type == TYPE_ARRAY:
		for nested_array: Array in array:
			_register_array_recursive(nested_array)
	elif array_type == TYPE_DICTIONARY:
		for dict: Dictionary in array:
			_register_dictionary_recursive(dict)
	elif array_type == TYPE_NIL:
		for variant: Variant in array:
			_register_variant_recursive(variant)


static func _register_dictionary_recursive(dict: Dictionary) -> void:
	const REGISTER_TYPES: Array[int] = [TYPE_OBJECT, TYPE_ARRAY, TYPE_DICTIONARY, TYPE_NIL]
	var key_type := dict.get_typed_key_builtin()
	if REGISTER_TYPES.has(key_type):
		var keys := Array(dict.keys(), key_type, &"", null)
		_register_array_recursive(keys)
	var value_type := dict.get_typed_value_builtin()
	if REGISTER_TYPES.has(value_type):
		var values := Array(dict.values(), value_type, &"", null)
		_register_array_recursive(values)
