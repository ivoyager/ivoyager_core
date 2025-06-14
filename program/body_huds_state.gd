# body_huds_state.gd
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
class_name IVBodyHUDsState
extends Node

## Maintains visibility and color state for [IVBody] HUDs.
##
## Body HUDs must connect and set their own visibility on changed signals.
## A complete set of group 'keys' is defined in data table 'visual_groups.tsv'
## based on exclusive bit flags in IVBody.BodyFlags.[br][br]
##
## See also [IVSBGHUDsState] for [IVSmallBodiesGroup] HUDs.

signal visibility_changed()
signal color_changed()


const NULL_COLOR := Color.BLACK
const BodyFlags: Dictionary = IVBody.BodyFlags

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"name_visible_flags",
	&"symbol_visible_flags",
	&"orbit_visible_flags",
	&"orbit_colors",
]


# persisted - read-only!
var name_visible_flags := 0 # exclusive w/ symbol_visible_flags
var symbol_visible_flags := 0 # exclusive w/ name_visible_flags
var orbit_visible_flags := 0
var orbit_colors: Dictionary[int, Color] = {} # must have full key set from all_flags bits!

# project vars - set at project init
var fallback_orbit_color := Color("FE9C33") # orange

# imported from visual_groups.tsv - ready-only!
var all_flags := 0
var default_name_visible_flags := 0 # exclusive w/ symbol_visible_flags
var default_symbol_visible_flags := 0 # exclusive w/ name_visible_flags
var default_orbit_visible_flags := 0
var default_orbit_colors: Dictionary[int, Color] = {}


# *****************************************************************************

func _init() -> void:
	IVGlobal.project_objects_instantiated.connect(_on_project_objects_instantiated)
	IVGlobal.simulator_exited.connect(_set_current_to_default)
	IVGlobal.update_gui_requested.connect(_signal_all_changed)


func _unhandled_key_input(event: InputEvent) -> void:
	# Only Body HUDs, for now...
	if event.is_action_pressed(&"toggle_orbits"):
		set_all_orbits_visibility(bool(orbit_visible_flags != all_flags))
	elif event.is_action_pressed(&"toggle_symbols"):
		set_all_symbols_visibility(bool(symbol_visible_flags != all_flags))
	elif event.is_action_pressed(&"toggle_names"):
		set_all_names_visibility(bool(name_visible_flags != all_flags))
	else:
		return # input NOT handled!
	get_window().set_input_as_handled()


# *****************************************************************************
# visibility

func hide_all() -> void:
	if !orbit_visible_flags and !name_visible_flags and !symbol_visible_flags:
		return
	orbit_visible_flags = 0
	name_visible_flags = 0
	symbol_visible_flags = 0
	visibility_changed.emit()


func set_default_visibilities() -> void:
	if (name_visible_flags == default_name_visible_flags
			and symbol_visible_flags == default_symbol_visible_flags
			and orbit_visible_flags == default_orbit_visible_flags):
		return
	name_visible_flags = default_name_visible_flags
	symbol_visible_flags = default_symbol_visible_flags
	orbit_visible_flags = default_orbit_visible_flags
	visibility_changed.emit()


func is_name_visible(body_flags: int, match_all := false) -> bool:
	if match_all:
		body_flags &= all_flags
		return body_flags & name_visible_flags == body_flags
	return bool(body_flags & name_visible_flags) # match any


func is_symbol_visible(body_flags: int, match_all := false) -> bool:
	if match_all:
		body_flags &= all_flags
		return body_flags & symbol_visible_flags == body_flags
	return bool(body_flags & symbol_visible_flags) # match any


func is_orbit_visible(body_flags: int, match_all := false) -> bool:
	if match_all:
		body_flags &= all_flags
		return body_flags & orbit_visible_flags == body_flags
	return bool(body_flags & orbit_visible_flags) # match any


func is_all_names_visible() -> bool:
	return name_visible_flags == all_flags


func is_all_symbols_visible() -> bool:
	return symbol_visible_flags == all_flags


func is_all_orbits_visible() -> bool:
	return orbit_visible_flags == all_flags


func set_name_visibility(body_flags: int, is_show: bool) -> void:
	body_flags &= all_flags
	if is_show:
		if name_visible_flags & body_flags == body_flags:
			return
		name_visible_flags |= body_flags
		symbol_visible_flags &= ~body_flags # exclusive
		visibility_changed.emit()
	else:
		if name_visible_flags & body_flags == 0:
			return
		name_visible_flags &= ~body_flags
		visibility_changed.emit()


func set_symbol_visibility(body_flags: int, is_show: bool) -> void:
	body_flags &= all_flags
	if is_show:
		if symbol_visible_flags & body_flags == body_flags:
			return
		symbol_visible_flags |= body_flags
		name_visible_flags &= ~body_flags # exclusive
		visibility_changed.emit()
	else:
		if symbol_visible_flags & body_flags == 0:
			return
		symbol_visible_flags &= ~body_flags
		visibility_changed.emit()


func set_orbit_visibility(body_flags: int, is_show: bool) -> void:
	body_flags &= all_flags
	if is_show:
		if orbit_visible_flags & body_flags == body_flags:
			return
		orbit_visible_flags |= body_flags
		visibility_changed.emit()
	else:
		if orbit_visible_flags & body_flags == 0:
			return
		orbit_visible_flags &= ~body_flags
		visibility_changed.emit()
	visibility_changed.emit()


