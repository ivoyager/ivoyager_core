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
## Dev note: Don't add non-Godot class dependencies other than [IVGlobal],
## [IVStateAuxiliary] and static utility classes. These could cause circular
## reference issues.



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


## "core_init_" signals are emitted during [IVCoreInitializer] processing before
## property updates here.
signal core_init_preinitialized()

## "core_init_" signals are emitted during [IVCoreInitializer] processing before
## property updates here.
signal core_init_object_instantiated(object: Object)

## "core_init_" signals are emitted during [IVCoreInitializer] processing before
## property updates here.
signal core_init_init_refcounteds_instantiated()
## "core_init_" signals are emitted during [IVCoreInitializer] processing before
## property updates here.
signal core_init_program_objects_instantiated()
## "core_init_" signals are emitted during [IVCoreInitializer] processing before
## property updates here.
signal core_init_program_nodes_added()
## "core_init_" signals are emitted during [IVCoreInitializer] processing before
## property updates here. DON'T USE THIS SIGNAL. Use [signal core_initialized]
## instead.
signal core_init_finished()
## Emitted after "init" and "program" objects have been instantiated and added
## to [member IVGlobal.program], "program" nodes have been added to the scene
## tree, and [member initialized_core] is set.
signal core_initialized()
## Emitted after [IVAssetPreloader] has finished loading assets and [member
## has_assets] is set. Always after [signal core_initialized] and the delay
## can be significant (asset preloading is the longest part of bootup).
signal assets_preloaded()
## Emitted after [member building_system] is set before system tree building
## begins for new or loaded game.
signal about_to_build_system_tree(new_game: bool)
## Emitted after [member built_system] is set. Procedural [IVBody] and
## [IVSmallBodiesGroup] instances have been added for new or loaded game, but
## non-procedural "finish" nodes (models, rings, lights, HUD elements, etc.)
## are still being added, possibly on thread.
signal system_tree_built(new_game: bool)
## Emitted after [member ready_system] is set. The system tree is built and
## ready, including "finish" nodes added on thread.
signal system_tree_ready(new_game: bool)
## Emitted after [member started_or_about_to_start] is set. This is one frame
## after [signal system_tree_ready].
signal about_to_start_simulator(new_game: bool)
## Emitted after [member started] is set. This is several frames after [signal
## about_to_start_simulator] and 1 frame after [signal IVGlobal.ui_dirty].
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
signal run_state_changed(running: bool)
## Emitted when network state changes.
signal network_state_changed(network_state: NetworkState)
## Emitted after pause state changes for any reason. If [param paused_tree]
## is true, then [param paused_by_user] indicates whether the pause is due to
## user input.
signal paused_changed(paused_tree: bool, paused_by_user: bool)


## Emitted after state changes except pause (unless pause coincides with some
## other state change). Also not emitted durring [IVCoreInitializer] processing
## (see "core_init_" signals). This signal is often emitted immediately before a
## specific state signal (e.g., [signal core_initialized], [signal system_tree_ready])
## but always after relevant class properties have been set.
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


# All read-only!

