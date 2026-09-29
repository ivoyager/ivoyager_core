# options_popup.gd
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
## option_control_properties], and given a tooltip by [member option_tooltips].[br][br]
##
## A graphics option's tooltip states its GPU cost, which differs by renderer,
## so tooltips come in two sets: [member option_tooltips], and [member
## option_compatibility_tooltips], whose entries replace the first set's whenever
## [member IVGlobal.is_gl_compatibility] is true.[br][br]
##
## A section with no options to show is hidden. While any setting registered with
## [method IVSettingsManager.set_running_value] differs from the value the running
## session uses, a warning at the bottom says that a restart is needed.[br][br]
##
## [signal IVGlobal.options_requested] opens this popup, or closes it as Cancel
## does if it's open. See [member modal] for the two ways it can work.


## Stop the simulator while this popup is open. This setting will be overridden
## if [member IVCoreSettings.popops_can_stop_sim] == false.
@export var stop_sim := true
## If true (default), the rest of the GUI and the view don't respond until this
## popup closes. Set false for a popup that stays open while the user works
## elsewhere, which its button or hotkey then closes.
@export var modal := true:
	set = set_modal
## Column width multiplied by [member IVCoreSettings.gui_size_multipliers] (minimum).
@export var column_base_width := 320

## If true (default), automatically remove cache settings that are not
## applicable due to [IVCoreSettings]. (Currently:
## [code]&"physical_light"[/code] when
## [member IVCoreSettings.enable_physical_light] is false.)
@export var autoremove_for_na_settings := true

## If true (default), automatically remove the Save/Load section if the
## Save plugin is not present and enabled.
@export var autoremove_for_missing_save_plugin := true

## Revert-to-default button text.
@export var default_button_text := "!"
## Revert-to-default button icon.
@export var default_button_icon: Texture2D
## Revert-to-default button text.
@export var default_button_tooltip_text := "HINT_RESTORE_DEFAULT_OPTION"

## Content layout is an array of columns, where each column is an array of 
## header labels. The header labels must correspond to keys in [member
## section_content].
@export var layout: Array[Array] = [
	# column 1
	[&"LABEL_SAVE_LOAD", &"LABEL_CAMERA", &"LABEL_SCREENSHOTS"],
	# column 2
	[&"LABEL_GUI_AND_HUD", &"LABEL_GRAPHICS_PERFORMANCE", &"LABEL_GRAPHICS_REQUIRES_RESTART"],
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
		[&"LABEL_PHYSICAL_LIGHT", &"physical_light"],
		[&"LABEL_TRANSFER_TIME", &"camera_transfer_time"],
		[&"LABEL_MOUSE_INVERT_IN_OUT", &"camera_mouse_in_out_inverse"],
		[&"LABEL_MOUSE_RATE_IN_OUT", &"camera_mouse_in_out_rate"],
		[&"LABEL_MOUSE_RATE_TANGENTIAL", &"camera_mouse_move_rate"],
		[&"LABEL_MOUSE_RATE_PITCH_YAW", &"camera_mouse_pitch_yaw_rate"],
		[&"LABEL_MOUSE_RATE_ROLL", &"camera_mouse_roll_rate"],
		[&"LABEL_KEY_RATE_IN_OUT", &"camera_key_in_out_rate"],
		[&"LABEL_KEY_RATE_TANGENTIAL", &"camera_key_move_rate"],
		[&"LABEL_KEY_RATE_PITCH_YAW", &"camera_key_pitch_yaw_rate"],
		[&"LABEL_KEY_RATE_ROLL", &"camera_key_roll_rate"],
	],
	LABEL_SCREENSHOTS = [
		[&"LABEL_WIDTH", &"screenshot_width"],
		[&"LABEL_ASPECT", &"screenshot_aspect"],
		[&"LABEL_FILE_DIALOG", &"screenshot_file_dialog"],
	],
	LABEL_GUI_AND_HUD = [
		[&"LABEL_LANGUAGE", &"language"],
		[&"LABEL_GUI_SIZE", &"gui_size"],
		[&"LABEL_NAMES_SIZE", &"label3d_names_size_percent"],
		[&"LABEL_SYMBOLS_SIZE", &"body_symbol_size_percent"],
		[&"LABEL_SMALL_BODIES_SYMBOL_SIZE", &"small_bodies_symbol_size_percent"],
		[&"LABEL_SMALL_BODIES_POINT_SIZE", &"small_bodies_point_size"],
		[&"LABEL_HIDE_HUDS_WHEN_CLOSE", &"hide_hud_when_close"],
	],
	LABEL_GRAPHICS_PERFORMANCE = [
		[&"LABEL_ATMOSPHERE_QUALITY", &"atmosphere_quality"],
		[&"LABEL_RENDER_SCALE", &"render_scale"],
		[&"LABEL_SHADOW_RESOLUTION", &"shadow_resolution"],
		[&"LABEL_MSAA", &"msaa_3d"],
		[&"LABEL_FRAME_RATE_CAP", &"frame_rate_cap"],
		[&"LABEL_FXAA", &"fxaa"],
		[&"LABEL_TAA", &"use_taa"],
	],
	LABEL_GRAPHICS_REQUIRES_RESTART = [
		[&"LABEL_RENDERER", &"renderer"],
		[&"LABEL_STAR_CATALOG", &"star_catalog"],
	],
}

