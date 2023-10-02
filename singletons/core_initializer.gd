# core_initializer.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2023 Charlie Whitfield
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

# This node is added as singleton 'IVCoreInitializer'.
#
# Modify properties or dictionary classes using res://ivoyager_override.cfg.
# Alternatively, you can use an initializer script.
#
# DON'T modify values here after program start!


# This node builds the program (not the solar system!) and makes program
# nodes, references, and class scripts availible in IVGlobal dictionaries. All
# dictionaries here (except procedural_objects) define "small-s singletons";
# a single instance of each class is instantiated, and nodes are added to
# either the top Node3D node (specified by 'universe') or the top Control node
# (specified by 'top_gui'). All object instantiations can be accessed in
# IVGlobal dictionary 'program' and all class scripts can be accessed in
# IVGlobal dictionary 'procedural_objects'.
#
# Only extension init files should access this node.
# RUNTIME CLASS FILES SHOULD NOT ACCESS THIS NODE!
#
# See example extension files for our Planetarium and Project Template:
# https://github.com/ivoyager/planetarium/blob/master/planetarium/planetarium.gd
# https://github.com/ivoyager/project_template/blob/master/replace_me/replace_me.gd
#
# To modify and extend I, Voyager:
# 1. Create an extension init file with path "res://<name>/<name>.gd" where
#    <name> is the name of your project or addon. This file should have an
#    _extension_init() function. Instructions 2-3 refer to this file.
# 2. Use _extension_init() to:
#     a. modify "project init" values in the IVGlobal singleton.
#     b. modify this node's dictionaries to extend (i.e., subclass) or replace
#        existing classes, remove classes, or add new classes. You can remove a
#        class by either erasing the dictionary key or setting it to null.
#     (Above happens before anything else is instantiated!)
# 3. Hook up to IVGlobal 'project_objects_instantiated' signal to modify
#    init values of instantiated Nodes (before they are added to tree) or
#    RefCounteds (before they are used). Nodes and RefCounteds can be
#    accessed after instantiation in the IVGlobal.program dictionary.
# 4. Build your project GUI using the many widgets in ivoyager/gui_widgets.
#
# By itself, ivoyager will run but it lacks a GUI: the default IVTopGUI has no
# child GUIs. You can either build on the existing IVTopGUI or provide your own
# by setting 'top_gui' here (but see comments in tree_nodes/top_gui.gd).
#
# For a game that needs a splash screen at startup, add the splash screen to
# 'gui_nodes' here and set IVCoreSettings.skip_splash_screen = false (for example,
# see https://github.com/ivoyager/project_template).


signal init_step_finished() # for internal use only

const files := preload("../static/files.gd")


# *************** PROJECT VARS - MODIFY THESE TO EXTEND !!!! ******************


var allow_project_build := true
var init_delay := 5 # frames


# init_sequence can be modified even after started (eg, by a preinitializer).
var init_sequence: Array[Array] = [
	# [object, method, wait_for_signal]
#	[self, "_init_extensions", false],
	[self, "_instantiate_preinitializers", false],
	[self, "_instantiate_initializers", false],
	[self, "_set_simulator_root", false],
	[self, "_set_simulator_top_gui", false],
	[self, "_instantiate_and_index_program_objects", false],
	[self, "_init_program_objects", true],
	[self, "_add_program_nodes", true],
	[self, "_finish", false]
]

# All nodes instatiated here are added to 'universe' or 'top_gui'. Use
# ivoyager_override.cfg or a preinitializer script to set either or both of
# these. Otherwise, IVCoreInitializer will assign default nodes from
# ivoyager_core (or for universe, by tree search for 'Universe').
# Whatever is assigned will be accessible from IVGlobal.program["Universe"] and
# IVGlobal.program["TopGUI"], irrespective of node names.

var universe: Node3D
var top_gui: Control
var universe_path: String # assign here if using ivoyager_override.cfg
var top_gui_path: String # assign here if using ivoyager_override.cfg
var add_top_gui_to_universe := true # if true, happens in add_program_nodes()

# Replace classes in dictionaries below with a subclass of the original unless
# comment indicates otherwise. E.g., "Node3D ok": replace with a class that
# extends Node3D. In some cases, elements can be erased for unneeded systems.
#
# Key formatting '_ClassName_' below is meant to be a reminder that the keyed
# item at runtime might be a project-specific subclass (or in some cases
# replacement) for the original class. For objects instanced by IVCoreInitializer,
# edge underscores are removed to form keys in the IVGlobal.program dictionary
# and the 'name' property in the case of nodes.
#
# All dictionary values below can be any one of three things:
#   - A GDScript class_name global
#   - A path to a GDScript object (*.gd)
#   - A path to a scene (*.tscn, *.scn)

