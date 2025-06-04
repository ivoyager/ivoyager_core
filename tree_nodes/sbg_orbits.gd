# sbg_orbits.gd
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
class_name IVSBGOrbits
extends MultiMeshInstance3D

## Visual orbits of a [IVSmallBodiesGroup] instance.
##
## If FragmentIdentifier exists, then a shader is used to allow screen
## identification of the orbit lines.
##
## Several subclass _init() overrides are provided to override above behavior,
## supply a different shader, or change other aspects of the MultiMesh.

const FRAGMENT_SBG_ORBIT := IVFragmentIdentifier.FRAGMENT_SBG_ORBIT

static var _fragment_identifier: IVFragmentIdentifier # optional
static var _sbg_huds_state: IVSBGHUDsState
static var _is_class_instanced := false

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
	if !_is_class_instanced:
		_is_class_instanced = true
		_fragment_identifier = IVGlobal.program.get(&"FragmentIdentifier")
		_sbg_huds_state = IVGlobal.program.SBGHUDsState
	_sbg_alias = sbg.sbg_alias
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	process_mode = PROCESS_MODE_ALWAYS # FragmentIdentifier still processing
	sbg.adding_visuals.connect(_hide_and_free, CONNECT_ONE_SHOT)
	_sbg_huds_state.orbits_visibility_changed.connect(_set_visibility)
	_sbg_huds_state.orbits_color_changed.connect(_set_color)
	
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
	
	if _shader_override:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = _shader_override
		material_override = shader_material
	elif _fragment_identifier and !_bypass_fragment_identifier: # use self-identifying shader
		multimesh.use_custom_data = true
		var shader_material := ShaderMaterial.new()
		shader_material.shader = IVGlobal.resources[&"orbits_id_shader"]
		material_override = shader_material
	else:
		var standard_material := StandardMaterial3D.new()
		standard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		standard_material.vertex_color_use_as_albedo = _multimesh_use_custom_data
		material_override = standard_material
	
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



func _hide_and_free() -> void:
	hide()
	queue_free()


func _set_visibility() -> void:
	visible = _sbg_huds_state.is_orbits_visible(_sbg_alias)


func _set_color() -> void:
	# subclass override if you don't want this for your shader_override
	var color := _sbg_huds_state.get_orbits_color(_sbg_alias)
	if _color == color:
		return
	_color = color
	if _shader_override or (_fragment_identifier and !_bypass_fragment_identifier):
		var shader_material: ShaderMaterial = material_override
		shader_material.set_shader_parameter(&"color", color)
	else:
		var standard_material: StandardMaterial3D = material_override
		standard_material.albedo_color = color
