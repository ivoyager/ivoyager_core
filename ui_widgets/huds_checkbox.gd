# huds_checkbox.gd
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
class_name IVHUDsCheckBox
extends CheckBox

## A CheckBox widget that toggles an HUD element (symbol, name or orbit) for a
## class of [IVBody] or [IVSmallBodiesGroup]
##
## Specify either [member body_flags] or [sbg_aliases], not both. For bodies,
## [member hud_type] may be SYMBOLS, NAMES or ORBITS. For SBGs, it may be SYMBOLS
## or ORBITS (SYMBOLS toggles the group's point/shape display).[br][br]

enum HUDsType {SYMBOLS, NAMES, ORBITS}

const SCENE := "res://addons/ivoyager_core/ui_widgets/huds_checkbox.tscn"

## For bodies, one of SYMBOLS, NAMES or ORBITS. For SBGs, SYMBOLS or ORBITS.
@export var hud_type: HUDsType
## Specify a class of body by [enum IVBody.BodyFlags]. In most cases this should
## be one of the exclusive flags defined in data table "visual_groups.tsv"
## field "body_flags" (only these have default colors and visibilities).
@export var body_flags: int
## Specify a class of small bodies by listing aliases matching
## [member IVSmallBodiesGroup.sbg_alias] (e.g., ["JT4", "JT5"] for both Trojan
## groups).
@export var sbg_aliases: Array[StringName]


var _on_action: Callable
var _off_action: Callable
var _is_visible_test: Callable


## Creates a new [IVHUDsCheckBox] instance using specified parameters.
@warning_ignore("shadowed_variable")
static func create(hud_type: HUDsType, body_flags: int, sbg_aliases: Array[StringName] = []
		) -> IVHUDsCheckBox:
	assert((!body_flags) != (!sbg_aliases), "Set either 'body_flags' or 'sbg_aliases', not both")
	assert(!sbg_aliases or hud_type != HUDsType.NAMES, "SBGs have no NAMES HUD")
	var ckbx: IVHUDsCheckBox = (load(SCENE) as PackedScene).instantiate()
	ckbx.hud_type = hud_type
	ckbx.body_flags = body_flags
	ckbx.sbg_aliases = sbg_aliases
	return ckbx


func _ready() -> void:
	assert((!body_flags) != (!sbg_aliases), "Set either 'body_flags' or 'sbg_aliases', not both")
	assert(!sbg_aliases or hud_type != HUDsType.NAMES, "SBGs have no NAMES HUD")
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	toggled.connect(_on_toggled)
	if body_flags:
		_configure_bodies()
	else:
		_configure_sbgs()


func _configure_bodies() -> void:
	var body_huds_state: IVBodyHUDsState = IVGlobal.program[&"BodyHUDsState"]
	body_huds_state.visibility_changed.connect(_on_state_changed)
	match hud_type:
		HUDsType.NAMES:
			_on_action = body_huds_state.set_name_visibility.bind(body_flags, true)
			_off_action = body_huds_state.set_name_visibility.bind(body_flags, false)
			_is_visible_test = body_huds_state.is_name_visible.bind(body_flags, true)
		HUDsType.SYMBOLS:
			_on_action = body_huds_state.set_symbol_visibility.bind(body_flags, true)
			_off_action = body_huds_state.set_symbol_visibility.bind(body_flags, false)
			_is_visible_test = body_huds_state.is_symbol_visible.bind(body_flags, true)
		HUDsType.ORBITS:
			_on_action = body_huds_state.set_orbit_visibility.bind(body_flags, true)
			_off_action = body_huds_state.set_orbit_visibility.bind(body_flags, false)
			_is_visible_test = body_huds_state.is_orbit_visible.bind(body_flags, true)


func _configure_sbgs() -> void:
	var sbg_huds_state: IVSBGHUDsState = IVGlobal.program[&"SBGHUDsState"]
	if hud_type == HUDsType.SYMBOLS:
		sbg_huds_state.symbols_visibility_changed.connect(_on_state_changed)
		_on_action = sbg_huds_state.set_visible_symbols_groups.bind(sbg_aliases, true)
		_off_action = sbg_huds_state.set_visible_symbols_groups.bind(sbg_aliases, false)
		_is_visible_test = sbg_huds_state.is_visible_symbols_groups.bind(sbg_aliases)
	else:
		sbg_huds_state.orbits_visibility_changed.connect(_on_state_changed)
		_on_action = sbg_huds_state.set_visible_orbits_groups.bind(sbg_aliases, true)
		_off_action = sbg_huds_state.set_visible_orbits_groups.bind(sbg_aliases, false)
		_is_visible_test = sbg_huds_state.is_visible_orbits_groups.bind(sbg_aliases)


func _on_toggled(toggled_on: bool) -> void:
	if toggled_on:
		_on_action.call()
	else:
		_off_action.call()


func _on_state_changed() -> void:
	var class_is_visible: bool = _is_visible_test.call()
	set_pressed_no_signal(class_is_visible)
