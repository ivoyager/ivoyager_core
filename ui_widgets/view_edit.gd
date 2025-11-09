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

## Container widget that provides controls for [IVViewButton] editing and saving.
##
## This widget is contained in [IVViewEditPopup] and works in conjunction with
## [IVViewCollection], [IVViewSaveButton] and [IVViewButton] instances. In
## normal setup, all methods (including [method init]) are called by [IVViewCollection].
## Configuration of this node's controls happens when shown.[br][br]
##
## Check boxes that are not specified in [method init] by [param allowed_flags]
## (see [enum IVView.ViewFlags]) will be removed.[br][br]
##
## If [member IVCoreSettings.allow_time_setting] == false (default), NowCkbx
## will be removed. TimeCkbx is still valid because "time state" includes game
## speed, but this checkbox will be re-texted to display as "Game Speed".

signal saved_new(view_name: String)
signal saved_edit(editing_button: IVViewButton, view_name: String)
signal restored_default(editing_button: IVViewButton)
signal deleted(editing_button: IVViewButton)

const ViewFlags := IVView.ViewFlags


# Note: ViewManager usage is confusing. To clarify: IVViewEdit does all view
# saves and removes (because it has the edit info). IVViewButton does all
# connects and disconnets (because it has the Button signals). The button
# expects the view to already exist (if it doesn't, the button won't do anything).
var _view_manager: IVViewManager

# init params
var _new_button_name: StringName
var _collection_name: String
var _is_cached: bool
var _allowed_flags: int
var _new_set_flags: int
var _button_containers: Array[Control] = []

# working params
var _editing_button: IVViewButton
var _reserved_names: Array[String] = []
var _reserved_text := false
var _view_flags := 0

@onready var _header: Label = %Header
@onready var _line_edit: LineEdit = $"%LineEdit"

@onready var _selection_ckbx: CheckBox = $"%SelectionCkbx"
@onready var _longitude_ckbx: CheckBox = $"%LongitudeCkbx"
@onready var _orientation_ckbx: CheckBox = $"%OrientationCkbx"
@onready var _visibilities_ckbx: CheckBox = $"%VisibilitiesCkbx"
@onready var _colors_ckbx: CheckBox = $"%ColorsCkbx"
@onready var _time_ckbx: CheckBox = $"%TimeCkbx"
@onready var _now_ckbx: CheckBox = $"%NowCkbx" # exclusive w/ _time_ckbx

# Unused checkboxes will be removed!
@onready var _flag_ckbxs: Dictionary[int, CheckBox] = {
	ViewFlags.VIEWFLAGS_CAMERA_SELECTION : _selection_ckbx,
	ViewFlags.VIEWFLAGS_CAMERA_LONGITUDE : _longitude_ckbx,
	ViewFlags.VIEWFLAGS_CAMERA_ORIENTATION : _orientation_ckbx,
	ViewFlags.VIEWFLAGS_HUDS_VISIBILITY : _visibilities_ckbx,
	ViewFlags.VIEWFLAGS_HUDS_COLOR : _colors_ckbx,
	ViewFlags.VIEWFLAGS_TIME_STATE : _time_ckbx,
	ViewFlags.VIEWFLAGS_IS_NOW : _now_ckbx,
}

@onready var _save_current_button: Button = %SaveCurrentButton
@onready var _restore_default_button: Button = %RestoreDefaultButton
@onready var _delete_button: Button = %DeleteButton



func _ready() -> void:
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	_view_manager = IVGlobal.program[&"ViewManager"]
	visibility_changed.connect(_on_visibility_changed)
	_save_current_button.pressed.connect(_on_save)
	_restore_default_button.pressed.connect(_on_restore_default)
	_delete_button.pressed.connect(_on_delete)
	_line_edit.text_changed.connect(_on_line_edit_text_changed)
	_line_edit.text_submitted.connect(_on_line_edit_text_submitted)
	if !IVCoreSettings.allow_time_setting:
		_time_ckbx.text = &"CKBX_GAME_SPEED"



## Called by [IVViewCollection] in standard setup. [param button_containers]
## should contain the IVViewCollection itself and any external containers that
## contain view buttons that should have exclusive names. 
func init(new_button_name: StringName, collection_name: String, is_cached: bool,
		allowed_flags: int, new_set_flags: int, button_containers: Array[Control]) -> void:
	_new_button_name = new_button_name
	_collection_name = collection_name
	_is_cached = is_cached
	_allowed_flags = allowed_flags
	_new_set_flags = new_set_flags
	_button_containers = button_containers
	
	# modify allowed and set flags as needed
	if !IVCoreSettings.allow_time_setting:
		_allowed_flags &= ~ViewFlags.VIEWFLAGS_IS_NOW
	_new_set_flags &= _allowed_flags # enforce subset
	if _new_set_flags & ViewFlags.VIEWFLAGS_TIME_STATE:
		_new_set_flags &= ~ViewFlags.VIEWFLAGS_IS_NOW # exclusive
	
	# set checkbox exclusivity if needed
	if (_allowed_flags & ViewFlags.VIEWFLAGS_TIME_STATE
			and _allowed_flags & ViewFlags.VIEWFLAGS_IS_NOW):
		_time_ckbx.toggled.connect(_unset_exclusive_ckbx.bind(_now_ckbx))
		_now_ckbx.toggled.connect(_unset_exclusive_ckbx.bind(_time_ckbx))
	
	# connect allowed and remove dis-allowed checkboxes
	for flag: int in _flag_ckbxs.keys(): # erase safe
		if flag & _allowed_flags:
			_flag_ckbxs[flag].toggled.connect(_on_any_ckbx_toggled)
		else:
			_flag_ckbxs[flag].queue_free()
			_flag_ckbxs.erase(flag)


