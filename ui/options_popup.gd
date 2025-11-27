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

## User options popup.
##
## User "options" are are a subset of cached settings managed by [IVSettingsManager].
## All options are cached settings, but not all cached settings are necessarily
## exposed here as user options.[br][br]
##
## This popup builds options Control items on-the-fly as defined in class
## properties. Columns and section headers are defined in [member layout] and
## section content is defined in [member section_content].[br][br]
##
## Depending on value type, an option item can be a [CheckBox], [OptionButton],
## [SpinBox], [LineEdit] or [ColorPickerButton]. Individual option Controls
## can be modified by [member option_enumerations] and [member
## option_control_properties].


## Stop the simulator while this popup is open. This setting will be overridden
## if [member IVCoreSettings.popops_can_stop_sim] == false.
@export var stop_sim := true

## Content layout is an array of columns, where each column is an array of 
## header labels. The header labels must correspond to keys in [member
## section_content].
@export var layout: Array[Array] = [
	# column 1
	[&"LABEL_SAVE_LOAD", &"LABEL_CAMERA"],
	# column 2
	[&"LABEL_GUI_AND_HUD", &"LABEL_GRAPHICS_PERFORMANCE"],
]

## Section keys are the header labels used in [member layout]. Content of each
## section is an array of 2-element arrays, where each 2-element array has an
## option label and a setting (setting must be defined in [IVSettingsManager]).
## Note: It's not necessary to remove a section here if it has been removed
## from [member layout].
@export var section_content: Dictionary[StringName, Array] = {
	LABEL_SAVE_LOAD = [
		[&"LABEL_BASE_NAME", &"save_base_name"],
		[&"LABEL_APPEND_DATE", &"append_date_to_save"],
		[&"LABEL_PAUSE_ON_LOAD", &"pause_on_load"],
		[&"LABEL_AUTOSAVE_TIME_MIN", &"autosave_time_min"],
	],
	LABEL_CAMERA = [
		[&"LABEL_TRANSFER_TIME", &"camera_transfer_time"],
		[&"LABEL_MOUSE_RATE_IN_OUT", &"camera_mouse_in_out_rate"],
		[&"LABEL_MOUSE_RATE_TANGENTIAL", &"camera_mouse_move_rate"],
		[&"LABEL_MOUSE_RATE_PITCH_YAW", &"camera_mouse_pitch_yaw_rate"],
		[&"LABEL_MOUSE_RATE_ROLL", &"camera_mouse_roll_rate"],
		[&"LABEL_KEY_RATE_IN_OUT", &"camera_key_in_out_rate"],
		[&"LABEL_KEY_RATE_TANGENTIAL", &"camera_key_move_rate"],
		[&"LABEL_KEY_RATE_PITCH_YAW", &"camera_key_pitch_yaw_rate"],
		[&"LABEL_KEY_RATE_ROLL", &"camera_key_roll_rate"],
	],
	LABEL_GUI_AND_HUD = [
		[&"LABEL_LANGUAGE", &"language"],
		[&"LABEL_GUI_SIZE", &"gui_size"],
		[&"LABEL_NAMES_SIZE", &"label3d_names_size_percent"],
		[&"LABEL_SYMBOLS_SIZE", &"label3d_symbols_size_percent"],
		[&"LABEL_POINT_SIZE", &"point_size"],
		[&"LABEL_HIDE_HUDS_WHEN_CLOSE", &"hide_hud_when_close"],
	],
	LABEL_GRAPHICS_PERFORMANCE = [
		[&"LABEL_STARMAP", &"starmap"],
	],
}

## Option enumerations. Enumerations are enums or enum-like dictionaries
## (i.e., sequential integer values from 0 keyed by StringNames). Enumeration
## keys are expected to be translatable. The enumeration is identified by an
## array containing an Object key in [member IVGlobal.program] and a property
## name.
@export var option_enumerations: Dictionary[StringName, Array] = {
	language = [&"LanguageManager", &"language_settings"],
	gui_size = [&"Global", &"GUISize"],
	starmap = [&"Global", &"StarmapSize"],
}

## Each option Control can be a [CheckBox], [OptionButton], [SpinBox],
## [LineEdit] or [ColorPickerButton]. Control property overrides can be defined
## here as a dictionary keyed by the option. E.g., if an option Control is a
## [SpinBox], properties can include "min_value", "max_value", etc.
@export var option_control_properties: Dictionary[StringName, Dictionary] = {
	camera_transfer_time = {max_value = 10.0},
	label3d_names_size_percent = {min_value = 20, max_value = 500, step = 10, suffix = "%"},
	label3d_symbols_size_percent = {min_value = 20, max_value = 500, step = 10, suffix = "%"},
	point_size = {min_value = 3, max_value = 20},
}

var _enumerations: Dictionary[StringName, Dictionary] = {}
var _suppress_close := true


@onready var _content_container: HBoxContainer = %ContentContainer
@onready var _restore_defaults: Button = %RestoreDefaultsButton
@onready var _confirm_changes: Button = %ConfirmChangesButton
@onready var _cancel: Button = %CancelButton



