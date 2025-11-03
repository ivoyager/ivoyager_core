# huds_color_picker_button.gd
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
class_name IVHUDsColorPickerButton
extends ColorPickerButton

## A ColorPickerButton widget for setting color of an HUD element (points or
## orbits) for a class of [IVBody] or [IVSmallBodiesGroup]
##
## Specify either [member body_flags] or [sbg_aliases], not both. For bodies,
## [member hud_type] can only be ORBITS. For SBGs, it can be POINTS or ORBITS.[br][br]

enum ColorHUDsType {POINTS, ORBITS}

const SCENE := "res://addons/ivoyager_core/ui_widgets/huds_color_picker_button.tscn"
const NULL_COLOR := Color.BLACK


## For bodies, must be ORBITS. For SBGs, can be POINTS or ORBITS.
@export var hud_type: ColorHUDsType
## Specify a class of body by [enum IVBody.BodyFlags]. In most cases this should
## be one of the exclusive flags defined in data table "visual_groups.tsv"
## field "body_flags" (only these have default colors and visibilities).
@export var body_flags: int
## Specify a class of small bodies by listing aliases matching
## [member IVSmallBodiesGroup.sbg_alias] (e.g., ["JT4", "JT5"] for both Trojan
## groups).
@export var sbg_aliases: Array[StringName]

var _body_huds_state: IVBodyHUDsState
var _sbg_huds_state: IVSBGHUDsState
var _current_color_test: Callable
var _suppress_state_update := false


@warning_ignore("shadowed_variable")
static func create(hud_type: ColorHUDsType, body_flags: int, sbg_aliases: Array[StringName] = []
		) -> IVHUDsColorPickerButton:
	assert((!body_flags) != (!sbg_aliases), "Set either 'body_flags' or 'sbg_aliases', not both")
	assert(!body_flags or hud_type == ColorHUDsType.ORBITS,
			"Bodies HUD must be ORBITS")
	var button: IVHUDsColorPickerButton = (load(SCENE) as PackedScene).instantiate()
	button.hud_type = hud_type
	button.body_flags = body_flags
	button.sbg_aliases = sbg_aliases
	return button


func _ready() -> void:
	if IVStateManager.is_core_inited:
		_configure_for_core()
	else:
		IVGlobal.core_inited.connect(_configure_for_core, CONNECT_ONE_SHOT)


func _configure_for_core() -> void:
	color_changed.connect(_on_color_changed)
	toggled.connect(_hack_fix_toggle_off)
	if body_flags:
		_configure_bodies()
	else:
		_configure_sbgs()


func _configure_bodies() -> void:
	_body_huds_state = IVGlobal.program[&"BodyHUDsState"]
	_body_huds_state.color_changed.connect(_on_state_changed)
	_current_color_test = _body_huds_state.get_orbit_color.bind(body_flags)
	var default_color := _body_huds_state.get_default_orbit_color(body_flags)
	if default_color != NULL_COLOR:
		get_picker().add_preset(default_color)
		# Godot ISSUE: As of 4.5.1, add_preset() adds to ALL ColorPickers,
		# contrary to docs. (But the ColorPickers are unique objects.)


func _configure_sbgs() -> void:
	_sbg_huds_state = IVGlobal.program[&"SBGHUDsState"]
	if hud_type == ColorHUDsType.POINTS:
		_sbg_huds_state.points_color_changed.connect(_on_state_changed)
		_current_color_test = _sbg_huds_state.get_consensus_points_color.bind(sbg_aliases)
		var default_color := _sbg_huds_state.get_consensus_points_color(sbg_aliases, true)
		if default_color != NULL_COLOR:
			get_picker().add_preset(default_color)
	else:
		_sbg_huds_state.orbits_color_changed.connect(_on_state_changed)
		_current_color_test = _sbg_huds_state.get_consensus_orbits_color.bind(sbg_aliases)
		var default_color := _sbg_huds_state.get_consensus_orbits_color(sbg_aliases, true)
		if default_color != NULL_COLOR:
			get_picker().add_preset(default_color)


func _on_color_changed(picker_color: Color) -> void:
	if picker_color == NULL_COLOR:
		return
	_suppress_state_update = true
	if body_flags:
		_body_huds_state.set_orbit_color(body_flags, picker_color)
	elif hud_type == ColorHUDsType.POINTS:
		for alias in sbg_aliases:
			_sbg_huds_state.set_points_color(alias, picker_color)
	else:
		for alias in sbg_aliases:
			_sbg_huds_state.set_orbits_color(alias, picker_color)
	_suppress_state_update = false


func _on_state_changed() -> void:
	if _suppress_state_update:
		return
	var class_color: Color = _current_color_test.call()
	color = class_color


func _hack_fix_toggle_off(button_is_pressed: bool) -> void:
	# Hack fix to let popup close when user reclicks the button.
	# Requres action_mode = ACTION_MODE_BUTTON_PRESS
	if !button_is_pressed:
		await get_tree().process_frame
		get_popup().hide()
