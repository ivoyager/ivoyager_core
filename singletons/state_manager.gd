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

## Singleton [IVStateManager] maintains and exposes high-level simulator state.
##
## Dev note: Don't add non-Godot class dependencies other than [IVGlobal] and
## [IVStateAuxiliary]. These could cause circular reference issues.



#
# If IVCoreSettings.pause_only_stops_time == true, then PAUSE_MODE_PROCESS is
# set in Universe and TopGUI so IVCamera can still move, visuals work (some are
# responsve to camera) and user can interact with the world. In this mode, only
# IVTimekeeper pauses to stop time.[br][br]
#
# There is no NetworkLobby in base I, Voyager. It's is a very application-
# specific manager that you'll have to code yourself, but see:
# https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
# Be sure to set IVStateManager.network_state and emit IVGlobal signal
# "network_state_changed".[br][br]
#
# IMPORTANT! Non-main threads should coordinate with signals and functions here
# for thread-safety. We wait for all threads to finish before proceding to save,
# load, exit, quit, etc.[br][br]
#
# Multithreading note: Godot's SceneTree and almost all I, Voyager public
# functions run in the main thread. Use call_defered() to invoke any function
# from another thread unless the function is guaranteed to be thread-safe. Most
# functions are NOT thread-safe![br][br]

# FIXME: Non-splash screen dependencies on is_prestart. Keep that true
# up until sim starts and when exiting.

# FIXME: Remove IVTableSystemBuilder and any other ivoyager classes. Signal for
# build.


## "core_init_" signals are emitted during [IVCoreInitializer] processing before
## property updates here. Consider using [signal core_initialized] instead.
signal core_init_preinitialized()
## "core_init_" signals are emitted during [IVCoreInitializer] processing before
## property updates here. Consider using [signal core_initialized] instead.
signal core_init_init_refcounteds_instantiated()
## "core_init_" signals are emitted during [IVCoreInitializer] processing before
## property updates here. Consider using [signal core_initialized] instead.
signal core_init_program_objects_instantiated()
## "core_init_" signals are emitted during [IVCoreInitializer] processing before
## property updates here. Consider using [signal core_initialized] instead.
signal core_init_program_nodes_added()
## "core_init_" signals are emitted during [IVCoreInitializer] processing before
## property updates here. Consider using [signal core_initialized] instead.
signal core_init_finished()

## Emitted after "init" and "program" objects have been instantiated and
## "program" nodes have been added to the scene tree.
signal core_initialized()


## Emitted after [IVAssetPreloader] has finished loading assets, always after
## [signal core_initialized]. (Asset preloading is the longest part of startup.)
## Must happen before [member is_ok_to_start] can be true.
signal asset_preloader_finished()
## Emitted immediately before the system tree is built (new or loaded game).
signal about_to_build_system_tree(is_new_game: bool)
## Procedural [IVBody] and [IVSmallBodiesGroup] instances have been added for
## new or loaded game, but non-procedural "finish" nodes (models, rings,
## lights, HUD elements, etc.) are still being added, possibly on thread.
signal system_tree_built(is_new_game: bool)
## The system tree is built and ready, including "finish" nodes added on thread.
signal system_tree_ready(is_new_game: bool)
## Emitted 1 frame after [signal system_tree_ready].
signal about_to_start_simulator(is_new_game: bool)
## Emitted a few frames after [signal about_to_start_simulator] and 1 frame
## after [signal IVGlobal.update_gui_requested].
signal simulator_started()
## Emitted immediately before procedural nodes are freed on exit, quit, and game
## load starting.
signal about_to_free_procedural_nodes()
## Emitted immediately before the simulator stops for quit.
signal about_to_stop_before_quit()
## Emitted immediately before quit.
signal about_to_quit()
## Emitted immediately before exit.
signal about_to_exit()
## Emitted after the simulator exits.
signal simulator_exited()
## Emitted when the simulator starts or stops. The tree is always paused when
## the simulator is stopped. However, user pause does not stop the simulator.
signal run_state_changed(is_running: bool)
## Emitted when network state changes.
signal network_state_changed(network_state: NetworkState)

