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
## Shows the symbol-atlas shapes in a grid (shape count and grid width both from
## [IVCoreSettings]). For SBGs an additional "point" toggle button selects the
## plain-point display (symbol -1),
## mutually exclusive with the shapes. Created and driven by [IVSymbolPickerButton];
## emits [signal symbol_selected] on a user pick.

## Emitted when the user picks a symbol (a symbol-atlas index, or -1
## for "point").
signal symbol_selected(symbol_type: int)

const BUTTON_SIZE := 34

var _button_group := ButtonGroup.new()
var _symbol_buttons: Array[Button] = []
var _point_button: Button
var _n_symbols: int # symbol_atlas_columns * symbol_atlas_rows; set in build()


## Builds the grid; include a "Point" checkbox if [param include_point] (SBGs only).
func build(include_point: bool) -> void:
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	_n_symbols = IVCoreSettings.symbol_atlas_columns * IVCoreSettings.symbol_atlas_rows
	var vbox := VBoxContainer.new()
	add_child(vbox)
	var grid := GridContainer.new()
	grid.columns = IVCoreSettings.symbol_atlas_columns
	vbox.add_child(grid)
	_symbol_buttons.resize(_n_symbols)
	for i in _n_symbols:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _button_group
		button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		button.expand_icon = true
		button.icon = asset_preloader.get_symbol_texture(i)
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
	elif symbol_type >= 0 and symbol_type < _n_symbols:
		_symbol_buttons[symbol_type].set_pressed_no_signal(true)


func _on_symbol_pressed(symbol_type: int) -> void:
	symbol_selected.emit(symbol_type)
	hide()


func _on_point_pressed() -> void:
	symbol_selected.emit(-1)
	hide()
