# small_bodies_group.gd
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
class_name IVSmallBodiesGroup
extends Node

## Base class to represent a large number of orbiting small bodies that are not
## individually instantiated.
##
## Data is packed for use by visual classes IVSBGOrbits and IVSBGPoints, which
## are added when this node is added to the tree on _ready() or upon calling
## rebuild_visuals().
##
## Note that visual nodes must be discarded and rebuilt if any data changes
## (due to visual node use of Godot's MultiMesh and ArrayMesh). This happens
## automatically when calling append_data().
##
## If modifying packed array data directly, it is necessary to ensure correct
## 'max_apoapsis' (call either reset_max_apoapsis() or update_max_apoapsis())
## and then call rebuild_visuals().
##
## TODO: It's possible to modify MultiMesh if it's not a resize. We could build
## signals and modify API to allow for that.
##
## 'de' is not currently implemented (amplitude of e libration in secular
## resonence).

signal group_appended(previous_size: int, new_size: int)
signal adding_visuals() # existing visual nodes must free themselves


enum SBGClass {
	SBG_CLASS_ASTEROIDS,
	SBG_CLASS_COMETS,
	SBG_CLASS_ARTIFICIAL_SATELLITES, # TODO: Roadmap
	SBG_CLASS_OTHER,
}


const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"name",
	&"sbg_alias",
	&"sbg_class",
	&"secondary_body",
	&"lp_integer",
	&"max_apoapsis",
	&"names",
	&"e_i_Om_w",
	&"a_M0_n",
	&"s_g_mag_de",
	&"da_D_f_th0",
]


var sbg_alias: StringName
var sbg_class: SBGClass # SBGClass
var secondary_body: IVBody # e.g., Jupiter for Trojans; usually null
var lp_integer := -1 # -1, 4 & 5 are currently supported
var max_apoapsis := 0.0

var names := PackedStringArray()
var e_i_Om_w := PackedFloat32Array() # fixed & precessing (except e in sec res)
var a_M0_n := PackedFloat32Array() # librating in l-point objects
var s_g_mag_de := PackedFloat32Array() # orbit precessions, magnitude, & e amplitude (sec res only)
var da_D_f_th0 := PackedFloat32Array() # Trojans only

## Contains all IVSmallBodiesGroup instances currently in the tree.
static var small_bodies_groups: Dictionary[StringName, IVSmallBodiesGroup] = {}
static var null_pf32_array := PackedFloat32Array()


func _enter_tree() -> void:
	IVGlobal.add_system_tree_item_started.emit(self)


func _ready() -> void:
	assert(!small_bodies_groups.has(name))
	small_bodies_groups[name] = self
	_build_visuals()
	IVGlobal.add_system_tree_item_finished.emit(self)


func _exit_tree() -> void:
	small_bodies_groups.erase(name)


# *****************************************************************************
# public API

func init(name_: StringName, sbg_alias_: StringName, sbg_class_: SBGClass,
		lp_integer_ := -1, secondary_body_: IVBody = null) -> void:
	# Last 2 args only if these are Lagrange point objects.
	name = name_
	sbg_alias = sbg_alias_
	sbg_class = sbg_class_
	lp_integer = lp_integer_
	secondary_body = secondary_body_


