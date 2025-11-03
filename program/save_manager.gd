# save_manager.gd
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
class_name IVSaveManager
extends Node

## Interfaces with plugin
## [url=https://github.com/ivoyager/ivoyager_save]I, Voyager - Save[/url]
## (if present) to manage saves and loads.
##
## This manager does nothing if the Save plugin is not present or is disabled. 

const DPRINT := false

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"save_project_version",
	&"save_ivoyager_version",
	&"save_game_mod"
]


## Init value from ProjectSettings. This value is persisted, so it will be saved
## in the gamesave file and overwritten at game load.
var save_project_version: String = ProjectSettings.get_setting("application/config/version")
## Init value from ivoyager_core plugin config. This value is persisted, so it
## will be saved in the gamesave file and overwritten at game load.
var save_ivoyager_version := IVGlobal.ivoyager_version
## Init value from [member IVGlobal.game_mod]. This value is persisted, so it
## will be saved in the gamesave file and overwritten at game load.
var save_game_mod := IVGlobal.game_mod

# private
var _settings := IVGlobal.settings
var _save_singleton: Node

@onready var _timekeeper: IVTimekeeper = IVGlobal.program[&"Timekeeper"]



func _ready() -> void:
	# The Core plugin needs to compile with or without the Save plugin, so we
	# duck type the IVSave singleton here. The mess of warnings is unavoidable. 
	_save_singleton = get_node_or_null(^"/root/IVSave")
	
	if !_save_singleton:
		return

	IVGlobal.simulator_started.connect(_start_autosave_timer)
	IVGlobal.setting_changed.connect(_settings_listener)
	@warning_ignore("unsafe_call_argument", "unsafe_property_access")
	IVGlobal.close_all_admin_popups_requested.connect(_save_singleton.close_dialogs)
	
	@warning_ignore_start("unsafe_property_access", "unsafe_method_access")
	
	# IVSave Callable properties
	_save_singleton.name_generator = _name_generator
	_save_singleton.suffix_generator = _suffix_generator
	_save_singleton.save_permit = _save_permit
	_save_singleton.load_permit = _load_permit
	_save_singleton.save_checkpoint = _save_checkpoint
	_save_singleton.load_checkpoint = _load_checkpoint
	
	# IVSave signal connections
	_save_singleton.save_started.connect(_on_save_started)
	_save_singleton.save_finished.connect(_on_save_finished)
	_save_singleton.load_started.connect(_on_load_started)
	_save_singleton.about_to_free_procedural_nodes.connect(_on_about_to_free_procedural_nodes)
	_save_singleton.about_to_build_procedural_tree_for_load.connect(
			_on_about_to_build_procedural_tree_for_load)
	_save_singleton.load_finished.connect(_on_load_finished)
	_save_singleton.status_changed.connect(_on_status_changed)
	_save_singleton.dialog_opened.connect(IVStateManager.require_stop)
	_save_singleton.dialog_closed.connect(IVStateManager.allow_run)
	
	@warning_ignore_restore("unsafe_property_access", "unsafe_method_access")



func _start_autosave_timer() -> void:
	var autosave_time_min: float = _settings[&"autosave_time_min"]
	@warning_ignore("unsafe_method_access")
	_save_singleton.start_autosave_timer(autosave_time_min) # 0.0 stops the timer


func _on_status_changed(is_saving: bool, is_loading: bool) -> void:
	if !is_saving and !is_loading:
		IVGlobal.close_main_menu_requested.emit()
		IVStateManager.allow_run(self)


func _name_generator() -> String:
	return _settings[&"save_base_name"]


func _suffix_generator() -> String:
	if _settings[&"append_date_to_save"]:
		return "-" + _timekeeper.get_current_date_for_file()
	return ""


func _save_permit() -> bool:
	const IS_CLIENT = IVGlobal.NetworkState.IS_CLIENT
	if not IVStateManager.is_system_built:
		return false
	if IVStateManager.network_state == IS_CLIENT:
		return false
	return true


func _load_permit() -> bool:
	const IS_CLIENT = IVGlobal.NetworkState.IS_CLIENT
	if not (IVStateManager.is_splash_screen or IVStateManager.is_system_built):
		return false
	if IVStateManager.network_state == IS_CLIENT:
		return false
	return true


func _save_checkpoint() -> bool:
	const SAVE = IVGlobal.NetworkStopSync.SAVE
	if !_save_permit():
		return false
	IVStateManager.require_stop(self, SAVE, true)
	await IVStateManager.threads_finished
	return true


func _load_checkpoint() -> bool:
	const LOAD = IVGlobal.NetworkStopSync.LOAD
	if !_load_permit():
		return false
	IVStateManager.require_stop(self, LOAD, true)
	await IVStateManager.threads_finished
	return true


func _on_save_started() -> void:
	pass


func _on_save_finished() -> void:
	pass


func _on_load_started() -> void:
	IVStateManager.set_game_loading()


func _on_about_to_free_procedural_nodes() -> void:
	IVGlobal.about_to_free_procedural_nodes.emit()


func _on_about_to_build_procedural_tree_for_load() -> void:
	pass


func _on_load_finished() -> void:
	IVStateManager.set_game_loaded()
	if !OS.is_debug_build():
		return
	_warn_version_mismatch()
	IVGlobal.simulator_started.connect(_print_node_count, CONNECT_ONE_SHOT)


func _warn_version_mismatch() -> void:
	var ivoyager_version := IVGlobal.ivoyager_version
	if save_ivoyager_version != ivoyager_version:
		push_warning("I, Voyager - Core (plugin) version mismatch: runing %s, loaded %s" % [
				ivoyager_version, save_ivoyager_version])
	var project_version: String = ProjectSettings.get_setting("application/config/version")
	if save_project_version != project_version:
		push_warning("Project version mismatch: runing %s, loaded %s" % [
				project_version, save_project_version])
	var game_mod := IVGlobal.game_mod
	if save_game_mod != game_mod:
		push_warning("Game mod mismatch: runing %s, loaded %s" % [
				game_mod, save_game_mod])


func _print_node_count() -> void:
	print("Nodes in tree after load & sim started: ", get_tree().get_node_count())


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"autosave_time_min":
		_start_autosave_timer()
