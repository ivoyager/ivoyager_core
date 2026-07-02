# symbol_picker_button.gd
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
class_name IVSymbolPickerButton
extends Button

## A Button that displays a class's current position symbol and opens an
## [IVSymbolPicker] to change it, analogous to Godot's [ColorPickerButton].
##
## Sets the shared symbol of a class of [IVBody] or [IVSmallBodiesGroup] (specify
## either [member body_flags] or [member sbg_aliases], not both). Bodies never
## show the "point" option; SBGs do.[br][br]

@export var popup_corner := Corner.CORNER_TOP_RIGHT
## Specify a class of body by [enum IVBody.BodyFlags] (an exclusive flag from
## "visual_groups.tsv"). If not 0, [member sbg_aliases] must be empty.
@export var body_flags := 0
## Specify a class of small bodies by [member IVSmallBodiesGroup.sbg_alias]
## aliases. If not empty, [member body_flags] must be 0.
@export var sbg_aliases: Array[StringName] = []

var _picker: IVSymbolPicker
var _body_huds_state: IVBodyHUDsState
var _sbg_huds_state: IVSBGHUDsState
var _current_symbol_test: Callable


## Creates a new [IVSymbolPickerButton] instance using specified parameters.
@warning_ignore("shadowed_variable")
static func create(body_flags: int, sbg_aliases: Array[StringName] = []) -> IVSymbolPickerButton:
	assert((!body_flags) != (!sbg_aliases), "Set either 'body_flags' or 'sbg_aliases', not both")
	var button := IVSymbolPickerButton.new()
	button.body_flags = body_flags
	button.sbg_aliases = sbg_aliases
	return button


func _ready() -> void:
	custom_minimum_size = Vector2(22, 22)
	toggle_mode = true
	action_mode = ACTION_MODE_BUTTON_PRESS # needed for the popup reclick close
	expand_icon = true
	_picker = IVSymbolPicker.new()
	add_child(_picker)
	_picker.symbol_selected.connect(_on_symbol_selected)
	_picker.visibility_changed.connect(_on_picker_visibility_changed)
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	toggled.connect(_on_toggled)
	if body_flags:
		_body_huds_state = IVGlobal.program[&"BodyHUDsState"]
		_body_huds_state.symbol_changed.connect(_update_icon)
		_current_symbol_test = _body_huds_state.get_symbol_type.bind(body_flags)
		_picker.build(false) # bodies have no "point" option
	else:
		_sbg_huds_state = IVGlobal.program[&"SBGHUDsState"]
		_sbg_huds_state.symbol_changed.connect(_update_icon)
		_current_symbol_test = _sbg_huds_state.get_consensus_symbol_type.bind(sbg_aliases)
		_picker.build(true)
	_update_icon()


func _on_toggled(toggle_pressed: bool) -> void:
	if toggle_pressed:
		var symbol_type: int = _current_symbol_test.call()
		_picker.set_current(symbol_type)
		_picker.popup()
		IVWidgets.position_popup_at_corner.call_deferred(_picker, self, popup_corner)
	else:
		_picker.hide()


func _on_symbol_selected(symbol_type: int) -> void:
	if body_flags:
		_body_huds_state.set_symbol_type(body_flags, symbol_type)
	else:
		for alias in sbg_aliases:
			_sbg_huds_state.set_symbol_type(alias, symbol_type)
	button_pressed = false


func _on_picker_visibility_changed() -> void:
	await get_tree().process_frame
	if !_picker.visible:
		button_pressed = false


func _update_icon() -> void:
	var symbol_type: int = _current_symbol_test.call()
	# Always icon-based so the button height stays constant between point and shape.
	if symbol_type == -1:
		icon = IVSymbolTextures.get_point_texture()
	elif symbol_type >= 0:
		icon = IVSymbolTextures.get_atlas_texture(symbol_type)
	else:
		icon = null # NULL_SYMBOL (mixed group)
