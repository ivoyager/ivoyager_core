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

## Singleton [IVCoreInitializer] inits the Core plugin program.
##
## This singleton (and [IVCoreSettings]) can be modified by config files:[br][br]
##
## [b]res://ivoyager_override.cfg[/b] (created by Core plugin if it doesn't exist)[br]
## [b]res://ivoyager_override2.cfg[/b] (overrides above if it exists)[br][br]
##
## These files override [b]res://addons/ivoyager_core/ivoyager_core.cfg[/b] and
## allow changes to properties in this class (and many other things too). For
## details, see comments in [b]res://addons/ivoyager_core/override_template.cfg[/b].
## [br][br]
##
## It's possible to modify most properties using config override files. However,
## it's easier and more flexible to specify a single "preinitializer" file and
## do subseqent changes by code. This also allows connection to
## "core_init_" signals in [IVStateManager] so program objects can be modified
## after instantiation. To add a preinitializer file, add these lines to
## ivoyager_override.cfg:
## [codeblock]
## 
## [core_initializer]
## 
## preinitializers/MyPreinitializer="res://path/my_preinitializer.gd"
## 
## [/codeblock][br]
##
## For an example preinitializer script, see the Planetarium's
## [url=https://github.com/ivoyager/planetarium/blob/master/planetarium/preinitializer.gd]
## here[/url].[br][br]
##
## Alternatively, this class could be modified by another autoload or some other
## early-executing code. In any case, it's recommended to have a dedicated "init"
## file modify this singleton and [IVCoreSettings] at program init. ONLY that
## file should reference this singleton (many files may reference [IVCoreSettings]
## for read only).[br][br]
##
## By default, this class will begin initialization after a 5 frame delay. To
## modify this, see [member init_after_delay], [member init_delay], and [method
## begin_init].[br][br]
##
## Init sequence is specified and can be modified in [member init_sequence].[br][br]
##
## The simulator root node can be specified by setting [member universe] or
## [member universe_path]. If left unset (default), the program will search for
## a node in the scene tree named "Universe".[br][br]
##
## "Init" and "program" objects are specified and can be modified in dictionaries
## [member init_refcounteds], [member program_refcounteds] and [member program_nodes].
## Instantiation order (and add order for nodes) can be specified where needed
## in the corresponding "ordered_" array properties.[br][br]
##
## See [IVUniverseTemplate] for scene tree construction.



## If true (default), this singleton will call [method begin_init] after [member
## init_delay] frames. If false, external project must call [method begin_init].
var init_after_delay := true
## Number of frames waited before this singleton will call [method begin_init]
## (if [member init_after_delay] is still true).
var init_delay := 5 # frames


## Sequence of Callables used for init. This array can be modified during init.
## Specifically, a preinitializer script intantiated at the first step could
## insert or replace Callables after index 0 if needed.
var init_sequence: Array[Callable] = [
	_instantiate_preinitializers,
	_do_conditional_modifications,
	_set_simulator_universe,
	_index_existing_nodes,
	_instantiate_init_refcounteds,
	_instantiate_program_objects,
	_add_program_nodes,
	_finish,
]

## If specified, this will be the root simulator node. The node will be added
## to dictionary [member IVGlobal.program] with key "Universe". If not specified
## here or in [member universe_path], the program will search for a node named
## "Universe" in the scene tree. If specified here, the node name does not
## matter (the simulator always gets it from [member IVGlobal.program]). 
var universe: Node3D
## See [member universe]. A node path can be specified here (e.g., if using
## ivoyager_override.cfg to set).
var universe_path: NodePath

## RefCounted "preinitializer" classes. IVCoreInitializer instances these first
## and keeps private references so they won't free themselves. External
## projects can add file paths here. See class documentation to do this.
var preinitializers: Dictionary[StringName, Variant] = {}

## RefCounted "init" classes. IVCoreInitializer instances these after [member
## preinitializers] and adds to [member IVGlobal.program]. Dictionary values can
## be either classes or class file paths. If specific instantiation order is
## needed, use [member ordered_init_refcounteds]. "Initializers" can erase
## themselves from dictionary [member IVGlobal.program] after init, thereby
## freeing themselves.
var init_refcounteds: Dictionary[StringName, Variant] = {
	TranslationImporter = IVTranslationImporter, # self-removes
	StateAuxiliary = IVStateAuxiliary,
	ResourceInitializer = IVResourceInitializer, # self-removes
	TableInitializer = IVTableInitializer, # self-removes
	InputMapManager = IVInputMapManager,
	AssetPreloader = IVAssetPreloader,
}
## Include keys from [member init_refcounteds] that need to be instantiated
## first and in order.
var ordered_init_refcounteds: Array[StringName] = [&"TranslationImporter", &"StateAuxiliary"]

## RefCounted "program" classes. IVCoreInitializer instances these after [member
## init_refcounteds] and adds to [member IVGlobal.program]. Dictionary values
## can be either classes or class file paths. If specific instantiation order is
## needed, use [member ordered_program_refcounteds].[br][br]
##
## Note for Save plugin: These RefCounted classes cannot have save/load
## persistence because their container dictionary is not persisted. Convert
## class to Node and add in [member program_nodes] if persistence is needed.
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
## Include keys from [member program_refcounteds] that need to be instantiated
## first and in order. (This probably shouldn't be needed. Consider adding the
## class to [member init_refcounteds] if it's needed by other program objects.)
var ordered_program_refcounteds: Array[StringName] = []

