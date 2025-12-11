# sync_os_time_checkbox.gd
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
class_name IVSyncOSTimeCheckBox
extends CheckBox

## CheckBox widget that syncs simulator time with operating system time.
##
## Requires [IVTimekeeper]. Time setting is disabled by default. To enable, set
## [member IVCoreSettings.allow_time_setting] == true.
## This button is used by Planetarium.[br][br]
##
## When set, [IVTimekeeper] will set time from the operating system. It will
## set again whenever the application becomes focused.[br][br]
##
## See also [IVTimeSetButton].

var _timekeeper: IVTimekeeper
var _speed_manager: IVSpeedManager


func _ready() -> void:
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _toggled(toggled_on: bool) -> void:
	if !_timekeeper or !_speed_manager:
		return
	if toggled_on:
		_timekeeper.synchronize_time_with_os()
	else:
		_update_ckbx.call_deferred()


func _configure_after_core_inited() -> void:
	_timekeeper = IVGlobal.program[&"Timekeeper"]
	_speed_manager = IVGlobal.program[&"SpeedManager"]
	_timekeeper.time_set.connect(_update_ckbx)
	_speed_manager.speed_changed.connect(_update_ckbx)


func _update_ckbx(_dummy: Variant = false) -> void:
	set_pressed_no_signal(_speed_manager.os_time_sync_on)