func _ready() -> void:
	hide() # Godot 4.5 editor keeps setting visibility == true !!!
	IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:
	IVGlobal.options_requested.connect(open)
	IVSettingsManager.changed.connect(_settings_listener)
	IVGlobal.close_admin_popups_required.connect(hide)
	close_requested.connect(_on_close_requested)
	popup_hide.connect(_on_popup_hide)
	_cancel.pressed.connect(_on_cancel)
	_restore_defaults.pressed.connect(_on_restore_defaults)
	_confirm_changes.pressed.connect(_on_confirm_changes)
	for key in option_enumerations:
		var array := option_enumerations[key]
		var object_key: StringName = array[0]
		var property: StringName = array[1]
		assert(IVGlobal.program.has(object_key))
		var object := IVGlobal.program[object_key]
		assert(property in object)
		var enumeration: Dictionary = object.get(property)
		_enumerations[key] = enumeration


func _shortcut_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"toggle_options", true):
		_on_cancel()
		set_input_as_handled()


func open() -> void:
	if visible:
		return
	if stop_sim:
		IVStateManager.require_stop(self)
	_build_content()
	size = Vector2i.ZERO
	popup_centered()


func _build_content() -> void:
	for child in _content_container.get_children():
		_content_container.remove_child(child)
		child.queue_free()
	for column_array in layout:
		var column_vbox := VBoxContainer.new()
		_content_container.add_child(column_vbox)
		for header: StringName in column_array:
			var subpanel_container := PanelContainer.new()
			column_vbox.add_child(subpanel_container)
			var subpanel_vbox := VBoxContainer.new()
			subpanel_container.add_child(subpanel_vbox)
			var header_label := Label.new()
			subpanel_vbox.add_child(header_label)
			header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			header_label.text = header
			var section := section_content[header]
			for option_array: Array in section:
				var option_text: StringName = option_array[0]
				var setting: StringName = option_array[1]
				if not IVSettingsManager.has_setting(setting):
					push_warning("Skipping nonexistent setting %s" % setting)
					continue
				var setting_hbox := _build_item(option_text, setting)
				subpanel_vbox.add_child(setting_hbox)
	_on_content_built()


func _build_item(option_text: StringName, setting: StringName) -> HBoxContainer:
	var setting_hbox := HBoxContainer.new()
	var label := Label.new()
	setting_hbox.add_child(label)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = option_text
	var default_button := Button.new()
	default_button.text = "!"
	default_button.disabled = IVSettingsManager.is_default(setting)
	default_button.pressed.connect(_restore_default.bind(setting))
	var value: Variant = IVSettingsManager.get_setting(setting)
	var default_value: Variant = IVSettingsManager.get_default(setting)
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
			if is_int and _enumerations.has(setting):
				# OptionButton
				var setting_enum := _enumerations[setting]
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
	if option_control_properties.has(setting):
		var overrides: Dictionary = option_control_properties[setting]
		for override: StringName in overrides:
			control.set(override, overrides[override])


func _on_content_built() -> void:
	_restore_defaults.disabled = IVSettingsManager.is_defaults()
	_confirm_changes.disabled = IVSettingsManager.is_cache_current()


func _restore_default(setting: StringName) -> void:
	IVSettingsManager.restore_default(setting, true)
	_build_content.call_deferred()


func _cancel_changes() -> void:
	IVSettingsManager.restore_from_cache()
	_suppress_close = false
	hide()


func _on_change(value: Variant, setting: StringName, default_button: Button,
		convert_to_int := false) -> void:
	if convert_to_int:
		var float_value: float = value
		value = int(float_value)
	print("Set " + setting + " = " + str(value))
	IVSettingsManager.change_setting(setting, value, true)
	default_button.disabled = IVSettingsManager.is_default(setting)
	_restore_defaults.disabled = IVSettingsManager.is_defaults()
	_confirm_changes.disabled = IVSettingsManager.is_cache_current()


func _on_restore_defaults() -> void:
	IVSettingsManager.restore_defaults(true)
	_build_content.call_deferred()


func _on_confirm_changes() -> void:
	IVSettingsManager.cache_now()
	_suppress_close = false
	hide()


func _on_cancel() -> void:
	if IVSettingsManager.is_cache_current():
		_suppress_close = false
		hide()
		return
	IVGlobal.confirmation_required.emit(&"LABEL_Q_CANCEL_OPTION_CHANGES", _cancel_changes, true,
			&"LABEL_PLEASE_CONFIRM", &"BUTTON_CANCEL_CHANGES", &"BUTTON_BACK")


func _on_close_requested() -> void:
	# Godot 4.1.1 ... 4.5 ISSUE: close_requested signal is useless. See:
	# https://github.com/godotengine/godot/issues/76896#issuecomment-1667027253
	# Also, hide() is done by the engine, contrary to docs.
	# If this is fixed we can remove the '_suppress_close' hack.
	print("Popup.close_requested signal works now! Maybe we can remove hack fixes...")


func _on_popup_hide() -> void:
	if _suppress_close:
		show.call_deferred()
		return
	_suppress_close = true
	for child in _content_container.get_children():
		_content_container.remove_child(child)
		child.queue_free()
	if stop_sim:
		IVStateManager.allow_run(self)


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"gui_size":
		# Needs resize (if shrunk) and repositioning...
		var center := position + size / 2
		await get_tree().process_frame
		size = Vector2i.ZERO
		position = center - size / 2
