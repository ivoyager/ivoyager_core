# speed_label.gd
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
class_name IVSpeedLabel
extends Label

## Label widget that displays game speed.
##
## Requires [IVTimekeeper].

## Display color if time is reversed. (Only possible if
## [IVCoreSettings.allow_time_reversal] is set to non-default true.)
@export var reverse_color := Color.RED

var _timekeeper: IVTimekeeper
var _is_reversed := false


func _ready() -> void:
	if IVStateManager.is_core_inited:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	IVGlobal.update_gui_requested.connect(_update_speed)
	_timekeeper = IVGlobal.program[&"Timekeeper"]
	_timekeeper.speed_changed.connect(_update_speed)
	_update_speed()


func _update_speed() -> void:
	text = _timekeeper.speed_name
	if _is_reversed == _timekeeper.is_reversed:
		return
	_is_reversed = !_is_reversed
	if _is_reversed:
		add_theme_color_override("font_color", reverse_color)
	else:
		remove_theme_color_override("font_color")
