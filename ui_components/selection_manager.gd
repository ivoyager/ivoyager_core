# selection_manager.gd
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
class_name IVSelectionManager
extends RefCounted

## Manages GUI selection and keeps selection history during a user session. 
##
## This class supports any Object type as a GUI "selection". If using selection
## types other than [IVBody], you must provide name-keyed dictionary(ies) of these
## objects at init via [method add_selection_dictionary].[br][br]
## 
## To support any Object type, methods use duck-typing with method/property
## existence tests and fallbacks. For example, [method get_name] obtains a
## selection name as follows:[br][br]
##
## 1. If [member selection] has method "get_selection_name", returns
##    [code]selection.call(&"get_selection_name")[/code].[br]
## 2. If [member selection] has property "name" (always the case for a [Node]),
##    returns [code]selection.get(&"name")[/code].[br]
## 3. Otherwise, fails and returns [code]&""[/code] without error or warning.[br][br]
##
## See individual "get_" methods for duck-type requirements or options. If a
## "get relative selection" method (e.g., [method get_next], [method get_last], etc.)
## returns null rather than an Object, the coresponding "has_" method will
## return false and "select_" method will do nothing (without error or warning).
## [br][br]
## 
## An application may have one or more instances of this class, where one is
## expected to be the "main" selection manager at the top of the UI tree.
## Others (if any) can be added to GUI tree branches for specialized use.
## The plugin's [IVTopUI] adds and sets up a selection manager so that it
## recieves input actions and is availble for general user interface.[br][br]
##
## This class's API provides generic and [IVBody]-specific functionality.
## It can be subclassed to provide additional functionality for other Object
## types; see [member replacement_subclass]. 

signal selection_changed(suppress_camera_move: bool)
signal selection_reselected(suppress_camera_move: bool)


const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_selection_name",
]


## Set this script to generate a subclass in place of IVSelectionManager in
## [method create]. A subclass can do this in their _static_init() for
## project-wide replacement.
static var replacement_subclass: Script

static var _selection_dictionaries: Array[Dictionary] = [IVBody.bodies]



## Current selection. Note that setting this property directly or via setter
## [method set_selection] won't emit [signal selection_changed] or add to
## selection history. Use [method select] or any "select_" method for GUI
## selection.
var selection: Object: get = get_selection, set = set_selection



var _selection_name: StringName # persisted

var _history: Array[WeakRef] = []
var _history_index := -1
var _supress_history := false



## Add dictonaries here that contain potential selections (any Object class)
## keyed by name (as StringName). This is required for [method select_by_name]
## and for save/load persistence of current selection. Each dictionary should
## be added only once at init. 
static func add_selection_dictionary(selections: Dictionary[StringName, Variant]) -> void:
	assert(not _selection_dictionaries.has(selections))
	_selection_dictionaries.append(selections)


## Creates an instance of this class or a subclass specified by [member
## replacement_subclass].
static func create() -> IVSelectionManager:
	if replacement_subclass:
		@warning_ignore("unsafe_method_access")
		return replacement_subclass.new()
	return IVSelectionManager.new()


## Get IVSelectionManager for the provided [param node] (usually a GUI widget).
## This is obtained from the first non-null "selection_manager" property going
## up the node's ancestry tree.
static func get_selection_manager(node: Node) -> IVSelectionManager:
	return IVTree.get_ancestor_object(node, &"selection_manager", true)



func _init() -> void:
	IVStateManager.system_tree_built.connect(_on_system_tree_built)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVGlobal.ui_dirty.connect(_on_ui_dirty)


## Pass shortcut input here if this manager needs to handle it. Returns true
## if handled. Does NOT call [method Viewport.set_input_as_handled]. In
## standard setup, this method is called for the "main" selection manager by
## [IVInputHandler].
func handle_shortcut_input(event: InputEvent) -> bool:
	if !event.is_pressed() or !event.is_action_type():
		return false
	
	# FIXME: Make actions and hotkey descriptions consitent with new methods
	
	if event.is_action("select_forward", true):
		select_history_forward()
	elif event.is_action("select_back", true):
		select_history_back()
	elif event.is_action("select_right", true):
		select_next()
	elif event.is_action("select_left", true):
		select_last()
	elif event.is_action("select_up", true):
		select_up()
	elif event.is_action("select_down", true):
		select_down()
	elif event.is_action("next_star", true):
		select_next_star()
	elif event.is_action("previous_star", true):
		select_last_star()
	elif event.is_action("next_planet", true):
		select_next_planet()
	elif event.is_action("previous_planet", true):
		select_last_planet()
	elif event.is_action("next_nav_moon", true):
		select_next_major_moon()
	elif event.is_action("previous_nav_moon", true):
		select_last_major_moon()
	elif event.is_action("next_moon", true):
		select_next_moon()
	elif event.is_action("previous_moon", true):
		select_last_moon()
	elif event.is_action("next_spacecraft", true):
		select_next_spacecraft()
	elif event.is_action("previous_spacecraft", true):
		select_last_spacecraft()
	else:
		return false # input NOT handled!
	return true



