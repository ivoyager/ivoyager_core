# body_huds_state.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield
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

## Maintains visibility, color and symbol state for [IVBody] HUDs.
##
## Body HUDs must connect and set their own state on changed signals. A complete
## set of group 'keys' is defined in data table 'visual_groups.tsv' based on
## exclusive bit flags in [enum IVBody.BodyFlags].[br][br]
##
## Symbol and name visibility are independent (either, both or neither may show).
## A group's single [member colors] entry is shared by its symbol, name and orbit.
## The symbol shape is a per-group symbol-atlas index in [member symbol_types].[br][br]
##
## See also [IVSBGHUDsState] for [IVSmallBodiesGroup] HUDs.


# TODO: API for VISUAL_GROUP_


## Emitted whenever any of [member name_visible_flags],
## [member symbol_visible_flags], or [member orbit_visible_flags] changes.
signal visibility_changed()
## Emitted whenever any entry of [member colors] changes.
signal color_changed()
## Emitted whenever any entry of [member symbol_types] changes.
signal symbol_changed()


## Sentinel returned by [method get_color] when a multi-bit query has no
## consensus color across the matching groups.
const NULL_COLOR := Color.BLACK
## Sentinel returned by [method get_symbol_type] when a multi-bit query has no
## consensus symbol across the matching groups. Distinct from -1 ("point"), which
## bodies never use.
const NULL_SYMBOL := -2
## Convenience alias for [enum IVBody.BodyFlags].
const BodyFlags: Dictionary = IVBody.BodyFlags

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"name_visible_flags",
	&"symbol_visible_flags",
	&"orbit_visible_flags",
	&"colors",
	&"symbol_types",
]


# persisted - read-only!
## Bitwise OR of [enum IVBody.BodyFlags] for body groups whose name labels are
## currently visible. Independent of [member symbol_visible_flags].
## Read-only; modify via setter methods.
var name_visible_flags := 0
## Bitwise OR of [enum IVBody.BodyFlags] for body groups whose symbols are
## currently visible. Independent of [member name_visible_flags].
var symbol_visible_flags := 0
## Bitwise OR of [enum IVBody.BodyFlags] for body groups whose orbits are
## currently visible.
var orbit_visible_flags := 0
## Per-flag color, shared by each group's symbol, name and orbit. Must have a
## full key set from [member all_flags] bits.
var colors: Dictionary[int, Color] = {} # must have full key set from all_flags bits!
## Per-flag symbol shape (a symbol-atlas index). Must have a full key set from
## [member all_flags] bits.
var symbol_types: Dictionary[int, int] = {} # must have full key set from all_flags bits!

# project vars - set at project init
## Color returned by [method get_default_color] when no single-flag match
## is found.
var fallback_color := Color("FE9C33") # orange
## Symbol returned by [method get_default_symbol_type] when no single-flag match
## is found.
var fallback_symbol_type := 0 # CIRCLE in the default atlas

# imported from visual_groups.tsv - ready-only!
## Bitwise OR of every body-flag in [code]visual_groups.tsv[/code] (read-only).
var all_flags := 0
## Default value for [member name_visible_flags] (read-only).
var default_name_visible_flags := 0
## Default value for [member symbol_visible_flags] (read-only).
var default_symbol_visible_flags := 0
## Default value for [member orbit_visible_flags] (read-only).
var default_orbit_visible_flags := 0
## Default value for [member colors] (read-only).
var default_colors: Dictionary[int, Color] = {}
## Default value for [member symbol_types] (read-only).
var default_symbol_types: Dictionary[int, int] = {}


# *****************************************************************************

func _init() -> void:
	IVStateManager.core_init_program_objects_instantiated.connect(_on_program_objects_instantiated)
	IVStateManager.simulator_exited.connect(_set_current_to_default)
	IVGlobal.ui_dirty.connect(_on_ui_dirty)


func _shortcut_input(event: InputEvent) -> void:
	# Only Body HUDs, for now...
	if not event.is_pressed():
		return
	if event.is_action_pressed(&"toggle_orbits"):
		set_all_orbits_visibility(bool(orbit_visible_flags != all_flags))
	elif event.is_action_pressed(&"toggle_symbols"):
		set_all_symbols_visibility(bool(symbol_visible_flags != all_flags))
	elif event.is_action_pressed(&"toggle_names"):
		set_all_names_visibility(bool(name_visible_flags != all_flags))
	else:
		return # input NOT handled!
	get_viewport().set_input_as_handled()


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


func set_all_names_visibility(is_show: bool) -> void:
	if is_show:
		if name_visible_flags == all_flags:
			return
		name_visible_flags = all_flags
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
	visibility_changed.emit()


func set_symbol_visible_flags(symbol_visible_flags_: int) -> void:
	if symbol_visible_flags == symbol_visible_flags_:
		return
	symbol_visible_flags = symbol_visible_flags_
	visibility_changed.emit()


func set_orbit_visible_flags(orbit_visible_flags_: int) -> void:
	if orbit_visible_flags == orbit_visible_flags_:
		return
	orbit_visible_flags = orbit_visible_flags_
	visibility_changed.emit()


# *****************************************************************************
# color (shared by symbol, name and orbit)

func set_default_colors() -> void:
	if colors == default_colors:
		return
	colors.merge(default_colors, true)
	color_changed.emit()


func get_default_color(body_flags: int) -> Color:
	# If >1 bit from all_flags, will return fallback_color
	body_flags &= all_flags
	return default_colors.get(body_flags, fallback_color)


