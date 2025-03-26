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
## This node self-adds DirectionalLight3D children that (together with itself)
## generate light and shadows on different mask levels.[br][br]
##
## 0b0001 (this node) - Astronomic objects
## 0b0010 (child1) - Astronomic objects
## 
## The parent node (this node) points in the direction from source to the
## camera. All lights are attenuated for source distance.

# Shadows should be visible on the camera's parent and on the ancestor
# "planet" (star orbiter). E.g., we see Io's shadow on Jupiter if we are
# anywhere in Jupiter's system. Also, Jupiter should shade Io even if Io is on
# the other side of Jupiter from us.
# TODO: Optimize by having star_orbiter in IVGlobal container.

# from table
var shadow_max_floor: float
var shadow_max_ceiling: float
var shadow_max_target_plus := NAN
var shadow_max_planet_plus := NAN

var _attenuation_exponent := IVCoreSettings.attenuation_exponent
var _parent_name: StringName
var _light_number: int
var _camera: Camera3D # only updated for light 0
var _planet: Node3D # only updated for light 0
var _add_target_dist: bool
var _add_planet_dist: bool
var _shared: Array[float]


## Names are constructed from the parent_name. E.g., STAR_SUN becomes
## DYNAMIC_LIGHT_STAR_SUN_0, DYNAMIC_LIGHT_STAR_SUN_1, DYNAMIC_LIGHT_STAR_SUN_2
## for three lights imported from dynamic_lights.tsv. Only the parent 0 light
## needs to be inited externally.
func _init(parent_name: StringName, light_number := 0, shared: Array[float] = [0.0, 0.0, 0.0]
		) -> void:
	_parent_name = parent_name
	_light_number = light_number
	_shared = shared
	var light_name := StringName("DYNAMIC_LIGHT_" + parent_name + "_" + str(light_number))
	var row := IVTableData.get_row(light_name)
	assert(row != -1)
	IVTableData.db_build_object_all_fields(self, &"dynamic_lights", row)
	_add_target_dist = !is_nan(shadow_max_target_plus)
	_add_planet_dist = !is_nan(shadow_max_planet_plus)
	if light_number == 0:
		IVGlobal.camera_tree_changed.connect(_on_camera_tree_changed)


func _ready() -> void:
	if _light_number != 0 or !IVCoreSettings.apply_size_layers:
		return
	for i in IVCoreSettings.size_layers.size():
		var child_light := IVDynamicLight.new(_parent_name, i + 1, _shared)
		add_child(child_light)


func _process(_delta: float) -> void:
	# Camera position determines light direction and intensity.
	# Only the parent light 0 points and calculates distances.
	# In this context, "planet" = star orbiter.
	const AU_SQ := IVUnits.AU ** 2
	
	if _camera: # only set for light 0
		var camera_global_position := _camera.global_position
		var source_vector := camera_global_position - global_position
		var planet_dist := 0.0
		if _planet:
			planet_dist = (_planet.global_position - camera_global_position).length()
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
	light_energy = _shared[2]


func _on_camera_tree_changed(camera: Camera3D, _parent: Node3D, planet: Node3D, _star: Node3D
		) -> void:
	# Only connected for light 0.
	_camera = camera
	_planet = planet # really star orbiter