## If [param object] is non-null and not the present [member selection], set
## as new selection, add to history, and emit [signal selection_changed]. If
## the present selection, emit [signal selection_reselected]. If null, nothing
## happens.
func select(object: Object, suppress_camera_move := false) -> void:
	if not object:
		return
	if selection == object:
		selection_reselected.emit(suppress_camera_move)
		return
	set_selection(object)
	_add_selection_to_history()
	selection_changed.emit(suppress_camera_move)


func select_by_name(name: StringName, suppress_camera_move := false) -> void:
	for dict in _selection_dictionaries:
		var object: Object = dict.get(name)
		if object:
			select(object, suppress_camera_move)
			return
	push_warning("Attempted to select non-existent selection name '%s'" % name)


func get_selection() -> Object:
	return selection


func set_selection(object: Object) -> void:
	selection = object
	_selection_name = get_name()


func has_selection() -> bool:
	return selection != null


# TODO: get_history_back() & get_history_forward(). This can make select
# and has methods consistent for null "skip-over".


func select_history_back() -> void:
	if _history_index < 1:
		return
	_history_index -= 1
	var wr: WeakRef = _history[_history_index]
	var object: Object = wr.get_ref()
	if object:
		_supress_history = true
		select(object)
	else:
		select_history_back()


func has_history_back() -> bool:
	return _history_index > 0


func select_history_forward() -> void:
	if _history_index > _history.size() - 2:
		return
	_history_index += 1
	var wr: WeakRef = _history[_history_index]
	var object: Object = wr.get_ref()
	if object:
		_supress_history = true
		select(object)
	else:
		select_history_forward()


func has_history_forward() -> bool:
	return _history_index < _history.size() - 1



# *****************************************************************************
# Below use duck typing, after checking method or property exists...

## Get name for current selection. This is obtained from selection method
## [code]get_selection_name()[/code] (if exists) or property [code]name[/code]
## (if exists). Otherwise returns &"".
func get_name() -> StringName:
	if not selection:
		return &""
	if selection.has_method(&"get_selection_name"):
		return selection.call(&"get_selection_name")
	if &"name" in selection:
		return selection.get(&"name")
	return &""


## Get GUI name for current selection. This is obtained from selection method
## [code]get_selection_gui_name()[/code] (if exists), property [code]gui_name[/code] (if exists),
## or the translated result of [method get_name]. Note: "GUI names" are
## always already translated Strings (these might be player-editable).
func get_gui_name() -> String:
	if not selection:
		return ""
	if selection.has_method(&"get_selection_gui_name"):
		return selection.call(&"get_selection_gui_name")
	if &"gui_name" in selection:
		return selection.get(&"gui_name")
	return tr(get_name())


## Get Texture2D for current selection. This is obtained from selection method
## [code]get_selection_texture_2d()[/code] (if exists) or property [code]texture_2d[/code] (if
## exists). Otherwise returns null.
func get_texture_2d() -> Texture2D:
	if not selection:
		return null
	if selection.has_method(&"get_selection_texture_2d"):
		return selection.call(&"get_selection_texture_2d")
	if &"texture_2d" in selection:
		return selection.get(&"texture_2d")
	return null


## Get camera Node3D for current selection. This is obtained from selection
## method [code]get_selection_camera_target()[/code] (if exists), selection property
## [code]camera_target[/code] (if exists), or the selection itself if it is a Node3D.
## Otherwise returns null.
func get_camera_target() -> Node3D:
	if not selection:
		return null
	if selection.has_method(&"get_selection_camera_target"):
		return selection.call(&"get_selection_camera_target")
	if &"camera_target" in selection:
		return selection.get(&"camera_target")
	if selection is Node3D:
		return selection
	return null


