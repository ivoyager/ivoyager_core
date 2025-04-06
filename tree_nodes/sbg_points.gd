# sbg_points.gd
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
class_name IVSBGPoints
extends MeshInstance3D

## Visual points of a [IVSmallBodiesGroup] instance.
##
## Uses one of the 'points'
## shaders ('points.x.x.gdshader', where x.x represents a shader variant).
## Point shaders maintain vertex positions using their own orbital math.
##
## Points shader variants:
##    '.l4l5.' - for lagrange points L4 & L5.
##    '.id.' - broadcasts identity for IVFragmentIdentifier.
##
## Several subclass _init() overrides are provided to bypass IVFragmentIdentifier
## or to supply a different shader.


const FRAGMENT_SBG_POINT := IVFragmentIdentifier.FRAGMENT_SBG_POINT
const PI_DIV_3 := PI / 3.0 # 60 degrees


const ARRAY_FLAGS = (
	Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	| Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	| Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT
)


const L4L5_ARRAY_FLAGS = (
	Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	| Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	| Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT
)


static var _fragment_identifier: IVFragmentIdentifier # optional
static var _sbg_huds_state: IVSBGHUDsState
static var _is_class_instanced := false

var _sbg_alias: StringName
var _color: Color
var _point_size: int = IVGlobal.settings.point_size
var _vec3ids := PackedVector3Array() # point ids for FragmentIdentifier

# Lagrange point
var _lp_integer := -1 # -1 or 1-5
var _secondary_orbit: IVOrbit

# subclass _init() overrides
var _points_shader_override: Shader
var _points_l4l5_shader_override: Shader
var _bypass_fragment_identifier := false



func _init(group: IVSmallBodiesGroup) -> void:
	name = "SBGPoints" + group.sbg_alias
	if !_is_class_instanced:
		_is_class_instanced = true
		_fragment_identifier = IVGlobal.program.get(&"FragmentIdentifier")
		_sbg_huds_state = IVGlobal.program[&"SBGHUDsState"]
	_sbg_alias = group.sbg_alias
	_lp_integer = group.lp_integer
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	group.adding_visuals.connect(_hide_and_free, CONNECT_ONE_SHOT)
	_sbg_huds_state.points_visibility_changed.connect(_set_visibility)
	_sbg_huds_state.points_color_changed.connect(_set_color)
	IVGlobal.setting_changed.connect(_settings_listener)
	
	var number := group.get_number()
	
	# fragment ids
	_vec3ids.resize(number) # needs resize whether we use ids or not
	if _fragment_identifier and !_bypass_fragment_identifier:
		process_mode = PROCESS_MODE_ALWAYS # FragmentIdentifier always processing
		var i := 0
		while i < number:
			var data := group.get_fragment_data(FRAGMENT_SBG_POINT, i)
			_vec3ids[i] = _fragment_identifier.get_new_id_as_vec3(data)
			i += 1
	
	# set shader
	var shader_material := ShaderMaterial.new()
	if _lp_integer == -1: # not trojans
		shader_material.shader = (_points_shader_override if _points_shader_override
				else IVGlobal.resources[&"points_id_shader"])
	elif _lp_integer >= 4: # trojans
		_secondary_orbit = group.secondary_body.orbit
		shader_material.shader = (_points_l4l5_shader_override if _points_l4l5_shader_override
				else IVGlobal.resources[&"points_l4l5_id_shader"])
	material_override = shader_material
	
	# ArrayMesh construction
	var points_mesh := ArrayMesh.new()
	var arrays := [] # packed arrays
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vec3ids
	arrays[Mesh.ARRAY_CUSTOM0] = group.e_i_Om_w
	arrays[Mesh.ARRAY_CUSTOM1] = group.a_M0_n if _lp_integer == -1 else group.da_D_f_th0
	arrays[Mesh.ARRAY_CUSTOM2] = group.s_g_mag_de
	var array_flags := ARRAY_FLAGS if _lp_integer == -1 else L4L5_ARRAY_FLAGS
	points_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays, [], {}, array_flags)
	var half_aabb := Vector3.ONE * group.max_apoapsis
	points_mesh.custom_aabb = AABB(-half_aabb, 2.0 * half_aabb)
	mesh = points_mesh
	
	# set shader parameters
	shader_material.set_shader_parameter(&"point_size", float(_point_size))
	if _lp_integer >= 4: # trojans
		shader_material.set_shader_parameter(&"lp_integer", _lp_integer)
		var characteristic_length := _secondary_orbit.get_semimajor_axis()
		shader_material.set_shader_parameter(&"characteristic_length", characteristic_length)


func _ready() -> void:
	set_process(_lp_integer == 4 or _lp_integer == 5)
	_set_visibility()
	_set_color()


func _process(_delta: float) -> void:
	# lagrange points 4 & 5 only
	if !visible:
		return
	var lp_mean_longitude: float
	if _lp_integer == 4:
		lp_mean_longitude = _secondary_orbit.get_mean_longitude() + PI_DIV_3
	elif _lp_integer == 5:
		lp_mean_longitude = _secondary_orbit.get_mean_longitude() - PI_DIV_3
	var shader_material: ShaderMaterial = material_override
	shader_material.set_shader_parameter(&"lp_mean_longitude", lp_mean_longitude)


func _hide_and_free() -> void:
	hide()
	queue_free()
	

func _set_visibility() -> void:
	visible = _sbg_huds_state.is_points_visible(_sbg_alias)


func _set_color() -> void:
	var color := _sbg_huds_state.get_points_color(_sbg_alias)
	if _color == color:
		return
	_color = color
	var shader_material: ShaderMaterial = material_override
	shader_material.set_shader_parameter(&"color", color)


func _settings_listener(setting: StringName, value: Variant) -> void:
	if setting == &"point_size":
		_point_size = value
		var shader_material: ShaderMaterial = material_override
		# setting value is int; shader parameter is float
		shader_material.set_shader_parameter(&"point_size", float(_point_size))
