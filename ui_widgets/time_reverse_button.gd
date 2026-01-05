# time_reverse_buttons.gd
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
class_name IVTimeReverseButton
extends Button

## Toggle button widget that sets reverse or forward time.
##
## Requires [IVSpeedManager]. Time reversal is disabled by default. Set
## [member IVCoreSettings.allow_time_reversal] = true to enable.
## This button is used by the Planetarium.[br][br]
##
## The widget has process_mode == PROCESS_MODE_ALWAYS so user can change time
## direction during pause.

@export var forward_text := "<"
@export var reverse_text := ">"
@export var forward_tooltip_text := "HINT_RUN_TIME_BACKWARDS"
@export var reverse_tooltip_text := "HINT_RESTORE_FORWARD_TIME"

var _speed_manager: IVSpeedManager


func _ready() -> void:
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _toggled(toggled_on: bool) -> void:
	if _speed_manager:
		_speed_manager.set_reversed_time(toggled_on)


func _configure_after_core_inited() -> void:
	_speed_manager = IVGlobal.program[&"SpeedManager"]
	_speed_manager.speed_changed.connect(_update_button) # signals on ui_dirty


func _update_button() -> void:
	var reversed_time := _speed_manager.get_reversed_time()
	set_pressed_no_signal(reversed_time)
	text = reverse_text if reversed_time else forward_text
	tooltip_text = reverse_tooltip_text if reversed_time else forward_tooltip_text
