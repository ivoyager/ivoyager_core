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
extends Node

## Has currently selected item (using [IVSelection] wrapper class) and keeps
## selection history. 
##
## An application may have one or more instances of this class, which are
## each associated with an individual [Control]. GUI widgets can call static
## [method get_selection_manager] to obtain the first instance of this
## class searching up their ancestor tree. If there are >1 instances, set
## [member is_action_listener] == false for additional instances that should
## not respond to key action input.    [br][br]
##
## This node may or may not be a "persist" node for game save/load, depending
## on how it is used in the scene tree. If it is child of a persist node,
## it will be be persisted. In either case, all IVSelectionManager references
## must be cleared (and nodes freed) on [signal
## IVStateManager.about_to_free_procedural_nodes]. They can be set on or after
## [signal IVStateManager.system_tree_built].


signal selection_changed(suppress_camera_move: bool)
signal selection_reselected(suppress_camera_move: bool)


enum {
	# not all of these are implemented yet...
	SELECTION_UNIVERSE,
	SELECTION_GALAXY,
	SELECTION_STAR_SYSTEM,
	SELECTION_STAR,
	SELECTION_TRUE_PLANET,
	SELECTION_DWARF_PLANET,
	SELECTION_PLANET, # both kinds ;-)
	SELECTION_NAVIGATOR_MOON, # present in navigator GUI
	SELECTION_MOON,
	SELECTION_ASTEROID,
	SELECTION_COMMET,
	SELECTION_SPACECRAFT,
	SELECTION_ALL_ASTEROIDS,
	SELECTION_ASTEROID_GROUP,
	SELECTION_ALL_COMMETS,
	SELECTION_ALL_SPACECRAFTS,
	# useful?
	SELECTION_BARYCENTER,
	SELECTION_LAGRANGE_POINT,
}


const BodyFlags := IVBody.BodyFlags

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"is_action_listener",
	&"selection",
]


static var replacement_subclass: Script

# persisted
var is_action_listener := true
var selection: IVSelection

# private
var _history: Array[WeakRef] = []
var _history_index := -1
var _supress_history := false



static func create() -> IVSelectionManager:
	if replacement_subclass:
		@warning_ignore("unsafe_method_access")
		return replacement_subclass.new()
	return IVSelectionManager.new()


static func get_selection_manager(control: Control) -> IVSelectionManager:
	return IVUtils.get_tree_object(control, &"selection_manager", true)


static func get_or_make_selection(selection_name: StringName) -> IVSelection:
	# I, Voyager supports IVBody selection only! Override for others.
	var selection_: IVSelection = IVSelection.selections.get(selection_name)
	if selection_:
		return selection_
	if IVBody.bodies.has(selection_name):
		return make_selection_for_body(selection_name)
	assert(false, "Unsupported selection type")
	return null


static func make_selection_for_body(body_name: StringName) -> IVSelection:
	assert(!IVSelection.selections.has(body_name))
	var body: IVBody = IVBody.bodies[body_name] # must exist
	#var selection_builder: IVSelectionBuilder = IVGlobal.program[&"SelectionBuilder"]
	var selection_ := IVSelection.create_for_body(body)
	if selection_:
		IVSelection.selections[body_name] = selection_
	return selection_


static func get_body_above_selection(selection_: IVSelection) -> IVBody:
	while selection_.up_selection_name:
		selection_ = get_or_make_selection(selection_.up_selection_name)
		if selection_.body:
			return selection_.body
	return IVBody.galaxy_orbiters.values()[0]


static func get_body_at_above_selection_w_flags(selection_: IVSelection, flags: int) -> IVBody:
	if selection_.get_body_flags() & flags:
		return selection_.body
	while selection_.up_selection_name:
		selection_ = get_or_make_selection(selection_.up_selection_name)
		if selection_.get_body_flags() & flags:
			return selection_.body
	return null



# TODO: Remove all name sets (except where needed) and allow name to have "IV" prefix
func _init() -> void:
	name = &"SelectionManager"