## Get IVBody for current selection. This is obtained from selection
## method [code]get_selection_body()[/code] (if exists), selection property
## [code]body[/code] (if exists), or the selection itself if it is an [IVBody].
## Otherwise returns null.
func get_body() -> IVBody:
	if not selection:
		return null
	if selection.has_method(&"get_selection_body"):
		return selection.call(&"get_selection_body")
	if &"body" in selection:
		return selection.get(&"body")
	if selection is IVBody:
		return selection
	return null


## Returns body.name if [method get_body] is not null, otherwise &"".
func get_body_name() -> StringName:
	var body := get_body()
	return body.name if body else &""


## Returns body.flags if [method get_body] is not null, otherwise 0.
func get_body_flags() -> int:
	var body := get_body()
	return body.flags if body else 0


## Returns result of method [code]get_float_precision(path)[/code], if exists,
## otherwise -1. Only relevant if [member IVCoreSettings.enable_precisions]
## == true, which is probably not the case for most games. (The setting is used
## by the Planetarium for scientifically correct precision display.)
func get_float_precision(path: String) -> int:
	if not selection:
		return -1
	if selection.has_method(&"get_float_precision"):
		return selection.call(&"get_float_precision", path)
	return -1



## Get "up" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_up")[/code] if the method exists,
## otherwise null.
func get_up() -> Object:
	if selection and selection.has_method(&"get_selection_up"):
		return selection.call(&"get_selection_up")
	return null


## Selects [method get_up] if not null.
func select_up() -> void:
	select(get_up())


## Returns true if [method get_up] is not null.
func has_up() -> bool:
	return get_up() != null


## Get "down" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_down")[/code] if the method exists,
## otherwise null.
func get_down() -> Object:
	if selection and selection.has_method(&"get_selection_down"):
		return selection.call(&"get_selection_down")
	return null


## Selects [method get_down] if not null.
func select_down() -> void:
	select(get_down())


## Returns true if [method get_down] is not null.
func has_down() -> bool:
	return get_down() != null


## Get "next" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_next")[/code] if the method exists,
## otherwise null.
func get_next() -> Object:
	if selection and selection.has_method(&"get_selection_next"):
		return selection.call(&"get_selection_next")
	return null


## Selects [method get_next] if not null.
func select_next() -> void:
	select(get_next())


## Returns true if [method get_next] is not null.
func has_next() -> bool:
	return get_next() != null


## Get "last" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_last")[/code] if the method exists,
## otherwise null.
func get_last() -> Object:
	if selection and selection.has_method(&"get_selection_last"):
		return selection.call(&"get_selection_last")
	return null


## Selects [method get_last] if not null.
func select_last() -> void:
	select(get_last())


## Returns true if [method get_last] is not null.
func has_last() -> bool:
	return get_last() != null


## Get "next_star" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_next_star")[/code] if the method exists,
## otherwise null.
func get_next_star() -> Object:
	if selection and selection.has_method(&"get_selection_next_star"):
		return selection.call(&"get_selection_next_star")
	return null


## Selects [method get_next_star] if not null.
func select_next_star() -> void:
	select(get_next_star())


## Returns true if [method get_next_star] is not null.
func has_next_star() -> bool:
	return get_next_star() != null


## Get "last_star" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_last_star")[/code] if the method exists,
## otherwise null.
func get_last_star() -> Object:
	if selection and selection.has_method(&"get_selection_last_star"):
		return selection.call(&"get_selection_last_star")
	return null


## Selects [method get_last_star] if not null.
func select_last_star() -> void:
	select(get_last_star())


## Returns true if [method get_last_star] is not null.
func has_last_star() -> bool:
	return get_last_star() != null


## Get "next_planet" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_next_planet")[/code] if the method exists,
## otherwise null.
func get_next_planet() -> Object:
	if selection and selection.has_method(&"get_selection_next_planet"):
		return selection.call(&"get_selection_next_planet")
	return null


## Selects [method get_next_planet] if not null.
func select_next_planet() -> void:
	select(get_next_planet())


## Returns true if [method get_next_planet] is not null.
func has_next_planet() -> bool:
	return get_next_planet() != null


## Get "last_planet" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_last_planet")[/code] if the method exists,
## otherwise null.
func get_last_planet() -> Object:
	if selection and selection.has_method(&"get_selection_last_planet"):
		return selection.call(&"get_selection_last_planet")
	return null


## Selects [method get_last_planet] if not null.
func select_last_planet() -> void:
	select(get_last_planet())


