# now_ckbx.gd
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
class_name IVNowCkbx
extends CheckBox

## UI widget.
##
## Used to set present time from user operating system (used by Planetarium).[br][br]
##
## Requires IVTimekeeper.

const IS_CLIENT := IVGlobal.NetworkState.IS_CLIENT


var _state: Dictionary[StringName, Variant] = IVGlobal.state

@onready var _timekeeper: IVTimekeeper = IVGlobal.program[&"Timekeeper"]



func _ready() -> void:
	IVGlobal.user_pause_changed.connect(_update_ckbx)
	_timekeeper.speed_changed.connect(_update_ckbx)
	_timekeeper.time_altered.connect(_update_ckbx)
	pressed.connect(_set_real_world)



func _update_ckbx(_dummy: Variant = false) -> void:
	button_pressed = _timekeeper.is_now


func _set_real_world() -> void:
	if _state.network_state != IS_CLIENT:
		_timekeeper.set_now_from_operating_system()
		button_pressed = true
