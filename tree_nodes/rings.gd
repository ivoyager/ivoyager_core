# rings.gd
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
class_name IVRings
extends MeshInstance3D

## Visual planetary rings of an [IVBody] instance.
##
## This node self-adds multiple IVRingsShadowCaster (inner class) instances to
## cast semi-transparent shadows (in conjuction with [IVDynamicLight] instances).
## Shadow casting is disabled for Compatibility renderer (see comments in
## [IVDynamicLight]).[br][br]
##
## All properties are set from data table rings.tsv.[br][br]
##
## These classes use rings.shader and rings_shadow_caster.shader. See comments
## in shader files for graphics issues and commentary.[br][br]
##
## Not persisted. [IVBodyFinisher] adds when [IVBody] is added to the tree.[br][br]

const files := preload("res://addons/ivoyager_core/static/files.gd")
const ShadowMask := IVGlobal.ShadowMask

const END_PADDING := 0.05 # must be same as ivbinary_maker that generated images
const RENDER_MARGIN := 0.01 # render outside of image data for smoothing
const LOD_LEVELS := 9 # must agree w/ assets, body.gd and rings.shader


# All built from table rings.tsv (shadow_lod is used by asset_preloader.gd).
var file_prefix: String
var inner_radius: float
var outer_radius: float
var shadow_radial_noise_a: float # breaks banding artifact (with camera distance squared)
var shadow_radial_noise_b: float  # breaks banding artifact pattern (with camera distance)
var shadow_radial_noise_c: float  # breaks banding artifact (constant)
var illuminating_star: StringName


var _rings_material := ShaderMaterial.new()
var _texture_arrays: Array[Texture2DArray] # backscatter/forwardscatter/unlitside for each LOD
var _texture_start: float
var _inner_margin: float
var _outer_margin: float
var _shadow_caster_texture: Texture2D
var _shadow_caster_shared: Array[float] = [1.0, 0.005] # alpha_exponent, noise_strength
var _blue_noise_1024: Texture2D
var _body: IVBody
var _illuminating_star: IVBody
var _camera: Camera3D

var _has_shadows := !IVGlobal.is_gl_compatibility


func _init(body: IVBody) -> void:
	# threadsafe
	name = &"Rings"
	_body = body
	var row := IVTableData.db_find_in_array(&"rings", &"bodies", body.name)
	assert(row != -1, "Could not find row in rings.tsv for %s" % body.name)
	IVTableData.db_build_object(self, &"rings", row)
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	_texture_arrays = asset_preloader.get_rings_texture_arrays(name)
	_shadow_caster_texture = asset_preloader.get_rings_shadow_caster_texture(name)
	_blue_noise_1024 = asset_preloader.get_blue_noise_1024()
	cast_shadow = SHADOW_CASTING_SETTING_OFF # semi-transparancy can't cast shadows
	mesh = PlaneMesh.new() # default 2x2
	rotation.x = PI / 2.0 # z up astronomy


func _ready() -> void:
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVGlobal.camera_ready.connect(_connect_camera)
	_connect_camera(get_viewport().get_camera_3d())
	
	_illuminating_star = IVBody.bodies.get(illuminating_star)
	assert(_illuminating_star, "Could not find illuminating star '%s'" % illuminating_star)
	
	# distances in sim scale
	var ring_span := outer_radius - inner_radius
	var outer_texture := outer_radius + END_PADDING * ring_span # edge of plane
	var inner_texture := inner_radius - END_PADDING * ring_span # texture start from center
	
	# normalized distances from center of 2x2 plane
	_texture_start = inner_texture / outer_texture
	_inner_margin = (inner_radius - RENDER_MARGIN * ring_span) / outer_texture # render boundary
	_outer_margin = (outer_radius + RENDER_MARGIN * ring_span) / outer_texture # render boundary
	
	scale = Vector3(outer_texture, 1.0, outer_texture)
	
	_rings_material.shader = IVGlobal.resources[&"rings_shader"]
	for lod in LOD_LEVELS:
		_rings_material.set_shader_parameter("textures%s" % lod, _texture_arrays[lod])
	_rings_material.set_shader_parameter(&"texture_width", float(_texture_arrays[0].get_width()))
	_rings_material.set_shader_parameter(&"texture_start", _texture_start)
	_rings_material.set_shader_parameter(&"inner_margin", _inner_margin)
	_rings_material.set_shader_parameter(&"outer_margin", _outer_margin)
	set_surface_override_material(0, _rings_material)
	
	if IVGlobal.is_gl_compatibility:
		_rings_material.set_shader_parameter(&"litside_phase_boost", 1.25)
		_rings_material.set_shader_parameter(&"unlitside_phase_boost", 1.5)
	
	if _has_shadows:
		_add_shadow_casters()