## Returns true if [method get_last_planet] is not null.
func has_last_planet() -> bool:
	return get_last_planet() != null


## Get "next_major_moon" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_next_major_moon")[/code] if the method exists,
## otherwise null.
func get_next_major_moon() -> Object:
	if selection and selection.has_method(&"get_selection_next_major_moon"):
		return selection.call(&"get_selection_next_major_moon")
	return null


## Selects [method get_next_major_moon] if not null.
func select_next_major_moon() -> void:
	select(get_next_major_moon())


## Returns true if [method get_next_major_moon] is not null.
func has_next_major_moon() -> bool:
	return get_next_major_moon() != null


## Get "last_major_moon" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_last_major_moon")[/code] if the method exists,
## otherwise null.
func get_last_major_moon() -> Object:
	if selection and selection.has_method(&"get_selection_last_major_moon"):
		return selection.call(&"get_selection_last_major_moon")
	return null


## Selects [method get_last_major_moon] if not null.
func select_last_major_moon() -> void:
	select(get_last_major_moon())


## Returns true if [method get_last_major_moon] is not null.
func has_last_major_moon() -> bool:
	return get_last_major_moon() != null


## Get "next_moon" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_next_moon")[/code] if the method exists,
## otherwise null.
func get_next_moon() -> Object:
	if selection and selection.has_method(&"get_selection_next_moon"):
		return selection.call(&"get_selection_next_moon")
	return null


## Selects [method get_next_moon] if not null.
func select_next_moon() -> void:
	select(get_next_moon())


## Returns true if [method get_next_moon] is not null.
func has_next_moon() -> bool:
	return get_next_moon() != null


## Get "last_moon" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_last_moon")[/code] if the method exists,
## otherwise null.
func get_last_moon() -> Object:
	if selection and selection.has_method(&"get_selection_last_moon"):
		return selection.call(&"get_selection_last_moon")
	return null


## Selects [method get_last_moon] if not null.
func select_last_moon() -> void:
	select(get_last_moon())


## Returns true if [method get_last_moon] is not null.
func has_last_moon() -> bool:
	return get_last_moon() != null


## Get "next_spacecraft" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_next_spacecraft")[/code] if the method exists,
## otherwise null.
func get_next_spacecraft() -> Object:
	if selection and selection.has_method(&"get_selection_next_spacecraft"):
		return selection.call(&"get_selection_next_spacecraft")
	return null


## Selects [method get_next_spacecraft] if not null.
func select_next_spacecraft() -> void:
	select(get_next_spacecraft())


## Returns true if [method get_next_spacecraft] is not null.
func has_next_spacecraft() -> bool:
	return get_next_spacecraft() != null


## Get "last_spacecraft" selection from the current [member selection]. Returns
## [code]selection.call(&"get_selection_last_spacecraft")[/code] if the method exists,
## otherwise null.
func get_last_spacecraft() -> Object:
	if selection and selection.has_method(&"get_selection_last_spacecraft"):
		return selection.call(&"get_selection_last_spacecraft")
	return null


## Selects [method get_last_spacecraft] if not null.
func select_last_spacecraft() -> void:
	select(get_last_spacecraft())


## Returns true if [method get_last_spacecraft] is not null.
func has_last_spacecraft() -> bool:
	return get_last_spacecraft() != null



func erase_history() -> void:
	_history.clear()
	_history_index = -1


## @deprecated
func get_selection_and_history() -> Array:
	return [selection, _history.duplicate(), _history_index]


## @deprecated
func set_selection_and_history(array: Array) -> void:
	var object: Object = array[0]
	set_selection(object)
	_history = array[1]
	_history_index = array[2]


func _clear_procedural() -> void:
	selection = null
	_selection_name = &""


func _on_system_tree_built(is_new_game: bool) -> void:
	if is_new_game:
		_selection_name = IVCoreSettings.home_name
	select_by_name(_selection_name, true)


func _on_ui_dirty() -> void:
	selection_changed.emit(true)


func _add_selection_to_history() -> void:
	if _supress_history:
		_supress_history = false
		return
	if _history_index >= 0:
		var last_wr: WeakRef = _history[_history_index]
		var last_selection: Object = last_wr.get_ref()
		if last_selection == selection:
			return
	_history_index += 1
	if _history.size() > _history_index:
		_history.resize(_history_index)
	var wr: WeakRef = weakref(selection)
	_history.append(wr)
