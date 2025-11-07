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
extends Node

## Singleton "IVStateManager" maintains and exposes high-level simulator state.
##
## General simulator state signals are emitted via IVGlobal, with more specific
## emitted by this class. Much of simulator state can be queried via dictionary
## [code]state[/code] in IVGlobal. This class defines certain expected keys
## in [code]state[/code] and (together with [IVSaveManager] and possibly an
## external NetworkLobby) manages these [code]state[/code] values.[br][br]
##
## IVGlobal [code]state[/code] keys inited here:[br][br]
##   [code]is_core_inited: bool[/code]
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
## Be sure to set IVStateManager.network_state and emit IVGlobal signal
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






signal state_changed()

# TODO?: one signal threads_state_changed() and then query allow_threads
signal run_threads_allowed() # ok to start threads that affect gamestate
signal run_threads_must_stop() # finish threads that affect gamestate
signal threads_finished() # all blocking threads removed

# TODO?: one signal server_state_changed()
signal client_is_dropping_out(is_exit: bool)
signal server_about_to_stop(network_sync_type: int) # IVGlobal.NetworkStopSync; server only
signal server_about_to_run() # server only


# FIXME: Should be INITIALIZERS_INSTANTIATED, PROGRAM_OBJECTS_INSTANTIATED,
# PROGRAM_NODES_ADDED.
# FIXME: PROJECT_INITED is deceptive name & redundant w/ PROJECT_OBJECTS_INSTANTIATED.
# FIXME: Last step should be CORE_INITED.
enum CoreInitializerStep {
	PREINITIALIZERS_INITED,
	PROJECT_INITIALIZERS_INSTANTIATED,
	PROJECT_OBJECTS_INSTANTIATED,
	PROJECT_NODES_ADDED,
	CORE_INITED,
}

const NO_NETWORK = IVGlobal.NetworkState.NO_NETWORK
const IS_SERVER = IVGlobal.NetworkState.IS_SERVER
const IS_CLIENT = IVGlobal.NetworkState.IS_CLIENT
const NetworkStopSync = IVGlobal.NetworkStopSync

const DPRINT := false



# read-only!
var is_user_paused := false # ignores pause from sim stop


var is_core_inited := false


var is_splash_screen := false
var is_assets_loaded := false
var is_ok_to_start := false
var is_building_tree := false # new or loading game
var is_system_built := false
var is_system_ready := false
var is_started_or_about_to_start := false
var is_started := false
var is_running := false # SceneTree.pause set in IVCoreInitializer
var is_quitting := false
var is_game_loading := false
var is_loaded_game := false
var network_state := NO_NETWORK

var allow_threads := false
var blocking_threads := []


var _settings: Dictionary[StringName, Variant] = IVGlobal.settings
var _nodes_requiring_stop := []
var _signal_when_threads_finished := false
var _tree_build_counter := 0

@onready var _tree: SceneTree = get_tree()





func _init() -> void:
	
	# TODO: Remove all of these in all projects; make direct
	IVGlobal.change_pause_requested.connect(change_pause)
	IVGlobal.sim_stop_required.connect(require_stop)
	IVGlobal.sim_run_allowed.connect(allow_run)
	IVGlobal.quit_requested.connect(quit)
	IVGlobal.exit_requested.connect(exit)



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


## IVCoreInitializer only.
func set_core_initializer_step(step: CoreInitializerStep) -> void:
	match step:
		CoreInitializerStep.PREINITIALIZERS_INITED:
			IVGlobal.preinitializers_inited.emit()
		CoreInitializerStep.PROJECT_INITIALIZERS_INSTANTIATED:
			IVGlobal.project_initializers_instantiated.emit()
		CoreInitializerStep.PROJECT_OBJECTS_INSTANTIATED:
			IVGlobal.project_objects_instantiated.emit()
		CoreInitializerStep.PROJECT_NODES_ADDED:
			IVGlobal.project_nodes_added.emit()
		CoreInitializerStep.CORE_INITED:
			is_core_inited = true
			is_splash_screen = true
			state_changed.emit()
			IVGlobal.core_inited.emit()


