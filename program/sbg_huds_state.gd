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

## Maintains visibility and color state for [IVSmallBodiesGroup] HUDs.
##
## HUD Nodes must connect and set visibility and color on changed signals.

## Emitted whenever any entry of [member points_visibilities] changes.
signal points_visibility_changed()
## Emitted whenever any entry of [member orbits_visibilities] changes.
signal orbits_visibility_changed()
## Emitted whenever any entry of [member points_colors] changes.
signal points_color_changed()
## Emitted whenever any entry of [member orbits_colors] changes.
signal orbits_color_changed()


## Sentinel returned by [method get_consensus_points_color] /
## [method get_consensus_orbits_color] when the queried groups don't agree.
const NULL_COLOR := Color.BLACK

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"points_visibilities",
	&"orbits_visibilities",
	&"points_colors",
	&"orbits_colors",
]


# persisted - read-only!
## Indexed by [code]sbg_alias[/code]; missing keys mean false.
var points_visibilities: Dictionary[StringName, bool] = {} # indexed by sbg_alias; missing same as false
## Indexed by [code]sbg_alias[/code]; missing keys mean false.
var orbits_visibilities: Dictionary[StringName, bool] = {} # "
## Indexed by [code]sbg_alias[/code]; missing keys fall back to
## [member fallback_points_color].
var points_colors: Dictionary[StringName, Color] = {} # indexed by sbg_alias; missing same as fallback color
## Indexed by [code]sbg_alias[/code]; missing keys fall back to
## [member fallback_orbits_color].
var orbits_colors: Dictionary[StringName, Color] = {} # "

# project vars - set at project init
## Color used by [method get_points_color] when a group has no entry.
var fallback_points_color := Color(0.0, 0.6, 0.0)
## Color used by [method get_orbits_color] when a group has no entry.
var fallback_orbits_color := Color(0.8, 0.2, 0.2)
## Default value for [member points_visibilities]. Empty by default; can be
## populated by a project preinitializer.
var default_points_visibilities: Dictionary[StringName, bool] = {} # default is none, unless project changes
## Default value for [member orbits_visibilities].
var default_orbits_visibilities: Dictionary[StringName, bool] = {}

# imported from small_bodies_groups.tsv - ready-only!
## Default value for [member points_colors], populated from
## [code]small_bodies_groups.tsv[/code] (read-only).
var default_points_colors: Dictionary[StringName, Color] = {}
## Default value for [member orbits_colors], populated from
## [code]small_bodies_groups.tsv[/code] (read-only).
var default_orbits_colors: Dictionary[StringName, Color] = {}



func _init() -> void:
	IVStateManager.core_init_program_objects_instantiated.connect(_on_program_objects_instantiated)
	IVStateManager.simulator_exited.connect(_set_current_to_default)
	IVGlobal.ui_dirty.connect(_on_ui_dirty)



func _on_program_objects_instantiated() -> void:
	for row in IVTableData.get_n_rows(&"small_bodies_groups"):
		if IVTableData.get_db_bool(&"small_bodies_groups", &"skip", row):
			continue
		var sbg_alias := IVTableData.get_db_string_name(&"small_bodies_groups", &"sbg_alias", row)
		var points_color := IVTableData.get_db_color(&"small_bodies_groups", &"points_color", row)
		var orbits_color := IVTableData.get_db_color(&"small_bodies_groups", &"orbits_color", row)
		default_points_colors[sbg_alias] = points_color
		default_orbits_colors[sbg_alias] = orbits_color
	_set_current_to_default()


# visibility

func hide_all() -> void:
	for key: StringName in points_visibilities:
		points_visibilities[key] = false
	for key: StringName in orbits_visibilities:
		orbits_visibilities[key] = false
	points_visibility_changed.emit()
	orbits_visibility_changed.emit()


func set_default_visibilities() -> void:
	if points_visibilities != default_points_visibilities:
		points_visibilities.clear()
		points_visibilities.merge(default_points_visibilities)
		points_visibility_changed.emit()
	if orbits_visibilities != default_orbits_visibilities:
		orbits_visibilities.clear()
		orbits_visibilities.merge(default_orbits_visibilities)
		orbits_visibility_changed.emit()


func is_points_visible(group: StringName) -> bool:
	return points_visibilities.get(group, false)


func change_points_visibility(group: StringName, is_show: bool) -> void:
	points_visibilities[group] = is_show
	points_visibility_changed.emit()


func is_orbits_visible(group: StringName) -> bool:
	return orbits_visibilities.get(group, false)


func change_orbits_visibility(group: StringName, is_show: bool) -> void:
	orbits_visibilities[group] = is_show
	orbits_visibility_changed.emit()


func get_visible_points_groups() -> Array[StringName]:
	var array: Array[StringName] = []
	for key in points_visibilities:
		if points_visibilities[key]:
			array.append(key)
	return array


func get_visible_orbits_groups() -> Array[StringName]:
	var array: Array[StringName] = []
	for key in orbits_visibilities:
		if orbits_visibilities[key]:
			array.append(key)
	return array


func is_visible_points_groups(groups: Array[StringName], all := true) -> bool:
	if all:
		for group in groups:
			if not points_visibilities.get(group):
				return false
		return true
	for group in groups:
		if points_visibilities.get(group):
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


