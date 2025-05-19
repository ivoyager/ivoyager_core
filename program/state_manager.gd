# state_manager.gd
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
class_name IVStateManager
extends Node

## Maintains high-level simulator state.
##
## General simulator state signals are emitted by IVGlobal, with more specific
## emitted by this class. Much of simulator state can be queried via dictionary
## [code]state[/code] in IVGlobal. This class defines certain expected keys
## in [code]state[/code] and (together with [IVSaveManager] and possibly an
## external NetworkLobby) manages these [code]state[/code] values.[br][br]
##
## IVGlobal [code]state[/code] keys inited here:[br][br]
##   [code]is_inited: bool[/code]
##   [code]is_splash_screen: bool[/code][br]
##   [code]is_system_built: bool[/code][br]
##   [code]is_system_ready: bool[/code][br]
##   [code]is_started_or_about_to_start: bool[/code][br]
##   [code]is_running: bool[/code] - _run/_stop_simulator(); not the same as pause![br]
##   [code]is_quitting: bool[/code][br]
##   [code]is_game_loading: bool[/code] - via method call[br]
##   [code]is_loaded_game: bool[/code] - via method cal[br]
##   [code]network_state: IVGlobal.NetworkState[/code] - if exists, NetworkLobby also writes[br][br]
##
## If IVCoreSettings.pause_only_stops_time == true, then PAUSE_MODE_PROCESS is
## set in Universe and TopGUI so IVCamera can still move, visuals work (some are
## responsve to camera) and user can interact with the world. In this mode, only
## IVTimekeeper pauses to stop time.[br][br]
##
## There is no NetworkLobby in base I, Voyager. It's is a very application-
## specific manager that you'll have to code yourself, but see:
## https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
## Be sure to set IVGlobal.state.network_state and emit IVGlobal signal
## "network_state_changed".[br][br]
##
## IMPORTANT! Non-main threads should coordinate with signals and functions here
## for thread-safety. We wait for all threads to finish before proceding to save,
## load, exit, quit, etc.[br][br]
##
## Multithreading note: Godot's SceneTree and almost all I, Voyager public
## functions run in the main thread. Use call_defered() to invoke any function
## from another thread unless the function is guaranteed to be thread-safe. Most
## functions are NOT thread-safe![br][br]

signal run_threads_allowed() # ok to start threads that affect gamestate
signal run_threads_must_stop() # finish threads that affect gamestate
signal threads_finished() # all blocking threads removed
signal client_is_dropping_out(is_exit: bool)
signal server_about_to_stop(network_sync_type: int) # IVGlobal.NetworkStopSync; server only
signal server_about_to_run() # server only

const NO_NETWORK = IVGlobal.NetworkState.NO_NETWORK
const IS_SERVER = IVGlobal.NetworkState.IS_SERVER
const IS_CLIENT = IVGlobal.NetworkState.IS_CLIENT
const NetworkStopSync = IVGlobal.NetworkStopSync

const DPRINT := false

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [&"is_user_paused"]

# project setting
var use_tree_saver_deconstruction_if_present := true

# persisted - read-only!
var is_user_paused := false # ignores pause from sim stop

# read-only!
var allow_threads := false
var blocking_threads := []

# private
var _state: Dictionary[StringName, Variant] = IVGlobal.state
var _settings: Dictionary[StringName, Variant] = IVGlobal.settings
var _nodes_requiring_stop := []
var _signal_when_threads_finished := false
var _tree_build_counter := 0

@onready var _tree: SceneTree = get_tree()


# *****************************************************************************
# virtual functions

