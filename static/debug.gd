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
## "dprint", "dlog" and most other functions always return true. They can be
## wrapped in assert() so they are called only in debug builds:
##
## [codeblock]
## const DPRINT := true
##
## assert(!DPRINT or IVDebug.dprint("print this only if DPRINT == true"))
## assert(IVDebug.dlog("log this in debug.log"))
## assert(IVDebug.register_objects_recursive_on_nodes_added())
## [/codeblock]
##
## A debug log is opened only in debug builds. It is flushed on
## [signal IVGlobal.run_state_changed], which happens whenever the sim stops
## for a popup (e.g., on [param esc] for the main menu) and closed when project
## autoloads exit the tree. To prevent log file opening, set
## [member dlog_name] = ""[br][br]
##
## Methods with a large singular output usually create a separate log file
## specified by [param log_name].


static var log_directory := "user://logs"
static var dlog_name := "debug.log"

static var _dlog: FileAccess


# Standard file order is violated below to keep related code together...

# *****************************************************************************
# log init, flush and destruction

static func _static_init() -> void:
	if !dlog_name or !OS.is_debug_build():
		return
	_dlog = FileAccess.open(log_directory.path_join(dlog_name), FileAccess.WRITE)
	assert(_dlog, "Failed to open %s" % log_directory.path_join(dlog_name))
	IVGlobal.run_state_changed.connect(_dlog_flush) # e.g., main menu opened/closed
	IVGlobal.tree_exited.connect(_dlog_destroy)


static func _dlog_flush(_dummy := false) -> void:
	_dlog.flush()


static func _dlog_destroy() -> void:
	_dlog.close()
	_dlog = null


# *****************************************************************************
# simple dprint and dlog

static func dprint(arg: Variant, arg2: Variant = "", arg3: Variant = "", arg4: Variant = ""
		) -> bool:
	prints(arg, arg2, arg3, arg4)
	return true


static func dlog(arg: Variant) -> bool:
	if _dlog:
		_dlog.store_line(str(arg))
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


# *****************************************************************************
# verbose signalling

## Prints when [param signal_name] is emitted from [param object] (print line
## will be prefixed with [param prefix]). Call before any other connections
## to this signal so that the print will occur first. Signal must have <= 8 args.
static func signal_verbosely(object: Object, signal_name: String, prefix: String) -> void:
	object.connect(signal_name, IVDebug._on_verbose_signal.bind(prefix + " " + signal_name))


## Prints when any signal is emitted from [param object] (print line
## will be prefixed with [param prefix]). Call before any other connections
## to this signal so that the print will occur first. Signal must have <= 8 args.
static func signal_verbosely_all(object: Object, prefix: String) -> void:
	var signal_list := object.get_signal_list()
	for signal_dict in signal_list:
		var signal_name: String = signal_dict.name
		signal_verbosely(object, signal_name, prefix)


static func _on_verbose_signal(arg: Variant, arg2: Variant = null, arg3: Variant = null,
		arg4: Variant = null, arg5: Variant = null, arg6: Variant = null, arg7: Variant = null,
		arg8: Variant = null, arg9: Variant = null) -> void:
	# Debug <prefix + signal_name> is the last arg (bound after the signal args),
	# so all nulls after that can be removed.
	var args := [arg, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9]
	while args[-1] == null:
		args.pop_back()
	var debug_text: String = args.pop_back()
	prints(debug_text, args)


# *****************************************************************************
# leaked objects

static var _object_register: Dictionary[int, WeakRef] = {}

## Registers objects recursively, searching properties (inculding nested in
## arrays or dictionaries), signal connections, and node children.
## Objects are kept as weak references so RefCounted will free normally.
## Supply [param log_name] to log the register now. Call
## [method log_object_register] to log at a later time. Use to test whether
## objects that are supposed to free themselves are really doing so.
static func register_objects_recursive(root: Node, log_name := "") -> bool:
	_register_object_recursive(root)
	if log_name:
		log_object_register(log_name)
	return true


## Registers objects recursively when any node is added to the tree. The
## registration is deferred so objects set or connected on _ready() will exist.
## See comments in [method register_objects_recursive].
static func register_objects_recursive_on_nodes_added() -> bool:
	IVGlobal.get_tree().node_added.connect(_on_node_added)
	return true


## Log the object register now. See [method register_objects_recursive]
## and [method register_objects_recursive_on_nodes_added].
static func log_object_register(log_name := "objects.log") -> bool:
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


static func _on_node_added(node: Node) -> void:
	_register_object_recursive.call_deferred(node)


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