## Emitted when pause state changes for any reason. If [param is_tree_paused]
## is true, then [param is_user_pause] indicates whether the pause is due to
## user input.
signal paused_changed(is_tree_paused: bool, is_user_pause: bool)
## Emitted after any state change ("is_" property change) except for pause.
## This signal is often emitted before a specific state signal, e.g.,
## [signal core_initialized], [signal system_tree_ready], etc.
signal state_changed()

# TODO?: one signal threads_state_changed() and then query allow_threads
signal run_threads_allowed() # ok to start threads that affect gamestate
signal run_threads_must_stop() # finish threads that affect gamestate
signal threads_finished() # all blocking threads removed

# TODO?: one signal server_state_changed()
signal client_is_dropping_out(is_exit: bool)
signal server_about_to_stop(network_sync_type: int) # NetworkStopSync; server only
signal server_about_to_run() # server only


enum NetworkState {
	NO_NETWORK,
	IS_SERVER,
	IS_CLIENT,
}

enum NetworkStopSync {
	BUILD_SYSTEM,
	SAVE,
	LOAD,
	NEW_PLAYER, # needs save to enter in-progress game
	EXIT,
	QUIT,
	DONT_SYNC,
}



const DPRINT := false


# read-only!

## Scene tree paused state.
var is_tree_paused := true
## User pause state. The tree might be paused for some other reason, e.g.,
## the main menu is open.
var is_user_pause := false
## True at and after [signal core_initialized].
var is_core_inited := false
## True at and after [signal asset_preloader_finished].
var is_assets_loaded := false

var is_prestart := false
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
var network_state := NetworkState.NO_NETWORK
## Use this property to set splash screen visibility on [signal state_changed].
## True until simulator started. True again on exit.
var show_splash_screen := true

var allow_threads := false
var blocking_threads := []


var _state_auxiliary: IVStateAuxiliary
var _nodes_requiring_stop := []
var _signal_when_threads_finished := false
var _tree_build_counter := 0

@onready var _tree: SceneTree = get_tree()



func _ready() -> void:
	IVGlobal.core_init_object_instantiated.connect(_on_global_project_object_instantiated)
	core_init_finished.connect(_on_core_initializer_finished)
	process_mode = PROCESS_MODE_ALWAYS
	_tree.paused = true
	require_stop(self, -1, true)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_pause"):
		change_user_pause()
	elif event.is_action_pressed(&"quit"):
		quit(false)
	else:
		return
	get_window().set_input_as_handled()





## Add before thread.start() if you want certain functions (e.g., save/load)
## to wait until these are removed. This is essential for any thread that
## might change persist data used in gamesave.
func add_blocking_thread(thread: Thread) -> void:
	if !blocking_threads.has(thread):
		blocking_threads.append(thread)


## Call on main thread after your thread has finished.
func remove_blocking_thread(thread: Thread) -> void:
	if thread:
		blocking_threads.erase(thread)
	if _signal_when_threads_finished and !blocking_threads:
		_signal_when_threads_finished = false
		threads_finished.emit()


## Generates a delayed "threads_finished" signal if/when there are no
## blocking threads. Called by require_stop if not rejected.
func signal_threads_finished() -> void:
	await _tree.process_frame
	if !_signal_when_threads_finished:
		_signal_when_threads_finished = true
		remove_blocking_thread(null)


## Toggle or set user pause. If [param toggle] is true (default) the second
## arg is ignored.
func change_user_pause(toggle := true, pause := true) -> void:
	# Only allowed if running and not otherwise prohibited.
	if network_state == NetworkState.IS_CLIENT:
		return
	if !is_running or IVCoreSettings.disable_pause:
		return
	if !toggle and pause == is_user_pause:
		return
	is_user_pause = !is_user_pause if toggle else pause
	if is_user_pause == _tree.paused:
		paused_changed.emit(is_user_pause, is_user_pause)
	else:
		_tree.paused = is_user_pause # will emit paused_changed via IVTimekeeper


