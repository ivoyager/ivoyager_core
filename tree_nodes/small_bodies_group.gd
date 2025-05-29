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
## Data is packed for use by visual classes [IVSBGOrbits] and [IVSBGPoints],
## which are added by [IVSBGFinisher] when this node is added to the tree.[br][br]
##
## If modifying packed array data directly, it is necessary to ensure correct
## 'max_apoapsis' (call either reset_max_apoapsis() or update_max_apoapsis()).[br][br]
##
## TODO: It's possible to modify MultiMesh if it's not a resize. We could build
## signals and modify API to allow for that.[br][br]
##
## 'de' is not currently implemented (amplitude of e libration in secular
## resonence).

signal group_appended(previous_size: int, new_size: int)
signal adding_visuals() # existing visual nodes must free themselves


enum SBGClass {
	SBG_CLASS_ASTEROIDS,
	SBG_CLASS_COMETS, # TODO: Roadmap
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
	&"e_i_lan_ap",
	&"a_m0_n",
	&"s_g_mag_de",
	&"da_d_f_th0",
]


var sbg_alias: StringName
var sbg_class: SBGClass # SBGClass
var secondary_body: IVBody # e.g., Jupiter for Trojans; usually null
var lp_integer := -1 # -1, 4 & 5 are currently supported
var max_apoapsis := 0.0

var names := PackedStringArray()
var e_i_lan_ap := PackedFloat32Array() # fixed & precessing (except e in sec res)
var a_m0_n := PackedFloat32Array() # librating in l-point objects
var s_g_mag_de := PackedFloat32Array() # orbit precessions, magnitude, & e amplitude (sec res only)
var da_d_f_th0 := PackedFloat32Array() # Trojans only


static var replacement_subclass: Script

## Contains all IVSmallBodiesGroup instances currently in the tree.
static var small_bodies_groups: Dictionary[StringName, IVSmallBodiesGroup] = {}
static var null_pf32_array := PackedFloat32Array()



func _ready() -> void:
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	assert(!small_bodies_groups.has(name))
	small_bodies_groups[name] = self


func _exit_tree() -> void:
	small_bodies_groups.erase(name)


# *****************************************************************************
# public API


## Last 2 args only if these are Lagrange point objects. This node creation MUST
## be followed by one or more calls to [method append_data] before adding to the
## tree.
@warning_ignore("shadowed_variable", "shadowed_variable_base_class")
static func create(name: StringName, sbg_alias: StringName, sbg_class: SBGClass,
		lp_integer := -1, secondary_body: IVBody = null) -> IVSmallBodiesGroup:
	
	var sbg: IVSmallBodiesGroup
	if replacement_subclass:
		@warning_ignore("unsafe_method_access")
		sbg = replacement_subclass.new()
	else:
		sbg = IVSmallBodiesGroup.new()
	
	sbg.name = name
	sbg.sbg_alias = sbg_alias
	sbg.sbg_class = sbg_class
	sbg.lp_integer = lp_integer
	sbg.secondary_body = secondary_body
	
	return sbg


#func init(name_: StringName, sbg_alias_: StringName, sbg_class_: SBGClass,
		#lp_integer_ := -1, secondary_body_: IVBody = null) -> void:
	## Last 2 args only if these are Lagrange point objects.
	#name = name_
	#sbg_alias = sbg_alias_
	#sbg_class = sbg_class_
	#lp_integer = lp_integer_
	#secondary_body = secondary_body_


## Append all data before adding this node to the tree.
func append_data(names_append: PackedStringArray, e_i_lan_aop_append: PackedFloat32Array,
		a_m0_n_append: PackedFloat32Array, s_g_mag_de_append: PackedFloat32Array,
		da_d_f_th0_append := null_pf32_array, suppress_max_apoapsis_update := false) -> void:
	var n_bodies := names_append.size()
	assert(e_i_lan_aop_append.size() == n_bodies * 4)
	assert(a_m0_n_append.size() == n_bodies * 3)
	assert(s_g_mag_de_append.size() == n_bodies * 4)
	assert(da_d_f_th0_append.size() == (0 if lp_integer == -1 else n_bodies * 4))
	
	
	# *************************************************************************
	# FIXME: WORKS FOR UNKNOWN REASON! The adjustment here fixes precessions
	# so that the Hildas maintain position correctly over 3000 BC - 3000 AD.
	# This strongly suggests a conversion error somewhere. HOWEVER, the print
	# statement shows that our conversion from source to internal units is correct.
	
	# Print statement unconverts internal rad/s back to source units "/yr. This
	# prints -59.1700357686738, 54.0702746719668 for Ceres, which agrees w/ source.
	#printt(rad_to_deg(s_g_mag_de_append[0]) * 3600 * IVUnits.YEAR,
			#rad_to_deg(s_g_mag_de_append[1]) * 3600 * IVUnits.YEAR, sbg_alias, names_append[0])
	
	# Here is the mystery fix...
	for i in n_bodies:
		s_g_mag_de_append[i * 4] /= 3.0 # s
		s_g_mag_de_append[i * 4 + 1] /= 3.0 # g
	# *************************************************************************
	
	
	var previous_size := names.size()
	names.append_array(names_append)
	e_i_lan_ap.append_array(e_i_lan_aop_append)
	a_m0_n.append_array(a_m0_n_append)
	s_g_mag_de.append_array(s_g_mag_de_append)
	if lp_integer != -1:
		da_d_f_th0.append_array(da_d_f_th0_append)
	
	var new_size := previous_size + n_bodies
	if !suppress_max_apoapsis_update:
		update_max_apoapsis(previous_size, new_size)
	group_appended.emit(previous_size, new_size)


func reset_max_apoapsis() -> void:
	update_max_apoapsis(0, names.size(), false)


func update_max_apoapsis(start_index: int, stop_index: int, increase_only := true) -> void:
	var range_max := 0.0
	var i := start_index
	if lp_integer == -1:
		while i < stop_index:
			var a := a_m0_n[i * 3]
			var e := e_i_lan_ap[i * 4]
			var apoapsis := a * (1.0 + e)
			if range_max < apoapsis:
				range_max = apoapsis
			i += 1
	else:
		var secondary_a := secondary_body.get_orbit_semi_major_axis()
		while i < stop_index:
			var da: float = da_d_f_th0[i * 4]
			var e: float = e_i_lan_ap[i * 4]
			var apoapsis := (secondary_a + da) * (1.0 + e)
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


func get_unit_circle_transform(index: int) -> Transform3D:
	var a := a_m0_n[index * 3]
	var e := e_i_lan_ap[index * 4]
	var i := e_i_lan_ap[index * 4 + 1]
	var lan := e_i_lan_ap[index * 4 + 2]
	var ap := e_i_lan_ap[index * 4 + 3]
	return IVOrbit.get_unit_circle_transform_from_elements(a, e, i, lan, ap)


## Returns an element list [a, e, i, lan, ap, m0, n]. FIXME: Trojan elements
## vary with libration. This is reflected in shader point calculations but not
## in elements here (yet).
## @experimental: The element list will change in the future to be more in line with [IVOrbit]. 
func get_orbit_elements(index: int) -> Array[float]:
	
	return [
		a_m0_n[index * 3],
		e_i_lan_ap[index * 4],
		e_i_lan_ap[index * 4 + 1],
		e_i_lan_ap[index * 4 + 2],
		e_i_lan_ap[index * 4 + 3],
		a_m0_n[index * 3 + 1],
		a_m0_n[index * 3 + 2],
	]


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


func _clear_procedural() -> void:
	secondary_body = null
	small_bodies_groups.clear()