## Option enumerations. Enumerations are enums or enum-like dictionaries
## (i.e., sequential integer values from 0 keyed by StringNames). Enumeration
## keys are expected to be translatable. The enumeration is identified by an
## array containing an Object key in [member IVGlobal.program] and a property
## name.
@export var option_enumerations: Dictionary[StringName, Array] = {
	language = [&"LanguageManager", &"language_settings"],
	gui_size = [&"CoreSettings", &"gui_size_settings"],
	atmosphere_quality = [&"GraphicsManager", &"atmosphere_quality_settings"],
	render_scale = [&"GraphicsManager", &"render_scale_settings"],
	msaa_3d = [&"GraphicsManager", &"msaa_settings"],
	shadow_resolution = [&"GraphicsManager", &"shadow_resolution_settings"],
	frame_rate_cap = [&"GraphicsManager", &"frame_rate_cap_settings"],
	renderer = [&"GraphicsManager", &"renderer_settings"],
	star_catalog = [&"GraphicsManager", &"star_catalog_settings"],
	screenshot_aspect = [&"ScreenshotManager", &"aspects"],
}

## Each option Control can be a [CheckBox], [OptionButton], [SpinBox],
## [LineEdit] or [ColorPickerButton]. Control property overrides can be defined
## here as a dictionary keyed by the option. E.g., if an option Control is a
## [SpinBox], properties can include "min_value", "max_value", etc.
@export var option_control_properties: Dictionary[StringName, Dictionary] = {
	camera_transfer_time = {max_value = 10.0},
	label3d_names_size_percent = {min_value = 20, max_value = 500, step = 10, suffix = "%"},
	body_symbol_size_percent = {min_value = 20, max_value = 500, step = 10, suffix = "%"},
	small_bodies_symbol_size_percent = {min_value = 10, max_value = 250, step = 10, suffix = "%"},
	small_bodies_point_size = {min_value = 1, max_value = 20},
	screenshot_width = {min_value = 300, max_value = 8192, step = 2, suffix = "px"},
}

## Option tooltips, keyed by setting. Values are translation keys (Core's are in
## [code]text/hints_text.csv[/code]); an option with no entry has no tooltip.
@export var option_tooltips: Dictionary[StringName, StringName] = {
	save_base_name = &"HINT_SAVE_BASE_NAME",
	append_date_to_save = &"HINT_APPEND_DATE_TO_SAVE",
	pause_on_load = &"HINT_PAUSE_ON_LOAD",
	autosave_time_min = &"HINT_AUTOSAVE_TIME_MIN",
	physical_light = &"HINT_PHYSICAL_LIGHT",
	camera_transfer_time = &"HINT_CAMERA_TRANSFER_TIME",
	camera_mouse_in_out_inverse = &"HINT_CAMERA_MOUSE_IN_OUT_INVERSE",
	camera_mouse_in_out_rate = &"HINT_CAMERA_MOUSE_IN_OUT_RATE",
	camera_mouse_move_rate = &"HINT_CAMERA_MOUSE_MOVE_RATE",
	camera_mouse_pitch_yaw_rate = &"HINT_CAMERA_MOUSE_PITCH_YAW_RATE",
	camera_mouse_roll_rate = &"HINT_CAMERA_MOUSE_ROLL_RATE",
	camera_key_in_out_rate = &"HINT_CAMERA_KEY_IN_OUT_RATE",
	camera_key_move_rate = &"HINT_CAMERA_KEY_MOVE_RATE",
	camera_key_pitch_yaw_rate = &"HINT_CAMERA_KEY_PITCH_YAW_RATE",
	camera_key_roll_rate = &"HINT_CAMERA_KEY_ROLL_RATE",
	screenshot_width = &"HINT_SCREENSHOT_WIDTH",
	screenshot_aspect = &"HINT_SCREENSHOT_ASPECT",
	screenshot_file_dialog = &"HINT_SCREENSHOT_FILE_DIALOG",
	language = &"HINT_LANGUAGE",
	gui_size = &"HINT_GUI_SIZE",
	label3d_names_size_percent = &"HINT_LABEL3D_NAMES_SIZE_PERCENT",
	body_symbol_size_percent = &"HINT_BODY_SYMBOL_SIZE_PERCENT",
	small_bodies_symbol_size_percent = &"HINT_SMALL_BODIES_SYMBOL_SIZE_PERCENT",
	small_bodies_point_size = &"HINT_SMALL_BODIES_POINT_SIZE",
	hide_hud_when_close = &"HINT_HIDE_HUD_WHEN_CLOSE",
	atmosphere_quality = &"HINT_ATMOSPHERE_QUALITY",
	render_scale = &"HINT_RENDER_SCALE",
	shadow_resolution = &"HINT_SHADOW_RESOLUTION",
	msaa_3d = &"HINT_MSAA_3D",
	frame_rate_cap = &"HINT_FRAME_RATE_CAP",
	fxaa = &"HINT_FXAA",
	use_taa = &"HINT_USE_TAA",
	renderer = &"HINT_RENDERER",
	star_catalog = &"HINT_STAR_CATALOG",
}

