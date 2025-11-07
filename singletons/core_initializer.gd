# core_initializer.gd
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

## Added as singleton 'IVCoreInitializer'.
##
## Modify properties or dictionary classes using res://ivoyager_override.cfg.
## Alternatively, you can modify values here using a preinitializer script.
## (To add your preinitializer, either add it using res://ivoyager_override.cfg
## or make it an autoload.)[br][br]
##
## For an example preinitializer script, see Planetarium: [url]
## https://github.com/ivoyager/planetarium/blob/master/planetarium/preinitializer.gd
## [/url].[br][br]
##
## DON'T modify values here after program start![br][br]
##
## By itself, ivoyager_core will run but it lacks a GUI (the default IVTopGUI
## has no child GUIs). You can either build on the existing IVTopGUI or provide
## your own by setting 'top_gui' or 'top_gui_path' here.[br][br]

## For internal use only.
signal init_step_finished()


# *************** PROJECT VARS - MODIFY THESE TO EXTEND !!!! ******************

var allow_project_build := true
var init_delay := 5 # frames


# init_sequence can be modified even after started (eg, by a preinitializer).
var init_sequence: Array[Array] = [
	# [object, method, wait_for_signal]
#	[self, "_init_extensions", false],
	[self, &"_instantiate_preinitializers", false],
	[self, &"_do_presets_and_plugin_mods", false],
	[self, &"_instantiate_initializers", false],
	[self, &"_set_simulator_universe", false],
	[self, &"_index_existing_nodes", false],
	[self, &"_instantiate_and_index_program_objects", true],
	[self, &"_add_program_nodes", true],
	[self, &"_finish", false]
]

# All nodes instatiated here are added to 'universe' or 'top_gui'. Use
# ivoyager_override.cfg or a preinitializer script to set either or both of
# these. Otherwise, IVCoreInitializer will assign default nodes from
# ivoyager_core (or for universe, by tree search for 'Universe').
# Whatever is assigned will be accessible from IVGlobal.program[&"Universe"]
# and IVGlobal.program[&"TopGUI"], irrespective of node names.

var universe: Node3D
#var top_gui: Control
var universe_path: String # assign here if using ivoyager_override.cfg
#var top_gui_path: String # assign here if using ivoyager_override.cfg
#var add_top_gui_to_universe := true # if true, happens in add_program_nodes()

# You can replace any class below with a subclass of the original. In some
# cases, you can replace with a base Godot class (e.g., Node3D) or erase
# unneeded systems, but you will have to investigate dependencies.
#
# Dictionary values below can be any one of three things:
#   - A GDScript class_name global.
#   - A path to a Script resource (*.gd for now).
#   - Where applicable, a path to a scene (*.tscn, *.scn).
#
# (We want to support GDExtension classes in the future. Please tell us if you
# want to help with that!)


## RefCounted classes. IVCoreInitializer instances these first. External
## projects can add script paths here using 'res://ivoyager_override.cfg'.
## A reference is kept in dictionary 'IVGlobal.program' (erase it if you
## want to de-reference your preinitializer so it will free itself).
var preinitializers: Dictionary[StringName, Variant] = {}

## RefCounted classes. IVCoreInitializer instances these after
## 'preinitializers'. Many of these instances may erase themselves from
## dictionary 'IVGlobal.program' after init, thereby freeing themselves.
## Path to RefCounted class ok.
var initializers: Dictionary[StringName, Variant] = {
	ResourceInitializer = IVResourceInitializer, # self-removes
	TranslationImporter = IVTranslationImporter, # self-removes
	TableInitializer = IVTableInitializer, # self-removes
	InputMapManager = IVInputMapManager,
	AssetPreloader = IVAssetPreloader,
}

## RefCounteds to instantiate and add to [member IVGlobal.program].
## No save/load persistence.
## Path to RefCounted class ok.
var program_refcounteds: Dictionary[StringName, Variant] = {
	# builders, finishers (of procedural objects)
	TableSystemBuilder = IVTableSystemBuilder,
	TableBodyBuilder = IVTableBodyBuilder,
	TableOrbitBuilder = IVTableOrbitBuilder,
	TableSBGBuilder = IVTableSBGBuilder,
	TableViewBuilder = IVTableViewBuilder,
	TableCompositionBuilder = IVTableCompositionBuilder, # ok to remove
	BinaryAsteroidsBuilder = IVBinaryAsteroidsBuilder,
	BodyFinisher = IVBodyFinisher,
	SBGFinisher = IVSBGFinisher,
	# managers, etc.
	ThemeManager = IVThemeManager,
	SleepManager = IVSleepManager,
	LazyModelInitializer = IVLazyModelInitializer,
	LanguageManager = IVLanguageManager,
}

## Nodes to instantiate, add to [member IVGlobal.program], and add to Universe.
## Path to RefCounted class ok.
var program_nodes: Dictionary[StringName, Variant] = {
	Scheduler = IVScheduler,
	ViewManager = IVViewManager,
	WorldEnvironment_ = IVWorldEnvironment,
	# Nodes below are ordered for input handling (last is first). We mainly
	# need to intercept cntr-something actions (quit, full-screen, etc.) before
	# CameraHandler.
	CameraHandler = IVCameraHandler, # remove or replace if not using IVCamera
	Timekeeper = IVTimekeeper,
	SBGHUDsState = IVSBGHUDsState, # (likely to have input in future)
	BodyHUDsState = IVBodyHUDsState,
	InputHandler = IVInputHandler,
	SaveManager = IVSaveManager, # auto removed if plugin missing or disabled
}

