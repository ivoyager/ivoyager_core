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

## User hotkeys popup.
##
## User hotkeys are are a subset of the cached input map managed by
## [IVInputMapManager].[br][br]
##
## This popup builds hotkey Control items on-the-fly as defined in class
## properties. Columns and section headers are defined in [member layout] and
## section content is defined in [member section_content].[br][br]
##
## TODO: "Views" will have hotkeys too, which can be edited in the view button's
## IVViewEdit but possibly also in their own section here.
## Implementation is confusing because views can be persisted via
## cache or gamesave. Should views persist their own hotkeys? If so, how does
## that work with IVInputMapManager? One possibility is to code all of these
## as cached "actions" via IVInputMapManager (even the gamesave ones). Probably
## gamesave view hotkeys should overwrite confilicting cache hotkeys on load.


## Stop the simulator while this popup is open. This setting will be overridden
## if [member IVCoreSettings.popops_can_stop_sim] == false.
@export var stop_sim := true
@export var item_min_size_x := 300

## Enable automatic removal of items based on [IVCoreSettings] or plugin status.
## For example, save/load related hotkeys are removed if the Save plugin is not
## present.
@export var enable_auto_removes := false


## Content layout is an array of columns, where each column is an array of 
## header labels. The header labels must correspond to keys in [member
## section_content].
@export var layout: Array[Array] = [
	# column 1
	[&"LABEL_ADMIN", &"LABEL_GUI", &"LABEL_TIME"],
	# column 2
	[&"LABEL_SELECTION"],
	# column 3
	[&"LABEL_CAMERA"],
]


## Section keys are the header labels used in [member layout]. Each section
## is an array of actions, where actions are defined in [IVInputMapManager].
## Note: Unlike Options, it IS necessary to remove sections or items here that
## aren't used. This is necessary so that the hotkeys aren't reserved.
@export var section_content: Dictionary[StringName, Array] = {
	LABEL_ADMIN = [
		&"toggle_fullscreen",
		&"toggle_options",
		&"toggle_hotkeys",
		&"load_file",
		&"quickload",
		&"save_as",
		&"quicksave",
		&"quit",
		&"save_quit",
	],
	LABEL_GUI = [
		&"toggle_all_gui",
		&"toggle_orbits",
		&"toggle_names",
		&"toggle_symbols",
	],
	LABEL_TIME = [
		&"incr_speed",
		&"decr_speed",
		&"reverse_time",
		&"toggle_pause",
	],
	LABEL_SELECTION = [
		&"select_up",
		&"select_down",
		&"select_left",
		&"select_right",
		&"select_forward",
		&"select_back",
		&"next_star",
		&"next_planet",
		&"previous_planet",
		&"next_nav_moon",
		&"previous_nav_moon",
		&"next_moon",
		&"previous_moon",
	],
	LABEL_CAMERA = [
		&"camera_up",
		&"camera_down",
		&"camera_left",
		&"camera_right",
		&"camera_in",
		&"camera_out",
		&"recenter",
		&"pitch_up",
		&"pitch_down",
		&"yaw_left",
		&"yaw_right",
		&"roll_left",
		&"roll_right",
	],
	# TODO: LABEL_VIEWS = [],
	# This section will be filled dynamically by IVViewManager.
}


var _input_map_manager: IVInputMapManager
var _suppress_close := true

@onready var _hotkey_dialog: IVHotkeyDialog = $HotkeyDialog
@onready var _content_container: HBoxContainer = %ContentContainer
@onready var _restore_defaults: Button = %RestoreDefaultsButton
@onready var _confirm_changes: Button = %ConfirmChangesButton
@onready var _cancel: Button = %CancelButton



func _ready() -> void:
	hide() # Godot 4.5 editor keeps setting visibility == true !!!
	IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _shortcut_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"toggle_hotkeys", true):
		_on_cancel()
		set_input_as_handled()


func _configure_after_core_inited() -> void:
	_input_map_manager = IVGlobal.program[&"InputMapManager"]
	IVGlobal.hotkeys_requested.connect(open)
	IVGlobal.close_admin_popups_required.connect(hide)
	close_requested.connect(_on_close_requested)
	popup_hide.connect(_on_popup_hide)
	_cancel.pressed.connect(_on_cancel)
	_restore_defaults.pressed.connect(_on_restore_defaults)
	_confirm_changes.pressed.connect(_on_confirm_changes)
	_hotkey_dialog.hotkey_confirmed.connect(_on_hotkey_confirmed)
	
	
	#if IVCoreSettings.disable_pause:
		#remove_item(&"toggle_pause")
	#if !IVCoreSettings.allow_time_reversal:
		#remove_item(&"reverse_time")
	#if !IVPluginUtils.is_plugin_enabled("ivoyager_save"):
		#remove_item(&"load_file")
		#remove_item(&"quickload")
		#remove_item(&"save_as")
		#remove_item(&"quicksave")
		#remove_item(&"save_quit")
	#if IVCoreSettings.disable_quit:
		#remove_item(&"quit")


func open() -> void:
	if visible:
		return
	#if _is_blocking_popup():
		#return
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
			for action: StringName in section:
				var hotkey_text := _input_map_manager.action_texts[action]
			
			#for hotkey_array: Array in section:
				#var hotkey_text: StringName = hotkey_array[0]
				#var action: StringName = hotkey_array[1]
				var hotkey_hbox := _build_item(hotkey_text, action)
				subpanel_vbox.add_child(hotkey_hbox)
	_on_content_built.call_deferred()


func _on_content_built() -> void:
	_restore_defaults.disabled = _input_map_manager.is_defaults()
	_confirm_changes.disabled = _input_map_manager.is_cache_current()


func _build_item(hotkey_text: StringName, action: StringName) -> HBoxContainer:
	var action_hbox := HBoxContainer.new()
	action_hbox.custom_minimum_size.x = item_min_size_x
	var action_label := Label.new()
	action_hbox.add_child(action_label)
	action_label.size_flags_horizontal = BoxContainer.SIZE_EXPAND_FILL
	action_label.text = hotkey_text
	var index := 0
	var scancodes := _input_map_manager.get_scancodes_w_mods_for_action(action)
	for keycode in scancodes:
		var key_button := Button.new()
		action_hbox.add_child(key_button)
		key_button.text = OS.get_keycode_string(keycode)
		key_button.pressed.connect(_hotkey_dialog.open.bind(action, index, hotkey_text,
				key_button.text, section_content))
		index += 1
	var add_key_button := Button.new()
	action_hbox.add_child(add_key_button)
	add_key_button.text = "+"
	add_key_button.pressed.connect(_hotkey_dialog.open.bind(action, index, hotkey_text,
			"", section_content))
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
	_suppress_close = false
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
	_suppress_close = false
	hide()


func _on_cancel() -> void:
	if _input_map_manager.is_cache_current():
		_suppress_close = false
		hide()
		return
	IVGlobal.confirmation_required.emit(&"LABEL_Q_CANCEL_HOTKEY_CHANGES", _cancel_changes, true,
			&"LABEL_PLEASE_CONFIRM", &"BUTTON_CANCEL_CHANGES", &"BUTTON_BACK")


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


func _on_close_requested() -> void:
	# Godot 4.1.1 ... 4.5 ISSUE: close_requested signal is useless. See:
	# https://github.com/godotengine/godot/issues/76896#issuecomment-1667027253
	# Also, hide() is done by the engine, contrary to docs.
	# If this is fixed we can remove the '_suppress_close' hack.
	print("Popup.close_requested signal works now! Maybe we can remove hack fixes...")
