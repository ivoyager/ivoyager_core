# hotkeys_popup.gd
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
class_name IVHotkeysPopup
extends PopupPanel
const SCENE := "res://addons/ivoyager_core/gui_popups/hotkeys_popup.tscn"


@export var stop_sim := true
@export var key_box_min_size_x := 300
@export var layout: Array[Array] = [
	# column 1
	[
		{
			&"header" : &"LABEL_ADMIN",
			&"toggle_fullscreen" : &"LABEL_TOGGLE_FULLSCREEN",
			&"toggle_options" : &"LABEL_OPTIONS",
			&"toggle_hotkeys" : &"LABEL_HOTKEYS",
			&"load_file" : &"LABEL_LOAD_FILE",
			&"quickload" : &"LABEL_QUICKLOAD",
			&"save_as" : &"LABEL_SAVE_AS",
			&"quicksave" : &"LABEL_QUICKSAVE",
			&"quit" : &"LABEL_QUIT",
			&"save_quit" : &"LABEL_SAVE_AND_QUIT",
		},
		{
			&"header" : &"LABEL_GUI",
			&"toggle_all_gui" : &"LABEL_SHOW_HIDE_ALL_GUI",
			&"toggle_orbits" : &"LABEL_SHOW_HIDE_ORBITS",
			&"toggle_names" : &"LABEL_SHOW_HIDE_NAMES",
			&"toggle_symbols" : &"LABEL_SHOW_HIDE_SYMBOLS",
			
			# Below two should be added by extension add_item(), if used.
			# See Planetarim project (planetarium/planetarium.gd).
#				&"cycle_next_panel" : &"LABEL_CYCLE_NEXT_PANEL",
#				&"cycle_prev_panel" : &"LABEL_CYCLE_LAST_PANEL",
			
			# Below UI controls have some engine hardcoding as of
			# Godot 3.2.2, so can't be user defined.
#				&"ui_up" : &"LABEL_GUI_UP",
#				&"ui_down" : &"LABEL_GUI_DOWN",
#				&"ui_left" : &"LABEL_GUI_LEFT",
#				&"ui_right" : &"LABEL_GUI_RIGHT",
		},
		{
			&"header" : &"LABEL_TIME",
			&"incr_speed" : &"LABEL_SPEED_UP",
			&"decr_speed" : &"LABEL_SLOW_DOWN",
			&"reverse_time" : &"LABEL_REVERSE_TIME",
			&"toggle_pause" : &"LABEL_TOGGLE_PAUSE",
		},
		
	],
	
	# column 2
	[
		{
			&"header" : &"LABEL_SELECTION",
			&"select_up" : &"LABEL_UP",
			&"select_down" : &"LABEL_DOWN",
			&"select_left" : &"LABEL_LAST",
			&"select_right" : &"LABEL_NEXT",
			&"select_forward" : &"LABEL_FORWARD",
			&"select_back" : &"LABEL_BACK",
			&"next_star" : &"LABEL_SELECT_SUN",
			&"next_planet" : &"LABEL_NEXT_PLANET",
			&"previous_planet" : &"LABEL_LAST_PLANET",
			&"next_nav_moon" : &"LABEL_NEXT_NAV_MOON",
			&"previous_nav_moon" : &"LABEL_LAST_NAV_MOON",
			&"next_moon" : &"LABEL_NEXT_ANY_MOON",
			&"previous_moon" : &"LABEL_LAST_ANY_MOON",
			# Below waiting for new code features
#			&"next_system" : &"Select System",
#			&"next_asteroid" : &"Next Asteroid",
#			&"previous_asteroid" : &"Last Asteroid",
#			&"next_comet" : &"Next Comet",
#			&"previous_comet" : &"Last Comet",
#			&"next_spacecraft" : &"Next Spacecraft",
#			&"previous_spacecraft" : &"Last Spacecraft",
		},
	],
	
	# column 3
	[
		{
			&"header" : &"LABEL_CAMERA",
			&"camera_up" : &"LABEL_MOVE_UP",
			&"camera_down" : &"LABEL_MOVE_DOWN",
			&"camera_left" : &"LABEL_MOVE_LEFT",
			&"camera_right" : &"LABEL_MOVE_RIGHT",
			&"camera_in" : &"LABEL_MOVE_IN",
			&"camera_out" : &"LABEL_MOVE_OUT",
			&"recenter" : &"LABEL_RECENTER",
			&"pitch_up" : &"LABEL_PITCH_UP",
			&"pitch_down" : &"LABEL_PITCH_DOWN",
			&"yaw_left" : &"LABEL_YAW_LEFT",
			&"yaw_right" : &"LABEL_YAW_RIGHT",
			&"roll_left" : &"LABEL_ROLL_LEFT",
			&"roll_right" : &"LABEL_ROLL_RIGHT",
		},
	],
]


var _hotkey_dialog: IVHotkeyDialog
var _blocking_windows: Array[Window] = IVGlobal.blocking_windows
var _allow_close := false

