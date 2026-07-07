# sbg_positions_visual.gd
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
class_name IVSBGPositionsVisual
extends MeshInstance3D

## Visual positions of an [IVSmallBodiesGroup], drawn as point sprites.
##
## Uses the [code]orbiting_positions_id[/code] shader, or [code]orbiting_positions_lp_id[/code] for
## Lagrange point groups (L4 & L5). Both compute vertex positions from orbital elements and
## can broadcast a per-point fragment id for [IVFragmentIdentifier].[br][br]
##
## Each point renders as the group's [enum IVGlobal.Symbols] shape (masked from the
## symbol atlas in the fragment shader) or, for [member IVSBGHUDsState.symbol_types] value
## -1, as a plain point. A shaped symbol's point size follows [IVThemeManager] (the
## "small_bodies_symbol_size_percent" setting); a plain point uses the smaller
## "small_bodies_point_size" setting.[br][br]
##
## The id broadcast is enabled (via the shaders' [code]broadcast_id[/code] uniform) only when
## an [IVFragmentIdentifier] is present; without it (e.g. on the Compatibility renderer) the
## points render their normal appearance and write no ids.[br][br]
##
## Several subclass [code]_init()[/code] overrides are provided to bypass
## [IVFragmentIdentifier] or to supply a different shader.


const FRAGMENT_SBG_POINT := IVFragmentIdentifier.FRAGMENT_SBG_POINT

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


var _fragment_identifier: IVFragmentIdentifier = IVGlobal.program.get(&"FragmentIdentifier") # optional
var _sbg_huds_state: IVSBGHUDsState = IVGlobal.program[&"SBGHUDsState"]

var _sbg_alias: StringName
var _color: Color
var _symbol_type := -1 # set from _sbg_huds_state in _init (after _sbg_alias)
var _point_size: int = IVSettingsManager.get_setting(&"small_bodies_point_size")
var _symbol_size: float # set from IVThemeManager in _init()
var _vec3ids := PackedVector3Array() # point ids for FragmentIdentifier

# Lagrange point
var _lp_integer := -1 # -1 or 1-5
var _longitude_offset := 0.0 # +PI/3 for L4; -PI/3 for L5
var _secondary_body: IVBody # e.g., Jupiter for Trojans; usually null

# subclass _init() overrides
var _points_shader_override: Shader
var _points_l4l5_shader_override: Shader
var _bypass_fragment_identifier := false