## IVAssetPreloader only.
func set_asset_preloader_finished() -> void:
	is_assets_loaded = true
	is_ok_to_start = true
	state_changed.emit()
	IVGlobal.asset_preloader_finished.emit()
	if not IVCoreSettings.wait_for_start:
		start()


## IVSaveManager only.
func set_game_loading() -> void:
	is_splash_screen = false
	is_ok_to_start = false
	is_system_built = false
	is_game_loading = true
	is_loaded_game = true
	state_changed.emit()
	require_stop(self, IVGlobal.NetworkStopSync.BUILD_SYSTEM, true)
	_set_about_to_build_system_tree(false)


## IVSaveManager only.
func set_game_loaded() -> void:
	is_game_loading = false
	state_changed.emit()
	_set_system_tree_built_or_loaded(false)



func increment_tree_building_counter(_item: Node) -> void:
	_tree_build_counter += 1


func decrement_tree_building_counter(_item: Node) -> void:
	_tree_build_counter -= 1
	if _tree_build_counter == 0 and is_building_tree:
		_set_system_tree_ready(not is_loaded_game)


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
	if network_state == IS_CLIENT:
		return
	if !is_running or IVCoreSettings.disable_pause:
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
		if network_state == IS_CLIENT:
			return false
		elif network_state == IS_SERVER:
			if IVCoreSettings.limit_stops_in_multiplayer:
				return false
	if network_state == IS_SERVER:
		if network_sync_type != NetworkStopSync.DONT_SYNC:
			server_about_to_stop.emit(network_sync_type)
	assert(!DPRINT or IVDebug.dprint("require_stop", who, network_sync_type))
	if !_nodes_requiring_stop.has(who):
		_nodes_requiring_stop.append(who)
	if is_running:
		_stop_simulator()
	signal_threads_finished()
	return true


func allow_run(who: Object) -> void:
	assert(!DPRINT or IVDebug.dprint("allow_run", who))
	_nodes_requiring_stop.erase(who)
	if is_running or _nodes_requiring_stop:
		return
	if network_state == IS_SERVER:
		server_about_to_run.emit()
	_run_simulator()



## Build the system tree for new game.
func start() -> void:
	assert(is_ok_to_start)
	is_ok_to_start = false
	is_loaded_game = false
	state_changed.emit()
	require_stop(self, IVGlobal.NetworkStopSync.BUILD_SYSTEM, true)
	_set_about_to_build_system_tree(true)
	var table_system_builder: IVTableSystemBuilder = IVGlobal.program[&"TableSystemBuilder"]
	table_system_builder.build_system_tree()
	_set_system_tree_built_or_loaded(true)


## Exit to splash screen
func exit(force_exit := false, following_server := false) -> void:
	# force_exit == true means we've confirmed and finished other preliminaries
	if !is_system_ready or IVCoreSettings.disable_exit:
		return
	if !force_exit:
		if network_state == IS_CLIENT:
			IVGlobal.confirmation_requested.emit("Disconnect from multiplayer game?", exit.bind(true))
			return
		elif IVPluginUtils.is_plugin_enabled("ivoyager_save"): # single player or network server
			IVGlobal.confirmation_requested.emit(&"LABEL_EXIT_WITHOUT_SAVING", exit.bind(true))
			return
	if network_state == IS_CLIENT:
		if !following_server:
			client_is_dropping_out.emit(true)
	is_system_built = false
	is_system_ready = false
	is_started_or_about_to_start = false
	is_started = false
	is_running = false
	_tree.paused = true
	is_loaded_game = false
	state_changed.emit()
	require_stop(self, NetworkStopSync.EXIT, true)
	await self.threads_finished
	IVGlobal.about_to_exit.emit()
	IVGlobal.about_to_free_procedural_nodes.emit()
	var universe: Node3D = IVGlobal.program.Universe
	IVUtils.free_procedural_nodes_recursive(universe)
	await _tree.process_frame
	IVGlobal.close_all_admin_popups_requested.emit()
	await _tree.process_frame
	is_splash_screen = true
	is_ok_to_start = true
	is_user_paused = false
	state_changed.emit()
	IVGlobal.simulator_exited.emit()


