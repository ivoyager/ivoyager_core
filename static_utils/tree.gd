# tree.gd
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
class_name IVTree
extends Object

## Tree static utility methods.


## Frees all "procedural" Nodes at or below [param node]. Note: The
## I, Voyager - Save plugin has a better deconstructor method
## [code]free_procedural_objects_recursive()[/code] if that is enabled.
## This one can't properly handle circular references to procedural
## RefCounted instances.
static func free_procedural_nodes_recursive(node: Node) -> void:
	if node.get(&"PERSIST_MODE") == IVGlobal.PERSIST_PROCEDURAL:
		node.queue_free() # children will also be freed!
		return
	for child in node.get_children():
		if child.get(&"PERSIST_MODE"): # procedural or properties only
			free_procedural_nodes_recursive(child)


## Returns common ancestor Node3D, including [param node1] or [param node2] if
## one is ancestor of the other. Assumes ancestor tree consists of only Node3D
## instances.
static func get_common_node3d(node1: Node3D, node2: Node3D) -> Node3D:
	while node1:
		var loop_spatial2 := node2
		while loop_spatial2:
			if node1 == loop_spatial2:
				return loop_spatial2
			loop_spatial2 = loop_spatial2.get_parent_node_3d()
		node1 = node1.get_parent_node_3d()
	return null


## Returns Variant result of [param target]/[param path]. Path is in the form
## "item/item/item/..." where "item" can be a method, a property, a node child,
## or a dictionary key. If a method is encountered, [param args] will be used.
## Each item except the last must resolve to an Object, a Dictionary, or null.
## Returns null if any item in the path does not exist.
static func get_path_variant(target: Variant, path: String, args := []) -> Variant:
	var path_split := path.split("/")
	var size := path_split.size()
	var i := 0
	while i < size:
		var item_name := path_split[i]
		assert(item_name, "Consecutive '/' in path %s" % path)
		if target is Object:
			if !is_instance_valid(target):
				return null
			var object: Object = target
			if object.has_method(item_name):
				target = object.callv(item_name, args)
			elif item_name in object: # property
				target = object.get(item_name)
			elif object is Node:
				var node: Node = object
				target = node.get_node_or_null(item_name)
			else:
				return null
		elif target is Dictionary:
			var dict: Dictionary = target
			target = dict.get(item_name)
		else:
			assert("target or non-final item in '%s' is not an Object or Dictionary" % path)
		if target == null:
			return null
		i += 1
	return target


## Gets [param property] Variant from an ancestor of [param node].
## Returns null if the property does not exist up the ancestry tree. If
## [param skip_null_type] is set to true, keep searching up the tree if a
## Node has property but its value evaluates to false in a boolean
## context (null, false, 0, 0.0, "", &"", [], Vector2(0, 0), etc.).
static func get_ancestor_variant(node: Node, property: StringName, skip_null_type := false
		) -> Variant:
	node = node.get_parent()
	while node:
		if property in node:
			var value: Variant = node.get(property)
			if value or !skip_null_type:
				return value
		node = node.get_parent()
	return null


## Gets [param property] bool from an ancestor of [param node].
## Returns false if property does not exist up the ancestry tree. If
## [param skip_false] is set to true, keep searching up the tree if a
## Node has property but its value is false.
static func get_ancestor_bool(node: Node, property: StringName, skip_false := false) -> bool:
	node = node.get_parent()
	while node:
		if property in node:
			var value: bool = node.get(property)
			if value or !skip_false:
				return value
		node = node.get_parent()
	return false


## Gets [param property] String from an ancestor of [param node].
## Returns "" if property does not exist up the ancestry tree. If
## [param skip_empty] is set to true, keep searching up the tree if a
## Node has property but its value is "".
static func get_ancestor_string(node: Node, property: StringName, skip_empty := false
		) -> String:
	node = node.get_parent()
	while node:
		if property in node:
			var string: String = node.get(property)
			if string or !skip_empty:
				return string
		node = node.get_parent()
	return ""


## Gets [param property] StringName from an ancestor of [param node].
## Returns &"" if property does not exist up the ancestry tree. If
## [param skip_empty] is set to true, keep searching up the tree if a
## Node has property but its value is &"".
static func get_ancestor_string_name(node: Node, property: StringName, skip_empty := false
		) -> StringName:
	node = node.get_parent()
	while node:
		if property in node:
			var string_name: String = node.get(property)
			if string_name or !skip_empty:
				return string_name
		node = node.get_parent()
	return &""


## Gets [param property] Dictionary from an ancestor of [param node].
## Returns an empty Dictionary if property does not exist up the ancestry tree.
## If [param skip_empty] is set to true, keep searching up the tree if
## a Node has property but its value is null.
static func get_ancestor_dictionary(node: Node, property: StringName, skip_empty := false
		) -> Dictionary:
	node = node.get_parent()
	while node:
		if property in node:
			var dict: Dictionary = node.get(property)
			if dict or !skip_empty:
				return dict
		node = node.get_parent()
	return {}


## Gets [param property] Array from an ancestor of [param node].
## Returns an empty Array if property does not exist up the ancestry tree.
## If [param skip_empty] is set to true, keep searching up the tree if
## a Node has property but its value is null.
static func get_ancestor_array(node: Node, property: StringName, skip_empty := false) -> Array:
	node = node.get_parent()
	while node:
		if property in node:
			var array: Array = node.get(property)
			if array or !skip_empty:
				return array
		node = node.get_parent()
	return []


## Gets [param property] Object from an ancestor of [param node].
## Returns null if property does not exist up the ancestry tree. If
## [param skip_null] is set to true, keep searching up the tree if a Node
## has property but its value is null.
static func get_ancestor_object(node: Node, property: StringName, skip_null := false) -> Object:
	node = node.get_parent()
	while node:
		if property in node:
			var object: Object = node.get(property)
			if object or !skip_null:
				return object
		node = node.get_parent()
	return null