func _init() -> void:
	IVGlobal.project_builder_finished.connect(_on_project_builder_finished, CONNECT_ONE_SHOT)
	IVGlobal.asset_preloader_finished.connect(_on_asset_preloader_finished, CONNECT_ONE_SHOT)
	IVGlobal.about_to_build_system_tree.connect(_on_about_to_build_system_tree)
	IVGlobal.system_tree_built_or_loaded.connect(_on_system_tree_built_or_loaded)
	IVGlobal.add_system_tree_item_started.connect(_increment_tree_build_counter)
	IVGlobal.add_system_tree_item_finished.connect(_decrement_tree_build_counter)
	IVGlobal.system_tree_ready.connect(_on_system_tree_ready)
	IVGlobal.simulator_exited.connect(_on_simulator_exited)
	IVGlobal.change_pause_requested.connect(change_pause)
	IVGlobal.start_requested.connect(build_system_tree_from_tables)
	IVGlobal.sim_stop_required.connect(require_stop)
	IVGlobal.sim_run_allowed.connect(allow_run)
	IVGlobal.quit_requested.connect(quit)
	IVGlobal.exit_requested.connect(exit)
	
	_state.is_inited = false
	_state.is_splash_screen = false
	_state.is_assets_loaded = false
	_state.is_ok_to_start = false
	_state.is_building_tree = false # new or loading game
	_state.is_system_built = false
	_state.is_system_ready = false
	_state.is_started_or_about_to_start = false
	_state.is_running = false # SceneTree.pause set in IVCoreInitializer
	_state.is_quitting = false
	_state.is_game_loading = false
	_state.is_loaded_game = false
	_state.network_state = NO_NETWORK
	IVGlobal.state_changed.emit(_state)
	
	var universe: Node3D = IVGlobal.program[&"Universe"]
	if IVCoreSettings.pause_only_stops_time:
		universe.process_mode = PROCESS_MODE_ALWAYS
	else:
		universe.process_mode = PROCESS_MODE_INHERIT


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_tree.paused = true
	require_stop(self, -1, true)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_pause"):
		change_pause()
	elif event.is_action_pressed(&"quit"):
		quit(false)
	else:
		return
	get_window().set_input_as_handled()


# *****************************************************************************
# public functions

## IVSaveManager only.
func set_game_loading() -> void:
	_state.is_splash_screen = false
	_state.is_ok_to_start = false
	_state.is_system_built = false
	_state.is_game_loading = true
	_state.is_loaded_game = true
	IVGlobal.state_changed.emit(_state)
	require_stop(self, IVGlobal.NetworkStopSync.BUILD_SYSTEM, true)
	IVGlobal.about_to_build_system_tree.emit()


## IVSaveManager only.
func set_game_loaded() -> void:
	_state.is_game_loading = false
	IVGlobal.state_changed.emit(_state)
	IVGlobal.system_tree_built_or_loaded.emit(false)


func build_system_tree_from_tables() -> void:
	assert(_state.is_ok_to_start)
	_state.is_ok_to_start = false
	_state.is_loaded_game = false
	IVGlobal.state_changed.emit(_state)
	require_stop(self, IVGlobal.NetworkStopSync.BUILD_SYSTEM, true)
	IVGlobal.about_to_build_system_tree.emit()
	var table_system_builder: IVTableSystemBuilder = IVGlobal.program[&"TableSystemBuilder"]
	table_system_builder.build_system_tree()
	IVGlobal.system_tree_built_or_loaded.emit(true)


func add_blocking_thread(thread: Thread) -> void:
	# Add before thread.start() if you want certain functions (e.g., save/load)
	# to wait until these are removed. This is essential for any thread that
	# might change persist data used in gamesave.
	if !blocking_threads.has(thread):
		blocking_threads.append(thread)


func remove_blocking_thread(thread: Thread) -> void:
	# Call on main thread after your thread has finished.
	if thread:
		blocking_threads.erase(thread)
	if _signal_when_threads_finished and !blocking_threads:
		_signal_when_threads_finished = false
		threads_finished.emit()


func signal_threads_finished() -> void:
	# Generates a delayed "threads_finished" signal if/when there are no
	# blocking threads. Called by require_stop if not rejected.
	await _tree.process_frame
	if !_signal_when_threads_finished:
		_signal_when_threads_finished = true
		remove_blocking_thread(null)


func change_pause(is_toggle := true, is_pause := true) -> void:
	# Only allowed if running and not otherwise prohibited.
	if _state.network_state == IS_CLIENT:
		return
	if !_state.is_running or IVCoreSettings.disable_pause:
		return
	is_user_paused = !_tree.paused if is_toggle else is_pause
	_tree.paused = is_user_paused
	IVGlobal.user_pause_changed.emit(is_user_paused)