func quit(force_quit := false) -> void:
	if !(is_splash_screen or is_system_ready) or IVCoreSettings.disable_quit:
		return
	if !force_quit:
		if network_state == IS_CLIENT:
			IVGlobal.confirmation_requested.emit("Disconnect from multiplayer game?", exit.bind(true))
			return
		elif IVPluginUtils.is_plugin_enabled("ivoyager_save") and !is_splash_screen:
			IVGlobal.confirmation_requested.emit(&"LABEL_QUIT_WITHOUT_SAVING", quit.bind(true))
			return
	if network_state == IS_CLIENT:
		client_is_dropping_out.emit(false)
	is_ok_to_start = false
	is_quitting = true
	state_changed.emit()
	IVGlobal.about_to_stop_before_quit.emit()
	require_stop(self, NetworkStopSync.QUIT, true)
	await threads_finished
	
	# debugging leaked objects...
	#IVDebug.register_all_objects(get_viewport())
	
	IVGlobal.about_to_quit.emit()
	IVGlobal.about_to_free_procedural_nodes.emit()
	var universe: Node3D = IVGlobal.program.Universe
	IVUtils.free_procedural_nodes_recursive(universe)
	await _tree.process_frame
	assert(IVDebug.dprint_orphan_nodes())
	
	
	print("Quitting...")
	_tree.quit()


# *****************************************************************************
# private functions


func _set_about_to_build_system_tree(is_new_game: bool) -> void:
	is_splash_screen = false
	is_building_tree = true
	state_changed.emit()
	IVGlobal.about_to_build_system_tree.emit(is_new_game)


func _set_system_tree_built_or_loaded(is_new_game: bool) -> void:
	is_system_built = true
	state_changed.emit()
	IVGlobal.system_tree_built_or_loaded.emit(is_new_game)


func _set_system_tree_ready(is_new_game: bool) -> void:
	is_building_tree = false
	is_game_loading = false
	is_system_ready = true
	state_changed.emit()
	IVGlobal.system_tree_ready.emit(is_new_game)
	print("System tree ready...")
	
	await _tree.process_frame
	is_started_or_about_to_start = true
	state_changed.emit()
	IVGlobal.about_to_start_simulator.emit(is_new_game)
	IVGlobal.close_all_admin_popups_requested.emit() # main menu possible
	await _tree.process_frame
	allow_run(self)
	await _tree.process_frame
	IVGlobal.update_gui_requested.emit()
	await _tree.process_frame
	is_started = true
	state_changed.emit()
	IVGlobal.simulator_started.emit()
	if !is_new_game and _settings.pause_on_load:
		is_user_paused = true


func _stop_simulator() -> void:
	# Project must ensure that state does not change during stop (in
	# particular, persist vars during save/load).
	print("Stop simulator")
	assert(!DPRINT or IVDebug.dprint("signal run_threads_must_stop"))
	allow_threads = false
	run_threads_must_stop.emit()
	is_running = false
	_tree.paused = true
	state_changed.emit()
	IVGlobal.run_state_changed.emit(false)


func _run_simulator() -> void:
	print("Run simulator")
	is_running = true
	_tree.paused = is_user_paused
	state_changed.emit()
	IVGlobal.run_state_changed.emit(true)
	assert(!DPRINT or IVDebug.dprint("signal run_threads_allowed"))
	allow_threads = true
	run_threads_allowed.emit()
