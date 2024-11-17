# rings.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charlie Whitfield
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
## This node uses rings.gdshader and hooks up to signal IVBody.model_visibility_changed
## so that it is only visible when the IVBody's model is visible.
##
## Not persisted. IVBody instance adds on _ready().

const END_PADDING := 0.05 # must be same as ivbinary_maker that generated images
const RENDER_MARGIN := 0.01 # render outside of image data for smoothing
const LOD_LEVELS := 9 # must agree w/ assets, body.gd and rings.shader

var _body: IVBody
var _shader_sun_index: int

var _texture_width: int
var _texture_arrays: Array[Texture2DArray] # backscatter/forwardscatter/unlitside for each LOD
var _rings_material := ShaderMaterial.new()



func _init(body: IVBody, shader_sun_index: int, rings_images: Array[Image]) -> void:
	assert(rings_images[0] and rings_images[1] and rings_images[2])
	_body = body
	_shader_sun_index = shader_sun_index
	_texture_width = rings_images[0].get_width()
	for lod in LOD_LEVELS:
		var lod_rings_images := rings_images.slice(lod * 3, lod * 3 + 3) as Array[Image]
		var texture_array := Texture2DArray.new() # backscatter/forwardscatter/unlitside for LOD
		texture_array.create_from_images(lod_rings_images)
		_texture_arrays.append(texture_array)


func _ready() -> void:
	const RIGHT_ANGLE := PI / 2.0
	
	_body.model_visibility_changed.connect(_on_model_visibility_changed)
	_on_model_visibility_changed(_body.model_visible)
	
	# distances in sim scale
	var outer_radius: float = _body.get_rings_outer_radius()
	var inner_radius: float = _body.get_rings_inner_radius()
	var ring_span := outer_radius - inner_radius
	var outer_texture := outer_radius + END_PADDING * ring_span # edge of plane
	var inner_texture := inner_radius - END_PADDING * ring_span # texture start from center
	
	# normalized distances from center of 2x2 plane
	var texture_start := inner_texture / outer_texture
	var inner_margin := (inner_radius - RENDER_MARGIN * ring_span) / outer_texture # render boundary
	var outer_margin := (outer_radius + RENDER_MARGIN * ring_span) / outer_texture # render boundary
	
	scale = Vector3(outer_texture, outer_texture, outer_texture)
	
	cast_shadow = SHADOW_CASTING_SETTING_DOUBLE_SIDED
	gi_mode = GI_MODE_DISABLED
	
	mesh = PlaneMesh.new() # default 2x2
	_rings_material.shader = IVCoreSettings.shared_resources[&"rings_shader"]
	_rings_material.set_shader_parameter(&"texture_width", float(_texture_width))
	_rings_material.set_shader_parameter(&"texture_start", texture_start)
	_rings_material.set_shader_parameter(&"inner_margin", inner_margin)
	_rings_material.set_shader_parameter(&"outer_margin", outer_margin)
	_rings_material.set_shader_parameter(&"sun_index", _shader_sun_index)
	for lod in LOD_LEVELS:
		_rings_material.set_shader_parameter("textures%s" % lod, _texture_arrays[lod])
	set_surface_override_material(0, _rings_material)
	rotate_x(RIGHT_ANGLE)


func _on_model_visibility_changed(is_model_visible: bool) -> void:
	visible = is_model_visible