var preinitializers := {
	# RefCounted classes. IVCoreInitializer instances these first. External
	# projects can add script paths here using 'res://ivoyager_override.cfg'.
	# A reference is kept in dictionary 'IVGlobal.program' (erase it if you
	# want to de-reference your preinitializer so it will free itself).
}


var initializers := {
	# RefCounted classes. IVCoreInitializer instances these after
	# 'preinitializers'. These classes typically erase themselves from
	# dictionary 'IVGlobal.program' after init, thereby freeing themselves.
	_LogInitializer_ = IVLogInitializer,
	_AssetInitializer_ = IVAssetInitializer,
	_SharedResourceInitializer_ = IVSharedResourceInitializer,
	_WikiInitializer_ = IVWikiInitializer,
	_TranslationImporter_ = IVTranslationImporter,
	_TableInitializer_ = IVTableInitializer,
}

var program_refcounteds := {
	# RefCounted classes. IVCoreInitializer instances one of each and adds to
	# dictionary IVGlobal.program. No save/load persistence.
	
	# need first!
	_SettingsManager_ = IVSettingsManager, # 1st so IVGlobal.settings are valid
	
	# builders (generators, often from table or binary data)
	_EnvironmentBuilder_ = IVEnvironmentBuilder,
	_SystemBuilder_ = IVSystemBuilder,
	_BodyBuilder_ = IVBodyBuilder,
	_SBGBuilder_ = IVSBGBuilder,
	_OrbitBuilder_ = IVOrbitBuilder,
	_SelectionBuilder_ = IVSelectionBuilder,
	_CompositionBuilder_ = IVCompositionBuilder, # remove or subclass
	_SaveBuilder_ = IVSaveBuilder, # ok to remove if you don't need game save
	
	# finishers (modify something on entering tree)
	_BodyFinisher_ = IVBodyFinisher,
	_SBGFinisher_ = IVSBGFinisher,
	
	# managers
	_IOManager_ = IVIOManager,
	_InputMapManager_ = IVInputMapManager,
	_FontManager_ = IVFontManager, # ok to replace
	_ThemeManager_ = IVThemeManager, # after IVFontManager; ok to replace
	_MainMenuManager_ = IVMainMenuManager,
	_SleepManager_ = IVSleepManager,
	_WikiManager_ = IVWikiManager,
	_ModelManager_ = IVModelManager,
	
	# tools and resources
	_ViewDefaults_ = IVViewDefaults,
}

var program_nodes := {
	# IVCoreInitializer instances one of each and adds as child to Universe
	# (before/"below" TopGUI) and to dictionary IVGlobal.program.
	# Use PERSIST_MODE = PERSIST_PROPERTIES_ONLY if there is data to persist.
	_Scheduler_ = IVScheduler,
	_ViewManager_ = IVViewManager,
	_FragmentIdentifier_ = IVFragmentIdentifier, # safe to remove
	
	# Nodes below are ordered for input handling (last is first). We mainly
	# need to intercept cntr-something actions (quit, full-screen, etc.) before
	# CameraHandler. Universe children can be reordered after
	# 'project_nodes_added' signal using API below.
	_CameraHandler_ = IVCameraHandler, # remove or replace if not using IVCamera
	_Timekeeper_ = IVTimekeeper,
	_WindowManager_ = IVWindowManager,
	_SBGHUDsState_ = IVSBGHUDsState, # (likely to have input in future)
	_BodyHUDsState_ = IVBodyHUDsState,
	_InputHandler_ = IVInputHandler,
	_SaveManager_ = IVSaveManager, # remove if you don't need game saves
	_StateManager_ = IVStateManager,
}

var gui_nodes := {
	# IVCoreInitializer instances one of each and adds as child to TopGUI (or
	# substitute Control set in 'top_gui') and to dictionary IVGlobal.program.
	# Order determines visual 'on top' and input event handling: last added
	# is on top and 1st handled. TopGUI children can be reordered after
	# 'project_nodes_added' signal using API below.
	# Use PERSIST_MODE = PERSIST_PROPERTIES_ONLY for save/load persistence.
	_WorldController_ = IVWorldController, # Control ok
	_MouseTargetLabel_ = IVMouseTargetLabel, # safe to replace or remove
	_GameGUI_ = null, # assign here if convenient (above MouseTargetLabel, below SplashScreen)
	_SplashScreen_ = null, # assign here if convenient (below popups)
	_MainMenuPopup_ = IVMainMenuPopup, # safe to replace or remove
	_LoadDialog_ = IVLoadDialog, # safe to replace or remove
	_SaveDialog_ = IVSaveDialog, # safe to replace or remove
	_OptionsPopup_ = IVOptionsPopup, # safe to replace or remove
	_HotkeysPopup_ = IVHotkeysPopup, # safe to replace or remove
	_Confirmation_ = IVConfirmation, # safe to replace or remove
	_MainProgBar_ = IVMainProgBar, # safe to replace or remove
}

