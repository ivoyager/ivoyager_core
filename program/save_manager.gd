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

## Interfaces with [url=https://github.com/ivoyager/ivoyager_save]I, Voyager - Save[/url]
## plugin (if present) to manage saves and loads.
##
## This class does nothing if the Save plugin is not present or is disabled. 

const files := preload("res://addons/ivoyager_core/static/files.gd")
const NO_NETWORK = IVEnums.NetworkState.NO_NETWORK
const IS_SERVER = IVEnums.NetworkState.IS_SERVER
const IS_CLIENT = IVEnums.NetworkState.IS_CLIENT
const NetworkStopSync = IVEnums.NetworkStopSync

const DPRINT := false

const PERSIST_MODE := IVEnums.PERSIST_PROPERTIES_ONLY
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
var _state: Dictionary = IVGlobal.state
var _settings: Dictionary = IVGlobal.settings
var _save_singleton: Node


@onready var _state_manager: IVStateManager = IVGlobal.program[&"StateManager"]
@onready var _timekeeper: IVTimekeeper = IVGlobal.program[&"Timekeeper"]



func _ready() -> void:
	# The Core plugin needs to compile with or without the Save plugin, so
	# we duck type the IVSave singleton. The mess of warnings is unavoidable. 
	_save_singleton = get_node_or_null(^"/root/IVSave")
	if !_save_singleton:
		process_mode = PROCESS_MODE_DISABLED
		#set_process_unhandled_key_input(false)
		return
	process_mode = PROCESS_MODE_ALWAYS
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
	@warning_ignore("unsafe_property_access", "unsafe_cast")
	(_save_singleton.save_started as Signal).connect(_on_save_started)
	@warning_ignore("unsafe_property_access", "unsafe_cast")
	(_save_singleton.save_finished as Signal).connect(_on_save_finished)
	@warning_ignore("unsafe_property_access", "unsafe_cast")
	(_save_singleton.load_started as Signal).connect(_on_load_started)
	@warning_ignore("unsafe_property_access", "unsafe_cast")
	(_save_singleton.about_to_free_procedural_tree_for_load as Signal).connect(
			_on_about_to_free_procedural_tree_for_load)
	@warning_ignore("unsafe_property_access", "unsafe_cast")
	(_save_singleton.about_to_build_procedural_tree_for_load as Signal).connect(
			_on_about_to_build_procedural_tree_for_load)
	@warning_ignore("unsafe_property_access", "unsafe_cast")
	(_save_singleton.load_finished as Signal).connect(_on_load_finished)
	@warning_ignore("unsafe_property_access", "unsafe_cast")
	IVGlobal.close_all_admin_popups_requested.connect(_save_singleton.close_dialogs as Callable)
	
	@warning_ignore("unsafe_property_access", "unsafe_cast")
	(_save_singleton.status_changed as Signal).connect(_on_status_changed)
	
	@warning_ignore("unsafe_property_access", "unsafe_cast")
	(_save_singleton.dialog_opened as Signal).connect(_state_manager.require_stop)
	@warning_ignore("unsafe_property_access", "unsafe_cast")
	(_save_singleton.dialog_closed as Signal).connect(_state_manager.allow_run)
	


func _unhandled_key_input(event: InputEvent) -> void:
	assert(_save_singleton)
	if !event.is_action_type() or !event.is_pressed():
		return
	if event.is_action_pressed(&"quick_save"):
		@warning_ignore("unsafe_method_access")
		_save_singleton.quicksave()
	elif event.is_action_pressed(&"save_as"):
		@warning_ignore("unsafe_method_access")
		_save_singleton.save_file()
	elif event.is_action_pressed(&"quick_load"):
		@warning_ignore("unsafe_method_access")
		_save_singleton.quickload()
	elif event.is_action_pressed(&"load_file"):
		@warning_ignore("unsafe_method_access")
		_save_singleton.load_file()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_status_changed(is_saving: bool, is_loading: bool) -> void:
	if !is_saving and !is_loading:
		IVGlobal.close_main_menu_requested.emit()
		_state_manager.allow_run(self)


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
