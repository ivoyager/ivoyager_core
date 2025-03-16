# view_saver.gd
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
class_name IVViewSaver
extends VBoxContainer

# GUI widget that saves current view. This widget is contained in
# IVViewSavePopup and works in conjunction with IVViewSaveFlow (which shows
# the resultant saved view buttons).
#
# Note: Unused buttions will be removed!

signal view_saved(view_name: StringName)

const ViewFlags := IVView.ViewFlags

var default_view_name := &"LABEL_CUSTOM1" # will increment if taken
var collection_name := &""
var is_cached := true
var show_flags: int = ViewFlags.ALL
var reserved_names: Array[StringName] = []

@onready var _view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]
@onready var _selection_ckbx: CheckBox = $"%SelectionCkbx"
@onready var _longitude_ckbx: CheckBox = $"%LongitudeCkbx"
@onready var _orientation_ckbx: CheckBox = $"%OrientationCkbx"
@onready var _visibilities_ckbx: CheckBox = $"%VisibilitiesCkbx"
@onready var _colors_ckbx: CheckBox = $"%ColorsCkbx"
@onready var _time_ckbx: CheckBox = $"%TimeCkbx"
@onready var _now_ckbx: CheckBox = $"%NowCkbx" # exclusive w/ _time_ckbx
@onready var _line_edit: LineEdit = $"%LineEdit"

# Unused buttons will be removed!
@onready var flag_ckbxs : Dictionary[int, CheckBox] = {
	ViewFlags.CAMERA_SELECTION : _selection_ckbx,
	ViewFlags.CAMERA_LONGITUDE : _longitude_ckbx,
	ViewFlags.CAMERA_ORIENTATION : _orientation_ckbx,
	ViewFlags.HUDS_VISIBILITY : _visibilities_ckbx,
	ViewFlags.HUDS_COLOR : _colors_ckbx,
	ViewFlags.TIME_STATE : _time_ckbx,
	ViewFlags.IS_NOW : _now_ckbx,
}



func _ready() -> void:
	_line_edit.text = tr(default_view_name)
	visibility_changed.connect(_on_visibility_changed)
	($"%SaveButton" as Button).pressed.connect(_on_save)
	_line_edit.text_submitted.connect(_on_save)
	if !IVCoreSettings.allow_time_setting:
		_time_ckbx.text = &"CKBX_GAME_SPEED" # this is the only 'time' element that can be modified


func init(default_view_name_ := &"LABEL_CUSTOM1", collection_name_ := &"", is_cached_ := true,
		show_flags_: int = ViewFlags.ALL, init_flags: int = ViewFlags.ALL,
		reserved_names_: Array[StringName] = []) -> void:
	# Called by IVViewSaveButton in standard setup.
	# Make 'collection_name_' unique to not share views with other GUI instances. 
	default_view_name = default_view_name_
	collection_name = collection_name_
	is_cached = is_cached_
	show_flags = show_flags_
	reserved_names = reserved_names_
	
	# modify input flags as needed
	if !IVCoreSettings.allow_time_setting:
		show_flags &= ~ViewFlags.IS_NOW
	init_flags &= show_flags # enforce subset
	if init_flags & ViewFlags.TIME_STATE:
		init_flags &= ~ViewFlags.IS_NOW # exclusive
	
	_line_edit.text = tr(default_view_name)
	_increment_name_as_needed()
	
	# set button exclusivity if needed
	if show_flags & ViewFlags.TIME_STATE and show_flags & ViewFlags.IS_NOW:
		_time_ckbx.toggled.connect(_unset_exclusive.bind(_now_ckbx))
		_now_ckbx.toggled.connect(_unset_exclusive.bind(_time_ckbx))
	
	# remove buttons we'll never use
	for flag: int in flag_ckbxs.keys(): # erase safe
		if not flag & show_flags:
			flag_ckbxs[flag].queue_free()
			flag_ckbxs.erase(flag)
	
	# initial pressed state
	for flag in flag_ckbxs:
		flag_ckbxs[flag].set_pressed_no_signal(bool(flag & init_flags))


func _unset_exclusive(is_pressed: bool, exclusive_button: CheckBox) -> void:
	if is_pressed:
		exclusive_button.button_pressed = false


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_increment_name_as_needed()
		_line_edit.select_all()
		_line_edit.set_caret_column(100)
		_line_edit.grab_focus.call_deferred()


func _on_save(_dummy := "") -> void:
	_increment_name_as_needed()
	var flags := _get_view_flags()
	_view_manager.save_view(_line_edit.text, collection_name, is_cached, flags)
	view_saved.emit(_line_edit.text)


func _increment_name_as_needed() -> void:
	if !_line_edit.text:
		_line_edit.text = "1"
	var text := _line_edit.text
	if !_view_manager.has_view(text, collection_name, is_cached) and !reserved_names.has(text):
		return
	if !text[-1].is_valid_int():
		_line_edit.text += "2"
	elif text[-1] == "9":
		_line_edit.text[-1] = "1"
		_line_edit.text += "0"
	else:
		_line_edit.text[-1] = str(int(text[-1]) + 1)
	_increment_name_as_needed()


func _get_view_flags() -> int:
	var flags := 0
	for flag in flag_ckbxs:
		if flag_ckbxs[flag].button_pressed:
			flags |= flag
	return flags
