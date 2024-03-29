# system_builder.gd
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
class_name IVSystemBuilder
extends RefCounted

## Builds the star system(s) from data tables & binaries (new game only) and
## emits IVGlobal signal [code]system_ready[/code] when all (possibly off-thread)
## system tree work is done (new and loaded game).
##
## For new game, this class uses [IVBodyBuilder] and [IVSBGBuilder] to build
## [IVBody] and [IVSmallBodiesGroup] instances, respectively, and adds them to
## the scene tree.[br][br]
##
## For new and loaded game, this class hooks up to [code]system_build_finished[/code]
## signals in [IVBodyFinisher] and [IVSBGFinisher] to detect completion (these
## may be doing off-thread work) and emit IVGlobal signal [code]system_ready[/code].

# project vars
var add_small_bodies_groups := true
var add_camera := true

# private
var _body_builder: IVBodyBuilder
var _body_finisher: IVBodyFinisher
var _sbg_builder: IVSBGBuilder
var _sbg_finisher: IVSBGFinisher

var _bodies_finished := false
var _sbgs_finished := false
var _is_built_or_loaded := false
var _is_ready := false


func _ivcore_init() -> void:
	IVGlobal.state_manager_inited.connect(_on_state_manager_inited, CONNECT_ONE_SHOT)
	IVGlobal.game_load_started.connect(_signal_when_system_is_ready.bind(false))
	IVGlobal.system_tree_built_or_loaded.connect(_on_system_tree_built_or_loaded)
	_body_builder = IVGlobal.program[&"BodyBuilder"]
	_body_finisher = IVGlobal.program[&"BodyFinisher"]
	_sbg_builder = IVGlobal.program[&"SBGBuilder"]
	_sbg_finisher = IVGlobal.program[&"SBGFinisher"]


func _on_state_manager_inited() -> void:
	if IVCoreSettings.skip_splash_screen:
		build_system_tree()


func build_system_tree() -> void:
	if !IVGlobal.state.is_splash_screen:
		return
	var state_manager: IVStateManager = IVGlobal.program.StateManager
	state_manager.require_stop(state_manager, IVEnums.NetworkStopSync.BUILD_SYSTEM, true)
	IVGlobal.about_to_build_system_tree.emit()
	_signal_when_system_is_ready(true)
	for table_name in IVCoreSettings.body_tables:
		_add_bodies(table_name)
	if add_small_bodies_groups:
		_sbg_builder.build_sbgs()
	if add_camera:
		_add_camera()
	IVGlobal.system_tree_built_or_loaded.emit(true)


func _signal_when_system_is_ready(is_new_game: bool) -> void:
	# This could be a new game build or a game load, with or without threads.
	# In all cases we want to signal once after EVERYTHING is done.
	_is_built_or_loaded = false
	_bodies_finished = false
	_sbgs_finished = false
	_is_ready = false
	_body_finisher.init_system_build()
	_body_finisher.system_build_finished.connect(_on_body_finisher_finished.bind(is_new_game),
			CONNECT_ONE_SHOT)
	_sbg_finisher.init_system_build()
	_sbg_finisher.system_build_finished.connect(_on_sbg_finisher_finished.bind(is_new_game),
			CONNECT_ONE_SHOT)


func _on_system_tree_built_or_loaded(_is_new_game: bool) -> void:
	_is_built_or_loaded = true
	_signal_if_ready.call_deferred(true)


func _on_body_finisher_finished(is_new_game: bool) -> void:
	_bodies_finished = true
	_signal_if_ready(is_new_game)


func _on_sbg_finisher_finished(is_new_game: bool) -> void:
	_sbgs_finished = true
	_signal_if_ready(is_new_game)


func _signal_if_ready(is_new_game: bool) -> void:
	if _is_ready:
		return
	if _is_built_or_loaded and _bodies_finished and (_sbgs_finished or !add_small_bodies_groups):
		_is_ready = true
		IVGlobal.system_tree_ready.emit(is_new_game)


func _add_bodies(table_name: String) -> void:
	var n_rows := IVTableData.get_n_rows(table_name)
	var row := 0
	while row < n_rows:
		var parent: IVBody
		var parent_name := IVTableData.get_db_string_name(table_name, &"parent", row) # "" top
		if parent_name:
			parent = IVGlobal.bodies[parent_name]
		var body := _body_builder.build_from_table(table_name, row, parent)
		body.hide() # Bodies set their own visibility as needed
		if parent:
			parent.add_child(body)
			parent.satellites.append(body)
		else: # top body
			var universe: Node3D = IVGlobal.program.Universe
			universe.add_child(body)
		row += 1


func _add_camera() -> void:
	var CameraScript: Script = IVGlobal.procedural_classes[&"Camera"]
	@warning_ignore("unsafe_method_access")
	var camera: Camera3D = CameraScript.new()
	var start_body: IVBody = IVGlobal.bodies[IVCoreSettings.home_name]
	start_body.add_child(camera)