func require_stop(who: Object, network_sync_type := -1, bypass_checks := false) -> bool:
	# network_sync_type used only if we are the network server.
	# bypass_checks intended for this node & NetworkLobby; could break sync.
	# Returns false if the caller doesn't have authority to stop the sim.
	# "Stopped" means SceneTree is paused, the player is locked out from most
	# input, and we have signaled "run_threads_must_stop" (any Threads added
	# via add_blocking_thread() should then be removed as they finish).
	# In many cases, you should yield to "threads_finished" after calling this.
	if !bypass_checks:
		if !IVCoreSettings.popops_can_stop_sim and who is Popup:
			return false
		if _state.network_state == IS_CLIENT:
			return false
		elif _state.network_state == IS_SERVER:
			if IVCoreSettings.limit_stops_in_multiplayer:
				return false
	if _state.network_state == IS_SERVER:
		if network_sync_type != NetworkStopSync.DONT_SYNC:
			server_about_to_stop.emit(network_sync_type)
	assert(!DPRINT or IVDebug.dprint("require_stop", who, network_sync_type))
	if !_nodes_requiring_stop.has(who):
		_nodes_requiring_stop.append(who)
	if _state.is_running:
		_stop_simulator()
	signal_threads_finished()
	return true


func allow_run(who: Object) -> void:
	assert(!DPRINT or IVDebug.dprint("allow_run", who))
	_nodes_requiring_stop.erase(who)
	if _state.is_running or _nodes_requiring_stop:
		return
	if _state.network_state == IS_SERVER:
		server_about_to_run.emit()
	_run_simulator()


func exit(force_exit := false, following_server := false) -> void:
	# force_exit == true means we've confirmed and finished other preliminaries
	if !_state.is_system_ready or IVCoreSettings.disable_exit:
		return
	if !force_exit:
		if _state.network_state == IS_CLIENT:
			IVGlobal.confirmation_requested.emit("Disconnect from multiplayer game?", exit.bind(true))
			return
		elif IVPluginUtils.is_plugin_enabled("ivoyager_save"): # single player or network server
			IVGlobal.confirmation_requested.emit(&"LABEL_EXIT_WITHOUT_SAVING", exit.bind(true))
			return
	if _state.network_state == IS_CLIENT:
		if !following_server:
			client_is_dropping_out.emit(true)
	_state.is_system_built = false
	_state.is_system_ready = false
	_state.is_started_or_about_to_start = false
	_state.is_running = false
	_tree.paused = true
	_state.is_loaded_game = false
	IVGlobal.state_changed.emit(_state)
	require_stop(self, NetworkStopSync.EXIT, true)
	await self.threads_finished
	IVGlobal.about_to_exit.emit()
	IVGlobal.about_to_free_procedural_nodes.emit()
	await _tree.process_frame
	_deconstruct_system_tree()
	IVGlobal.close_all_admin_popups_requested.emit()
	await _tree.process_frame
	_state.is_splash_screen = true
	_state.is_ok_to_start = true
	IVGlobal.state_changed.emit(_state)
	IVGlobal.simulator_exited.emit()


func quit(force_quit := false) -> void:
	if !(_state.is_splash_screen or _state.is_system_ready) or IVCoreSettings.disable_quit:
		return
	if !force_quit:
		if _state.network_state == IS_CLIENT:
			IVGlobal.confirmation_requested.emit("Disconnect from multiplayer game?", exit.bind(true))
			return
		elif IVPluginUtils.is_plugin_enabled("ivoyager_save") and !_state.is_splash_screen:
			IVGlobal.confirmation_requested.emit(&"LABEL_QUIT_WITHOUT_SAVING", quit.bind(true))
			return
	if _state.network_state == IS_CLIENT:
		client_is_dropping_out.emit(false)
	_state.is_ok_to_start = false
	_state.is_quitting = true
	IVGlobal.state_changed.emit(_state)
	
	#print("\n\nOrphans before quit...")
	#IVDebug.dprint_orphan_nodes()
	#print("\n\nSceneTree before quit...")
	#IVDebug.dprint_nodes_recursive()
	#print("\n\n")
	
	IVDebug.dlog_nodes_recursive()
	
	IVGlobal.about_to_stop_before_quit.emit()
	require_stop(self, NetworkStopSync.QUIT, true)
	await threads_finished
	IVGlobal.about_to_quit.emit()
	IVGlobal.about_to_free_procedural_nodes.emit()
	await _tree.process_frame
	_deconstruct_system_tree()
	assert(IVDebug.dprint_orphan_nodes())
	
	
	print("Quitting...")
	_tree.quit()


