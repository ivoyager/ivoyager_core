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

const NO_NETWORK = IVGlobal.NetworkState.NO_NETWORK
const IS_SERVER = IVGlobal.NetworkState.IS_SERVER
const IS_CLIENT = IVGlobal.NetworkState.IS_CLIENT
const NetworkStopSync = IVGlobal.NetworkStopSync

const DPRINT := false

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"save_project_version",
	&"save_ivoyager_version",
	&"is_modded"
]


# persisted - values will be replaced by file values on game load!
var save_project_version: String = IVCoreSettings.project_version
var save_ivoyager_version: String = IVGlobal.ivoyager_version
var is_modded: bool = IVCoreSettings.is_modded

# private
var _state: Dictionary[StringName, Variant] = IVGlobal.state
var _settings: Dictionary[StringName, Variant] = IVGlobal.settings
var _save_singleton: Node

@onready var _state_manager: IVStateManager = IVGlobal.program[&"StateManager"]
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
	_save_singleton.dialog_opened.connect(_state_manager.require_stop)
	_save_singleton.dialog_closed.connect(_state_manager.allow_run)
	
	@warning_ignore_restore("unsafe_property_access", "unsafe_method_access")


func _start_autosave_timer() -> void:
	var autosave_time_min: float = _settings[&"autosave_time_min"]
	@warning_ignore("unsafe_method_access")
	_save_singleton.start_autosave_timer(autosave_time_min) # 0.0 stops the timer


func _on_status_changed(is_saving: bool, is_loading: bool) -> void:
	if !is_saving and !is_loading:
		IVGlobal.close_main_menu_requested.emit()
		_state_manager.allow_run(self)


func _name_generator() -> String:
	return _settings[&"save_base_name"]


func _suffix_generator() -> String:
	if _settings[&"append_date_to_save"]:
		return "-" + _timekeeper.get_current_date_for_file()
	return ""


func _save_permit() -> bool:
	if !_state.is_system_built:
		return false
	if _state.network_state == IS_CLIENT:
		return false
	return true


func _load_permit() -> bool:
	if !(_state.is_splash_screen or _state.is_system_built):
		return false
	if _state.network_state == IS_CLIENT:
		return false
	return true


func _save_checkpoint() -> bool:
	if !_save_permit():
		return false
	_state_manager.require_stop(self, NetworkStopSync.SAVE, true)
	await _state_manager.threads_finished
	return true


func _load_checkpoint() -> bool:
	if !_load_permit():
		return false
	_state_manager.require_stop(self, NetworkStopSync.LOAD, true)
	await _state_manager.threads_finished
	return true


func _on_save_started() -> void:
	pass


func _on_save_finished() -> void:
	pass


func _on_load_started() -> void:
	_state_manager.set_game_loading()


func _on_about_to_free_procedural_nodes() -> void:
	IVGlobal.about_to_free_procedural_nodes.emit()


func _on_about_to_build_procedural_tree_for_load() -> void:
	pass


func _on_load_finished() -> void:
	_state_manager.set_game_loaded()
	if !OS.is_debug_build():
		return
	_warn_version_mismatch()
	IVGlobal.simulator_started.connect(_print_node_count, CONNECT_ONE_SHOT)


func _warn_version_mismatch() -> void:
	if save_ivoyager_version != IVGlobal.ivoyager_version:
		push_warning("I, Voyager - Core (plugin) version mismatch: runing %s, loaded %s" % [
				IVGlobal.ivoyager_version, save_ivoyager_version])
	if save_project_version != IVCoreSettings.project_version:
		push_warning("Project version mismatch: runing %s, loaded %s" % [
				IVCoreSettings.project_version, save_project_version])


func _print_node_count() -> void:
	print("Nodes in tree after load & sim started: ", get_tree().get_node_count())


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"autosave_time_min":
		_start_autosave_timer()
