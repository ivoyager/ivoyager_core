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
extends BoxContainer

## BoxContainer widget with increase (+) and decrease (-) game speed buttons.
##
## Requires [IVTimekeeper]. The widget has process_mode == PROCESS_MODE_ALWAYS
## so user can set speed during pause.[br][br]
##
## You can add the [IVPauseButton] as an additional child if needed.

@export var increase_text := "+"
@export var decrease_text := "-"

var _timekeeper: IVTimekeeper

@onready var _plus: Button = $Plus
@onready var _minus: Button = $Minus


func _ready() -> void:
	_plus.text = increase_text
	_minus.text = decrease_text
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	_timekeeper = IVGlobal.program[&"Timekeeper"]
	_timekeeper.speed_changed.connect(_update_buttons) # signals on ui_dirty
	_plus.pressed.connect(_timekeeper.increment_speed)
	_minus.pressed.connect(_timekeeper.decrement_speed)


func _update_buttons() -> void:
	_plus.disabled = not _timekeeper.can_increment_speed()
	_minus.disabled = not _timekeeper.can_decrement_speed()
