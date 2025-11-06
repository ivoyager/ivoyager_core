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

## CheckBox widget for setting "real world" time.
##
## Used to set present time from user operating system (used by Planetarium).[br][br]
##
## Requires IVTimekeeper.

const IS_CLIENT := IVGlobal.NetworkState.IS_CLIENT

var _timekeeper: IVTimekeeper


func _ready() -> void:
	if IVStateManager.is_core_inited:
		_configure_after_core_inited()
	else:
		IVGlobal.core_inited.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	_timekeeper = IVGlobal.program[&"Timekeeper"]
	_timekeeper.speed_changed.connect(_update_ckbx)
	_timekeeper.time_altered.connect(_update_ckbx)
	IVGlobal.user_pause_changed.connect(_update_ckbx)
	pressed.connect(_set_real_world)


func _update_ckbx(_dummy: Variant = false) -> void:
	button_pressed = _timekeeper.is_now


func _set_real_world() -> void:
	if IVStateManager.network_state != IS_CLIENT:
		_timekeeper.set_now_from_operating_system()
		button_pressed = true
