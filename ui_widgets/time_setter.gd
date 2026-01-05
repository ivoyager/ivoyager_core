# time_setter.gd
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
class_name IVTimeSetter
extends VBoxContainer

## Control widget that lets the user set simulator time.
##
## Requires [IVTimekeeper]. Time setting is disabled by default. To enable, set
## [member IVCoreSettings.allow_time_setting] == true.
## This widget is used by Planetarium.[br][br]
##
## In typical setup, this control is in [IVTimeSetPopup] which is a child of,
## and evoked by, [IVTimeSetButton]. You only have to add the button.[br][br]
##
## If not used in a popup, call [method update_setter_time] as needed.

signal closed() # not emitted after we removed close button


var _timekeeper: IVTimekeeper
var _date := IVGlobal.date
var _clock := IVGlobal.clock
var _updating_setter := false

@onready var _year: SpinBox = $SetterHBox/Year
@onready var _month: SpinBox = $SetterHBox/Month
@onready var _day: SpinBox = $SetterHBox/Day
@onready var _hour: SpinBox = $SetterHBox/Hour
@onready var _minute: SpinBox = $SetterHBox/Minute
@onready var _second: SpinBox = $SetterHBox/Second
@onready var _ut_tt_label: Label = %UTTTLabel


func _ready() -> void:
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func update_setter_time() -> void:
	_updating_setter = true
	_year.value = _date[0]
	_month.value = _date[1]
	_day.value = _date[2]
	_hour.value = _clock[0]
	_minute.value = _clock[1]
	_second.value = _clock[2]
	_ut_tt_label.text = "  TT" if _timekeeper.terrestrial_time_clock else "  UT"
	_updating_setter = false


func _configure_after_core_inited() -> void:
	_timekeeper = IVGlobal.program[&"Timekeeper"]
	visibility_changed.connect(_on_visibility_changed)
	_year.value_changed.connect(_on_time_changed.bind(true))
	_month.value_changed.connect(_on_time_changed.bind(true))
	_day.value_changed.connect(_on_time_changed.bind(true))
	_hour.value_changed.connect(_on_time_changed)
	_minute.value_changed.connect(_on_time_changed)
	_second.value_changed.connect(_on_time_changed)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		update_setter_time()


func _on_time_changed(_value: float, is_date := false) -> void:
	if _updating_setter: # prevents infinite recursion!
		return
	# _decrement_invalid_day() will cause a recursive call to this method if it
	# decrements the day spinbox. It will recurse at most 3 times (for Feb 31 in
	# a non-leap year).
	if is_date and _decrement_invalid_day():
		return 
	_set_time()


@warning_ignore_start("narrowing_conversion")

func _set_time() -> void:
	var tt_clock_time := _timekeeper.terrestrial_time_clock
	_timekeeper.set_time_from_date_clock_elements(_year.value, _month.value,
			_day.value, _hour.value, _minute.value, _second.value, tt_clock_time)


func _decrement_invalid_day() -> bool:
	# returns true if it decremented the day spinbox
	if _day.value < 29.0:
		return false
	if _timekeeper.is_valid_gregorian_date(_year.value, _month.value, _day.value):
		return false
	_day.value -= 1.0
	return true