func _init(sbg: IVSmallBodiesGroup) -> void:
	name = "SBGPositions" + sbg.sbg_alias
	_sbg_alias = sbg.sbg_alias
	_symbol_type = _sbg_huds_state.get_symbol_type(_sbg_alias)
	_lp_integer = sbg.lp_integer
	if _lp_integer == 4:
		_longitude_offset = PI / 3
	elif _lp_integer == 5:
		_longitude_offset = -PI / 3
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	_sbg_huds_state.symbols_visibility_changed.connect(_set_visibility)
	_sbg_huds_state.color_changed.connect(_set_color)
	_sbg_huds_state.symbol_changed.connect(_set_symbol)
	IVSettingsManager.changed.connect(_settings_listener)

	var theme_manager: IVThemeManager = IVGlobal.program[&"ThemeManager"]
	_symbol_size = theme_manager.get_small_bodies_symbol_size()
	theme_manager.small_bodies_symbol_size_changed.connect(_on_small_bodies_symbol_size_changed)

	var number := sbg.get_number()

	# fragment ids
	# Broadcast ids only when an IVFragmentIdentifier exists to read them back (it is
	# absent on the Compatibility renderer). The shader's 'broadcast_id' uniform gates
	# the write; _vec3ids holds real ids only when broadcasting but always doubles as
	# the mesh vertex array (one vertex per point), so it is sized either way.
	var broadcast_id := _fragment_identifier != null and !_bypass_fragment_identifier
	_vec3ids.resize(number)
	if broadcast_id:
		var i := 0
		while i < number:
			var data := sbg.get_fragment_data(FRAGMENT_SBG_POINT, i)
			_vec3ids[i] = _fragment_identifier.get_new_id_as_vec3(data)
			i += 1

	# set shader
	var shader_material := ShaderMaterial.new()
	if _lp_integer == -1: # not trojans
		shader_material.shader = (_points_shader_override if _points_shader_override
				else IVGlobal.resources[&"orbiting_positions_id_shader"])
	elif _lp_integer >= 4: # trojans
		_secondary_body = sbg.secondary_body
		shader_material.shader = (_points_l4l5_shader_override if _points_l4l5_shader_override
				else IVGlobal.resources[&"orbiting_positions_lp_id_shader"])
	shader_material.set_shader_parameter(&"broadcast_id", broadcast_id)
	material_override = shader_material

	# ArrayMesh construction
	var points_mesh := ArrayMesh.new()
	var arrays := [] # packed arrays
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vec3ids
	arrays[Mesh.ARRAY_CUSTOM0] = sbg.e_i_lan_ap
	arrays[Mesh.ARRAY_CUSTOM1] = sbg.a_m0_n if _lp_integer == -1 else sbg.da_d_f_th0
	arrays[Mesh.ARRAY_CUSTOM2] = sbg.s_g_mag_de
	var array_flags := ARRAY_FLAGS if _lp_integer == -1 else L4L5_ARRAY_FLAGS
	points_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays, [], {}, array_flags)
	var half_aabb_size := sbg.max_apoapsis
	if IVCoreSettings.apply_farwarp:
		# Frustum culling tests this true-scale AABB against the far plane, but
		# farwarp-remapped points are on-screen even when that test fails;
		# make the test always pass wherever the camera can be.
		half_aabb_size = maxf(half_aabb_size, IVCoreSettings.max_camera_distance)
	var half_aabb := Vector3.ONE * half_aabb_size
	points_mesh.custom_aabb = AABB(-half_aabb, 2.0 * half_aabb)
	mesh = points_mesh

	# set shader parameters
	shader_material.set_shader_parameter(&"symbol_atlas", IVGlobal.resources[&"symbol_atlas"])
	shader_material.set_shader_parameter(&"symbol_type", _symbol_type)
	shader_material.set_shader_parameter(&"point_size", _get_point_size())
	if _lp_integer >= 4: # trojans
		shader_material.set_shader_parameter(&"leading_sign", 1.0 if _lp_integer == 4 else -1.0)
		var characteristic_length := _secondary_body.get_orbit_semi_major_axis(0.0)
		shader_material.set_shader_parameter(&"characteristic_length", characteristic_length)


func _ready() -> void:
	set_process(_lp_integer == 4 or _lp_integer == 5)
	_set_visibility()
	_set_color()


func _process(_delta: float) -> void:
	# Only L4 and L5 process!
	if !visible:
		return
	var lp_longitude := _secondary_body.get_orbit_mean_longitude() + _longitude_offset
	var shader_material: ShaderMaterial = material_override
	shader_material.set_shader_parameter(&"lp_longitude", lp_longitude)


# Point-sprite pixel size: the larger "symbol" size for a shaped symbol, or the
# smaller "point" size for a plain point (symbol_type -1).
func _get_point_size() -> float:
	if _symbol_type != -1:
		return _symbol_size
	return float(_point_size)


func _set_visibility() -> void:
	visible = _sbg_huds_state.is_symbols_visible(_sbg_alias)


func _set_color() -> void:
	var color := _sbg_huds_state.get_color(_sbg_alias)
	if _color == color:
		return
	_color = color
	var shader_material: ShaderMaterial = material_override
	shader_material.set_shader_parameter(&"color", color)


func _set_symbol() -> void:
	var symbol_type := _sbg_huds_state.get_symbol_type(_sbg_alias)
	if _symbol_type == symbol_type:
		return
	_symbol_type = symbol_type
	var shader_material: ShaderMaterial = material_override
	shader_material.set_shader_parameter(&"symbol_type", _symbol_type)
	shader_material.set_shader_parameter(&"point_size", _get_point_size()) # size depends on symbol_type


func _settings_listener(setting: StringName, value: Variant) -> void:
	if setting != &"small_bodies_point_size":
		return
	_point_size = value
	var shader_material: ShaderMaterial = material_override
	shader_material.set_shader_parameter(&"point_size", _get_point_size())


func _on_small_bodies_symbol_size_changed(symbol_size: float) -> void:
	if _symbol_size == symbol_size:
		return
	_symbol_size = symbol_size
	var shader_material: ShaderMaterial = material_override
	shader_material.set_shader_parameter(&"point_size", _get_point_size())