func _ready() -> void:
	IVStateManager.system_tree_ready.connect(_on_system_tree_ready)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVGlobal.ui_dirty.connect(_on_ui_dirty)
	set_process_shortcut_input(is_action_listener)


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action_pressed("select_forward"):
		forward()
	elif event.is_action_pressed("select_back"):
		back()
	elif event.is_action_pressed("select_left"):
		next_last(-1)
	elif event.is_action_pressed("select_right"):
		next_last(1)
	elif event.is_action_pressed("select_up"):
		up()
	elif event.is_action_pressed("select_down"):
		down()
	elif event.is_action_pressed("next_star"):
		next_last(1, SELECTION_STAR)
	elif event.is_action_pressed("previous_planet"):
		next_last(-1, SELECTION_PLANET)
	elif event.is_action_pressed("next_planet"):
		next_last(1, SELECTION_PLANET)
	elif event.is_action_pressed("previous_nav_moon"):
		next_last(-1, SELECTION_NAVIGATOR_MOON)
	elif event.is_action_pressed("next_nav_moon"):
		next_last(1, SELECTION_NAVIGATOR_MOON)
	elif event.is_action_pressed("previous_moon"):
		next_last(-1, SELECTION_MOON)
	elif event.is_action_pressed("next_moon"):
		next_last(1, SELECTION_MOON)
	elif event.is_action_pressed("previous_spacecraft"):
		next_last(-1, SELECTION_SPACECRAFT)
	elif event.is_action_pressed("next_spacecraft"):
		next_last(1, SELECTION_SPACECRAFT)
	else:
		return # input NOT handled!
	get_viewport().set_input_as_handled()



func select(selection_: IVSelection, suppress_camera_move := false) -> void:
	if selection == selection_:
		selection_reselected.emit(suppress_camera_move)
		return
	selection = selection_
	_add_history()
	selection_changed.emit(suppress_camera_move)


func select_body(body: IVBody, suppress_camera_move := false) -> void:
	var selection_ := get_or_make_selection(body.name)
	if selection_:
		select(selection_, suppress_camera_move)


func select_by_name(selection_name: StringName, suppress_camera_move := false) -> void:
	var selection_ := get_or_make_selection(selection_name)
	if selection_:
		select(selection_, suppress_camera_move)


func has_selection() -> bool:
	return selection != null


func get_selection() -> IVSelection:
	return selection


func get_gui_name() -> String:
	# return is already translated
	return selection.get_gui_name() if selection else ""


func get_selection_name() -> StringName:
	return selection.name if selection else &""


func get_body_name() -> StringName:
	return selection.get_body_name() if selection else &""


func get_texture_2d() -> Texture2D:
	return selection.texture_2d if selection else null


func get_body() -> IVBody:
	return selection.body if selection else null


func is_body() -> bool:
	return selection.is_body


func back() -> void:
	if _history_index < 1:
		return
	_history_index -= 1
	var wr: WeakRef = _history[_history_index]
	var new_selection: IVSelection = wr.get_ref()
	if new_selection:
		_supress_history = true
		select(new_selection)
	else:
		back()


func forward() -> void:
	if _history_index > _history.size() - 2:
		return
	_history_index += 1
	var wr: WeakRef = _history[_history_index]
	var new_selection: IVSelection = wr.get_ref()
	if new_selection:
		_supress_history = true
		select(new_selection)
	else:
		forward()


func up() -> void:
	var up_name := selection.up_selection_name
	if up_name:
		var new_selection := get_or_make_selection(up_name)
		select(new_selection)


func can_go_back() -> bool:
	return _history_index > 0


func can_go_forward() -> bool:
	return _history_index < _history.size() - 1


func can_go_up() -> bool:
	return selection and selection.up_selection_name


func down() -> void:
	var body: IVBody = selection.body
	if body and body.satellites:
		var satellite: IVBody = body.satellites.values()[0]
		select_body(satellite)


