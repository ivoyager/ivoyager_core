# main_menu_manager.gd
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
class_name IVMainMenuManager
extends RefCounted

## Maintains button state for a main menu.

signal buttons_changed()
signal button_state_changed()

enum {ACTIVE, DISABLED, HIDDEN} # button_state

# project var
var button_inits: Array[Array] = [
	# External project can modify this array at _ivcore_init() or use API
	# below. "target" here must be a key in IVGlobal.program. Core buttons here
	# may be excluded depending on IVCoreSettings project settings.
	# [text, priority, is_splash, is_running, target_name, method, args]
	[&"BUTTON_START", 1100, true, false, &"SystemBuilder", &"build_system_tree"],
	[&"BUTTON_SAVE_AS", 1000, false, true, &"SaveManager", &"save_game"],
	[&"BUTTON_QUICK_SAVE", 900, false, true, &"SaveManager", &"quick_save"],
	[&"BUTTON_LOAD_FILE", 800, true, true, &"SaveManager", &"load_game"],
	[&"BUTTON_QUICK_LOAD", 700, false, true, &"SaveManager", &"quick_load"],
	[&"BUTTON_OPTIONS", 600, true, true, &"OptionsPopup", &"open"],
	[&"BUTTON_HOTKEYS", 500, true, true, &"HotkeysPopup", &"open"],
	[&"BUTTON_EXIT", 300, false, true, &"StateManager", &"exit"],
	[&"BUTTON_QUIT", 200, true, true, &"StateManager", &"quit"],
	[&"BUTTON_RESUME", 100, false, true, &"MainMenuPopup", &"close"],
] 

# read-only!
var button_infos: Array[Array] = []


func _ivcore_init() -> void:
	IVGlobal.project_inited.connect(_init_buttons)
	IVGlobal.about_to_quit.connect(_clear_for_quit)


func _init_buttons() -> void:
	for init_info in button_inits:
		var text: StringName = init_info[0]
		var target_name: StringName = init_info[4]
		if !IVGlobal.program.has(target_name):
			continue
		var skip := false
		match text:
			&"BUTTON_START":
				skip = IVCoreSettings.skip_splash_screen
			&"BUTTON_SAVE_AS", &"BUTTON_QUICK_SAVE", &"BUTTON_LOAD_FILE", &"BUTTON_QUICK_LOAD":
				skip = !IVGlobal.tree_saver_enabled
			&"BUTTON_EXIT":
				skip = IVCoreSettings.disable_exit or IVCoreSettings.skip_splash_screen
			&"BUTTON_QUIT":
				skip = IVCoreSettings.disable_quit
		if skip:
			continue
		var priority: int = init_info[1]
		var is_splash: bool = init_info[2]
		var is_running: bool = init_info[3]
		var target: Object = IVGlobal.program[target_name]
		var method: StringName = init_info[5]
		var has_args: bool = init_info.size() > 6
		var args: Array = init_info[6] if has_args else []
		make_button(text, priority, is_splash, is_running, target, method, args)


func _clear_for_quit() -> void:
	button_infos.clear()


func make_button(text: StringName, priority: int, is_splash: bool, is_running: bool,
		target: Object, method: String, args := [], button_state := ACTIVE) -> void:
	# Highest priority will be top menu item.
	button_infos.append([text, priority, is_splash, is_running, target, method, args, button_state])
	button_infos.sort_custom(_sort_button_infos)
	buttons_changed.emit()


func remove_button(text: StringName) -> void:
	var i := 0
	while i < button_infos.size():
		if button_infos[i][0] == text:
			button_infos.remove_at(i)
			buttons_changed.emit()
			return
		i += 1


func change_button_state(text: StringName, button_state: int) -> void:
	for button_info in button_infos:
		if text == button_info[0]:
			button_info[7] = button_state
			break
	button_state_changed.emit()


func _sort_button_infos(a: Array, b: Array) -> bool:
	return a[1] > b[1] # priority

