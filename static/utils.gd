# utils.gd
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
class_name IVUtils
extends Object

## Miscellaneous utility static functions.


# Tree utilities

## Frees all 'procedural' Nodes at or below [code]root_node[/code]. Note: The
## 'I, Voyager - Save' plugin has a better deconstructor method
## [code]free_procedural_objects_recursive()[/code] if that is enabled.
## This one can't properly handle circular references to procedural
## RefCounted instances.
static func free_procedural_nodes_recursive(root_node: Node) -> void:
	if root_node.get(&"PERSIST_MODE") == IVGlobal.PERSIST_PROCEDURAL:
		root_node.queue_free() # children will also be freed!
		return
	for child in root_node.get_children():
		if &"PERSIST_MODE" in child:
			free_procedural_nodes_recursive(child)


## Returns common ancestor Node3D, or parent if one arg is parent of the
## other. Assumes ancestor tree consists of only Node3D instances.
static func get_common_node3d(node1: Node3D, node2: Node3D) -> Node3D:
	while node1:
		var loop_spatial2 := node2
		while loop_spatial2:
			if node1 == loop_spatial2:
				return loop_spatial2
			loop_spatial2 = loop_spatial2.get_parent_node_3d()
		node1 = node1.get_parent_node_3d()
	return null


## Searches 'item/item/item/...' path starting from target, where 'item' can
## be object properties or dictionary keys.
static func get_deep(target: Variant, path: String) -> Variant:
	if !path:
		return target
	var path_stack := Array(path.split("/", false))
	path_stack.reverse()
	while path_stack:
		var item_name: String = path_stack.pop_back()
		@warning_ignore("unsafe_method_access")
		target = target.get(item_name)
		if target == null:
			return null
	return target


## Searches 'item/item/item/...' path starting from target, where 'item' can
## be object properties, dictionary keys, or method names.
static func get_path_result(target: Variant, path: String, args := []) -> Variant:
	# as above but path could include methods
	if !path:
		return target
	var path_stack := Array(path.split("/", false))
	path_stack.reverse()
	while path_stack:
		var item_name: String = path_stack.pop_back()
		if target is Object:
			@warning_ignore("unsafe_cast")
			var object := target as Object
			if object.has_method(item_name):
				target = object.callv(item_name, args)
			else:
				target = object.get(item_name)
		else:
			@warning_ignore("unsafe_method_access")
			target = target.get(item_name)
		if target == null:
			return null
	return target


# Arrays

## Init array of given size, fill content, and type. Will throw error if
## [code]fill[/code] is incorrect type (leave null to not fill).
static func init_array(size: int, fill: Variant = null, type := -1, class_name_ := &"",
		script: Variant = null) -> Array:
	var array: Array
	if type == -1:
		array = []
	else:
		array = Array([], type, class_name_, script)
	array.resize(size)
	if fill == null:
		return array
	array.fill(fill)
	return array


# Conversions

static func srgb2linear(color: Color) -> Color:
	if color.r <= 0.04045:
		color.r /= 12.92
	else:
		color.r = pow((color.r + 0.055) / 1.055, 2.4)
	if color.g <= 0.04045:
		color.g /= 12.92
	else:
		color.g = pow((color.g + 0.055) / 1.055, 2.4)
	if color.b <= 0.04045:
		color.b /= 12.92
	else:
		color.b = pow((color.b + 0.055) / 1.055, 2.4)
	return color


static func linear2srgb(x: float) -> float:
	if x <= 0.0031308:
		return x * 12.92
	else:
		return pow(x, 1.0 / 2.4) * 1.055 - 0.055


# Number strings

## Returns 64 bit string formatted '00000000_00000000_00000000_...'.
static func get_bit_string(flags: int, bytes := 4) -> String:
	var bits := bytes * 8
	var result := ""
	var index := 0
	while index < bits:
		if index % 8 == 0 and index != 0:
			result = "_" + result
		result = "1" + result if flags & 1 else "0" + result
		flags >>= 1
		index += 1
	return result


# GUI

## Positions [param popup] at [param corner] of [param at_control].
## Call deferred may be needed if popup changes size when shown.
static func position_popup_at_corner(popup: Popup, at_control: Control, corner: Corner) -> void:
	# Note: at_control may be in its own popup. However, popup seems to be always
	# be in root window even if it was added as descendent of a popup.
	var popup_size := popup.size
	var control_size := Vector2i(at_control.size)
	var root := at_control.get_tree().get_root()
	var viewport_size := Vector2i(root.get_visible_rect().size)
	var position := Vector2i(at_control.global_position)
	var window := at_control.get_window()
	if window != root: # at_control is in a popup
		position += window.position
	if corner == Corner.CORNER_TOP_LEFT or corner == Corner.CORNER_BOTTOM_LEFT:
		position.x = maxi(position.x - popup_size.x, 0)
	else:
		position.x = mini(position.x + control_size.x, viewport_size.x - popup_size.x)
	if corner == Corner.CORNER_TOP_LEFT or corner == Corner.CORNER_TOP_RIGHT:
		position.y = maxi(position.y - popup_size.y, 0)
	else:
		position.y = mini(position.y + control_size.y, viewport_size.y - popup_size.y)
	popup.position = position


# Patches

## Patch method to handle "\u", which is not handled by Godot's [code]c_unescape()[/code].
## See Godot issue #38716. Large unicodes are not supported by Godot, so we
## can't do anything with "\U".
static func c_unescape_patch(text: String) -> String:
	var u_esc := text.find("\\u")
	while u_esc != -1:
		var esc_str := text.substr(u_esc, 6)
		var hex_str := esc_str.replace("\\u", "0x")
		var unicode := hex_str.hex_to_int()
		var unicode_chr := char(unicode)
		text = text.replace(esc_str, unicode_chr)
		u_esc = text.find("\\u")
	return text