@onready var _input_map_manager: IVInputMapManager = IVGlobal.program[&"InputMapManager"]
@onready var _content_container: HBoxContainer = $VBox/Content
@onready var _cancel: Button = $VBox/BottomHBox/Cancel
@onready var _confirm_changes: Button = $VBox/BottomHBox/ConfirmChanges
@onready var _restore_defaults: Button = $VBox/BottomHBox/RestoreDefaults



func _ready() -> void:
	IVGlobal.hotkeys_requested.connect(open)
	IVGlobal.close_all_admin_popups_requested.connect(hide)
	close_requested.connect(_on_close_requested)
	popup_hide.connect(_on_popup_hide)
	exclusive = false # Godot ISSUE? not editable in scene?
	
	_cancel.pressed.connect(_on_cancel)
	_restore_defaults.pressed.connect(_on_restore_defaults)
	_confirm_changes.pressed.connect(_on_confirm_changes)
	_blocking_windows.append(self)

	_hotkey_dialog = IVFiles.make_object_or_scene(IVHotkeyDialog)
	_hotkey_dialog.hotkey_confirmed.connect(_on_hotkey_confirmed)
	add_child(_hotkey_dialog)
	
	if IVCoreSettings.disable_pause:
		remove_item(&"toggle_pause")
	if !IVCoreSettings.allow_time_reversal:
		remove_item(&"reverse_time")
	if !IVPluginUtils.is_plugin_enabled("ivoyager_save"):
		remove_item(&"load_file")
		remove_item(&"quickload")
		remove_item(&"save_as")
		remove_item(&"quicksave")
		remove_item(&"save_quit")
	if IVCoreSettings.disable_quit:
		remove_item(&"quit")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		set_input_as_handled()
		_on_cancel()


# public

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
	# See example subpanel_dict formats in IVOptionsPopup or IVHotkeysPopup.
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


# private

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
	_on_content_built.call_deferred()


func _on_content_built() -> void:
	_restore_defaults.disabled = _input_map_manager.is_defaults()
	_confirm_changes.disabled = _input_map_manager.is_cache_current()


func _build_item(action: StringName, action_label_str: StringName) -> HBoxContainer:
	var action_hbox := HBoxContainer.new()
	action_hbox.custom_minimum_size.x = key_box_min_size_x
	var action_label := Label.new()
	action_hbox.add_child(action_label)
	action_label.size_flags_horizontal = BoxContainer.SIZE_EXPAND_FILL
	action_label.text = action_label_str
	var index := 0
	var scancodes := _input_map_manager.get_scancodes_w_mods_for_action(action)
	for keycode in scancodes:
		var key_button := Button.new()
		action_hbox.add_child(key_button)
		key_button.text = OS.get_keycode_string(keycode)
		key_button.pressed.connect(_hotkey_dialog.open.bind(action, index, action_label_str,
				key_button.text, layout))
		index += 1
	var add_key_button := Button.new()
	action_hbox.add_child(add_key_button)
	add_key_button.text = "+"
	add_key_button.pressed.connect(_hotkey_dialog.open.bind(action, index, action_label_str,
			"", layout))
	var default_button := Button.new()
	action_hbox.add_child(default_button)
	default_button.text = "!"
	default_button.disabled = _input_map_manager.is_default(action)
	default_button.pressed.connect(_restore_default.bind(action))
	return action_hbox


func _restore_default(action: StringName) -> void:
	_input_map_manager.restore_default(action, true)
	_build_content.call_deferred()


func _cancel_changes() -> void:
	_input_map_manager.restore_from_cache()
	_allow_close = true
	hide()


func _on_hotkey_confirmed(action: StringName, index: int, keycode: int,
		control: bool, alt: bool, shift: bool, meta: bool) -> void:
	if keycode == -1:
		_input_map_manager.remove_event_dict_by_index(action, &"InputEventKey", index, true)
	else:
		var event_dict := {event_class = &"InputEventKey", keycode = keycode}
		if control:
			event_dict.ctrl_pressed = true
		if alt:
			event_dict.alt_pressed = true
		if shift:
			event_dict.shift_pressed = true
		if meta:
			event_dict.meta_pressed = true
		print("Set ", action, ": ", event_dict)
		_input_map_manager.set_action_event_dict(action, event_dict, index, true)
	_build_content.call_deferred()


func _on_restore_defaults() -> void:
	_input_map_manager.restore_defaults(true)
	_build_content.call_deferred()


func _on_confirm_changes() -> void:
	_input_map_manager.cache_now()
	_allow_close = true
	hide()


func _on_cancel() -> void:
	if _input_map_manager.is_cache_current():
		_allow_close = true
		hide()
		return
	IVGlobal.confirmation_requested.emit(&"LABEL_Q_CANCEL_HOTKEY_CHANGES", _cancel_changes, true,
			&"LABEL_PLEASE_CONFIRM", &"BUTTON_CANCEL_CHANGES", &"BUTTON_BACK")


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
