# input_map_manager.gd
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
class_name IVInputMapManager
extends RefCounted

## Defines and manages InputMap actions.
##
## We define InputMap actions here to allow player modification via [IVHotkeysPopup].
## Non-default actions are persisted in a cache file.[br][br]
##
## This node and [IVHotkeysPopup] are unaware of actions defined in project.godot.


var file_name := "input_map.ivbinary"
var file_version := "0.0.23" # update when obsoleted
var current: Dictionary[StringName, Variant] = {}
var defaults := IVCoreSettings.default_input_map
var cache_handler: IVCacheHandler

# project vars
var reserved_scancodes: Array[int] = [] # user can't overwrite w/ or w/out key mods
var event_classes: Dictionary[StringName, Object] = { # we'll expand this as needed
	&"InputEventKey" : InputEventKey,
	&"InputEventJoypadButton" : InputEventJoypadButton,
	}

# read-only!
var actions_by_scancode_w_mods: Dictionary[int, StringName]= {}


func _init() -> void:
	cache_handler = IVCacheHandler.new(defaults, current, file_name, file_version)
	cache_handler.current_changed.connect(_reset_scancodes_and_input_map)
	IVGlobal.project_objects_instantiated.connect(_init_actions)


func _init_actions() -> void:
	for action: StringName in current:
		var scancodes := get_scancodes_w_mods_for_action(action)
		for scancode_w_mods in scancodes:
			actions_by_scancode_w_mods[scancode_w_mods] = action
		_reset_input_map(action)


# *****************************************************************************

## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func set_action_event_dict(action: StringName, event_dict: Dictionary, index: int,
		suppress_caching := false) -> void:
	# index can be arbitrarily large to add to end.
	# If suppress_caching = true, be sure to call cache_now() later.
	var events_array: Array = current[action]
	var event_class: StringName = event_dict.event_class
	var event_array_index := get_event_array_index(action, event_class, index)
	if event_array_index == events_array.size():
		events_array.append(event_dict)
	else:
		events_array[event_array_index] = event_dict
	_reset_scancodes_and_input_map(action)
	if !suppress_caching:
		cache_handler.cache_now()


func get_event_array_index(action: StringName, event_class: StringName, index: int) -> int:
	# index can be arbitrarily large
	var events_array: Array = current[action]
	var i := 0
	var class_index := 0
	while i < events_array.size():
		var event_dict: Dictionary = events_array[i]
		if event_dict.event_class == event_class:
			if index == class_index:
				return i
			class_index += 1
		i += 1
	return i # size of events_array


func get_event_dicts(action: StringName, event_class: StringName) -> Array:
	var result := []
	var events_array: Array = current[action]
	for event_dict: Dictionary in events_array:
		if event_dict.event_class == event_class:
			result.append(event_dict)
	return result


func remove_event_dict_by_index(action: StringName, event_class: StringName, index: int,
		suppress_caching := false) -> void:
	# index is for event dicts of specified event_class (not array index!)
	var scancodes_w_mods: Array[int]
	if event_class == &"InputEventKey":
		scancodes_w_mods = get_scancodes_w_mods_for_action(action)
	var events_array: Array = current[action]
	var i := 0
	var class_index := 0
	while i < events_array.size():
		var event_dict: Dictionary = events_array[i]
		if event_dict.event_class == event_class:
			if index == class_index:
				events_array.remove_at(i)
				if event_class == &"InputEventKey":
					var scancode_w_mods: int = scancodes_w_mods[index]
					actions_by_scancode_w_mods.erase(scancode_w_mods)
				break
			class_index += 1
		i += 1
	_reset_scancodes_and_input_map(action)
	if !suppress_caching:
		cache_handler.cache_now()


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func remove_event_dict_by_match(action: StringName, event_class: StringName, scancode_w_mods := -1,
		button_index := -1, suppress_caching := false) -> void:
	# NOT TESTED!!!
	# supply scancode_w_mods or button_index, depending on event_class
	var events_array: Array = current[action]
	var i := 0
	while i < events_array.size():
		var event_dict: Dictionary = events_array[i]
		if event_dict.event_class == event_class:
			if event_class == &"InputEventKey":
				if scancode_w_mods == get_scancode_w_mods_for_event_dict(event_dict):
					events_array.remove_at(i)
					actions_by_scancode_w_mods.erase(scancode_w_mods)
					break
			elif event_class == &"InputEventJoypadButton":
				if button_index == event_dict.button_index:
					events_array.remove_at(i)
					break
		i += 1
	if !suppress_caching:
		cache_handler.cache_now()