func set_visible_points_groups(groups: Array[StringName], is_show := true, hide_others := false
		) -> void:
	if hide_others:
		points_visibilities.clear()
	for key in groups:
		points_visibilities[key] = is_show
	points_visibility_changed.emit()


func set_visible_orbits_groups(groups: Array[StringName], is_show := true, hide_others := false
		) -> void:
	if hide_others:
		orbits_visibilities.clear()
	for key in groups:
		orbits_visibilities[key] = is_show
	orbits_visibility_changed.emit()


# color

func set_default_colors() -> void:
	# TEST34
	if points_colors != default_points_colors:
		points_colors.clear()
		points_colors.merge(default_points_colors)
		points_color_changed.emit()
	if orbits_colors != default_orbits_colors:
		orbits_colors.clear()
		orbits_colors.merge(default_orbits_colors)
		orbits_color_changed.emit()


func get_default_points_color(group: StringName) -> Color:
	if default_points_colors.has(group):
		return default_points_colors[group]
	return fallback_points_color


func get_default_orbits_color(group: StringName) -> Color:
	if default_orbits_colors.has(group):
		return default_orbits_colors[group]
	return fallback_orbits_color


func get_points_color(group: StringName) -> Color:
	if points_colors.has(group):
		return points_colors[group]
	return fallback_points_color


func get_orbits_color(group: StringName) -> Color:
	if orbits_colors.has(group):
		return orbits_colors[group]
	return fallback_orbits_color


func get_consensus_points_color(groups: Array[StringName], is_default := false) -> Color:
	var has_theme_color := false
	var consensus_color := NULL_COLOR
	for group in groups:
		var color := get_default_points_color(group) if is_default else get_points_color(group)
		if !has_theme_color:
			has_theme_color = true
			consensus_color = color
		elif color != consensus_color:
			return NULL_COLOR
	return consensus_color


func get_consensus_orbits_color(groups: Array[StringName], is_default := false) -> Color:
	var has_theme_color := false
	var consensus_color := NULL_COLOR
	for group in groups:
		var color := get_default_orbits_color(group) if is_default else get_orbits_color(group)
		if !has_theme_color:
			has_theme_color = true
			consensus_color = color
		elif color != consensus_color:
			return NULL_COLOR
	return consensus_color


func set_points_color(group: StringName, color: Color) -> void:
	if points_colors.has(group):
		if color == points_colors[group]:
			return
	elif color == fallback_points_color:
		return
	points_colors[group] = color
	points_color_changed.emit()


func set_orbits_color(group: StringName, color: Color) -> void:
	if orbits_colors.has(group):
		if color == orbits_colors[group]:
			return
	elif color == fallback_orbits_color:
		return
	orbits_colors[group] = color
	orbits_color_changed.emit()


## Returns a dictionary of only those entries from [member points_colors] that
## differ from [member default_points_colors].
func get_non_default_points_colors() -> Dictionary[StringName, Color]:
	# key-values equal to default are skipped
	var dict: Dictionary[StringName, Color] = {}
	for key: StringName in points_colors:
		if points_colors[key] != default_points_colors[key]:
			dict[key] = points_colors[key]
	return dict


## Returns a dictionary of only those entries from [member orbits_colors] that
## differ from [member default_orbits_colors].
func get_non_default_orbits_colors() -> Dictionary[StringName, Color]:
	# key-values equal to default are skipped
	var dict: Dictionary[StringName, Color] = {}
	for key: StringName in orbits_colors:
		if orbits_colors[key] != default_orbits_colors[key]:
			dict[key] = orbits_colors[key]
	return dict


## Bulk-applies [param dict] to [member points_colors]. Any group not present
## in [param dict] is reset to its default color.
func set_all_points_colors(dict: Dictionary[StringName, Color]) -> void:
	# missing key-values are set to default
	var is_change := false
	for key: StringName in points_colors:
		if dict.has(key):
			if points_colors[key] != dict[key]:
				is_change = true
				points_colors[key] = dict[key]
		else:
			if points_colors[key] != default_points_colors[key]:
				is_change = true
				points_colors[key] = default_points_colors[key]
	if is_change:
		points_color_changed.emit()


## Bulk-applies [param dict] to [member orbits_colors]. Any group not present
## in [param dict] is reset to its default color.
func set_all_orbits_colors(dict: Dictionary[StringName, Color]) -> void:
	# missing key-values are set to default
	var is_change := false
	for key: StringName in orbits_colors:
		if dict.has(key):
			if orbits_colors[key] != dict[key]:
				is_change = true
				orbits_colors[key] = dict[key]
		else:
			if orbits_colors[key] != default_orbits_colors[key]:
				is_change = true
				orbits_colors[key] = default_orbits_colors[key]
	if is_change:
		orbits_color_changed.emit()


# private

func _set_current_to_default() -> void:
	set_default_visibilities()
	set_default_colors()


func _on_ui_dirty() -> void:
	points_visibility_changed.emit()
	orbits_visibility_changed.emit()
	points_color_changed.emit()
	orbits_color_changed.emit()