## network_sync_type used only if we are the network server.
## bypass_checks intended for this node & NetworkLobby; could break sync.
## Returns false if the caller doesn't have authority to stop the sim.
## "Stopped" means SceneTree is paused, the player is locked out from most
## input, and we have signaled "run_threads_must_stop" (any Threads added
## via add_blocking_thread() should then be removed as they finish).
## In many cases, you should yield to "threads_finished" after calling this.
func require_stop(who: Object, network_sync_type := -1, bypass_checks := false) -> bool:
	if !bypass_checks:
		if !IVCoreSettings.popops_can_stop_sim and who is Popup:
			return false
		if network_state == NetworkState.IS_CLIENT:
			return false
		elif network_state == NetworkState.IS_SERVER:
			if IVCoreSettings.limit_stops_in_multiplayer:
				return false
	if network_state == NetworkState.IS_SERVER:
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
	if network_state == NetworkState.IS_SERVER:
		server_about_to_run.emit()
	_run_simulator()



## Build the system tree for new game.
func start() -> void:
	assert(is_ok_to_start)
	is_ok_to_start = false
	is_loaded_game = false
	state_changed.emit()
	require_stop(self, NetworkStopSync.BUILD_SYSTEM, true)
	_set_about_to_build_system_tree(true)
	IVGlobal.build_system_tree_requested.emit()
	_set_system_tree_built(true)


## Exit to splash screen. [param force_exit] = true means we've confirmed
## already or confirmation isn't applicable.
func exit(force_exit := false, following_server := false) -> void:
	# 
	if !is_system_ready or IVCoreSettings.disable_exit:
		return
	if !force_exit:
		if network_state == NetworkState.IS_CLIENT:
			IVGlobal.confirmation_requested.emit("Disconnect from multiplayer game?", exit.bind(true))
			return
		elif IVPluginUtils.is_plugin_enabled("ivoyager_save"): # single player or network server
			IVGlobal.confirmation_requested.emit(&"LABEL_EXIT_WITHOUT_SAVING", exit.bind(true))
			return
	if network_state == NetworkState.IS_CLIENT:
		if !following_server:
			client_is_dropping_out.emit(true)
	is_system_built = false
	is_system_ready = false
	is_started_or_about_to_start = false
	is_started = false
	is_running = false
	_tree.paused = true
	is_loaded_game = false
	show_splash_screen = true
	state_changed.emit()
	require_stop(self, NetworkStopSync.EXIT, true)
	await self.threads_finished
	about_to_exit.emit()
	about_to_free_procedural_nodes.emit()
	var universe: Node3D = IVGlobal.program[&"Universe"]
	IVUtils.free_procedural_nodes_recursive(universe)
	await _tree.process_frame
	IVGlobal.close_all_admin_popups_requested.emit()
	await _tree.process_frame
	is_prestart = true
	is_ok_to_start = true
	is_user_pause = false
	state_changed.emit()
	simulator_exited.emit()


## Quit the application. [param force_quit] = true means we've confirmed
## already or confirmation isn't applicable.
func quit(force_quit := false) -> void:
	if !(is_prestart or is_system_ready) or IVCoreSettings.disable_quit:
		return
	if !force_quit:
		if network_state == NetworkState.IS_CLIENT:
			IVGlobal.confirmation_requested.emit("Disconnect from multiplayer game?", exit.bind(true))
			return
		elif IVPluginUtils.is_plugin_enabled("ivoyager_save") and !is_prestart:
			IVGlobal.confirmation_requested.emit(&"LABEL_QUIT_WITHOUT_SAVING", quit.bind(true))
			return
	if network_state == NetworkState.IS_CLIENT:
		client_is_dropping_out.emit(false)
	is_ok_to_start = false
	is_quitting = true
	state_changed.emit()
	about_to_stop_before_quit.emit()
	require_stop(self, NetworkStopSync.QUIT, true)
	await threads_finished
	
	# debugging leaked objects...
	#IVDebug.register_all_objects(get_viewport())
	
	about_to_quit.emit()
	about_to_free_procedural_nodes.emit()
	var universe: Node3D = IVGlobal.program[&"Universe"]
	IVUtils.free_procedural_nodes_recursive(universe)
	await _tree.process_frame
	assert(IVDebug.dprint_orphan_nodes())
	print("Quitting...")
	_tree.quit()


# *****************************************************************************

func _on_core_initializer_finished() -> void:
	assert(_state_auxiliary)
	is_core_inited = true
	is_prestart = true
	state_changed.emit()
	core_initialized.emit()