func set_all_names_visibility(is_show: bool) -> void:
	if is_show:
		if name_visible_flags == all_flags:
			return
		name_visible_flags = all_flags
		symbol_visible_flags = 0 # exclusive
	else:
		if name_visible_flags == 0:
			return
		name_visible_flags = 0
	visibility_changed.emit()


func set_all_symbols_visibility(is_show: bool) -> void:
	if is_show:
		if symbol_visible_flags == all_flags:
			return
		symbol_visible_flags = all_flags
		name_visible_flags = 0 # exclusive
	else:
		if symbol_visible_flags == 0:
			return
		symbol_visible_flags = 0
	visibility_changed.emit()


func set_all_orbits_visibility(is_show: bool) -> void:
	if is_show:
		if orbit_visible_flags == all_flags:
			return
		orbit_visible_flags = all_flags
	else:
		if orbit_visible_flags == 0:
			return
		orbit_visible_flags = 0
	visibility_changed.emit()


func set_name_visible_flags(name_visible_flags_: int) -> void:
	if name_visible_flags == name_visible_flags_:
		return
	name_visible_flags = name_visible_flags_
	symbol_visible_flags &= ~name_visible_flags_ # exclusive
	visibility_changed.emit()


func set_symbol_visible_flags(symbol_visible_flags_: int) -> void:
	if symbol_visible_flags == symbol_visible_flags_:
		return
	symbol_visible_flags = symbol_visible_flags_
	name_visible_flags &= ~symbol_visible_flags_ # exclusive
	visibility_changed.emit()


func set_orbit_visible_flags(orbit_visible_flags_: int) -> void:
	if orbit_visible_flags == orbit_visible_flags_:
		return
	orbit_visible_flags = orbit_visible_flags_
	visibility_changed.emit()


# *****************************************************************************
# color

func set_default_colors() -> void:
	if orbit_colors == default_orbit_colors:
		return
	orbit_colors.merge(default_orbit_colors, true)
	color_changed.emit()


func get_default_orbit_color(body_flags: int) -> Color:
	# If >1 bit from all_flags, will return fallback_orbit_color
	body_flags &= all_flags
	return default_orbit_colors.get(body_flags, fallback_orbit_color)


func get_orbit_color(body_flags: int) -> Color:
	# If >1 bit from all_flags, all must agree or returns NULL_COLOR
	body_flags &= all_flags
	if body_flags and !(body_flags & (body_flags - 1)): # single bit test
		return orbit_colors[body_flags]
	var has_first := false
	var consensus_color := NULL_COLOR
	var flag := 1
	while body_flags:
		if body_flags & 1:
			var color: Color = orbit_colors[flag]
			if has_first and color != consensus_color:
				return NULL_COLOR
			has_first = true
			consensus_color = color
		flag <<= 1
		body_flags >>= 1
	return consensus_color


func set_orbit_color(body_flags: int, color: Color) -> void:
	# Can set any number from all_flags.
	body_flags &= all_flags
	if body_flags and !(body_flags & (body_flags - 1)): # single bit test
		if orbit_colors[body_flags] != color:
			orbit_colors[body_flags] = color
			color_changed.emit()
		return
	var changed := false
	var flag := 1
	while body_flags:
		if body_flags & 1:
			if orbit_colors[flag] != color:
				orbit_colors[flag] = color
				changed = true
		flag <<= 1
		body_flags >>= 1
	if changed:
		color_changed.emit()


func get_non_default_orbit_colors() -> Dictionary[int, Color]:
	# key-values equal to default are skipped
	var dict: Dictionary[int, Color] = {}
	for flag: int in orbit_colors:
		if orbit_colors[flag] != default_orbit_colors[flag]:
			dict[flag] = orbit_colors[flag]
	return dict


func set_all_orbit_colors(dict: Dictionary[int, Color]) -> void:
	# missing key-values are set to default
	var is_change := false
	for flag: int in orbit_colors:
		if dict.has(flag):
			if orbit_colors[flag] != dict[flag]:
				is_change = true
				orbit_colors[flag] = dict[flag]
		else:
			if orbit_colors[flag] != default_orbit_colors[flag]:
				is_change = true
				orbit_colors[flag] = default_orbit_colors[flag]
	if is_change:
		color_changed.emit()


# *****************************************************************************
# private


func _on_project_objects_instantiated() -> void:
	for row in IVTableData.get_n_rows(&"visual_groups"):
		var body_flag := IVTableData.get_db_int(&"visual_groups", &"body_flag", row)
		var name_visible := IVTableData.get_db_bool(&"visual_groups", &"default_name_visible", row)
		var symbol_visible := IVTableData.get_db_bool(&"visual_groups", &"default_symbol_visible", row)
		var orbit_visible := IVTableData.get_db_bool(&"visual_groups", &"default_orbit_visible", row)
		var orbit_color := IVTableData.get_db_color(&"visual_groups", &"default_orbit_color", row)
		
		all_flags |= body_flag
		if name_visible:
			default_name_visible_flags |= body_flag
		if symbol_visible:
			default_symbol_visible_flags |= body_flag
		if orbit_visible:
			default_orbit_visible_flags |= body_flag
		default_orbit_colors[body_flag] = orbit_color
	
	_set_current_to_default()


func _set_current_to_default() -> void:
	set_default_visibilities()
	set_default_colors()


func _signal_all_changed() -> void:
	visibility_changed.emit()
	color_changed.emit()