## Nodes that already exist in the tree that we want added to [member IVGlobal.program].
var tree_program_nodes: Array[StringName] = [
	&"FragmentIdentifier",
	&"TopUI",
	&"WorldController",
]



func _enter_tree() -> void:
	IVFiles.init_from_config(self, IVGlobal.ivoyager_config, "core_initializer")


func _ready() -> void:
	var init_countdown := init_delay
	while init_countdown > 0:
		await get_tree().process_frame
		init_countdown -= 1
	build_project() # after all other singletons _ready()


# **************************** PUBLIC FUNCTIONS *******************************
# These should be called only by extension init file!

func build_project(override := false) -> void:
	# Call directly only if extension set allow_project_build = false.
	if !override and !allow_project_build:
		return
	# Build loop is designed so that array 'init_sequence' can be modified even
	# during loop execution -- in particular, by an extention instantiated in
	# the first step. Otherwise, it could be modified by an autoload singleton.
	var init_index := 0
	while init_index < init_sequence.size():
		var init_array: Array = init_sequence[init_index]
		var object: Object = init_array[0]
		var method: String = init_array[1]
		var wait_for_signal: bool = init_array[2]
		object.call(method)
		if wait_for_signal:
			await self.init_step_finished
		init_index += 1


# ************************ 'init_sequence' FUNCTIONS **************************

func _instantiate_preinitializers() -> void:
	for key: StringName in preinitializers:
		if !preinitializers[key]:
			continue
		assert(!IVGlobal.program.has(key))
		var preinitializer: RefCounted = IVFiles.make_object_or_scene(preinitializers[key])
		IVGlobal.program[key] = preinitializer
	IVStateManager.set_core_initializer_step(
			IVStateManager.CoreInitializerStep.PREINITIALIZERS_INITED)


func _do_presets_and_plugin_mods() -> void:
	# TODO: We might add class presets here
	if !IVPluginUtils.is_plugin_enabled("ivoyager_save"):
		program_nodes.erase(&"SaveManager")


func _instantiate_initializers() -> void:
	IVGlobal.about_to_run_initializers.emit()
	for key: StringName in initializers:
		if !initializers[key]:
			continue
		assert(!IVGlobal.program.has(key))
		var initializer: RefCounted = IVFiles.make_object_or_scene(initializers[key])
		IVGlobal.program[key] = initializer
		IVGlobal.project_object_instantiated.emit(initializer)
	IVStateManager.set_core_initializer_step(
			IVStateManager.CoreInitializerStep.PROJECT_INITIALIZERS_INSTANTIATED)


func _set_simulator_universe() -> void:
	if universe:
		return
	if universe_path:
		universe = IVFiles.make_object_or_scene(universe_path)
		assert(universe)
		return
	var scenetree_root := get_tree().get_root()
	universe = scenetree_root.find_child(&"Universe", true, false)
	assert(universe, "'Universe' was not found nor explicitly set")


func _index_existing_nodes() -> void:
	IVGlobal.program[&"Universe"] = universe
	IVGlobal.program[&"Global"] = IVGlobal
	IVGlobal.program[&"CoreSettings"] = IVCoreSettings
	IVGlobal.program[&"SettingsManager"] = IVSettingsManager
	IVGlobal.program[&"StateManager"] = IVStateManager
	var scenetree_root := get_tree().get_root()
	for node_name in tree_program_nodes:
		var node := scenetree_root.find_child(node_name, true, false)
		if node:
			IVGlobal.program[node_name] = node
		else:
			push_warning("Did not find '$s' listed in 'tree_program_nodes'" % node_name)


func _instantiate_and_index_program_objects() -> void:
	for dict: Dictionary in [program_refcounteds, program_nodes]:
		for key: StringName in dict:
			if !dict[key]:
				continue
			assert(!IVGlobal.program.has(key))
			var object: Object = IVFiles.make_object_or_scene(dict[key])
			IVGlobal.program[key] = object
			if object is Node:
				@warning_ignore("unsafe_property_access")
				object.name = key
			IVGlobal.project_object_instantiated.emit(object)
	IVStateManager.set_core_initializer_step(
			IVStateManager.CoreInitializerStep.PROJECT_OBJECTS_INSTANTIATED)
	await get_tree().process_frame
	init_step_finished.emit()


func _add_program_nodes() -> void:
	for key: StringName in program_nodes:
		if !program_nodes[key]:
			continue
		var node: Node = IVGlobal.program[key]
		universe.add_child(node)
	IVStateManager.set_core_initializer_step(IVStateManager.CoreInitializerStep.PROJECT_NODES_ADDED)
	await get_tree().process_frame
	init_step_finished.emit()


func _finish() -> void:
	IVStateManager.set_core_initializer_step(IVStateManager.CoreInitializerStep.CORE_INITED)
