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

const files := preload("res://addons/ivoyager_core/static/files.gd")
const ShadowMask := IVGlobal.ShadowMask

const END_PADDING := 0.05 # must be same as ivbinary_maker that generated images
const RENDER_MARGIN := 0.01 # render outside of image data for smoothing
const LOD_LEVELS := 9 # must agree w/ assets, body.gd and rings.shader


# set from table rings.tsv
var file_prefix: String
var inner_radius: float
var outer_radius: float
var sun_index: int
var shadow_lod: int # affects shadow aliasing
var shadow_noise_base_strength: float # affects shadow aliasing


var _rings_material := ShaderMaterial.new()

var _texture_arrays: Array[Texture2DArray] = [] # backscatter/forwardscatter/unlitside for each LOD
var _texture_start: float
var _inner_margin: float
var _outer_margin: float

var _sun_global_positions: Array[Vector3]
var _shadow_caster_texture: Texture2D
var _shadow_caster_shared: Array[float] = [1.0, 0.005] # alpha_exponent, noise_strength

var _body: IVBody
var _camera: Camera3D

static var _pregenerated_resources: Dictionary[String, Array] = {} # indexed by file_prefix



static func _static_init() -> void:
	# Preload & process all rings textures.
	IVGlobal.project_builder_finished.connect(_pregenerate_resources)


func _init(body: IVBody) -> void:
	# threadsafe
	_body = body
	_sun_global_positions = IVBody.sun_global_positions
	var row := IVTableData.db_find_in_array(&"rings", &"bodies", body.name)
	assert(row != -1, "Could not find row in rings.tsv for %s" % body.name)
	IVTableData.db_build_object_all_fields(self, &"rings", row)
	var resources := _pregenerated_resources[file_prefix]
	_texture_arrays = resources[0]
	_shadow_caster_texture = resources[1]
	cast_shadow = SHADOW_CASTING_SETTING_OFF # semi-transparancy can't cast shadows
	mesh = PlaneMesh.new() # default 2x2
	rotation.x = PI / 2.0 # z up astronomy


func _ready() -> void:
	IVGlobal.about_to_free_procedural_nodes.connect(_clear)
	IVGlobal.camera_ready.connect(_connect_camera)
	_connect_camera(get_viewport().get_camera_3d())
	_body.model_visibility_changed.connect(_on_model_visibility_changed)
	_on_model_visibility_changed(_body.model_visible)
	
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
	_rings_material.set_shader_parameter(&"sun_index", sun_index)
	set_surface_override_material(0, _rings_material)
	_add_shadow_casters()


func _process(_delta: float) -> void:
	var MIN_SHADOW_ALPHA_EXPONENT := 0.001
	
	if !_camera:
		return
	
	# rings.shader expects sun-facing and the ShadowCasters require it (because
	# a GeometryInstance3D can't be shadow only and double sided at the same
	# time). 
	var sun_direction := _sun_global_positions[sun_index].normalized()
	var cos_sun_angle := global_basis.y.dot(sun_direction)
	if cos_sun_angle < 0.0:
		rotation.x *= -1
		cos_sun_angle *= -1
	
	# Travel distance through the rings is proportional to 1/cos(sun_angle).
	# We use cos_sun_angle (with minimum) as alpha exponent to adjust
	# for light travel through rings at an angle. If sun were straight above,
	# exponent would be 1.0 (no adjustment). When sun is edge on, exponent
	# goes to minimum and all alpha values approach 1.0.
	_shadow_caster_shared[0] = maxf(cos_sun_angle, MIN_SHADOW_ALPHA_EXPONENT) # alpha_exponent
	
	# Shadow noise needs to increase with distance to prevent alias effect.
	var dist_ratio := (_camera.global_position - global_position).length() / outer_radius
	_shadow_caster_shared[1] = shadow_noise_base_strength * dist_ratio