func next_last(incr: int, selection_type := -1, _alt_selection_type := -1) -> void:
	const BODYFLAGS_STAR := IVBody.BodyFlags.BODYFLAGS_STAR
	const BODYFLAGS_PLANET_OR_DWARF_PLANET := IVBody.BodyFlags.BODYFLAGS_PLANET_OR_DWARF_PLANET
	const BODYFLAGS_MOON := IVBody.BodyFlags.BODYFLAGS_MOON
	
	var current_body := selection.body # could be null
	var iteration_array: Array
	var index := -1
	match selection_type:
		-1:
			var up_body := get_body_above_selection(selection)
			iteration_array = up_body.satellites.values()
			index = iteration_array.find(current_body)
		SELECTION_STAR:
			# TODO: code for multistar systems
			var sun: IVBody = IVBody.galaxy_orbiters.values()[0]
			select_body(sun)
			return
		SELECTION_PLANET:
			var star := get_body_at_above_selection_w_flags(selection, BODYFLAGS_STAR)
			if !star:
				return
			iteration_array = star.satellites.values()
			var planet := get_body_at_above_selection_w_flags(selection,
					BODYFLAGS_PLANET_OR_DWARF_PLANET)
			if planet:
				index = iteration_array.find(planet)
				if planet != current_body and incr == 1:
					index -= 1
		SELECTION_NAVIGATOR_MOON, SELECTION_MOON:
			var planet := get_body_at_above_selection_w_flags(selection,
					BODYFLAGS_PLANET_OR_DWARF_PLANET)
			if !planet:
				return
			iteration_array = planet.satellites.values()
			var moon := get_body_at_above_selection_w_flags(selection, BODYFLAGS_MOON)
			if moon:
				index = iteration_array.find(moon)
				if moon != current_body and incr == 1:
					index -= 1
		SELECTION_SPACECRAFT:
			if current_body:
				iteration_array = current_body.satellites.values()
			else:
				var up_body := get_body_above_selection(selection)
				iteration_array = up_body.satellites.values()
	if !iteration_array:
		return
	var array_size := iteration_array.size()
	var count := 0
	while count < array_size:
		index += incr
		if index < 0:
			index = array_size - 1
		elif index >= array_size:
			index = 0
		var body: IVBody = iteration_array[index]
		var do_selection := false
		match selection_type:
			-1:
				do_selection = true
			SELECTION_STAR:
				do_selection = bool(body.flags & BodyFlags.BODYFLAGS_STAR)
			SELECTION_PLANET:
				do_selection = bool(body.flags & BodyFlags.BODYFLAGS_PLANET_OR_DWARF_PLANET)
			SELECTION_NAVIGATOR_MOON:
				do_selection = (body.flags & BodyFlags.BODYFLAGS_MOON
						and body.flags & BodyFlags.BODYFLAGS_SHOW_IN_NAVIGATION_PANEL)
			SELECTION_MOON:
				do_selection = bool(body.flags & BodyFlags.BODYFLAGS_MOON)
			SELECTION_SPACECRAFT:
				do_selection = bool(body.flags & BodyFlags.BODYFLAGS_SPACECRAFT)
		if do_selection:
			select_body(body)
			return
		count += 1


func erase_history() -> void:
	_history.clear()
	_history_index = -1


func get_selection_and_history() -> Array:
	return [selection, _history.duplicate(), _history_index]


func set_selection_and_history(array: Array) -> void:
	selection = array[0]
	_history = array[1]
	_history_index = array[2]


func _clear_procedural() -> void:
	selection = null


func _on_system_tree_ready(is_new_game: bool) -> void:
	if is_new_game:
		var selection_ := get_or_make_selection(IVCoreSettings.home_name)
		select(selection_, true)
	else:
		_add_history()


func _on_ui_dirty() -> void:
	selection_changed.emit(true)


func _add_history() -> void:
	if _supress_history:
		_supress_history = false
		return
	if _history_index >= 0:
		var last_wr: WeakRef = _history[_history_index]
		var last_selection: IVSelection = last_wr.get_ref()
		if last_selection == selection:
			return
	_history_index += 1
	if _history.size() > _history_index:
		_history.resize(_history_index)
	var wr: WeakRef = weakref(selection) # weakref() is untyped in Godot4.1.1. Open issue? 
	_history.append(wr)
