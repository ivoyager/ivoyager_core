# sbg_huds_state.gd
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
class_name IVSBGHUDsState
extends Node

## Maintains visibility, color and symbol state for [IVSmallBodiesGroup] HUDs.
##
## HUD Nodes must connect and set state on changed signals. A group's single
## [member colors] entry is shared by its symbol points and its orbits. The
## symbol shape is a per-group symbol-atlas index in
## [member symbol_types], or -1 for a plain point (the default).

## Emitted whenever any entry of [member symbols_visibilities] changes.
signal symbols_visibility_changed()
## Emitted whenever any entry of [member orbits_visibilities] changes.
signal orbits_visibility_changed()
## Emitted whenever any entry of [member colors] changes.
signal color_changed()
## Emitted whenever any entry of [member symbol_types] changes.
signal symbol_changed()


## Sentinel returned by [method get_consensus_color] when the queried groups
## don't agree.
const NULL_COLOR := Color.BLACK
## Sentinel returned by [method get_consensus_symbol_type] when the queried
## groups don't agree.
const NULL_SYMBOL := -2

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"symbols_visibilities",
	&"orbits_visibilities",
	&"colors",
	&"symbol_types",
]


# persisted - read-only!
## Indexed by [code]sbg_alias[/code]; missing keys mean false.
var symbols_visibilities: Dictionary[StringName, bool] = {} # indexed by sbg_alias; missing same as false
## Indexed by [code]sbg_alias[/code]; missing keys mean false.
var orbits_visibilities: Dictionary[StringName, bool] = {} # "
## Indexed by [code]sbg_alias[/code], shared by symbol points and orbits; missing
## keys fall back to [member fallback_color].
var colors: Dictionary[StringName, Color] = {} # indexed by sbg_alias; missing same as fallback color
## Per-group symbol shape (a symbol-atlas index, or -1 for a plain point).
## Indexed by [code]sbg_alias[/code]; missing keys fall back to
## [member fallback_symbol_type].
var symbol_types: Dictionary[StringName, int] = {} # indexed by sbg_alias; missing same as fallback

# project vars - set at project init
## Color used by [method get_color] when a group has no entry.
var fallback_color := Color(0.0, 0.6, 0.0)
## Symbol used by [method get_symbol_type] when a group has no entry (-1 = point).
var fallback_symbol_type := -1
## Default value for [member symbols_visibilities]. Empty by default; can be
## populated by a project preinitializer.
var default_symbols_visibilities: Dictionary[StringName, bool] = {} # default is none, unless project changes
## Default value for [member orbits_visibilities].
var default_orbits_visibilities: Dictionary[StringName, bool] = {}

# imported from small_bodies_groups.tsv - ready-only!
## Default value for [member colors], populated from
## [code]small_bodies_groups.tsv[/code] (read-only).
var default_colors: Dictionary[StringName, Color] = {}
## Default value for [member symbol_types], populated from
## [code]small_bodies_groups.tsv[/code] (read-only).
var default_symbol_types: Dictionary[StringName, int] = {}



func _init() -> void:
	IVStateManager.core_init_program_objects_instantiated.connect(_on_program_objects_instantiated)
	IVStateManager.simulator_exited.connect(_set_current_to_default)
	IVGlobal.ui_dirty.connect(_on_ui_dirty)



func _on_program_objects_instantiated() -> void:
	for row in IVTableData.get_n_rows(&"small_bodies_groups"):
		if IVTableData.get_db_bool(&"small_bodies_groups", &"skip", row):
			continue
		var sbg_alias := IVTableData.get_db_string_name(&"small_bodies_groups", &"sbg_alias", row)
		var color := IVTableData.get_db_color(&"small_bodies_groups", &"color", row)
		var symbol_type := IVTableData.get_db_int(&"small_bodies_groups", &"symbol_type", row)
		default_colors[sbg_alias] = color
		default_symbol_types[sbg_alias] = symbol_type
	_set_current_to_default()


# visibility

func hide_all() -> void:
	for key: StringName in symbols_visibilities:
		symbols_visibilities[key] = false
	for key: StringName in orbits_visibilities:
		orbits_visibilities[key] = false
	symbols_visibility_changed.emit()
	orbits_visibility_changed.emit()


func set_default_visibilities() -> void:
	if symbols_visibilities != default_symbols_visibilities:
		symbols_visibilities.clear()
		symbols_visibilities.merge(default_symbols_visibilities)
		symbols_visibility_changed.emit()
	if orbits_visibilities != default_orbits_visibilities:
		orbits_visibilities.clear()
		orbits_visibilities.merge(default_orbits_visibilities)
		orbits_visibility_changed.emit()


func is_symbols_visible(group: StringName) -> bool:
	return symbols_visibilities.get(group, false)


func change_symbols_visibility(group: StringName, is_show: bool) -> void:
	symbols_visibilities[group] = is_show
	symbols_visibility_changed.emit()


func is_orbits_visible(group: StringName) -> bool:
	return orbits_visibilities.get(group, false)


func change_orbits_visibility(group: StringName, is_show: bool) -> void:
	orbits_visibilities[group] = is_show
	orbits_visibility_changed.emit()


func get_visible_symbols_groups() -> Array[StringName]:
	var array: Array[StringName] = []
	for key in symbols_visibilities:
		if symbols_visibilities[key]:
			array.append(key)
	return array


func get_visible_orbits_groups() -> Array[StringName]:
	var array: Array[StringName] = []
	for key in orbits_visibilities:
		if orbits_visibilities[key]:
			array.append(key)
	return array