func _on_global_project_object_instantiated(object: Object) -> void:
	if object is not IVStateAuxiliary:
		return
	_state_auxiliary = object
	_state_auxiliary.asset_preloader_finished.connect(_on_aux_asset_preloader_finished)
	_state_auxiliary.about_to_free_procedural_nodes.connect(_on_aux_about_to_free_procedural_nodes)
	_state_auxiliary.game_loading.connect(_on_aux_game_loading)
	_state_auxiliary.game_loaded.connect(_on_aux_game_loaded)
	_state_auxiliary.engine_paused_changed.connect(_on_aux_engine_paused_changed)
	_state_auxiliary.tree_building_count_changed.connect(_on_aux_tree_building_count_changed)


func _on_aux_asset_preloader_finished() -> void:
	is_assets_loaded = true
	is_ok_to_start = true
	state_changed.emit()
	asset_preloader_finished.emit()
	if not IVCoreSettings.wait_for_start:
		start()


func _on_aux_about_to_free_procedural_nodes() -> void:
	about_to_free_procedural_nodes.emit()


func _on_aux_game_loading() -> void:
	is_prestart = false
	is_ok_to_start = false
	is_system_built = false
	is_game_loading = true
	is_loaded_game = true
	state_changed.emit()
	require_stop(self, NetworkStopSync.BUILD_SYSTEM, true)
	_set_about_to_build_system_tree(false)


func _on_aux_game_loaded(user_pause: bool) -> void:
	is_user_pause = user_pause
	is_game_loading = false
	state_changed.emit()
	_set_system_tree_built(false)


func _on_aux_engine_paused_changed(engine_paused: bool) -> void:
	if is_tree_paused == engine_paused:
		return
	is_tree_paused = engine_paused
	paused_changed.emit(is_tree_paused, is_user_pause)


func _on_aux_tree_building_count_changed(incr: int) -> void:
	_tree_build_counter += incr
	if incr > 0:
		return
	if _tree_build_counter == 0 and is_building_tree:
		_set_system_tree_ready(not is_loaded_game)


func _set_about_to_build_system_tree(is_new_game: bool) -> void:
	is_prestart = false
	is_building_tree = true
	state_changed.emit()
	about_to_build_system_tree.emit(is_new_game)


func _set_system_tree_built(is_new_game: bool) -> void:
	is_system_built = true
	state_changed.emit()
	system_tree_built.emit(is_new_game)


func _set_system_tree_ready(is_new_game: bool) -> void:
	is_building_tree = false
	is_game_loading = false
	is_system_ready = true
	state_changed.emit()
	system_tree_ready.emit(is_new_game)
	print("System tree ready...")
	await _tree.process_frame
	is_started_or_about_to_start = true
	state_changed.emit()
	about_to_start_simulator.emit(is_new_game)
	IVGlobal.close_all_admin_popups_requested.emit() # main menu possible
	await _tree.process_frame
	allow_run(self)
	await _tree.process_frame
	IVGlobal.update_gui_requested.emit()
	await _tree.process_frame
	is_started = true
	show_splash_screen = false
	state_changed.emit()
	simulator_started.emit()


func _stop_simulator() -> void:
	# Project must ensure that state does not change during stop (in
	# particular, persist vars during save/load).
	print("Stop simulator")
	assert(!DPRINT or IVDebug.dprint("signal run_threads_must_stop"))
	allow_threads = false
	run_threads_must_stop.emit()
	is_running = false
	if _tree.paused:
		paused_changed.emit(true, is_user_pause)
	else:
		_tree.paused = true # will emit paused_changed via IVTimekeeper
	state_changed.emit()
	run_state_changed.emit(false)


func _run_simulator() -> void:
	print("Run simulator")
	is_running = true
	if is_user_pause == _tree.paused:
		paused_changed.emit(is_user_pause, is_user_pause)
	else:
		_tree.paused = is_user_pause # will emit paused_changed via IVTimekeeper
	state_changed.emit()
	run_state_changed.emit(true)
	assert(!DPRINT or IVDebug.dprint("signal run_threads_allowed"))
	allow_threads = true
	run_threads_allowed.emit()