## Scene tree paused state. Follows changes in [code]get_tree().paused[/code].
var paused_tree := true
## True if pause is due to user input. The tree might be paused for some other
## reason (e.g., the main menu is open). However, if [member paused_by_user] is
## true, then [member paused_tree] must be true.
var paused_by_user := false
## Set after "init" and "program" objects have been instantiated and added to
## [member IVGlobal.program], and "program" nodes have been added to the scene
## tree (followed by [signal core_initialized]).
var initialized_core := false
## Set after [IVAssetPreloader] has finished loading assets (followed by [signal
## assets_preloaded]). 
var has_assets := false
## Set true after [IVCoreInitializer] has finished and false before system tree
## building begins (for new or loaded game). Set true again after a game has
## exited. When booting up, [member has_assets] may not be true yet (see
## [member ok_to_start]).
var prestart := false
## Indicates whether it is safe to build a new system tree: [member prestart]
## and [member has_assets] are both true. If true, it's also safe to load a
## gamesave file.
var ok_to_start := false
## Indicates whether a system tree is currently being built. This may be a new
## system or loaded system from a gamesave file. This property stays true until
## [member ready_system] is true.
var building_system := false
## Indicates whether a system tree has been built (new or loaded): specifically,
## procedural [IVBody] and [IVSmallBodiesGroup] instances have been added. It's
## possible that non-procedural "finish" nodes (models, rings, lights, HUD
## elements, etc.) are still being added, possibly on thread.
var built_system := false
## True indicates that the system tree is built and ready, including "finish"
## nodes added on thread.
var ready_system := false
## Indicates whether the simulation is started or about to start (soon after
## [signal system_tree_ready]).
var started_or_about_to_start := false
## Indicates whether the simulation is started (soon after
## [signal about_to_start_simulator]). 
var started := false
var running := false
var quitting := false
var loading_game := false
var loaded_game := false
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
	IVStateManager.core_init_object_instantiated.connect(_on_global_project_object_instantiated)
	core_init_finished.connect(_on_core_initializer_finished)
	#process_mode = PROCESS_MODE_ALWAYS
	_tree.paused = true
	require_stop(self, -1, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		if paused_tree:
			return
	elif what == NOTIFICATION_UNPAUSED:
		if !paused_tree:
			return
	else:
		return
	paused_tree = not paused_tree
	paused_changed.emit(paused_tree, paused_by_user)



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


## Set user paused. Does nothing if [member IVCoreSettings.disable_pause] == true
## or [member network_state] == NetworkState.IS_CLIENT.
func set_user_paused(pause: bool) -> void:
	if paused_by_user == pause:
		return
	if network_state == NetworkState.IS_CLIENT:
		return
	if !running or IVCoreSettings.disable_pause:
		return
	paused_by_user = pause
	if paused_by_user == _tree.paused:
		paused_changed.emit(paused_by_user, paused_by_user)
	else:
		_tree.paused = paused_by_user # will emit paused_changed via IVTimekeeper


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
	if running:
		_stop_simulator()
	signal_threads_finished()
	return true


func allow_run(who: Object) -> void:
	assert(!DPRINT or IVDebug.dprint("allow_run", who))
	_nodes_requiring_stop.erase(who)
	if running or _nodes_requiring_stop:
		return
	if network_state == NetworkState.IS_SERVER:
		server_about_to_run.emit()
	_run_simulator()



## Build the system tree for new game.
func start() -> void:
	assert(ok_to_start)
	ok_to_start = false
	loaded_game = false
	state_changed.emit()
	require_stop(self, NetworkStopSync.BUILD_SYSTEM, true)
	_set_about_to_build_system_tree(true)
	IVGlobal.build_system_tree_now.emit()
	_set_system_tree_built(true)


## Exit to splash screen. Set [param force_exit] = true to force exit without
## confirmation.
func exit(force_exit := false, following_server := false) -> void:
	# 
	if !ready_system or IVCoreSettings.disable_exit:
		return
	if !force_exit:
		if network_state == NetworkState.IS_CLIENT:
			IVGlobal.confirmation_required.emit("Disconnect from multiplayer game?", exit.bind(true))
			return
		elif IVPluginUtils.is_plugin_enabled("ivoyager_save"): # single player or network server
			IVGlobal.confirmation_required.emit(&"LABEL_EXIT_WITHOUT_SAVING", exit.bind(true))
			return
	if network_state == NetworkState.IS_CLIENT:
		if !following_server:
			client_is_dropping_out.emit(true)
	built_system = false
	ready_system = false
	started_or_about_to_start = false
	started = false
	running = false
	_tree.paused = true
	loaded_game = false
	show_splash_screen = true
	state_changed.emit()
	require_stop(self, NetworkStopSync.EXIT, true)
	await self.threads_finished
	about_to_exit.emit()
	about_to_free_procedural_nodes.emit()
	var universe: Node3D = IVGlobal.program[&"Universe"]
	IVUtils.free_procedural_nodes_recursive(universe)
	await _tree.process_frame
	IVGlobal.close_admin_popups_required.emit()
	await _tree.process_frame
	prestart = true
	ok_to_start = true
	paused_by_user = false
	state_changed.emit()
	simulator_exited.emit()


## Quit the application. Set [param force_quit] = true to force quit without
## confirmation.
func quit(force_quit := false) -> void:
	if !(prestart or ready_system) or IVCoreSettings.disable_quit:
		return
	if !force_quit:
		if network_state == NetworkState.IS_CLIENT:
			IVGlobal.confirmation_required.emit("Disconnect from multiplayer game?", exit.bind(true))
			return
		elif IVPluginUtils.is_plugin_enabled("ivoyager_save") and !prestart:
			IVGlobal.confirmation_required.emit(&"LABEL_QUIT_WITHOUT_SAVING", quit.bind(true))
			return
	if network_state == NetworkState.IS_CLIENT:
		client_is_dropping_out.emit(false)
	ok_to_start = false
	quitting = true
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
	initialized_core = true
	prestart = true
	state_changed.emit()
	core_initialized.emit()


func _on_global_project_object_instantiated(object: Object) -> void:
	if object is not IVStateAuxiliary:
		return
	_state_auxiliary = object
	_state_auxiliary.asset_preloader_finished.connect(_on_aux_asset_preloader_finished)
	_state_auxiliary.about_to_free_procedural_nodes_for_load.connect(
			_on_aux_about_to_free_procedural_nodes_for_load)
	_state_auxiliary.game_loading.connect(_on_aux_game_loading)
	_state_auxiliary.game_loaded.connect(_on_aux_game_loaded)
	_state_auxiliary.tree_building_count_changed.connect(_on_aux_tree_building_count_changed)


func _on_aux_asset_preloader_finished() -> void:
	has_assets = true
	ok_to_start = true
	state_changed.emit()
	assets_preloaded.emit()
	if not IVCoreSettings.wait_for_start:
		start()


func _on_aux_about_to_free_procedural_nodes_for_load() -> void:
	about_to_free_procedural_nodes.emit()


func _on_aux_game_loading() -> void:
	prestart = false
	ok_to_start = false
	built_system = false
	loading_game = true
	loaded_game = true
	state_changed.emit()
	require_stop(self, NetworkStopSync.BUILD_SYSTEM, true)
	_set_about_to_build_system_tree(false)


func _on_aux_game_loaded(user_paused_on_load: bool) -> void:
	paused_by_user = user_paused_on_load
	loading_game = false
	state_changed.emit()
	_set_system_tree_built(false)


func _on_aux_tree_building_count_changed(incr: int) -> void:
	_tree_build_counter += incr
	if incr > 0:
		return
	if _tree_build_counter == 0 and building_system:
		_set_system_tree_ready(not loaded_game)


func _set_about_to_build_system_tree(is_new_game: bool) -> void:
	prestart = false
	building_system = true
	state_changed.emit()
	about_to_build_system_tree.emit(is_new_game)


func _set_system_tree_built(is_new_game: bool) -> void:
	built_system = true
	state_changed.emit()
	system_tree_built.emit(is_new_game)


func _set_system_tree_ready(is_new_game: bool) -> void:
	building_system = false
	loading_game = false
	ready_system = true
	state_changed.emit()
	system_tree_ready.emit(is_new_game)
	print("System tree ready...")
	await _tree.process_frame
	started_or_about_to_start = true
	state_changed.emit()
	about_to_start_simulator.emit(is_new_game)
	IVGlobal.close_admin_popups_required.emit() # main menu possible
	await _tree.process_frame
	allow_run(self)
	await _tree.process_frame
	IVGlobal.ui_dirty.emit()
	await _tree.process_frame
	started = true
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
	running = false
	if _tree.paused:
		paused_changed.emit(true, paused_by_user)
	else:
		_tree.paused = true # will emit paused_changed via IVTimekeeper
	state_changed.emit()
	run_state_changed.emit(false)


func _run_simulator() -> void:
	print("Run simulator")
	running = true
	if paused_by_user == _tree.paused:
		paused_changed.emit(paused_by_user, paused_by_user)
	else:
		_tree.paused = paused_by_user # will emit paused_changed via IVTimekeeper
	state_changed.emit()
	run_state_changed.emit(true)
	assert(!DPRINT or IVDebug.dprint("signal run_threads_allowed"))
	allow_threads = true
	run_threads_allowed.emit()
