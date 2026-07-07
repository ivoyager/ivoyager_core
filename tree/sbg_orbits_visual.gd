# sbg_orbits_visual.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield
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
class_name IVSBGOrbitsVisual
extends MultiMeshInstance3D

## Visual orbits of an [IVSmallBodiesGroup].
##
## If [IVFragmentIdentifier] exists, a pure id-overlay (the [code]instance_id[/code] shader,
## attached as [member GeometryInstance3D.material_overlay]) provides screen identification of
## the orbit lines, orthogonal to the base material's appearance.[br][br]
##
## Several subclass [code]_init()[/code] overrides are provided: [code]_shader_override[/code]
## sets the base appearance only (the id overlay is still added);
## [code]_bypass_fragment_identifier[/code] suppresses the id overlay. Other overrides change
## aspects of the MultiMesh.

const FRAGMENT_SBG_ORBIT := IVFragmentIdentifier.FRAGMENT_SBG_ORBIT

var _fragment_identifier: IVFragmentIdentifier = IVGlobal.program.get(&"FragmentIdentifier") # optional
var _sbg_huds_state: IVSBGHUDsState = IVGlobal.program.SBGHUDsState

var _sbg_alias: StringName
var _color: Color
var _vec3ids := PackedVector3Array() # orbit ids for FragmentIdentifier

# subclass _init() overrides
var _shader_override: Shader
var _bypass_fragment_identifier := false
var _multimesh_use_custom_data := true # forced true if base shader used w/ fragment ids
var _multimesh_use_colors := false # default is to set as a group
var _suppress_set_custom_data := false



func _init(sbg: IVSmallBodiesGroup) -> void:
	name = "SBGOrbit" + sbg.sbg_alias
	_sbg_alias = sbg.sbg_alias
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	_sbg_huds_state.orbits_visibility_changed.connect(_set_visibility)
	_sbg_huds_state.color_changed.connect(_set_color)
	
	var number := sbg.get_number()
	
	# fragment ids
	var i := 0
	if _fragment_identifier and !_bypass_fragment_identifier:
		_vec3ids.resize(number)
		while i < number:
			var data := sbg.get_fragment_data(FRAGMENT_SBG_ORBIT, i)
			_vec3ids[i] = _fragment_identifier.get_new_id_as_vec3(data)
			i += 1
	
	# MultiMesh construction
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = IVGlobal.resources[&"circle_mesh_low_res"]
	multimesh.use_colors = _multimesh_use_colors
	multimesh.use_custom_data = _multimesh_use_custom_data # may be forced true below
	
	# base (visible) material
	var shader_material := ShaderMaterial.new()
	shader_material.shader = (_shader_override if _shader_override
			else IVGlobal.resources[&"farwarp_line_shader"])
	material_override = shader_material
	if IVCoreSettings.apply_farwarp:
		# Frustum culling tests the true-scale AABB against the far plane, but
		# farwarp-remapped vertices are on-screen even when that test fails;
		# make the test always pass wherever the camera can be.
		var extent := IVCoreSettings.max_camera_distance
		custom_aabb = AABB(-Vector3.ONE * extent, 2.0 * Vector3.ONE * extent)

	# id overlay, orthogonal to appearance (_bypass_fragment_identifier suppresses it)
	if _fragment_identifier and !_bypass_fragment_identifier:
		multimesh.use_custom_data = true
		var id_material := ShaderMaterial.new()
		id_material.shader = IVGlobal.resources[&"instance_id_shader"]
		id_material.render_priority = 1
		material_overlay = id_material
	
	multimesh.instance_count = number # must be set after above!
	
	# set transforms & id
	var is_set_custom_data := (_fragment_identifier and !_bypass_fragment_identifier
			and !_suppress_set_custom_data)
	i = 0
	while i < number:
		# currently assumes ecliptic reference
		var orbit_transform := sbg.get_unit_circle_transform(i)
		multimesh.set_instance_transform(i, orbit_transform)
		if is_set_custom_data:
			var vec3id := _vec3ids[i]
			multimesh.set_instance_custom_data(i, Color(vec3id.x, vec3id.y, vec3id.z, 0.0))
		i += 1


func _ready() -> void:
	_set_visibility()
	_set_color()



func _set_visibility() -> void:
	visible = _sbg_huds_state.is_orbits_visible(_sbg_alias)


func _set_color() -> void:
	# subclass override if you don't want this for your shader_override
	var color := _sbg_huds_state.get_color(_sbg_alias)
	if _color == color:
		return
	_color = color
	var shader_material: ShaderMaterial = material_override
	shader_material.set_shader_parameter(&"color", color)
