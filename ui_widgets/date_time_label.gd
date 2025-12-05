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
## Requires [IVTimekeeper]. This widget updates every frame using [member
## IVGlobal.date] and [member IVGlobal.clock]. It queries [IVTimekeeper] on
## [signal IVTimekeeper.speed_changed] to know whether to display the clock or
## clock seconds.[br][br]
##
## This widget has process_mode == PROCESS_MODE_ALWAYS so it can always update
## "...(paused)" text, if applicable.

## Format string for [year, month, day].
@export var date_format := "%02d/%02d/%02d"
## Format string for [hour, minute, second], including preceding spaces to separate from date.
@export var clock_hms_format := "  %02d:%02d:%02d"
## Format string for [hour, minute], including preceding spaces to separate from date.
@export var clock_hm_format := "  %02d:%02d"
## Suffix " UT" or " TT", depending on [member IVTimekeeper.terrestrial_time_clock]
@export var suffix_ut_tt := true
## Time zone suffix, if needed. E.g., " UT"
@export var suffix_text := ""
## If true, suffix the string with localized " (paused)" when paused.
@export var show_pause := true
## Font color when time runs backwards. Only matters if [member
## IVCoreSettings.allow_time_reversal] == true.
@export var reverse_color := Color.RED


var _timekeeper: IVTimekeeper
var _date: Array[int] = IVGlobal.date
var _clock: Array[int] = IVGlobal.clock
var _show_clock := false
var _show_seconds := false
var _is_reversed := false
var _hm: Array[int] = [0, 0]



func _ready() -> void:
	set_process(false)
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	var new_text: String = date_format % _date
	if _show_clock:
		if _show_seconds:
			new_text += clock_hms_format % _clock
		else:
			_hm[0] = _clock[0]
			_hm[1] = _clock[1]
			new_text += clock_hm_format % _hm
	if suffix_ut_tt:
		new_text += " TT" if _timekeeper.terrestrial_time_clock else " UT"
	new_text += suffix_text
	if show_pause and IVStateManager.paused_by_user:
		new_text += " " + tr(&"LABEL_PAUSED")
	text = new_text


func _configure_after_core_inited() -> void:
	_timekeeper = IVGlobal.program[&"Timekeeper"]
	_timekeeper.speed_changed.connect(_update_display)
	set_process(true)


func _update_display() -> void:
	_show_clock = _timekeeper.show_clock
	_show_seconds = _timekeeper.show_seconds
	if _is_reversed != _timekeeper.reversed_time:
		_is_reversed = !_is_reversed
		if _is_reversed:
			add_theme_color_override("font_color", reverse_color)
		else:
			remove_theme_color_override("font_color")
