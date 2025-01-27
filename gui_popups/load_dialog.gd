# load_dialog.gd
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
class_name IVLoadDialog
extends FileDialog
const SCENE := "res://addons/ivoyager_core/gui_popups/load_dialog.tscn"

# Key actions for save/load are handled in save_manager.gd.

const files := preload("res://addons/ivoyager_core/static/files.gd")


var _state: Dictionary = IVGlobal.state
var _blocking_windows: Array[Window] = IVGlobal.blocking_windows


func _ready() -> void:
	if !IVPluginUtils.is_plugin_enabled("ivoyager_tree_saver"):
		return
	add_filter("*." + IVCoreSettings.save_file_extension + ";"
			+ IVCoreSettings.save_file_extension_name)
	IVGlobal.load_dialog_requested.connect(_open)
	IVGlobal.close_all_admin_popups_requested.connect(_close)
	file_selected.connect(_load_file)
	canceled.connect(_on_canceled)
	process_mode = PROCESS_MODE_ALWAYS
	theme = IVGlobal.themes.main
	_blocking_windows.append(self)



func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		set_input_as_handled()


func _open() -> void:
	if visible:
		return
	if _is_blocking_popup():
		return
	IVGlobal.sim_stop_required.emit(self)
	popup_centered()
	access = ACCESS_FILESYSTEM
	var settings_save_dir: String = IVGlobal.settings[&"save_dir"]
	var save_dir := files.get_save_dir_path(IVCoreSettings.is_modded, settings_save_dir)
	current_dir = save_dir
	if _state.last_save_path:
		current_path = _state.last_save_path
		deselect_all()


func _close() -> void:
	hide()
	_on_canceled()


func _load_file(path: String) -> void:
	IVGlobal.close_main_menu_requested.emit()
	IVGlobal.load_requested.emit(path, false)


func _on_canceled() -> void:
	IVGlobal.sim_run_allowed.emit(self)


func _is_blocking_popup() -> bool:
	for window in _blocking_windows:
		if window.visible:
			return true
	return false
