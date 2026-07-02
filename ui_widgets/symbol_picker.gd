# symbol_picker.gd
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
class_name IVSymbolPicker
extends PopupPanel

## Popup grid for choosing a position symbol, analogous to Godot's [ColorPicker].
##
## Shows the 12 [enum IVGlobal.Symbols] shapes in a 3-column grid. For SBGs an
## additional "point" toggle button selects the plain-point display (symbol -1),
## mutually exclusive with the shapes. Created and driven by [IVSymbolPickerButton];
## emits [signal symbol_selected] on a user pick.

## Emitted when the user picks a symbol (an [enum IVGlobal.Symbols] value, or -1
## for "point").
signal symbol_selected(symbol_type: int)

const N_SYMBOLS := 12
const GRID_COLS := 3
const BUTTON_SIZE := 34

var _button_group := ButtonGroup.new()
var _symbol_buttons: Array[Button] = []
var _point_button: Button


## Builds the grid; include a "Point" checkbox if [param include_point] (SBGs only).
func build(include_point: bool) -> void:
	var vbox := VBoxContainer.new()
	add_child(vbox)
	var grid := GridContainer.new()
	grid.columns = GRID_COLS
	vbox.add_child(grid)
	_symbol_buttons.resize(N_SYMBOLS)
	for i in N_SYMBOLS:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _button_group
		button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		button.expand_icon = true
		button.icon = IVSymbolTextures.get_atlas_texture(i)
		button.pressed.connect(_on_symbol_pressed.bind(i))
		grid.add_child(button)
		_symbol_buttons[i] = button
	if include_point:
		_point_button = Button.new()
		_point_button.toggle_mode = true
		_point_button.text = "• (point)" # U+2022 dot + label
		_point_button.button_group = _button_group
		_point_button.pressed.connect(_on_point_pressed)
		vbox.add_child(_point_button)


## Reflects the current [param symbol_type] in the grid (-1 = point). A
## [constant IVSBGHUDsState.NULL_SYMBOL] leaves nothing selected.
func set_current(symbol_type: int) -> void:
	for button in _symbol_buttons:
		button.set_pressed_no_signal(false)
	if _point_button:
		_point_button.set_pressed_no_signal(false)
	if symbol_type == -1:
		if _point_button:
			_point_button.set_pressed_no_signal(true)
	elif symbol_type >= 0 and symbol_type < N_SYMBOLS:
		_symbol_buttons[symbol_type].set_pressed_no_signal(true)


func _on_symbol_pressed(symbol_type: int) -> void:
	symbol_selected.emit(symbol_type)
	hide()


func _on_point_pressed() -> void:
	symbol_selected.emit(-1)
	hide()
