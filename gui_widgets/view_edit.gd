# view_edit.gd
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
class_name IVViewEdit
extends VBoxContainer

## GUI widget that saves current "view", where view may or may not include
## position, orientation, HUDs state, and time state.
##
## This widget is contained in [IVViewEditPopup] and works in conjunction with
## [IVViewSaveFlow] (which shows the resultant saved view buttons).[br][br]
##
## Unused buttions will be removed.[br][br]
##
## In normal game usage where [member IVCoreSettings.allow_time_setting] == false,
## TimeCkbx is still valid because "time state" includes game speed. This
## check box will be relabled "CKBX_GAME_SPEED". NowCkbx is not valid and
## will be removed.

signal saved_new(view_name: String)
signal saved_edit(editing_button: IVViewButton, view_name: String)
signal restored_default(editing_button: IVViewButton)
signal deleted(editing_button: IVViewButton)
signal canceled()


const ViewFlags := IVView.ViewFlags


var _new_button_name: StringName
var _collection_name: String
var _is_cached := true
var _allowed_flags: int
var _new_set_flags: int

var _reserved_names: Array[String] = []

var _editing_button: IVViewButton


# Note: ViewManager usage is a little confusing. IVViewEdit does all view_name
# saves and removes. IVViewButton does all connects and disconnets.
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
@onready var _flag_ckbxs: Dictionary[int, CheckBox] = {
	ViewFlags.VIEWFLAGS_CAMERA_SELECTION : _selection_ckbx,
	ViewFlags.VIEWFLAGS_CAMERA_LONGITUDE : _longitude_ckbx,
	ViewFlags.VIEWFLAGS_CAMERA_ORIENTATION : _orientation_ckbx,
	ViewFlags.VIEWFLAGS_HUDS_VISIBILITY : _visibilities_ckbx,
	ViewFlags.VIEWFLAGS_HUDS_COLOR : _colors_ckbx,
	ViewFlags.VIEWFLAGS_TIME_STATE : _time_ckbx,
	ViewFlags.VIEWFLAGS_IS_NOW : _now_ckbx,
}



func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	($"%SaveCurrentButton" as Button).pressed.connect(_on_save)
	(%RestoreDefaultButton as Button).pressed.connect(_on_restore_default)
	(%DeleteButton as Button).pressed.connect(_on_delete)
	(%CancelButton as Button).pressed.connect(canceled.emit)
	_line_edit.text_submitted.connect(_on_save)
	if !IVCoreSettings.allow_time_setting:
		_time_ckbx.text = &"CKBX_GAME_SPEED" # this is the only 'time' element that can be modified



func init(new_button_name: StringName, collection_name: String, is_cached: bool,
		allowed_flags: int, new_set_flags: int, reserved_names: Array[String] = []) -> void:
	# Called by IVViewCollection in standard setup.
	# Make 'collection_name_' unique to not share views with other GUI instances. 
	_new_button_name = new_button_name
	_collection_name = collection_name
	_is_cached = is_cached
	_allowed_flags = allowed_flags
	_new_set_flags = new_set_flags
	_reserved_names = reserved_names
	
	# translate reserved names
	for i in _reserved_names.size():
		_reserved_names[i] = tr(_reserved_names[i])
	
	# modify input flags as needed
	if !IVCoreSettings.allow_time_setting:
		_allowed_flags &= ~ViewFlags.VIEWFLAGS_IS_NOW
	new_set_flags &= _allowed_flags # enforce subset
	if new_set_flags & ViewFlags.VIEWFLAGS_TIME_STATE:
		new_set_flags &= ~ViewFlags.VIEWFLAGS_IS_NOW # exclusive
	
	_line_edit.text = tr(_new_button_name)
	_increment_suffix()
	
	# set button exclusivity if needed
	if _allowed_flags & ViewFlags.VIEWFLAGS_TIME_STATE and _allowed_flags & ViewFlags.VIEWFLAGS_IS_NOW:
		_time_ckbx.toggled.connect(_unset_exclusive_ckbx.bind(_now_ckbx))
		_now_ckbx.toggled.connect(_unset_exclusive_ckbx.bind(_time_ckbx))
	
	# remove buttons we'll never use
	for flag: int in _flag_ckbxs.keys(): # erase safe
		if not flag & _allowed_flags:
			_flag_ckbxs[flag].queue_free()
			_flag_ckbxs.erase(flag)
	
	_set_ckbx_state(_new_set_flags)



func set_editing_button(editing_button: IVViewButton) -> void:
	_editing_button = editing_button # null if creating new button



func _set_ckbx_state(flags: int) -> void:
	for flag in _flag_ckbxs:
		_flag_ckbxs[flag].set_pressed_no_signal(bool(flag & flags))


func _unset_exclusive_ckbx(is_pressed: bool, exclusive_button: CheckBox) -> void:
	if is_pressed:
		exclusive_button.button_pressed = false


func _on_visibility_changed() -> void:
	
	if !is_visible_in_tree():
		_editing_button = null
		return
	
	(%RestoreDefaultButton as Button).visible = (_editing_button
			and _editing_button.is_edited_default_button())
	(%DeleteButton as Button).visible = _editing_button and _editing_button.deletable
	if _editing_button:
		_set_ckbx_state(_editing_button.get_view_flags())
		_line_edit.editable = _editing_button.renamable
		_line_edit.text = tr(_editing_button.text)
	else:
		_set_ckbx_state(_new_set_flags)
		_line_edit.editable = true
		_line_edit.text = tr(_new_button_name)
		_increment_suffix()
	if _line_edit.editable:
		_line_edit.select_all()
		_line_edit.set_caret_column(100)
		_line_edit.grab_focus.call_deferred()
	size = Vector2.ZERO # triggers resize in popup


func _on_save(_dummy := "") -> void:
	_increment_suffix()
	var flags := _get_view_flags()
	if !_editing_button:
		_view_manager.save_view(_line_edit.text, _collection_name, _is_cached, flags)
		saved_new.emit(_line_edit.text)
		return
	if _line_edit.text != tr(_editing_button.text):
		_view_manager.remove_view(_editing_button.text, _collection_name, _is_cached)
	_view_manager.save_view(_line_edit.text, _collection_name, _is_cached, flags)
	saved_edit.emit(_editing_button, _line_edit.text)


func _on_restore_default() -> void:
	if _editing_button and _editing_button.default_view: # unavailable otherwise, but just in case
		_view_manager.remove_view(_editing_button.text, _collection_name, _is_cached)
		restored_default.emit(_editing_button)


func _on_delete() -> void:
	if _editing_button and _editing_button.deletable: # unavailable otherwise, but just in case
		_view_manager.remove_view(_editing_button.text, _collection_name, _is_cached)
		deleted.emit(_editing_button)


func _increment_suffix() -> void:
	if _editing_button and tr(_editing_button.text) == _line_edit.text:
		return
	if !_line_edit.text:
		_line_edit.text = "1"
	var text := _line_edit.text
	if !_view_manager.has_view(text, _collection_name, _is_cached) and !_reserved_names.has(text):
		return
	if !text[-1].is_valid_int():
		_line_edit.text += "2"
	elif text[-1] == "9":
		_line_edit.text[-1] = "1"
		_line_edit.text += "0"
	else:
		_line_edit.text[-1] = str(int(text[-1]) + 1)
	_increment_suffix()


func _get_view_flags() -> int:
	var flags := 0
	for flag in _flag_ckbxs:
		if _flag_ckbxs[flag].button_pressed:
			flags |= flag
	return flags
