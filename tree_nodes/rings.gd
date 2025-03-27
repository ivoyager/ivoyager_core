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
## hack semi-transparent shadows (in conjuction with IVDynamicLight instances).
##
## These classes use rings.shader and rings_shadow_caster.shader.
##
## Not persisted. IVBody instance adds on _ready().

const ShadowMask := IVGlobal.ShadowMask

const END_PADDING := 0.05 # must be same as ivbinary_maker that generated images
const RENDER_MARGIN := 0.01 # render outside of image data for smoothing
const LOD_LEVELS := 9 # must agree w/ assets, body.gd and rings.shader


var shadow_lod := 5 # affects shadow aliasing
var shadow_noise_base_strength := 0.006 # affects shadow aliasing


var _body: IVBody
var _texture_width: int
var _texture_start: float
var _inner_margin: float
var _outer_margin: float
var _outer_radius: float
var _texture_arrays: Array[Texture2DArray] # backscatter/forwardscatter/unlitside for each LOD
var _rings_material := ShaderMaterial.new()
var _sun_index: int
var _sun_global_positions: Array[Vector3]
var _shadow_caster_image: Image
var _camera: Camera3D

var _shadow_caster_shared: Array[float] = [1.0, 0.006] # alpha_exponent, noise_strength



func _init(body: IVBody, sun_index: int, rings_images: Array[Image]) -> void:
	assert(rings_images[0] and rings_images[1] and rings_images[2])
	_body = body
	_sun_index = sun_index
	_texture_width = rings_images[0].get_width()
	_sun_global_positions = body.sun_global_positions
	_shadow_caster_image = rings_images[shadow_lod * 3] # all have the same alpha channel
	for lod in LOD_LEVELS:
		var lod_rings_images := rings_images.slice(lod * 3, lod * 3 + 3) as Array[Image]
		var texture_array := Texture2DArray.new() # backscatter/forwardscatter/unlitside for LOD
		texture_array.create_from_images(lod_rings_images)
		_texture_arrays.append(texture_array)


func _ready() -> void:
	IVGlobal.camera_ready.connect(_connect_camera)
	_connect_camera(get_viewport().get_camera_3d())
	_body.model_visibility_changed.connect(_on_model_visibility_changed)
	_on_model_visibility_changed(_body.model_visible)
	
	# distances in sim scale
	_outer_radius = _body.get_rings_outer_radius()
	var inner_radius: float = _body.get_rings_inner_radius()
	var ring_span := _outer_radius - inner_radius
	var outer_texture := _outer_radius + END_PADDING * ring_span # edge of plane
	var inner_texture := inner_radius - END_PADDING * ring_span # texture start from center
	
	# normalized distances from center of 2x2 plane
	_texture_start = inner_texture / outer_texture
	_inner_margin = (inner_radius - RENDER_MARGIN * ring_span) / outer_texture # render boundary
	_outer_margin = (_outer_radius + RENDER_MARGIN * ring_span) / outer_texture # render boundary
	
	scale = Vector3(outer_texture, 1.0, outer_texture)
	cast_shadow = SHADOW_CASTING_SETTING_OFF # semi-transparancy can't cast shadows
	
	mesh = PlaneMesh.new() # default 2x2
	_rings_material.shader = IVGlobal.resources[&"rings_shader"]
	_rings_material.set_shader_parameter(&"texture_width", float(_texture_width))
	_rings_material.set_shader_parameter(&"texture_start", _texture_start)
	_rings_material.set_shader_parameter(&"inner_margin", _inner_margin)
	_rings_material.set_shader_parameter(&"outer_margin", _outer_margin)
	_rings_material.set_shader_parameter(&"sun_index", _sun_index)
	for lod in LOD_LEVELS:
		_rings_material.set_shader_parameter("textures%s" % lod, _texture_arrays[lod])
	set_surface_override_material(0, _rings_material)
	rotation.x = PI / 2.0
	_add_shadow_casters()


