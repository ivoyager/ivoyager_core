# options_popup.gd
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
class_name IVOptionsPopup
extends PopupPanel


const SCENE := "res://addons/ivoyager_core/gui_popups/options_popup.tscn"

const DPRINT := true


@export var stop_sim := true
@export var layout: Array[Array] = [
	# column 1
	[
		{
			&"header" : &"LABEL_SAVE_LOAD",
			&"save_base_name" : &"LABEL_BASE_NAME",
			&"append_date_to_save" : &"LABEL_APPEND_DATE",
			&"pause_on_load" : &"LABEL_PAUSE_ON_LOAD",
			&"autosave_time_min" : &"LABEL_AUTOSAVE_TIME_MIN",
		},
		{
			&"header" : &"LABEL_CAMERA",
			&"camera_transfer_time" : &"LABEL_TRANSFER_TIME",
			&"camera_mouse_in_out_rate" : &"LABEL_MOUSE_RATE_IN_OUT",
			&"camera_mouse_move_rate" : &"LABEL_MOUSE_RATE_TANGENTIAL",
			&"camera_mouse_pitch_yaw_rate" : &"LABEL_MOUSE_RATE_PITCH_YAW",
			&"camera_mouse_roll_rate" : &"LABEL_MOUSE_RATE_ROLL",
			&"camera_key_in_out_rate" : &"LABEL_KEY_RATE_IN_OUT",
			&"camera_key_move_rate" : &"LABEL_KEY_RATE_TANGENTIAL",
			&"camera_key_pitch_yaw_rate" : &"LABEL_KEY_RATE_PITCH_YAW",
			&"camera_key_roll_rate" : &"LABEL_KEY_RATE_ROLL",
		},
	],
	
	# column 2
	[
		{
			&"header" : &"LABEL_GUI_AND_HUD",
			&"gui_size" : &"LABEL_GUI_SIZE",
			&"viewport_names_size" : &"LABEL_NAMES_SIZE",
			&"viewport_symbols_size" : &"LABEL_SYMBOLS_SIZE",
			&"point_size" : &"LABEL_POINT_SIZE",
			&"hide_hud_when_close" : &"LABEL_HIDE_HUDS_WHEN_CLOSE",
		},
		{
			&"header" : &"LABEL_GRAPHICS_PERFORMANCE",
			&"starmap" : &"LABEL_STARMAP",
		},
	],
]

@export var setting_enums := {
	gui_size = IVGlobal.GUISize,
	starmap = IVGlobal.StarmapSize,
}
@export var format_overrides := {
	&"camera_transfer_time" : {&"max_value" : 10.0},
	&"viewport_names_size" : {&"min_value" : 4.0, &"max_value" : 50.0},
	&"viewport_symbols_size" : {&"min_value" : 4.0, &"max_value" : 50.0},
	&"point_size" : {&"min_value" : 3, &"max_value" : 20},
}


var _settings: Dictionary[StringName, Variant] = IVGlobal.settings
var _blocking_windows: Array[Window] = IVGlobal.blocking_windows
var _allow_close := false


@onready var _settings_manager: IVSettingsManager = IVGlobal.program[&"SettingsManager"]
@onready var _content_container: HBoxContainer = $VBox/Content
@onready var _cancel: Button = $VBox/BottomHBox/Cancel
@onready var _confirm_changes: Button = $VBox/BottomHBox/ConfirmChanges
@onready var _restore_defaults: Button = $VBox/BottomHBox/RestoreDefaults



func _ready() -> void:
	IVGlobal.options_requested.connect(open)
	IVGlobal.setting_changed.connect(_settings_listener)
	IVGlobal.close_all_admin_popups_requested.connect(hide)
	close_requested.connect(_on_close_requested)
	popup_hide.connect(_on_popup_hide)
	exclusive = false # Godot ISSUE? not editable in scene?
	_cancel.pressed.connect(_on_cancel)
	_restore_defaults.pressed.connect(_on_restore_defaults)
	_confirm_changes.pressed.connect(_on_confirm_changes)
	_blocking_windows.append(self)
	
	if !IVPluginUtils.is_plugin_enabled("ivoyager_save"):
		remove_subpanel(&"LABEL_SAVE_LOAD")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		set_input_as_handled()
		_on_cancel()



func open() -> void:
	if visible:
		return
	if _is_blocking_popup():
		return
	if stop_sim:
		IVGlobal.sim_stop_required.emit(self)
	_build_content()
	size = Vector2i.ZERO
	popup_centered()