func _process(_delta: float) -> void:
	var MIN_SHADOW_ALPHA_EXPONENT := 0.001
	
	if !visible or !_camera:
		return
	
	# rings.shader expects sun-facing and the ShadowCasters require it (because
	# a GeometryInstance3D can't be both shadow-only and double-sided). So we
	# flip here as needed to keep mesh front face toward the sun.
	var illumination_position := _illuminating_star.global_position
	var cos_illumination_angle := global_basis.y.dot(illumination_position.normalized())
	if cos_illumination_angle < 0.0:
		rotation.x *= -1
		cos_illumination_angle *= -1
	
	_rings_material.set_shader_parameter(&"illumination_position", illumination_position)
	
	if !_has_shadows:
		return
	
	# Travel distance through the rings is proportional to 1/cos(illumination_angle).
	# We use cos_illumination_angle (with minimum) as alpha exponent to adjust shadows
	# for light travel through rings at an angle. If sun were straight above,
	# exponent would be 1.0 (no adjustment). When sun is edge on, exponent
	# goes to minimum and all alpha values approach 1.0.
	_shadow_caster_shared[0] = maxf(cos_illumination_angle, MIN_SHADOW_ALPHA_EXPONENT) # alpha_exponent
	
	# Shadow radial_noise_multiplier needs to increase with distance to prevent
	# banding artifacts.
	var dist_ratio := (_camera.global_position - global_position).length() / outer_radius
	_shadow_caster_shared[1] = (shadow_radial_noise_a * (dist_ratio ** 2)
			+ shadow_radial_noise_b * dist_ratio + shadow_radial_noise_c) # radial_noise_multiplier


func _clear_procedural() -> void:
	_body = null
	_illuminating_star = null
	_camera = null


func _connect_camera(camera: Camera3D) -> void:
	_camera = camera


func _add_shadow_casters() -> void:
	var i := 1
	var increment := 1.0 / 16.0
	for shadow_mask: ShadowMask in ShadowMask.values():
		var low_alpha := i * increment
		var max_alpha := (i + 1) * increment
		if is_equal_approx(max_alpha, 1.0):
			max_alpha = 3.0 # >1.0 allows for noise addition
		var shadow_caster := IVRingsShadowCaster.new(_shadow_caster_texture, _texture_start,
			_inner_margin, _outer_margin, low_alpha, max_alpha, shadow_mask, _shadow_caster_shared,
			_blue_noise_1024)
		add_child(shadow_caster)
		i += 1



class IVRingsShadowCaster extends MeshInstance3D:
	
	var _shadow_caster_material := ShaderMaterial.new()
	var _texture_r8: Texture2D
	var _texture_start: float
	var _inner_margin: float
	var _outer_margin: float
	var _low_alpha: float
	var _max_alpha: float
	var _shadow_caster_shared: Array[float]
	var _blue_noise_1024: Texture2D
	
	
	func _init(texture_r8: Texture2D, texture_start: float, inner_margin: float, outer_margin: float,
			low_alpha: float, max_alpha: float, shadow_mask: ShadowMask,
			shadow_caster_shared: Array[float], blue_noise_1024: Texture2D) -> void:
		_texture_r8 = texture_r8
		_texture_start = texture_start
		_inner_margin = inner_margin
		_outer_margin = outer_margin
		_low_alpha = low_alpha
		_max_alpha = max_alpha
		_shadow_caster_shared = shadow_caster_shared
		_blue_noise_1024 = blue_noise_1024
		layers = shadow_mask
		cast_shadow = SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mesh = PlaneMesh.new() # default 2x2
		name = "RingsShadowCaster" + str(low_alpha).replace(".", "p")


	func _ready() -> void:
		_shadow_caster_material.shader = IVGlobal.resources[&"rings_shadow_caster_shader"]
		_shadow_caster_material.set_shader_parameter(&"texture_r8", _texture_r8)
		_shadow_caster_material.set_shader_parameter(&"texture_width", float(_texture_r8.get_width()))
		_shadow_caster_material.set_shader_parameter(&"texture_start", _texture_start)
		_shadow_caster_material.set_shader_parameter(&"inner_margin", _inner_margin)
		_shadow_caster_material.set_shader_parameter(&"outer_margin", _outer_margin)
		_shadow_caster_material.set_shader_parameter(&"low_alpha", _low_alpha)
		_shadow_caster_material.set_shader_parameter(&"max_alpha", _max_alpha)
		_shadow_caster_material.set_shader_parameter(&"blue_noise_1024", _blue_noise_1024)
		set_surface_override_material(0, _shadow_caster_material)


	func _process(_delta: float) -> void:
		_shadow_caster_material.set_shader_parameter(&"alpha_exponent", _shadow_caster_shared[0])
		_shadow_caster_material.set_shader_parameter(&"radial_noise_multiplier",
				_shadow_caster_shared[1])
