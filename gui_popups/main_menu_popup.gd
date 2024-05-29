# main_menu_popup.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charlie Whitfield
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
class_name IVMainMenuPopup
extends PopupPanel
const SCENE := "res://addons/ivoyager_core/gui_popups/main_menu_popup.tscn"

## Main Menu popup that opens/closes on 'ui_cancel' action event and IVGlobal 
## signals.
##
## For a base main menu popup without content, use [IVMainMenuBasePopup].

@export var sim_started_only := true
@export var use_theme_manager_setting := true
@export var center := true
@export var stop_sim := true
@export var require_explicit_close := true

@export var include_full_screen_button := false
@export var include_save_button := true
@export var include_load_button := true
@export var include_options_button := true
@export var include_hotkeys_button := true
@export var include_exit_button := true
@export var include_quit_button := true
@export var include_resume_button := true


var _is_explicit_close := false


func _ready() -> void:
	IVGlobal.open_main_menu_requested.connect(open)
	IVGlobal.close_main_menu_requested.connect(close)
	IVGlobal.close_all_admin_popups_requested.connect(close)
	IVGlobal.resume_requested.connect(close)
	popup_hide.connect(_on_popup_hide)
	if use_theme_manager_setting:
		theme = IVGlobal.themes.main_menu
	
	var menu_vbox: VBoxContainer = $MarginContainer/MenuVBox
	if !include_full_screen_button:
		menu_vbox.remove_child($MarginContainer/MenuVBox/FullScreenButton)
	if !include_save_button:
		menu_vbox.remove_child($MarginContainer/MenuVBox/SaveButton)
	if !include_load_button:
		menu_vbox.remove_child($MarginContainer/MenuVBox/LoadButton)
	if !include_options_button:
		menu_vbox.remove_child($MarginContainer/MenuVBox/OptionsButton)
	if !include_hotkeys_button:
		menu_vbox.remove_child($MarginContainer/MenuVBox/HotkeysButton)
	if !include_exit_button:
		menu_vbox.remove_child($MarginContainer/MenuVBox/ExitButton)
	if !include_quit_button:
		menu_vbox.remove_child($MarginContainer/MenuVBox/QuitButton)
	if !include_resume_button:
		menu_vbox.remove_child($MarginContainer/MenuVBox/ResumeButton)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		close()
		set_input_as_handled()


func open() -> void:
	if visible:
		return
	if sim_started_only and !IVGlobal.state.is_started_or_about_to_start:
		return
	if stop_sim:
		IVGlobal.sim_stop_required.emit(self)
	_is_explicit_close = false
	if center:
		popup_centered()
	else:
		popup()


func close() -> void:
	_is_explicit_close = true
	hide()


func _on_popup_hide() -> void:
	if require_explicit_close and !_is_explicit_close:
		show.call_deferred()
		return
	_is_explicit_close = false
	if stop_sim:
		IVGlobal.sim_run_allowed.emit(self)

