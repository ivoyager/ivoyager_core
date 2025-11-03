# date_time_label.gd
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
class_name IVDateTimeLabel
extends Label

## Label widget that shows current date and time.
##
## Requires [IVTimekeeper].

## Format string for [year, month, day].
@export var date_format := "%02d/%02d/%02d"
## Format string for [hour, minute, second], including preceding spaces to separate from date.
@export var clock_hms_format := "  %02d:%02d:%02d"
## Format string for [hour, minute], including preceding spaces to separate from date.
@export var clock_hm_format := "  %02d:%02d"
## Time zone suffix, if needed. E.g., " UT"
@export var time_zone_suffix := ""
## If true, suffix the string with localized " (paused)" when paused.
@export var show_pause := true
## Override font color if time reversed (only used if time reversal enabled).
@export var reverse_color := Color.RED

var _date: Array[int] = IVGlobal.date
var _clock: Array[int] = IVGlobal.clock
var _show_clock := false
var _show_seconds := false
var _is_reversed := false
var _ymd: Array[int] = [0, 0, 0]
var _hms: Array[int] = [0, 0, 0]
var _hm: Array[int] = [0, 0]

var _timekeeper: IVTimekeeper


func _ready() -> void:
	IVGlobal.update_gui_requested.connect(_update_display)
	if IVStateManager.is_core_inited:
		_configure_for_core()
	else:
		IVGlobal.core_inited.connect(_configure_for_core, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	_ymd[0] = _date[0]
	_ymd[1] = _date[1]
	_ymd[2] = _date[2]
	var new_text: String = date_format % _ymd
	if _show_clock:
		if _show_seconds:
			_hms[0] = _clock[0]
			_hms[1] = _clock[1]
			_hms[2] = _clock[2]
			new_text += clock_hms_format % _hms
		else:
			_hm[0] = _clock[0]
			_hm[1] = _clock[1]
			new_text += clock_hm_format % _hm
	
	new_text += time_zone_suffix
	if show_pause and IVStateManager.is_user_paused:
		new_text += " " + tr(&"LABEL_PAUSED")
	text = new_text


func _configure_for_core() -> void:
	_timekeeper = IVGlobal.program[&"Timekeeper"]
	_timekeeper.speed_changed.connect(_update_display)
	_update_display()


func _update_display() -> void:
	_show_clock = _timekeeper.show_clock
	_show_seconds = _timekeeper.show_seconds
	if _is_reversed != _timekeeper.is_reversed:
		_is_reversed = !_is_reversed
		if _is_reversed:
			add_theme_color_override("font_color", reverse_color)
		else:
			remove_theme_color_override("font_color")