# *****************************************************************************
# private functions

func _on_project_builder_finished() -> void:
	await _tree.process_frame
	_state.is_inited = true
	_state.is_splash_screen = true
	IVGlobal.state_changed.emit(_state)


func _on_asset_preloader_finished() -> void:
	_state.is_assets_loaded = true
	_state.is_ok_to_start = true
	IVGlobal.state_changed.emit(_state)
	if IVCoreSettings.skip_splash_screen:
		build_system_tree_from_tables()


func _on_about_to_build_system_tree() -> void:
	_state.is_splash_screen = false
	_state.is_building_tree = true
	IVGlobal.state_changed.emit(_state)


func _on_system_tree_built_or_loaded(_is_new_game: bool) -> void:
	_state.is_system_built = true
	IVGlobal.state_changed.emit(_state)


func _increment_tree_build_counter(_item: Node) -> void:
	_tree_build_counter += 1


func _decrement_tree_build_counter(_item: Node) -> void:
	_tree_build_counter -= 1
	if _tree_build_counter == 0 and _state.is_building_tree:
		IVGlobal.system_tree_ready.emit(!_state.is_loaded_game)


func _on_system_tree_ready(is_new_game: bool) -> void:
	_state.is_building_tree = false
	_state.is_game_loading = false
	_state.is_system_ready = true
	IVGlobal.state_changed.emit(_state)
	print("System tree ready...")
	await _tree.process_frame
	_state.is_started_or_about_to_start = true
	IVGlobal.state_changed.emit(_state)
	IVGlobal.about_to_start_simulator.emit(is_new_game)
	IVGlobal.close_all_admin_popups_requested.emit()
	await _tree.process_frame
	allow_run(self)
	await _tree.process_frame
	IVGlobal.update_gui_requested.emit()
	await _tree.process_frame
	IVGlobal.simulator_started.emit()
	if !is_new_game and _settings.pause_on_load:
		is_user_paused = true


func _on_simulator_exited() -> void:
	is_user_paused = false


func _deconstruct_system_tree() -> void:
	var universe: Node3D = IVGlobal.program.Universe
	if use_tree_saver_deconstruction_if_present and IVPluginUtils.is_plugin_enabled("ivoyager_save"):
		var save_utils: Script = load("res://addons/ivoyager_save/save_utils.gd")
		@warning_ignore("unsafe_method_access")
		save_utils.free_procedural_objects_recursive(universe)
	else:
		IVUtils.free_procedural_nodes_recursive(universe)


func _stop_simulator() -> void:
	# Project must ensure that state does not change during stop (in
	# particular, persist vars during save/load).
	print("Stop simulator")
	assert(!DPRINT or IVDebug.dprint("signal run_threads_must_stop"))
	allow_threads = false
	run_threads_must_stop.emit()
	_state.is_running = false
	_tree.paused = true
	IVGlobal.state_changed.emit(_state)
	IVGlobal.run_state_changed.emit(false)


func _run_simulator() -> void:
	print("Run simulator")
	_state.is_running = true
	_tree.paused = is_user_paused
	IVGlobal.state_changed.emit(_state)
	IVGlobal.run_state_changed.emit(true)
	assert(!DPRINT or IVDebug.dprint("signal run_threads_allowed"))
	allow_threads = true
	run_threads_allowed.emit()
	
