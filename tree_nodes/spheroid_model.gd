# spheroid_model.gd
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
class_name IVSpheroidModel
extends MeshInstance3D

## A generic spheroid model that uses a shared sphere mesh.
##
## Stars and almost all planetary mass objects use this class as model.
## Instances are scaled for size and oblateness.[br][br]
## 
## If is_dynamic_star = true, the model will grow with great distances to stay
## visible and appropriately prominent relative to the star field. The grow
## settings are currently subjective.

const MATERIAL_FIELDS: Array[StringName] = [
	&"metallic",
	&"roughness",
	&"rim_enabled",
	&"rim",
	&"rim_tint"
]
const DYNAMIC_STAR_GROW_DIST := 2.0 * IVUnits.AU
const DYNAMIC_STAR_GROW_FACTOR := 0.3


var is_dynamic_star := false

var _reference_basis: Basis
var _camera: Camera3D # only set if is_dynamic_star == true



func _init(model_type: int, reference_basis: Basis, albedo_map: Texture2D,
		emission_map: Texture2D) -> void:
	name = &"SpheroidModel"
	_reference_basis = reference_basis
	transform.basis = _reference_basis # z up, possibly oblate
	mesh = IVGlobal.resources[&"sphere_mesh"]
	var surface := StandardMaterial3D.new()
	set_surface_override_material(0, surface)
	IVTableData.db_build_object(surface, &"models", model_type, MATERIAL_FIELDS)
	if albedo_map:
		surface.albedo_texture = albedo_map
	if emission_map:
		surface.emission_enabled = true
		surface.emission_texture = emission_map
		surface.emission_energy_multiplier = IVTableData.get_db_float(&"models",
				&"emission_energy_multiplier", model_type)
	if IVTableData.get_db_bool(&"models", &"is_star", model_type):
		cast_shadow = SHADOW_CASTING_SETTING_OFF
		is_dynamic_star = true
	else:
		cast_shadow = SHADOW_CASTING_SETTING_ON


func _ready() -> void:
	set_process(is_dynamic_star)
	if !is_dynamic_star:
		return
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVGlobal.current_camera_changed.connect(_set_camera)
	_set_camera(get_viewport().get_camera_3d())


func _process(_delta: float) -> void:
	# Dynamic star only!
	if !_camera:
		return
	var camera_dist := global_position.distance_to(_camera.global_position)
	if camera_dist < DYNAMIC_STAR_GROW_DIST:
		transform.basis = _reference_basis
		return
	var excess := camera_dist / DYNAMIC_STAR_GROW_DIST - 1.0
	var factor := DYNAMIC_STAR_GROW_FACTOR * excess + 1.0
	transform.basis = _reference_basis.scaled(Vector3(factor, factor, factor))



func _clear_procedural() -> void:
	_camera = null


func _set_camera(camera: Camera3D) -> void:
	_camera = camera
