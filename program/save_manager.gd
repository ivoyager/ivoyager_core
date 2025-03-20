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
extends Timer

## Interfaces with plugin [url=https://github.com/ivoyager/ivoyager_save]I, Voyager - Save[/url]
## (if present) to manage saves and loads.
##
## This class does nothing if the Save plugin is not present or is disabled. 

const files := preload("res://addons/ivoyager_core/static/files.gd")
const NO_NETWORK = IVGlobal.NetworkState.NO_NETWORK
const IS_SERVER = IVGlobal.NetworkState.IS_SERVER
const IS_CLIENT = IVGlobal.NetworkState.IS_CLIENT
const NetworkStopSync = IVGlobal.NetworkStopSync

const DPRINT := false

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"project_version",
	&"ivoyager_version",
	&"is_modded"
]

# persisted - values will be replaced by file values on game load!
var project_version: String = IVCoreSettings.project_version
var ivoyager_version: String = IVGlobal.ivoyager_version
var is_modded: bool = IVCoreSettings.is_modded



# private
var _state: Dictionary[StringName, Variant] = IVGlobal.state
var _settings: Dictionary[StringName, Variant] = IVGlobal.settings
var _save_singleton: Node


@onready var _state_manager: IVStateManager = IVGlobal.program[&"StateManager"]
@onready var _timekeeper: IVTimekeeper = IVGlobal.program[&"Timekeeper"]



func _ready() -> void:
	# The Core plugin needs to compile with or without the Save plugin, so
	# we duck type the IVSave singleton. The mess of warnings is unavoidable. 
	_save_singleton = get_node_or_null(^"/root/IVSave")
	
	if !_save_singleton:
		process_mode = PROCESS_MODE_DISABLED
		return
	
	process_mode = PROCESS_MODE_ALWAYS
	timeout.connect(_on_timeout)
	IVGlobal.simulator_started.connect(_start_autosave_timer)
	IVGlobal.run_state_changed.connect(_on_run_state_changed)
	IVGlobal.setting_changed.connect(_settings_listener)
	
	@warning_ignore("unsafe_property_access")
	_save_singleton.name_generator = _name_generator
	@warning_ignore("unsafe_property_access")
	_save_singleton.suffix_generator = _suffix_generator
	@warning_ignore("unsafe_property_access")
	_save_singleton.save_permission_test = _save_permission_test
	@warning_ignore("unsafe_property_access")
	_save_singleton.load_permission_test = _load_permission_test
	@warning_ignore("unsafe_property_access")
	_save_singleton.save_checkpoint = _save_checkpoint
	@warning_ignore("unsafe_property_access")
	_save_singleton.load_checkpoint = _load_checkpoint
	
	@warning_ignore("unsafe_property_access", "unsafe_method_access")
	_save_singleton.save_started.connect(_on_save_started)
	@warning_ignore("unsafe_property_access", "unsafe_method_access")
	_save_singleton.save_finished.connect(_on_save_finished)
	@warning_ignore("unsafe_property_access", "unsafe_method_access")
	_save_singleton.load_started.connect(_on_load_started)
	@warning_ignore("unsafe_property_access", "unsafe_method_access")
	_save_singleton.about_to_free_procedural_tree_for_load.connect(
			_on_about_to_free_procedural_tree_for_load)
	@warning_ignore("unsafe_property_access", "unsafe_method_access")
	_save_singleton.about_to_build_procedural_tree_for_load.connect(
			_on_about_to_build_procedural_tree_for_load)
	@warning_ignore("unsafe_property_access", "unsafe_method_access")
	_save_singleton.load_finished.connect(_on_load_finished)
	@warning_ignore("unsafe_property_access", "unsafe_method_access")
	_save_singleton.status_changed.connect(_on_status_changed)
	@warning_ignore("unsafe_property_access", "unsafe_method_access")
	_save_singleton.dialog_opened.connect(_state_manager.require_stop)
	@warning_ignore("unsafe_property_access", "unsafe_method_access")
	_save_singleton.dialog_closed.connect(_state_manager.allow_run)
	@warning_ignore("unsafe_property_access", "unsafe_call_argument")
	IVGlobal.close_all_admin_popups_requested.connect(_save_singleton.close_dialogs)


func _start_autosave_timer() -> void:
	var autosave_time_min: float = _settings[&"autosave_time_min"]
	if autosave_time_min == 0:
		stop()
		return
	start(autosave_time_min * 60)


func _on_timeout() -> void:
	@warning_ignore("unsafe_method_access")
	_save_singleton.autosave()
	_start_autosave_timer()


func _on_run_state_changed(is_running: bool) -> void:
	paused = !is_running


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


func _save_permission_test() -> bool:
	if !_state.is_system_built:
		return false
	if _state.network_state == IS_CLIENT:
		return false
	return true


func _load_permission_test() -> bool:
	if !(_state.is_splash_screen or _state.is_system_built):
		return false
	if _state.network_state == IS_CLIENT:
		return false
	return true


func _save_checkpoint() -> bool:
	if !_save_permission_test():
		return false
	_state_manager.require_stop(self, NetworkStopSync.SAVE, true)
	await _state_manager.threads_finished
	return true


func _load_checkpoint() -> bool:
	if !_load_permission_test():
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


func _on_about_to_free_procedural_tree_for_load() -> void:
	IVGlobal.about_to_free_procedural_nodes.emit()


func _on_about_to_build_procedural_tree_for_load() -> void:
	pass


func _on_load_finished() -> void:
	_warn_if_versions_mismatch()
	_state_manager.set_game_loaded()
	IVGlobal.simulator_started.connect(_print_node_count, CONNECT_ONE_SHOT)


func _warn_if_versions_mismatch() -> void:
	if ivoyager_version != IVGlobal.ivoyager_version:
		push_warning("I, Voyager - Core (plugin) version mismatch: runing %s, loaded %s" % [
				IVGlobal.ivoyager_version, ivoyager_version])
	if project_version != IVCoreSettings.project_version:
		push_warning("Project version mismatch: runing %s, loaded %s" % [
				IVCoreSettings.project_version, project_version])


func _print_node_count() -> void:
	print("Nodes in tree after load & sim started: ", get_tree().get_node_count())
	print("If unexpected relative to pre-save, set DEBUG_PRINT_NODES in ivoyager_save/save.gd.")


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"autosave_time_min":
		_start_autosave_timer()