func get_color(body_flags: int) -> Color:
	# If >1 bit from all_flags, all must agree or returns NULL_COLOR
	body_flags &= all_flags
	if body_flags and !(body_flags & (body_flags - 1)): # single bit test
		return colors[body_flags]
	var has_first := false
	var consensus_color := NULL_COLOR
	var flag := 1
	while body_flags:
		if body_flags & 1:
			var color: Color = colors[flag]
			if has_first and color != consensus_color:
				return NULL_COLOR
			has_first = true
			consensus_color = color
		flag <<= 1
		body_flags >>= 1
	return consensus_color


func set_color(body_flags: int, color: Color) -> void:
	# Can set any number from all_flags.
	body_flags &= all_flags
	if body_flags and !(body_flags & (body_flags - 1)): # single bit test
		if colors[body_flags] != color:
			colors[body_flags] = color
			color_changed.emit()
		return
	var changed := false
	var flag := 1
	while body_flags:
		if body_flags & 1:
			if colors[flag] != color:
				colors[flag] = color
				changed = true
		flag <<= 1
		body_flags >>= 1
	if changed:
		color_changed.emit()


func get_non_default_colors() -> Dictionary[int, Color]:
	# key-values equal to default are skipped
	var dict: Dictionary[int, Color] = {}
	for flag: int in colors:
		if colors[flag] != default_colors[flag]:
			dict[flag] = colors[flag]
	return dict


func set_all_colors(dict: Dictionary[int, Color]) -> void:
	# missing key-values are set to default
	var is_change := false
	for flag: int in colors:
		if dict.has(flag):
			if colors[flag] != dict[flag]:
				is_change = true
				colors[flag] = dict[flag]
		else:
			if colors[flag] != default_colors[flag]:
				is_change = true
				colors[flag] = default_colors[flag]
	if is_change:
		color_changed.emit()


# *****************************************************************************
# symbol

func set_default_symbols() -> void:
	if symbol_types == default_symbol_types:
		return
	symbol_types.merge(default_symbol_types, true)
	symbol_changed.emit()


func get_default_symbol_type(body_flags: int) -> int:
	# If >1 bit from all_flags, will return fallback_symbol_type
	body_flags &= all_flags
	return default_symbol_types.get(body_flags, fallback_symbol_type)


func get_symbol_type(body_flags: int) -> int:
	# If >1 bit from all_flags, all must agree or returns NULL_SYMBOL
	body_flags &= all_flags
	if body_flags and !(body_flags & (body_flags - 1)): # single bit test
		return symbol_types[body_flags]
	var has_first := false
	var consensus_symbol := NULL_SYMBOL
	var flag := 1
	while body_flags:
		if body_flags & 1:
			var symbol: int = symbol_types[flag]
			if has_first and symbol != consensus_symbol:
				return NULL_SYMBOL
			has_first = true
			consensus_symbol = symbol
		flag <<= 1
		body_flags >>= 1
	return consensus_symbol


func set_symbol_type(body_flags: int, symbol: int) -> void:
	# Can set any number from all_flags.
	body_flags &= all_flags
	if body_flags and !(body_flags & (body_flags - 1)): # single bit test
		if symbol_types[body_flags] != symbol:
			symbol_types[body_flags] = symbol
			symbol_changed.emit()
		return
	var changed := false
	var flag := 1
	while body_flags:
		if body_flags & 1:
			if symbol_types[flag] != symbol:
				symbol_types[flag] = symbol
				changed = true
		flag <<= 1
		body_flags >>= 1
	if changed:
		symbol_changed.emit()


func get_non_default_symbol_types() -> Dictionary[int, int]:
	# key-values equal to default are skipped
	var dict: Dictionary[int, int] = {}
	for flag: int in symbol_types:
		if symbol_types[flag] != default_symbol_types[flag]:
			dict[flag] = symbol_types[flag]
	return dict


func set_all_symbol_types(dict: Dictionary[int, int]) -> void:
	# missing key-values are set to default
	var is_change := false
	for flag: int in symbol_types:
		if dict.has(flag):
			if symbol_types[flag] != dict[flag]:
				is_change = true
				symbol_types[flag] = dict[flag]
		else:
			if symbol_types[flag] != default_symbol_types[flag]:
				is_change = true
				symbol_types[flag] = default_symbol_types[flag]
	if is_change:
		symbol_changed.emit()


# *****************************************************************************
# private


func _on_program_objects_instantiated() -> void:
	for row in IVTableData.get_n_rows(&"visual_groups"):
		var body_flag := IVTableData.get_db_int(&"visual_groups", &"body_flag", row)
		var name_visible := IVTableData.get_db_bool(&"visual_groups", &"default_name_visible", row)
		var symbol_visible := IVTableData.get_db_bool(&"visual_groups", &"default_symbol_visible", row)
		var orbit_visible := IVTableData.get_db_bool(&"visual_groups", &"default_orbit_visible", row)
		var color := IVTableData.get_db_color(&"visual_groups", &"default_color", row)
		var symbol_type := IVTableData.get_db_int(&"visual_groups", &"symbol_type", row)

		all_flags |= body_flag
		if name_visible:
			default_name_visible_flags |= body_flag
		if symbol_visible:
			default_symbol_visible_flags |= body_flag
		if orbit_visible:
			default_orbit_visible_flags |= body_flag
		default_colors[body_flag] = color
		default_symbol_types[body_flag] = symbol_type

	_set_current_to_default()


func _set_current_to_default() -> void:
	set_default_visibilities()
	set_default_colors()
	set_default_symbols()


func _on_ui_dirty() -> void:
	visibility_changed.emit()
	color_changed.emit()
	symbol_changed.emit()