## Node "program" classes. IVCoreInitializer instances these after [member
## program_refcounteds], adds to [member IVGlobal.program], and adds as children
## to Universe. Dictionary values can be either classes or class file paths. If
## specific instantiation or add order is needed, use [member
## ordered_program_nodes].[br][br]
##
## Note for Save plugin: For save/load persistence, these Node classes can have:[br][br]
## [code]const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY[/code]  
var program_nodes: Dictionary[StringName, Variant] = {
	# Ordered
	CameraHandler = IVCameraHandler, # remove or replace if not using IVCamera
	Timekeeper = IVTimekeeper,
	SBGHUDsState = IVSBGHUDsState, # (likely to have input in future)
	BodyHUDsState = IVBodyHUDsState,
	InputHandler = IVInputHandler,
	SaveManager = IVSaveManager, # auto removed if plugin missing or disabled
	# Unordered
	Scheduler = IVScheduler,
	ViewManager = IVViewManager,
}
## Include keys from [member program_nodes] that need to be instantiated or
## added first and in order. Note: all are instantiated (in specified order),
## then all are added (in specified order).[br][br]
##
## Node order determines input handling order, where last added is first
## to recieve input. We mainly need to intercept ctrl-Q, ctrl-S, etc., actions
## before CameraHandler or other nodes consume the Q, S, etc., actions.
var ordered_program_nodes: Array[StringName] = [&"CameraHandler", &"Timekeeper",
	&"SBGHUDsState", &"BodyHUDsState", &"InputHandler", &"SaveManager"]

## Include the names of Nodes that already exist in the scene tree that you want
## added to [member IVGlobal.program] for easy access.
var tree_program_nodes: Array[StringName] = [
	&"FragmentIdentifier",
	&"TopUI",
	&"WorldController",
]


var _preinitializers: Array[RefCounted] = []


func _enter_tree() -> void:
	IVFiles.init_from_config(self, IVGlobal.ivoyager_config, "core_initializer")


func _ready() -> void:
	var count_up := 0
	while count_up < init_delay:
		await get_tree().process_frame
		count_up += 1
	if init_after_delay:
		begin_init() # after all other singletons _ready()


## Call only if external project set [member init_after_delay] = false.
func begin_init() -> void:
	var i := 0
	while i < init_sequence.size():
		var callable := init_sequence[i]
		await callable.call()
		i += 1



func _instantiate_preinitializers() -> void:
	for key in preinitializers:
		assert(not IVGlobal.program.has(key))
		var preinitializer: RefCounted = IVFiles.make_object_or_scene(preinitializers[key])
		_preinitializers.append(preinitializer)
		#IVGlobal.program[key] = preinitializer
	IVStateManager.core_init_preinitialized.emit()


func _do_conditional_modifications() -> void:
	if not IVPluginUtils.is_plugin_enabled("ivoyager_save"):
		# This isn't required, but why not...
		program_nodes.erase(&"SaveManager")
		ordered_program_nodes.erase(&"SaveManager")


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


func _instantiate_init_refcounteds() -> void:
	for key in ordered_init_refcounteds:
		assert(not IVGlobal.program.has(key))
		var refcounted: RefCounted = IVFiles.make_object_or_scene(init_refcounteds[key])
		IVGlobal.program[key] = refcounted
		IVStateManager.core_init_object_instantiated.emit(refcounted)
	for key in init_refcounteds:
		if ordered_init_refcounteds.has(key):
			continue
		assert(not IVGlobal.program.has(key))
		var refcounted: RefCounted = IVFiles.make_object_or_scene(init_refcounteds[key])
		IVGlobal.program[key] = refcounted
		IVStateManager.core_init_object_instantiated.emit(refcounted)
	IVStateManager.core_init_init_refcounteds_instantiated.emit()


func _instantiate_program_objects() -> void:
	# RefCounteds
	for key in ordered_program_refcounteds:
		assert(not IVGlobal.program.has(key))
		var refcounted: RefCounted = IVFiles.make_object_or_scene(program_refcounteds[key])
		IVGlobal.program[key] = refcounted
		IVStateManager.core_init_object_instantiated.emit(refcounted)
	for key in program_refcounteds:
		if ordered_program_refcounteds.has(key):
			continue
		assert(not IVGlobal.program.has(key))
		var refcounted: RefCounted = IVFiles.make_object_or_scene(program_refcounteds[key])
		IVGlobal.program[key] = refcounted
		IVStateManager.core_init_object_instantiated.emit(refcounted)
	# Nodes
	for key in ordered_program_nodes:
		assert(not IVGlobal.program.has(key))
		var node: Node = IVFiles.make_object_or_scene(program_nodes[key])
		node.name = key
		IVGlobal.program[key] = node
		IVStateManager.core_init_object_instantiated.emit(node)
	for key in program_nodes:
		if ordered_program_nodes.has(key):
			continue
		assert(not IVGlobal.program.has(key))
		var node: Node = IVFiles.make_object_or_scene(program_nodes[key])
		node.name = key
		IVGlobal.program[key] = node
		IVStateManager.core_init_object_instantiated.emit(node)
	IVStateManager.core_init_program_objects_instantiated.emit()
	await get_tree().process_frame


func _add_program_nodes() -> void:
	for key in ordered_program_nodes:
		var node: Node = IVGlobal.program[key]
		universe.add_child(node)
	for key in program_nodes:
		if ordered_program_nodes.has(key):
			continue
		var node: Node = IVGlobal.program[key]
		universe.add_child(node)
	IVStateManager.core_init_program_nodes_added.emit()
	await get_tree().process_frame


func _finish() -> void:
	IVStateManager.core_init_finished.emit()