func _process(_delta: float) -> void:
	var MIN_SHADOW_ALPHA_EXPONENT := 0.001
	
	if !_camera:
		return
	
	# rings.shader expects sun-facing and the ShadowCasters require it (because
	# a GeometryInstance3D can't be shadow only and double sided at the same
	# time). 
	var sun_direction := _sun_global_positions[_sun_index].normalized()
	var cos_sun_angle := global_basis.y.dot(sun_direction)
	if cos_sun_angle < 0.0:
		rotation.x *= -1
		cos_sun_angle *= -1
	
	# Travel distance through the rings is proportional to 1/cos(sun_angle).
	# We use cos_sun_angle (with minimum) as alpha exponent to adjust
	# for light travel through rings at an angle. If sun were straight above,
	# exponent would be 1.0 (no adjustment). When sun is edge on, exponent
	# goes to minimum and all alpha values approach 1.0.
	_shadow_caster_shared[0] = maxf(cos_sun_angle, MIN_SHADOW_ALPHA_EXPONENT)
	
	# Shadow noise needs to increase with distance to prevent alias effect.
	var dist_ratio := (_camera.global_position - global_position).length() / _outer_radius
	_shadow_caster_shared[1] = shadow_noise_base_strength * dist_ratio


func _connect_camera(camera: Camera3D) -> void:
	_camera = camera


func _on_model_visibility_changed(is_model_visible: bool) -> void:
	visible = is_model_visible


func _add_shadow_casters() -> void:
	var i := 1
	var increment := 1.0 / 16.0
	for shadow_mask: ShadowMask in ShadowMask.values():
		var low_alpha := i * increment
		var max_alpha := (i + 1) * increment
		if is_equal_approx(max_alpha, 1.0):
			max_alpha = 1.1
		var shadow_caster := IVRingsShadowCaster.new(_shadow_caster_image, _texture_start,
			_inner_margin, _outer_margin, low_alpha, max_alpha, shadow_mask, _shadow_caster_shared)
		add_child(shadow_caster)
		i += 1
	_shadow_caster_image = null



class IVRingsShadowCaster extends MeshInstance3D:
	
	var _texture_start: float
	var _inner_margin: float
	var _outer_margin: float
	var _low_alpha: float
	var _max_alpha: float

	var _texture_width: int
	var _texture_r8: ImageTexture
	var _shadow_caster_material := ShaderMaterial.new()

	var _shadow_caster_shared: Array[float]
	
	
	func _init(image_rgba8: Image, texture_start: float, inner_margin: float, outer_margin: float,
			low_alpha: float, max_alpha: float, shadow_mask: ShadowMask,
			shadow_caster_shared: Array[float]) -> void:
		_texture_start = texture_start
		_inner_margin = inner_margin
		_outer_margin = outer_margin
		_low_alpha = low_alpha
		_max_alpha = max_alpha
		_shadow_caster_shared = shadow_caster_shared
		_texture_width = image_rgba8.get_width()
		var image_r8 := Image.create_empty(_texture_width, 1, false, Image.FORMAT_R8)
		for x in _texture_width:
			var color := image_rgba8.get_pixel(x, 0)
			color.r = color.a
			image_r8.set_pixel(x, 0, color)
		_texture_r8 = ImageTexture.create_from_image(image_r8)
		
		layers = shadow_mask


	func _ready() -> void:
		cast_shadow = SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mesh = PlaneMesh.new() # default 2x2
		_shadow_caster_material.shader = IVGlobal.resources[&"rings_shadow_caster_shader"]
		_shadow_caster_material.set_shader_parameter(&"texture_r8", _texture_r8)
		_shadow_caster_material.set_shader_parameter(&"texture_width", float(_texture_width))
		_shadow_caster_material.set_shader_parameter(&"texture_start", _texture_start)
		_shadow_caster_material.set_shader_parameter(&"inner_margin", _inner_margin)
		_shadow_caster_material.set_shader_parameter(&"outer_margin", _outer_margin)
		_shadow_caster_material.set_shader_parameter(&"low_alpha", _low_alpha)
		_shadow_caster_material.set_shader_parameter(&"max_alpha", _max_alpha)
		var blue_noise_1024: Texture2D = IVGlobal.assets[&"blue_noise_1024"]
		_shadow_caster_material.set_shader_parameter(&"blue_noise_1024", blue_noise_1024)
		set_surface_override_material(0, _shadow_caster_material)


	func _process(_delta: float) -> void:
		_shadow_caster_material.set_shader_parameter(&"alpha_exponent", _shadow_caster_shared[0])
		_shadow_caster_material.set_shader_parameter(&"noise_strength", _shadow_caster_shared[1])