func add_subpanel(subpanel_dict: Dictionary, to_column: int, to_row := 999) -> void:
	# Set to_column and/or to_row arbitrarily large to move to end.
	if to_column >= layout.size():
		to_column = layout.size()
		layout.append([])
	var column_array: Array[Dictionary] = layout[to_column]
	if to_row >= column_array.size():
		to_row = column_array.size()
	column_array.insert(to_row, subpanel_dict)


func remove_subpanel(header: StringName) -> Dictionary:
	for column_array in layout:
		var dict_index := 0
		while dict_index < column_array.size():
			var subpanel_dict: Dictionary = column_array[dict_index]
			if subpanel_dict.header == header:
				column_array.remove_at(dict_index)
				return subpanel_dict
			dict_index += 1
	print("Could not find subpanel with header ", header)
	return {}


func move_subpanel(header: StringName, to_column: int, to_row: int) -> void:
	# to_column and/or to_row can be arbitrarily big to move to end
	var subpanel_dict := remove_subpanel(header)
	if subpanel_dict:
		add_subpanel(subpanel_dict, to_column, to_row)


func add_item(item: StringName, setting_label_str: StringName, header: StringName, at_index := 999
		) -> void:
	# use add_subpanel() instead if subpanel doesn't exist already.
	assert(item != "header")
	for column_array in layout:
		var dict_index := 0
		while dict_index < column_array.size():
			var subpanel_dict: Dictionary = column_array[dict_index]
			if subpanel_dict.header == header:
				if at_index >= subpanel_dict.size() - 1:
					subpanel_dict[item] = setting_label_str
					return
				# Dictionaries are ordered but there is no insert!
				var new_subpanel_dict := {}
				var index := 0
				for key: StringName in subpanel_dict:
					new_subpanel_dict[key] = subpanel_dict[key] # 1st is header
					if index == at_index:
						new_subpanel_dict[item] = setting_label_str
					index += 1
				column_array[dict_index] = new_subpanel_dict
				return
			dict_index += 1
	print("Could not find Options subpanel with header ", header)


func remove_item(item: StringName) -> void:
	assert(item != "header")
	for column_array in layout:
		var dict_index := 0
		while dict_index < column_array.size():
			var subpanel_dict: Dictionary = column_array[dict_index]
			subpanel_dict.erase(item)
			if subpanel_dict.size() == 1: # only header remains
				column_array.remove_at(dict_index)
				dict_index -= 1
			dict_index += 1



func _build_content() -> void:
	for child in _content_container.get_children():
		_content_container.remove_child(child)
		child.queue_free()
	for column_array in layout:
		var column_vbox := VBoxContainer.new()
		_content_container.add_child(column_vbox)
		for subpanel_dict: Dictionary in column_array:
			var subpanel_container := PanelContainer.new()
			column_vbox.add_child(subpanel_container)
			var subpanel_vbox := VBoxContainer.new()
			subpanel_container.add_child(subpanel_vbox)
			var header_label := Label.new()
			subpanel_vbox.add_child(header_label)
			header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			header_label.text = subpanel_dict.header
			for item: StringName in subpanel_dict:
				if item != &"header":
					var label_name: StringName = subpanel_dict[item]
					var setting_hbox := _build_item(item, label_name)
					subpanel_vbox.add_child(setting_hbox)
	_on_content_built()


func _build_item(setting: StringName, setting_label_str: StringName) -> HBoxContainer:
	var setting_hbox := HBoxContainer.new()
	var setting_label := Label.new()
	setting_hbox.add_child(setting_label)
	setting_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setting_label.text = setting_label_str
	var default_button := Button.new()
	default_button.text = "!"
	default_button.disabled = _settings_manager.is_default(setting)
	default_button.pressed.connect(_restore_default.bind(setting))
	var value: Variant = _settings[setting]
	var default_value: Variant = _settings_manager.defaults[setting]
	var type := typeof(default_value)
	match type:
		TYPE_BOOL:
			# CheckBox
			var checkbox := CheckBox.new()
			setting_hbox.add_child(checkbox)
			checkbox.size_flags_horizontal = Control.SIZE_SHRINK_END
			_set_overrides(checkbox, setting)
			checkbox.button_pressed = value
			checkbox.toggled.connect(_on_change.bind(setting, default_button))
		TYPE_INT, TYPE_FLOAT:
			var is_int := type == TYPE_INT
			if is_int and setting_enums.has(setting):
				# OptionButton
				var setting_enum: Dictionary = setting_enums[setting]
				var keys: Array = setting_enum.keys()
				var option_button := OptionButton.new()
				setting_hbox.add_child(option_button)
				for key: String in keys:
					option_button.add_item(key)
				_set_overrides(option_button, setting)
				option_button.selected = value
				option_button.item_selected.connect(_on_change.bind(setting, default_button))
			else: # non-option int or float
				# SpinBox
				var spin_box := SpinBox.new()
				setting_hbox.add_child(spin_box)
				spin_box.step = 1.0 if is_int else 0.1
				spin_box.rounded = is_int
				spin_box.min_value = 0.0
				spin_box.max_value = 100.0
				_set_overrides(spin_box, setting)
				spin_box.value = value
				spin_box.value_changed.connect(_on_change.bind(setting, default_button, is_int))
				var line_edit := spin_box.get_line_edit()
				line_edit.context_menu_enabled = false
