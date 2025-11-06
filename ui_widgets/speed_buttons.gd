# speed_buttons.gd
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
class_name IVSpeedButtons
extends HBoxContainer

## HBoxContainer widget with game speed controls.
##
## Requires [IVTimekeeper].

const IS_CLIENT := IVGlobal.NetworkState.IS_CLIENT


## Display pause button: "||". This will be removed regardless of this setting
## if [IVCoreSettings.disable_pause] == true.
@export var pause_button := true
## Display reverse button: "<". This will be removed regardless of this setting
## if [IVCoreSettings.allow_time_reversal] == false (default).
@export var reverse_button := false


var _timekeeper: IVTimekeeper

@onready var _minus: Button = $Minus
@onready var _plus: Button = $Plus
@onready var _pause: Button = $Pause
@onready var _reverse: Button = $Reverse


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	IVGlobal.update_gui_requested.connect(_update_buttons)
	IVGlobal.user_pause_changed.connect(_update_buttons)
	_minus.pressed.connect(_increment_speed.bind(-1))
	_plus.pressed.connect(_increment_speed.bind(1))
	if pause_button and !IVCoreSettings.disable_pause:
		_pause.pressed.connect(_change_paused)
	else:
		_pause.queue_free()
		_pause = null
	if reverse_button and IVCoreSettings.allow_time_reversal:
		_reverse.pressed.connect(_change_reversed)
	else:
		_reverse.queue_free()
		_reverse = null
	if IVStateManager.is_core_inited:
		_configure_after_core_inited()
	else:
		IVGlobal.core_inited.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	_timekeeper = IVGlobal.program[&"Timekeeper"]
	_timekeeper.speed_changed.connect(_update_buttons)
	_update_buttons()


func _increment_speed(increment: int) -> void:
	_timekeeper.change_speed(increment)


func _change_paused() -> void:
	IVStateManager.change_pause(false, _pause.button_pressed)


func _change_reversed() -> void:
	_timekeeper.set_time_reversed(_reverse.button_pressed)


func _update_buttons(_dummy := false) -> void:
	if IVStateManager.network_state == IS_CLIENT:
		if _pause:
			_pause.disabled = true
		if _reverse:
			_reverse.disabled = true
		_plus.disabled = true
		_minus.disabled = true
		return
	if _pause:
		_pause.disabled = false
		_pause.button_pressed = IVStateManager.is_user_paused
	if _reverse:
		_reverse.disabled = false
		_reverse.button_pressed = _timekeeper.is_reversed
	_plus.disabled = !_timekeeper.can_increment_speed()
	_minus.disabled = !_timekeeper.can_decrement_speed()