func is_visible_symbols_groups(groups: Array[StringName], all := true) -> bool:
	if all:
		for group in groups:
			if not symbols_visibilities.get(group):
				return false
		return true
	for group in groups:
		if symbols_visibilities.get(group):
			return true
	return false


func is_visible_orbits_groups(groups: Array[StringName], all := true) -> bool:
	if all:
		for group in groups:
			if not orbits_visibilities.get(group):
				return false
		return true
	for group in groups:
		if orbits_visibilities.get(group):
			return true
	return false


func set_visible_symbols_groups(groups: Array[StringName], is_show := true, hide_others := false
		) -> void:
	if hide_others:
		symbols_visibilities.clear()
	for key in groups:
		symbols_visibilities[key] = is_show
	symbols_visibility_changed.emit()


func set_visible_orbits_groups(groups: Array[StringName], is_show := true, hide_others := false
		) -> void:
	if hide_others:
		orbits_visibilities.clear()
	for key in groups:
		orbits_visibilities[key] = is_show
	orbits_visibility_changed.emit()


# color (shared by symbol points and orbits)

func set_default_colors() -> void:
	if colors != default_colors:
		colors.clear()
		colors.merge(default_colors)
		color_changed.emit()


func get_default_color(group: StringName) -> Color:
	if default_colors.has(group):
		return default_colors[group]
	return fallback_color


func get_color(group: StringName) -> Color:
	if colors.has(group):
		return colors[group]
	return fallback_color


func get_consensus_color(groups: Array[StringName], is_default := false) -> Color:
	var has_theme_color := false
	var consensus_color := NULL_COLOR
	for group in groups:
		var color := get_default_color(group) if is_default else get_color(group)
		if !has_theme_color:
			has_theme_color = true
			consensus_color = color
		elif color != consensus_color:
			return NULL_COLOR
	return consensus_color


func set_color(group: StringName, color: Color) -> void:
	if colors.has(group):
		if color == colors[group]:
			return
	elif color == fallback_color:
		return
	colors[group] = color
	color_changed.emit()


## Returns a dictionary of only those entries from [member colors] that differ
## from [member default_colors].
func get_non_default_colors() -> Dictionary[StringName, Color]:
	# key-values equal to default are skipped
	var dict: Dictionary[StringName, Color] = {}
	for key: StringName in colors:
		if colors[key] != default_colors[key]:
			dict[key] = colors[key]
	return dict


## Bulk-applies [param dict] to [member colors]. Any group not present in
## [param dict] is reset to its default color.
func set_all_colors(dict: Dictionary[StringName, Color]) -> void:
	# missing key-values are set to default
	var is_change := false
	for key: StringName in colors:
		if dict.has(key):
			if colors[key] != dict[key]:
				is_change = true
				colors[key] = dict[key]
		else:
			if colors[key] != default_colors[key]:
				is_change = true
				colors[key] = default_colors[key]
	if is_change:
		color_changed.emit()


# symbol

func set_default_symbols() -> void:
	if symbol_types != default_symbol_types:
		symbol_types.clear()
		symbol_types.merge(default_symbol_types)
		symbol_changed.emit()


func get_default_symbol_type(group: StringName) -> int:
	if default_symbol_types.has(group):
		return default_symbol_types[group]
	return fallback_symbol_type


func get_symbol_type(group: StringName) -> int:
	if symbol_types.has(group):
		return symbol_types[group]
	return fallback_symbol_type


func get_consensus_symbol_type(groups: Array[StringName], is_default := false) -> int:
	var has_first := false
	var consensus_symbol := NULL_SYMBOL
	for group in groups:
		var symbol := get_default_symbol_type(group) if is_default else get_symbol_type(group)
		if !has_first:
			has_first = true
			consensus_symbol = symbol
		elif symbol != consensus_symbol:
			return NULL_SYMBOL
	return consensus_symbol


func set_symbol_type(group: StringName, symbol: int) -> void:
	if symbol_types.has(group):
		if symbol == symbol_types[group]:
			return
	elif symbol == fallback_symbol_type:
		return
	symbol_types[group] = symbol
	symbol_changed.emit()


## Returns a dictionary of only those entries from [member symbol_types] that
## differ from [member default_symbol_types].
func get_non_default_symbol_types() -> Dictionary[StringName, int]:
	# key-values equal to default are skipped
	var dict: Dictionary[StringName, int] = {}
	for key: StringName in symbol_types:
		if symbol_types[key] != default_symbol_types[key]:
			dict[key] = symbol_types[key]
	return dict


## Bulk-applies [param dict] to [member symbol_types]. Any group not present in
## [param dict] is reset to its default symbol.
func set_all_symbol_types(dict: Dictionary[StringName, int]) -> void:
	# missing key-values are set to default
	var is_change := false
	for key: StringName in symbol_types:
		if dict.has(key):
			if symbol_types[key] != dict[key]:
				is_change = true
				symbol_types[key] = dict[key]
		else:
			if symbol_types[key] != default_symbol_types[key]:
				is_change = true
				symbol_types[key] = default_symbol_types[key]
	if is_change:
		symbol_changed.emit()


# private

func _set_current_to_default() -> void:
	set_default_visibilities()
	set_default_colors()
	set_default_symbols()


func _on_ui_dirty() -> void:
	symbols_visibility_changed.emit()
	orbits_visibility_changed.emit()
	color_changed.emit()
	symbol_changed.emit()