## Tooltips that replace [member option_tooltips] entries while the Compatibility
## renderer runs, keyed the same way.
@export var option_compatibility_tooltips: Dictionary[StringName, StringName] = {
	atmosphere_quality = &"HINT_COMPATIBILITY_ATMOSPHERE_QUALITY",
	render_scale = &"HINT_COMPATIBILITY_RENDER_SCALE",
	shadow_resolution = &"HINT_COMPATIBILITY_SHADOW_RESOLUTION",
	msaa_3d = &"HINT_COMPATIBILITY_MSAA_3D",
}

var _enumerations: Dictionary[StringName, Dictionary] = {}
var _suppress_close := true


@onready var _content_container: HBoxContainer = %ContentContainer
@onready var _restore_defaults: Button = %RestoreDefaultsButton
@onready var _confirm_changes: Button = %ConfirmChangesButton
@onready var _cancel: Button = %CancelButton
@onready var _restart_warning: Label = %RestartWarningLabel



func _ready() -> void:
	hide() # Godot 4.5 editor keeps setting visibility == true !!!
	IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _shortcut_input(event: InputEvent) -> void:
	if (event.is_action_pressed(&"ui_cancel")
			or IVInputMapManager.is_action_pressed(event, &"toggle_options", true)):
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


## Opens this popup, or closes it as its Cancel button does if it's open.
func toggle() -> void:
	if visible:
		_on_cancel()
	else:
		open()


func set_modal(value: bool) -> void:
	modal = value
	exclusive = value
	popup_window = value


## Add an options section at specified position. (This might be easier than
## adding in the Editor.) Adds at end of column if [param section_index] is
## greater than the number of existing column sections.
func add_section(section_name: StringName, column_index: int, section_index := 999) -> void:
	var column: Array
	if layout.size() > column_index:
		column = layout[column_index]
	else:
		column = []
		layout.append(column)
	section_index = mini(column.size(), section_index)
	column.insert(section_index, section_name)
	if not section_content.has(section_name):
		section_content[section_name] = []


## Add an option in specified section. (This might be easier than adding in the
## Editor.) Adds at end of section if [param option_index] is greater than the
## number of options already in the section. Use [method add_section] first if
## the section doesn't already exist. Use [method IVSettingsManager.set_default]
## first if the setting doesn't already exist.
func add_option(section_name: StringName, option_name: StringName, setting: StringName,
		option_index := 999) -> void:
	assert(section_content.has(section_name),
			"Section '%s' doesn't exist; use add_section() first" % section_name)
	assert(IVSettingsManager.has_setting(setting),
			"Setting '%s' doesn't exist; use IVSettingsManager.set_default() first" % setting)
	var section := section_content[section_name]
	option_index = mini(section.size(), option_index)
	section.insert(option_index, [option_name, setting])
	


