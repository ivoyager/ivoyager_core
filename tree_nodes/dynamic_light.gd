# dynamic_light.gd
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
class_name IVDynamicLight
extends DirectionalLight3D

## Dynamic system to generate proper light and shadows over vast scale
## differences and for Saturn Rings semi-transparancy.
##
## This node self-adds IVDynamicLight children that (together with itself)
## generate light and shadows on different mask levels and with different
## shadow opacity.[br][br]
## 
## The parent light points in the direction from source to the camera.
## All lights are attenuated for source distance.[br][br]
##
## Shadows are intentionally disabled if using Compatibility renderer. There
## are many problems:[br]
##  1. The current implementation doesn't work correctly for far. Io shadow on
##     Jupiter disappears when moving in.[br]
##  2. There seems to be issues with light_cull_mask, shadow_caster_mask and/or
##     shadow_opacity. One or more of these don't work correctly.[br]
##  3. Lighting energy is wrong with multiple lights. See Godot issue:
##     https://github.com/godotengine/godot/issues/90259.[br]
##  4. In Compatibility mode, all color handling changes if any light has
##     shadows enabled. See comments in issue above.[br]


# from table
var energy_multiplier: float
var shadow_max_floor: float
var shadow_max_ceiling: float
var shadow_max_target_plus := NAN
var shadow_max_star_orbiter_plus := NAN


var _body_name: StringName
var _top_light: bool
var _row: int
var _shared: Array[float]
var _process_shadow_distances: bool
var _add_shadow_target_dist: bool
var _add_shadow_star_orbiter_dist: bool

var _energy_at_1_au := IVCoreSettings.nonphysical_energy_at_1_au
var _attenuation_exponent := IVCoreSettings.nonphysical_attenuation_exponent

# top light only
var _camera: Camera3D
var _camera_star_orbiter: Node3D



## External call should provide [param body_name] only.
func _init(body_name: StringName, top_light := true, row := -1,
		shared: Array[float] = [0.0, 0.0, 0.0]) -> void:
	_body_name = body_name
	_top_light = top_light
	var is_gl_compatibility := IVGlobal.is_gl_compatibility
	if top_light:
		row = _get_top_light(is_gl_compatibility)
	_row = row
	_shared = shared
	IVTableData.db_build_object(self, &"dynamic_lights", row)
	_process_shadow_distances = !is_gl_compatibility
	_add_shadow_target_dist = !is_nan(shadow_max_target_plus)
	_add_shadow_star_orbiter_dist = !is_nan(shadow_max_star_orbiter_plus)
	name = "DynamicLight" + str(row)


func _ready() -> void:
	if !_top_light:
		return
	# Only top light connects to camera or has children!
	IVGlobal.camera_tree_changed.connect(_on_camera_tree_changed)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear)
	if !IVGlobal.is_gl_compatibility:
		_add_child_lights()


func _process(_delta: float) -> void:
	const AU := IVUnits.AU
	
	# top light (only top can have _camera)
	if _camera:
		var camera_global_position := _camera.global_position
		var source_vector := camera_global_position - global_position
		var source_dist_au := source_vector.length() / AU
		var energy := _energy_at_1_au / (source_dist_au ** _attenuation_exponent)
		# parent light sets for all
		look_at(source_vector)
		_shared[0] = energy
		
		if _process_shadow_distances:
			var star_orbiter_dist := 0.0
			if _camera_star_orbiter:
				star_orbiter_dist = (_camera_star_orbiter.global_position - camera_global_position).length()
			# parent light sets for all
			_shared[1] = _camera.position.length() # target distance
			_shared[2] = star_orbiter_dist
	
	# all lights
	light_energy = _shared[0] * energy_multiplier
	if _process_shadow_distances:
		var shadow_max_dist := shadow_max_floor
		if _add_shadow_target_dist:
			shadow_max_dist = maxf(shadow_max_dist, shadow_max_target_plus + _shared[1])
		if _add_shadow_star_orbiter_dist:
			shadow_max_dist = maxf(shadow_max_dist, shadow_max_star_orbiter_plus + _shared[2])
		shadow_max_dist = minf(shadow_max_dist, shadow_max_ceiling)
		directional_shadow_max_distance = shadow_max_dist


func _clear() -> void:
	# Only connected for top light.
	_camera = null
	_camera_star_orbiter = null


func _on_camera_tree_changed(camera: Camera3D, _parent: Node3D, star_orbiter: Node3D, _star: Node3D
		) -> void:
	# Only connected for top light.
	_camera = camera
	_camera_star_orbiter = star_orbiter # really star orbiter


func _get_top_light(gl_compatibility: bool) -> int:
	for row in IVTableData.get_n_rows(&"dynamic_lights"):
		if gl_compatibility != IVTableData.get_db_bool(&"dynamic_lights", &"gl_compatibility", row):
			continue
		var bodies: Array[StringName] = IVTableData.get_db_array(&"dynamic_lights", &"bodies", row)
		if bodies.has(_body_name):
			return row
	assert(false, "Could not find top light in dynamic_lights.tsv for " + _body_name)
	return -1


func _add_child_lights() -> void:
	for row in IVTableData.get_n_rows(&"dynamic_lights"):
		if row == _row:
			continue
		if IVTableData.get_db_bool(&"dynamic_lights", &"gl_compatibility", row):
			continue
		var bodies: Array[StringName] = IVTableData.get_db_array(&"dynamic_lights", &"bodies", row)
		if bodies.has(_body_name):
			var child_light := IVDynamicLight.new(_body_name, false, row, _shared)
			add_child(child_light)