## Called by [IVViewCollection] in standard setup.
func set_editing_button(editing_button: IVViewButton) -> void:
	_editing_button = editing_button # null if creating new button



func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_editing_button = null
		return
	_configure_controls()


func _configure_controls() -> void:
	_reserved_text = false
	if _editing_button:
		_header.text = &"LABEL_EDIT_ELLIPSIS"
		_set_ckbx_state(_editing_button.get_view_flags())
		_restore_default_button.visible = _editing_button.is_edited_default_button()
		_delete_button.visible = _editing_button.deletable
		_line_edit.text = _editing_button.text
		_line_edit.editable = _editing_button.renamable
	else:
		_header.text = &"LABEL_NEW_ELLIPSIS"
		_set_ckbx_state(_new_set_flags)
		_restore_default_button.hide()
		_delete_button.hide()
		_line_edit.text = tr(_new_button_name)
		_line_edit.editable = true
		
	if _line_edit.editable:
		_set_reserved_names()
		_increment_line_edit_suffix()
		_line_edit.select_all()
		_line_edit.set_caret_column(100)
	_reset_view_flags()
	_save_current_button.disabled = !_view_flags # text can't be reserved here
	_line_edit.grab_focus.call_deferred()
	size = Vector2.ZERO # triggers resize in popup


func _set_ckbx_state(flags: int) -> void:
	for flag in _flag_ckbxs:
		_flag_ckbxs[flag].set_pressed_no_signal(bool(flag & flags))


func _unset_exclusive_ckbx(is_pressed: bool, exclusive_button: CheckBox) -> void:
	if is_pressed:
		exclusive_button.button_pressed = false


func _on_any_ckbx_toggled(_toggled_on: bool) -> void:
	_reset_view_flags()
	_save_current_button.disabled = _reserved_text or !_view_flags


func _on_save() -> void:
	if !_editing_button:
		_view_manager.save_view(_line_edit.text, _collection_name, _is_cached, _view_flags)
		saved_new.emit(_line_edit.text)
		return
	if _line_edit.text != _editing_button.text:
		_view_manager.remove_view(_editing_button.text, _collection_name, _is_cached)
	_view_manager.save_view(_line_edit.text, _collection_name, _is_cached, _view_flags)
	saved_edit.emit(_editing_button, _line_edit.text)


func _on_restore_default() -> void:
	if _editing_button and _editing_button.is_edited_default_button(): # redundant for safety
		_view_manager.remove_view(_editing_button.text, _collection_name, _is_cached)
		restored_default.emit(_editing_button)


func _on_delete() -> void:
	if _editing_button and _editing_button.deletable: # redundant for safety
		_view_manager.remove_view(_editing_button.text, _collection_name, _is_cached)
		deleted.emit(_editing_button)


func _on_line_edit_text_changed(new_text: String) -> void:
	_reserved_text = _reserved_names.has(new_text)
	_save_current_button.disabled = _reserved_text or !_view_flags
	if _reserved_text:
		_line_edit.add_theme_color_override("font_color", Color.RED)
	else:
		_line_edit.remove_theme_color_override("font_color")


func _on_line_edit_text_submitted(_new_text: String) -> void:
	if !_save_current_button.disabled:
		_on_save()
		return
	# same action here, regardless of why...
	_increment_line_edit_suffix()
	_reserved_text = false
	_line_edit.remove_theme_color_override("font_color")
	await get_tree().process_frame
	_line_edit.grab_focus()
	_line_edit.set_caret_column(100)
	_line_edit.edit()
	_save_current_button.disabled = !_view_flags


func _set_reserved_names() -> void:
	_reserved_names.clear()
	for container in _button_containers:
		if is_instance_valid(container):
			for child in container.get_children():
				var view_button := child as IVViewButton
				if view_button:
					_reserved_names.append(view_button.text) # defaults were pre-translated


func _increment_line_edit_suffix() -> void:
	if !_line_edit.text:
		_line_edit.text = _editing_button.text if _editing_button else tr(_new_button_name)
	if _editing_button and _line_edit.text == _editing_button.text: # always valid
		return
	var text := _line_edit.text
	if !_reserved_names.has(text): # available button name
		return
	if !text[-1].is_valid_int():
		_line_edit.text += "2"
	elif text[-1] == "9":
		_line_edit.text[-1] = "1"
		_line_edit.text += "0"
	else:
		_line_edit.text[-1] = str(int(text[-1]) + 1)
	_increment_line_edit_suffix()


func _reset_view_flags() -> void:
	_view_flags = 0
	for flag in _flag_ckbxs:
		if _flag_ckbxs[flag].button_pressed:
			_view_flags |= flag