func _configure_after_core_inited() -> void:
	IVGlobal.options_requested.connect(toggle)
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
	if autoremove_for_missing_save_plugin and !IVPluginUtils.is_plugin_enabled("ivoyager_save"):
		for column in layout:
			column.erase(&"LABEL_SAVE_LOAD")
	if autoremove_for_na_settings and !IVCoreSettings.enable_physical_light:
		# The physical_light setting only acts through IVExposureManager, which exists
		# only when the core setting enables the system.
		_remove_option(&"physical_light")
	if IVGlobal.is_gl_compatibility:
		# FXAA and TAA are unsupported in the Compatibility renderer (incl. web);
		# the shadow resolution option applies only when Compatibility shadows are on
		# (see IVCoreSettings.apply_gl_compatibility_shadows).
		_remove_option(&"fxaa")
		_remove_option(&"use_taa")
		if not IVCoreSettings.apply_gl_compatibility_shadows:
			_remove_option(&"shadow_resolution")
	if !IVGraphicsManager.can_set_renderer():
		_remove_option(&"renderer")
	if !IVGraphicsManager.can_scale_render():
		_remove_option(&"render_scale")


func _remove_option(setting: StringName) -> void:
	for section: Array in section_content.values():
		for i in range(section.size() - 1, -1, -1):
			var option_array: Array = section[i]
			if option_array[1] == setting:
				section.remove_at(i)


func _build_content() -> void:
	for child in _content_container.get_children():
		_content_container.remove_child(child)
		child.queue_free()
	for column_array in layout:
		var headers := column_array.filter(_has_existing_option)
		if headers.is_empty():
			continue
		var column_vbox := VBoxContainer.new()
		_content_container.add_child(column_vbox)
		for header: StringName in headers:
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
		var mod_resizable := IVControlModResizable.create(Vector2(column_base_width, 0))
		column_vbox.add_child(mod_resizable)
	_on_content_built()


func _has_existing_option(header: StringName) -> bool:
	for option_array: Array in section_content[header]:
		var setting: StringName = option_array[1]
		if IVSettingsManager.has_setting(setting):
			return true
	return false


func _build_item(option_text: StringName, setting: StringName) -> HBoxContainer:
	# Labels ignore the mouse and value Controls stop the tooltip search at themselves,
	# so both the row and its value Control need the tooltip.
	var tooltip: StringName = option_tooltips.get(setting, &"")
	if IVGlobal.is_gl_compatibility:
		tooltip = option_compatibility_tooltips.get(setting, tooltip)
	var setting_hbox := HBoxContainer.new()
	setting_hbox.tooltip_text = tooltip
	var label := Label.new()
	setting_hbox.add_child(label)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = option_text
	var default_button := Button.new()
	default_button.text = default_button_text
	default_button.icon = default_button_icon
	default_button.tooltip_text = default_button_tooltip_text
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
			checkbox.tooltip_text = tooltip
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
				option_button.tooltip_text = tooltip
				_set_overrides(option_button, setting)
				# A value cached before its enumeration lost entries shows as the last entry.
				var index: int = value
				option_button.selected = mini(index, keys.size() - 1)
				option_button.item_selected.connect(_on_change.bind(setting, default_button))
			else: # non-option int or float
				# SpinBox
				var spin_box := SpinBox.new()
				setting_hbox.add_child(spin_box)
				spin_box.alignment = HORIZONTAL_ALIGNMENT_RIGHT
				spin_box.step = 1.0 if is_int else 0.1
				spin_box.rounded = is_int
				spin_box.min_value = 0.0
				spin_box.max_value = 100.0
				spin_box.tooltip_text = tooltip
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
			line_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			line_edit.size_flags_horizontal = Control.SIZE_SHRINK_END
			line_edit.custom_minimum_size.x = 100.0
			line_edit.tooltip_text = tooltip
			_set_overrides(line_edit, setting)
			line_edit.text = value
			line_edit.text_changed.connect(_on_change.bind(setting, default_button))
		TYPE_COLOR:
			# ColorPickerButton
			var color_picker_button := ColorPickerButton.new()
			setting_hbox.add_child(color_picker_button)
			color_picker_button.custom_minimum_size.x = 60.0
			color_picker_button.edit_alpha = false
			color_picker_button.tooltip_text = tooltip
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
	_update_restart_warning()


func _update_restart_warning() -> void:
	var is_restart_pending := IVSettingsManager.is_restart_pending()
	if _restart_warning.visible == is_restart_pending:
		return
	_restart_warning.visible = is_restart_pending
	if !is_restart_pending:
		size.y = 0 # a popup grows to fit its content, but never shrinks back on its own


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
	_update_restart_warning()


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
		@warning_ignore_start("integer_division")
		var center := position + size / 2
		await get_tree().process_frame
		size = Vector2i.ZERO
		position = center - size / 2