var procedural_objects := {
	# Nodes and references NOT instantiated by IVCoreInitializer. These class
	# scripts plus all above can be accessed from IVGlobal.procedural_classes (keys
	# have underscores). 
	# tree_nodes
	_Body_ = IVBody, # many dependencies, best to subclass
	_Camera_ = IVCamera, # replaceable, but look for dependencies
	_BodyLabel_ = IVBodyLabel, # replace w/ Node3D
	_BodyOrbit_ = IVBodyOrbit, # replace w/ Node3D
	_SBGOrbits_ = IVSBGOrbits, # replace w/ Node3D
	_SBGPoints_ = IVSBGPoints, # replace w/ Node3D
	_LagrangePoint_ = IVLagrangePoint, # replace w/ subclass
	_ModelSpace_ = IVModelSpace, # replace w/ Node3D
	_RotatingSpace_ = IVRotatingSpace, # replace w/ subclass
	_Rings_ = IVRings, # replace w/ Node3D
	_SpheroidModel_ = IVSpheroidModel, # replace w/ Node3D
	_SelectionManager_ = IVSelectionManager, # replace w/ Node3D
	# tree_refs
	_SmallBodiesGroup_ = IVSmallBodiesGroup,
	_Orbit_ = IVOrbit,
	_Selection_ = IVSelection,
	_View_ = IVView,
	_Composition_ = IVComposition, # replaceable, but look for dependencies	
}


# ***************************** PRIVATE VARS **********************************

var _program: Dictionary = IVGlobal.program
var _procedural_classes: Dictionary = IVGlobal.procedural_classes


# ****************************** PROJECT BUILD ********************************


func _enter_tree() -> void:
	const plugin_utils := preload("../editor_plugin/plugin_utils.gd")
	var config: ConfigFile = plugin_utils.get_config_with_override(
			"res://addons/ivoyager_core/core.cfg",
			"res://ivoyager_override.cfg", "core_initializer")
	plugin_utils.init_from_config(self, config, "core_initializer")


func _ready() -> void:
	var init_countdown := init_delay
	while init_countdown > 0:
		await get_tree().process_frame
		init_countdown -= 1
	build_project() # after all other singletons _ready()


# **************************** PUBLIC FUNCTIONS *******************************
# These should be called only by extension init file!

func reindex_universe_child(node_name: StringName, new_index: int) -> void:
	# Call at 'project_nodes_added' signal.
	var node: Node = _program[node_name]
	universe.move_child(node, new_index)


func reindex_top_gui_child(node_name: StringName, new_index: int) -> void:
	# Call at 'project_nodes_added' signal.
	var node: Node = _program[node_name]
	top_gui.move_child(node, new_index)


func move_universe_child_to_sibling(node_name: StringName, sibling_name: StringName,
		before_sibling: bool) -> void:
	# Call at 'project_nodes_added' signal.
	var node: Node = _program[node_name]
	var sibling: Node = _program[sibling_name]
	var sibling_index := sibling.get_index()
	universe.move_child(node, sibling_index if before_sibling else sibling_index + 1)


func move_top_gui_child_to_sibling(node_name: StringName, sibling_name: StringName,
		before_sibling: bool) -> void:
	# Call at 'project_nodes_added' signal.
	var node: Node = _program[node_name]
	var sibling: Node = _program[sibling_name]
	var sibling_index := sibling.get_index()
	top_gui.move_child(node, sibling_index if before_sibling else sibling_index + 1)


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
	for key in preinitializers:
		if !preinitializers[key]:
			continue
		var preinitializer: RefCounted = files.make_object_or_scene(preinitializers[key])
		_program[key] = preinitializer
	IVGlobal.preinitializers_inited.emit()


func _instantiate_initializers() -> void:
	for key in initializers:
		if !initializers[key]:
			continue
		var initializer: RefCounted = files.make_object_or_scene(initializers[key])
		_program[key] = initializer
	IVGlobal.initializers_inited.emit()


