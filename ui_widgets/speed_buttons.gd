# speed_buttons.gd
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
class_name IVSpeedButtons
extends BoxContainer

## BoxContainer widget with increase (+) and decrease (-) game speed buttons.
##
## Requires [IVSpeedManager]. The widget has process_mode == PROCESS_MODE_ALWAYS
## so user can set speed during pause.[br][br]
##
## You can add the [IVPauseButton] as an additional child if needed.

@export var increase_text := "+"
@export var decrease_text := "-"

var _speed_manager: IVSpeedManager

@onready var _plus: Button = $Plus
@onready var _minus: Button = $Minus


func _ready() -> void:
	_plus.text = increase_text
	_minus.text = decrease_text
	_plus.accessibility_name = _plus.tooltip_text # text is a symbol
	_minus.accessibility_name = _minus.tooltip_text
	if !accessibility_name:
		accessibility_name = &"CKBX_GAME_SPEED"
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	_speed_manager = IVGlobal.program[&"SpeedManager"]
	_speed_manager.speed_changed.connect(_update_buttons) # signals on ui_dirty
	_plus.pressed.connect(_speed_manager.increment_speed)
	_minus.pressed.connect(_speed_manager.decrement_speed)


## The current [member IVSpeedManager.speed_index], for an automation client.
func get_automation_value() -> int:
	return _speed_manager.speed_index if _speed_manager else 0


## The speed names, in [member IVSpeedManager.speed_index] order.
func get_automation_options() -> Array[String]:
	var names: Array[String] = []
	if _speed_manager:
		for speed_name in _speed_manager.speed_names:
			names.append(tr(speed_name))
	return names


## Sets the speed by its index in [method get_automation_options], as the buttons
## step through it. Returns false for an index out of range.
func set_automation_value(speed_index: int) -> bool:
	if !_speed_manager or speed_index < 0 or speed_index >= _speed_manager.speeds.size():
		return false
	_speed_manager.change_speed(speed_index)
	return true


func _update_buttons() -> void:
	_plus.disabled = not _speed_manager.can_increment_speed()
	_minus.disabled = not _speed_manager.can_decrement_speed()
