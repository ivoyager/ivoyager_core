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

## Hack system to generate proper light and shadows despite vast scale
## differences.
##
## This node self-adds IVDynamicLight children that (together with itself)
## generate light and shadows on different mask levels.[br][br]
## 
## The parent node (this node) points in the direction from source to the
## camera. All lights are attenuated for source distance.

# Shadows should be visible on the camera's parent and on the ancestor
# "planet" (star orbiter). E.g., we see Io's shadow on Jupiter if we are
# anywhere in Jupiter's system. Also, Jupiter should shade Io even if Io is on
# the other side of Jupiter from us.
# TODO: Optimize by having star_orbiter in IVGlobal container.

# from table
var energy_multiplier: float
var shadow_max_floor: float
var shadow_max_ceiling: float
var shadow_max_target_plus := NAN
var shadow_max_planet_plus := NAN


var _body_name: StringName
var _add_target_dist: bool
var _add_planet_dist: bool
var _shared: Array[float]

var _attenuation_exponent := IVCoreSettings.attenuation_exponent
var _top_light := false

# top light only
var _camera: Camera3D
var _camera_planet: Node3D


func _init(body_name: StringName, row := -1, top_light := true,
		shared: Array[float] = [0.0, 0.0, 0.0]) -> void:
	assert(row != -1)
	_body_name = body_name
	_top_light = top_light
	_shared = shared
	IVTableData.db_build_object_all_fields(self, &"dynamic_lights", row)
	_add_target_dist = !is_nan(shadow_max_target_plus)
	_add_planet_dist = !is_nan(shadow_max_planet_plus)


func _ready() -> void:
	if !_top_light:
		return
	# Only top light connects to camera!
	IVGlobal.camera_tree_changed.connect(_on_camera_tree_changed)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear)
	# add child lights
	for row in IVTableData.get_n_rows(&"dynamic_lights"):
		if IVTableData.get_db_entity_name(&"dynamic_lights", row) == name:
			continue
		var bodies: Array[StringName] = IVTableData.get_db_array(&"dynamic_lights", &"bodies", row)
		if bodies.has(_body_name):
			var child_light := IVDynamicLight.new(_body_name, row, false, _shared)
			add_child(child_light)


func _process(_delta: float) -> void:
	# Camera position determines light direction and intensity.
	# Only the parent light 0 points and calculates distances.
	# In this context, "planet" = star orbiter.
	const AU_SQ := IVUnits.AU ** 2
	
	if _camera: # only the top light has _camera
		var camera_global_position := _camera.global_position
		var source_vector := camera_global_position - global_position
		var planet_dist := 0.0
		if _camera_planet:
			planet_dist = (_camera_planet.global_position - camera_global_position).length()
		var energy := AU_SQ / source_vector.length_squared()
		if _attenuation_exponent != 2.0:
			energy **= _attenuation_exponent * 0.5
		
		# parent light sets for all
		_shared[0] = _camera.position.length() # target distance
		_shared[1] = planet_dist
		_shared[2] = energy
		look_at(source_vector)
	
	# all lights
	var shadow_max := shadow_max_floor
	if _add_target_dist:
		shadow_max = maxf(shadow_max, shadow_max_target_plus + _shared[0])
	if _add_planet_dist:
		shadow_max = maxf(shadow_max, shadow_max_planet_plus + _shared[1])
	shadow_max = minf(shadow_max, shadow_max_ceiling)
	directional_shadow_max_distance = shadow_max
	light_energy = _shared[2] * energy_multiplier


func _clear() -> void:
	# Only connected for top light.
	_camera = null
	_camera_planet = null


func _on_camera_tree_changed(camera: Camera3D, _parent: Node3D, planet: Node3D, _star: Node3D
		) -> void:
	# Only connected for top light.
	_camera = camera
	_camera_planet = planet # really star orbiter