func cache_now() -> void:
	cache_handler.cache_now()


func is_default(key: StringName) -> bool:
	return cache_handler.is_default(key)


func is_defaults() -> bool:
	return cache_handler.is_defaults()


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func restore_default(key: StringName, suppress_caching := false) -> void:
	cache_handler.restore_default(key, suppress_caching)


## If [param suppress_caching] == true, be sure to call [method cache_now] later.
func restore_defaults(suppress_caching := false) -> void:
	cache_handler.restore_defaults(suppress_caching)


func is_cache_current() -> bool:
	return cache_handler.is_cache_current()


func restore_from_cache() -> void:
	cache_handler.restore_from_cache()



func get_scancodes_w_mods_for_action(action: StringName) -> Array[int]:
	var scancodes: Array[int] = []
	var events_array: Array = current[action]
	for event_dict: Dictionary in events_array:
		if event_dict.event_class == &"InputEventKey":
			var keycode := get_scancode_w_mods_for_event_dict(event_dict)
			scancodes.append(keycode)
	return scancodes


static func get_scancode_w_mods_for_event_dict(event_dict: Dictionary) -> int:
	assert(event_dict.event_class == &"InputEventKey")
	var keycode: int = event_dict.keycode
	var shift_pressed: bool = event_dict.get(&"shift_pressed", false)
	var ctrl_pressed: bool = event_dict.get(&"ctrl_pressed", false)
	var alt_pressed: bool = event_dict.get(&"alt_pressed", false)
	var meta_pressed: bool = event_dict.get(&"meta_pressed", false)
	return get_scancode_w_mods(keycode, shift_pressed, ctrl_pressed, alt_pressed, meta_pressed)


static func get_scancode_w_mods(keycode: int, shift_pressed := false, ctrl_pressed := false,
		alt_pressed := false, meta_pressed := false) -> int:
	if shift_pressed:
		keycode |= KEY_MASK_SHIFT
	if ctrl_pressed:
		keycode |= KEY_MASK_CTRL
	if alt_pressed:
		keycode |= KEY_MASK_ALT
	if meta_pressed:
		keycode |= KEY_MASK_META
	return keycode


# Rename get_scancode_without_mods()?
static func strip_scancode_mods(keycode: int) -> int:
	# Note: InputEventKey.scancode is already stripped.
	keycode &= ~KEY_MASK_SHIFT
	keycode &= ~KEY_MASK_CTRL
	keycode &= ~KEY_MASK_ALT
	keycode &= ~KEY_MASK_META
	return keycode


# *****************************************************************************


func _reset_scancodes_and_input_map(action: StringName, _dummy: Variant = null) -> void:
	for scancode_w_mods: int in actions_by_scancode_w_mods.keys():
		if actions_by_scancode_w_mods[scancode_w_mods] == action:
			actions_by_scancode_w_mods.erase(scancode_w_mods)
	var scancodes := get_scancodes_w_mods_for_action(action)
	for scancode_w_mods in scancodes:
		actions_by_scancode_w_mods[scancode_w_mods] = action
	_reset_input_map(action)


func _reset_input_map(action: StringName) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
	var events_array: Array = current[action]
	for event_dict: Dictionary in events_array:
		@warning_ignore("unsafe_method_access")
		var event: InputEvent = event_classes[event_dict.event_class].new()
		for key: StringName in event_dict:
			if key != &"event_class":
				event.set(key, event_dict[key])
		InputMap.action_add_event(action, event)