## If possible, append all data before adding this node to the tree. If called
## after tree add, existing visual nodes will be discarded and new ones will
## be created.
func append_data(names_append: PackedStringArray, e_i_Om_w_append: PackedFloat32Array,
		a_M0_n_append: PackedFloat32Array, s_g_mag_de_append: PackedFloat32Array,
		da_D_f_th0_append := null_pf32_array, suppress_max_apoapsis_update := false,
		suppress_visuals_rebuild := false) -> void:
	var n_bodies := names_append.size()
	assert(e_i_Om_w_append.size() == n_bodies * 4)
	assert(a_M0_n_append.size() == n_bodies * 3)
	assert(s_g_mag_de_append.size() == n_bodies * 4)
	assert(da_D_f_th0_append.size() == (0 if lp_integer == -1 else n_bodies * 4))
	
	var previous_size := names.size()
	names.append_array(names_append)
	e_i_Om_w.append_array(e_i_Om_w_append)
	a_M0_n.append_array(a_M0_n_append)
	s_g_mag_de.append_array(s_g_mag_de_append)
	if lp_integer != -1:
		da_D_f_th0.append_array(da_D_f_th0_append)
	
	var new_size := previous_size + n_bodies
	if !suppress_max_apoapsis_update:
		update_max_apoapsis(previous_size, new_size)
	if !suppress_visuals_rebuild:
		_build_visuals()
	group_appended.emit(previous_size, new_size)


## Required for visual update if any data changes not via append_data(). Be
## sure to call update_max_apoapsis() first if that might be needed.
func rebuild_visuals() -> void:
	_build_visuals()


func reset_max_apoapsis() -> void:
	update_max_apoapsis(0, names.size(), false)


func update_max_apoapsis(start_index: int, stop_index: int, increase_only := true) -> void:
	var range_max := 0.0
	var i := start_index
	if lp_integer == -1:
		while i < stop_index:
			var a := a_M0_n[i * 3]
			var e := e_i_Om_w[i * 4]
			var apoapsis := a * (1.0 + e)
			if range_max < apoapsis:
				range_max = apoapsis
			i += 1
	else:
		var characteristic_length := secondary_body.get_orbit_semi_major_axis()
		while i < stop_index:
			var da: float = da_D_f_th0[i * 4]
			var e: float = e_i_Om_w[i * 4]
			var apoapsis := (characteristic_length + da) * (1.0 + e)
			if range_max < apoapsis:
				range_max = apoapsis
			i += 1
	
	if !increase_only or max_apoapsis < range_max:
		max_apoapsis = range_max


func vprint_load(what: String) -> bool:
	print("%s %s %s loaded from binaries" % [names.size(), sbg_alias, what])
	return true


func get_number() -> int:
	return names.size()


func get_orbit_elements(index: int) -> Array[float]:
	# [a, e, i, Om, w, M0, n]
	# WIP - Trojan elements a, M0 & n vary with libration. This is reflected in
	# shader point calculations but not in elements here (yet).
	
	return Array([
		a_M0_n[index * 3],
		e_i_Om_w[index * 4],
		e_i_Om_w[index * 4 + 1],
		e_i_Om_w[index * 4 + 2],
		e_i_Om_w[index * 4 + 3],
		a_M0_n[index * 3 + 1],
		a_M0_n[index * 3 + 2],
	], TYPE_FLOAT, &"", null)


func get_fragment_data(fragment_type: int, index: int) -> Array:
	return [get_instance_id(), fragment_type, index]


func get_fragment_text(data: Array) -> String:
	var fragment_type: int = data[1]
	var index: int = data[2]
	var text := names[index]
	if fragment_type == IVFragmentIdentifier.FRAGMENT_SBG_ORBIT:
		text += " (" + tr("LABEL_ORBIT").to_lower() + ")"
	return text


# *****************************************************************************
# private


func _build_visuals() -> void:
	# add non-persisted HUD elements
	if !is_inside_tree():
		return
	adding_visuals.emit() # any pre-existing will queue_free
	var sbg_points_script: Script = IVGlobal.procedural_classes[&"SBGPoints"]
	@warning_ignore("unsafe_method_access")
	var sbg_points: Node3D = sbg_points_script.new(self)
	var sbg_orbits_script: Script = IVGlobal.procedural_classes[&"SBGOrbits"]
	@warning_ignore("unsafe_method_access")
	var sbg_orbits: Node3D = sbg_orbits_script.new(self)

	var parent: Node3D = get_parent()
	parent.add_child(sbg_points)
	parent.add_child(sbg_orbits)