func _set_simulator_root() -> void:
	# Simulator root node 'universe' is assigned in one of three ways:
	# 1. External project assigns property 'universe' or 'universe_path' via
	#    preinitializer script or res://ivoyager_override.cfg.
	# 2. This method finds an existing tree node named 'Universe'.
	# 3. This method intantiates IVUniverse (tree_nodes/universe.gd).
	#
	# Note: We don't add Universe to the scene tree here. That must be done
	# elsewhere if it isn't already in the tree.
	# 
	# Note2: ivoyager_core always gets this node via IVGlobal.program.Universe,
	# never by node name. The actual node name doesn't matter.
	if universe:
		return
	if universe_path:
		universe = files.make_object_or_scene(universe_path)
		assert(universe)
		return
	var scenetree_root := get_tree().get_root()
	universe = scenetree_root.find_child("Universe", true, false)
	if universe:
		return
	universe = files.make_object_or_scene(IVUniverse)
	universe.name = "Universe"


func _set_simulator_top_gui() -> void:
	# 'top_gui' is assigned in one of two ways:
	# 1. External project assigns property 'top_gui' or 'top_gui_path' via
	#    preinitializer script or res://ivoyager_override.cfg.
	# 2. This method intantiates IVTopGUI (tree_nodes/top_gui.gd).
	#
	# Method add_program_nodes() will add TopGUI to Universe if
	# add_top_gui_to_universe == true. Otherwise, external project must add it
	# somewhere if it isn't already in the tree.
	#
	# Note: ivoyager_core always gets this node via IVGlobal.program.TopGUI,
	# never by node name. The actual node name doesn't matter.
	if top_gui:
		return
	if top_gui_path:
		top_gui = files.make_object_or_scene(top_gui_path)
		assert(top_gui)
		return
	top_gui = files.make_object_or_scene(IVTopGUI)
	top_gui.name = "TopGUI"


func _instantiate_and_index_program_objects() -> void:
	_program.Global = IVGlobal
	_program.CoreSettings = IVCoreSettings
	_program.Universe = universe
	_program.TopGUI = top_gui
	for dict in [program_refcounteds, program_nodes, gui_nodes]:
		for key in dict:
			var key_str: String = key
			if !dict[key_str]:
				continue
			var object_key: String = key_str.rstrip("_").lstrip("_")
			assert(!_program.has(object_key))
			var object: Object = files.make_object_or_scene(dict[key_str])
			_program[object_key] = object
			if object is Node:
				@warning_ignore("unsafe_property_access")
				object.name = object_key
	for key in procedural_objects:
		if !procedural_objects[key]:
			continue
		assert(!_procedural_classes.has(key))
		_procedural_classes[key] = procedural_objects[key]
	IVGlobal.project_objects_instantiated.emit()


func _init_program_objects() -> void:
#	for key in initializers:
#		var key_str: String = key
#		if !initializers[key_str]:
#			continue
#		var object_key: String = key_str.rstrip("_").lstrip("_")
#		if !_program.has(object_key): # might have removed itself already
#			continue
#		var object: Object = _program[object_key]
#		if object.has_method("_ivcore_init"):
#			@warning_ignore("unsafe_method_access")
#			object._ivcore_init()
	if universe.has_method("_ivcore_init"):
		@warning_ignore("unsafe_method_access")
		universe._ivcore_init()
	if top_gui.has_method("_ivcore_init"):
		@warning_ignore("unsafe_method_access")
		top_gui._ivcore_init()
	for dict in [program_refcounteds, program_nodes, gui_nodes]:
		for key in dict:
			var key_str: String = key
			if !dict[key_str]:
				continue
			var object_key: String = key_str.rstrip("_").lstrip("_")
			var object: Object = _program[object_key]
			if object.has_method("_ivcore_init"):
				@warning_ignore("unsafe_method_access")
				object._ivcore_init()
	IVGlobal.project_inited.emit()
	await get_tree().process_frame
	init_step_finished.emit()


func _add_program_nodes() -> void:
	# TopGUI added after program_nodes, so gui_nodes will recieve input first
	# and then program_nodes.
	for key in program_nodes:
		var key_str: String = key
		if !program_nodes[key_str]:
			continue
		var object_key = key_str.rstrip("_").lstrip("_")
		universe.add_child(_program[object_key])
	if add_top_gui_to_universe:
		universe.add_child(top_gui)
	for key in gui_nodes:
		var key_str: String = key
		if !gui_nodes[key_str]:
			continue
		var object_key = key_str.rstrip("_").lstrip("_")
		top_gui.add_child(_program[object_key])
	IVGlobal.project_nodes_added.emit()
	await get_tree().process_frame
	init_step_finished.emit()


func _finish() -> void:
	IVGlobal.project_builder_finished.emit()


