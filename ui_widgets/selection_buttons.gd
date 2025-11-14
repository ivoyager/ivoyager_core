# selection_buttons.gd
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
class_name IVSelectionButtons
extends HBoxContainer

## HBoxContainer widget with back, forward and up buttons for user selection.
##
## Expects an ancestor Control with property [param selection_manager] set
## before [signal IVStateManager.system_tree_ready].

var _selection_manager: IVSelectionManager

@onready var _back_buttion: Button = $Back
@onready var _forward_buttion: Button = $Forward
@onready var _up_buttion: Button = $Up


func _ready() -> void:
	_back_buttion.pressed.connect(_back)
	_forward_buttion.pressed.connect(_forward)
	_up_buttion.pressed.connect(_up)
	IVWidgets.connect_selection_manager(self, &"_on_selection_manager_changed",
			[&"selection_changed", &"_update_buttons"])


func _on_selection_manager_changed(selection_manager: IVSelectionManager) -> void:
	_selection_manager = selection_manager
	if _selection_manager:
		_update_buttons()


func _back() -> void:
	if _selection_manager:
		_selection_manager.back()


func _forward() -> void:
	if _selection_manager:
		_selection_manager.forward()


func _up() -> void:
	if _selection_manager:
		_selection_manager.up()


func _update_buttons(_dummy := false) -> void:
	_back_buttion.disabled = !_selection_manager.can_go_back()
	_forward_buttion.disabled = !_selection_manager.can_go_forward()
	_up_buttion.disabled = !_selection_manager.can_go_up()