static func _pregenerate_resources() -> void:
	
	const BACKSCATTER_FILE_FORMAT := "%s.backscatter.%s"
	const FORWARDSCATTER_FILE_FORMAT := "%s.forwardscatter.%s"
	const UNLITSIDE_FILE_FORMAT := "%s.unlitside.%s"
	
	var rings_search := IVCoreSettings.rings_search
	
	for row in IVTableData.get_n_rows(&"rings"):
		var file_prefix_ := IVTableData.get_db_string(&"rings", &"file_prefix", row)
		var shadow_lod_ := IVTableData.get_db_int(&"rings", &"shadow_lod", row)
		shadow_lod_ = mini(shadow_lod_, LOD_LEVELS - 1)
		
		var texture_arrays: Array[Texture2DArray] = []
		var shadow_image_rgba: Image
		for lod in LOD_LEVELS:
			var file_elements := [file_prefix_, lod]
			var backscatter_file := BACKSCATTER_FILE_FORMAT % file_elements
			var backscatter: Texture2D = files.find_and_load_resource(rings_search, backscatter_file)
			assert(backscatter, "Failed to load '%s'" % backscatter_file)
			var forwardscatter_file := FORWARDSCATTER_FILE_FORMAT % file_elements
			var forwardscatter: Texture2D = files.find_and_load_resource(rings_search, forwardscatter_file)
			assert(forwardscatter, "Failed to load '%s'" % forwardscatter_file)
			var unlitside_file := UNLITSIDE_FILE_FORMAT % file_elements
			var unlitside: Texture2D = files.find_and_load_resource(rings_search, unlitside_file)
			assert(unlitside, "Failed to load '%s'" % unlitside_file)
			
			# We seem to need to load as textures, convert to images, then reconvert
			# back to texture arrays. Maybe there is a better way?
			var backscatter_image := backscatter.get_image()
			var forwardscatter_image := forwardscatter.get_image()
			var unlitside_image := unlitside.get_image()
			var lod_images: Array[Image] = [backscatter_image, forwardscatter_image, unlitside_image]
			var texture_array := Texture2DArray.new() # backscatter/forwardscatter/unlitside for LOD
			texture_array.create_from_images(lod_images)
			texture_arrays.append(texture_array)
			if lod == shadow_lod_:
				shadow_image_rgba = backscatter_image # all have the same alpha channel
		
		# shadow caster texture is FORMAT_R8, alpha only
		var shadow_width := shadow_image_rgba.get_width()
		var shadow_image_r8 := Image.create_empty(shadow_width, 1, false, Image.FORMAT_R8)
		for x in shadow_width:
			var color := shadow_image_rgba.get_pixel(x, 0)
			color.r = color.a
			shadow_image_r8.set_pixel(x, 0, color)
		var shadow_caster_texture := ImageTexture.create_from_image(shadow_image_r8)
		
		_pregenerated_resources[file_prefix_] = [texture_arrays, shadow_caster_texture]


func _clear() -> void:
	_body = null
	_camera = null


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
		var shadow_caster := IVRingsShadowCaster.new(_shadow_caster_texture, _texture_start,
			_inner_margin, _outer_margin, low_alpha, max_alpha, shadow_mask, _shadow_caster_shared)
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
	
	
	func _init(texture_r8: Texture2D, texture_start: float, inner_margin: float, outer_margin: float,
			low_alpha: float, max_alpha: float, shadow_mask: ShadowMask,
			shadow_caster_shared: Array[float]) -> void:
		_texture_r8 = texture_r8
		_texture_start = texture_start
		_inner_margin = inner_margin
		_outer_margin = outer_margin
		_low_alpha = low_alpha
		_max_alpha = max_alpha
		_shadow_caster_shared = shadow_caster_shared
		layers = shadow_mask
		cast_shadow = SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mesh = PlaneMesh.new() # default 2x2


	func _ready() -> void:
		_shadow_caster_material.shader = IVGlobal.resources[&"rings_shadow_caster_shader"]
		_shadow_caster_material.set_shader_parameter(&"texture_r8", _texture_r8)
		_shadow_caster_material.set_shader_parameter(&"texture_width", float(_texture_r8.get_width()))
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