#				line_edit.update() # TEST34: Do we need to do something?
		TYPE_STRING:
			# LineEdit
			var line_edit := LineEdit.new()
			setting_hbox.add_child(line_edit)
			line_edit.size_flags_horizontal = BoxContainer.SIZE_SHRINK_END
			line_edit.custom_minimum_size.x = 100.0
			_set_overrides(line_edit, setting)
			line_edit.text = value
			line_edit.text_changed.connect(_on_change.bind(setting, default_button))
		TYPE_COLOR:
			# ColorPickerButton
			var color_picker_button := ColorPickerButton.new()
			setting_hbox.add_child(color_picker_button)
			color_picker_button.custom_minimum_size.x = 60.0
			color_picker_button.edit_alpha = false
			_set_overrides(color_picker_button, setting)
			color_picker_button.color = value
			color_picker_button.color_changed.connect(_on_change.bind(setting, default_button))
		_:
			print("ERROR: Unknown Option type!")
	setting_hbox.add_child(default_button)
	return setting_hbox


func _set_overrides(control: Control, setting: StringName) -> void:
	if format_overrides.has(setting):
		var overrides: Dictionary = format_overrides[setting]
		for override: StringName in overrides:
			control.set(override, overrides[override])


func _on_content_built() -> void:
	_restore_defaults.disabled = _settings_manager.is_defaults()
	_confirm_changes.disabled = _settings_manager.is_cache_current()


func _restore_default(setting: StringName) -> void:
	_settings_manager.restore_default(setting, true)
	_build_content.call_deferred()


func _cancel_changes() -> void:
	_settings_manager.restore_from_cache()
	_allow_close = true
	hide()


func _on_change(value: Variant, setting: StringName, default_button: Button,
		convert_to_int := false) -> void:
	if convert_to_int:
		var float_value: float = value
		value = int(float_value)
	assert(!DPRINT or IVDebug.dprint("Set " + setting + " = " + str(value)))
	_settings_manager.change_current(setting, value, true)
	default_button.disabled = _settings_manager.is_default(setting)
	_restore_defaults.disabled = _settings_manager.is_defaults()
	_confirm_changes.disabled = _settings_manager.is_cache_current()


func _on_restore_defaults() -> void:
	_settings_manager.restore_defaults(true)
	_build_content.call_deferred()


func _on_confirm_changes() -> void:
	_settings_manager.cache_now()
	_allow_close = true
	hide()


func _on_cancel() -> void:
	if _settings_manager.is_cache_current():
		_allow_close = true
		hide()
		return
	IVGlobal.confirmation_requested.emit(&"LABEL_Q_CANCEL_OPTION_CHANGES", _cancel_changes, true,
			&"LABEL_PLEASE_CONFIRM", &"BUTTON_CANCEL_CHANGES", &"BUTTON_BACK")


func _on_close_requested() -> void:
	# TODO Godot 4.1.1 ISSUE: This is basically useless. It is only called if
	# exclusive == false and root viewport gui_embed_subwindows == false.
	# But we want to keep gui_embed_subwindows == true.
	# Also, hide() is done by the engine, contrary to docs.
	# If this is fixed we can remove the '_allow_close' hack.
	print("close_requested signal works now! Use requirements were prohibitive in Godot 4.1.1")


func _is_blocking_popup() -> bool:
	for window in _blocking_windows:
		if window.visible:
			return true
	return false


func _on_popup_hide() -> void:
	if !_allow_close:
		show.call_deferred()
		return
	_allow_close = false
	for child in _content_container.get_children():
		_content_container.remove_child(child)
		child.queue_free()
	if stop_sim:
		IVGlobal.sim_run_allowed.emit(self)


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"gui_size":
		var center := position + size / 2
		await get_tree().process_frame
		#child_controls_changed() # Godot ISSUE4.2.dev2: does not resize
		size = Vector2i.ZERO # hack fix above
		position = center - size / 2
