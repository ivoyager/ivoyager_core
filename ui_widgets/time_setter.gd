# time_setter.gd
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

signal closed()


var _timekeeper: IVTimekeeper
var _updating_setter := false

@onready var _year: SpinBox = $SetterHBox/Year
@onready var _month: SpinBox = $SetterHBox/Month
@onready var _day: SpinBox = $SetterHBox/Day
@onready var _hour: SpinBox = $SetterHBox/Hour
@onready var _minute: SpinBox = $SetterHBox/Minute
@onready var _second: SpinBox = $SetterHBox/Second
@onready var _update_ckbx: CheckBox = %UpdateCkbx


func _ready() -> void:
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func update_setter_time() -> void:
	var date_time := _timekeeper.get_gregorian_date_time()
	var date_array: Array[int] = date_time[0]
	var time_array: Array[int] = date_time[1]
	_updating_setter = true
	_year.value = date_array[0]
	_month.value = date_array[1]
	_day.value = date_array[2]
	_hour.value = time_array[0]
	_minute.value = time_array[1]
	_second.value = time_array[2]
	_updating_setter = false


func _configure_after_core_inited() -> void:
	_timekeeper = IVGlobal.program[&"Timekeeper"]
	visibility_changed.connect(_on_visibility_changed)
	(%SetButton as Button).pressed.connect(_set_time.bind(true))
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
	if is_date and _decrement_invalid_day():
		# _decrement_invalid_day() causes a recursive call to this method when it
		# sets the day spinbox. It will recurse at most 3 times (Feb 31, non-leap year).
		return 
	if _update_ckbx.button_pressed:
		_set_time(false)


func _set_time(set_and_close: bool) -> void:
	@warning_ignore("narrowing_conversion")
	var new_time := _timekeeper.get_sim_time(_year.value, _month.value, _day.value,
			_hour.value, _minute.value, _second.value)
	_timekeeper.set_time(new_time)
	if set_and_close:
		closed.emit()


func _decrement_invalid_day() -> bool:
	if _day.value < 29.0:
		return false
	@warning_ignore("narrowing_conversion")
	if not _timekeeper.is_valid_gregorian_date(_year.value, _month.value, _day.value):
		_day.value -= 1.0
		return true
	return false
