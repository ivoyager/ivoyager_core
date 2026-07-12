# rings.gd
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
class_name IVRings
extends MeshInstance3D

## Visual planetary rings of an [IVBody] instance.
##
## This node self-adds multiple IVRingsShadowCaster (inner class) instances to
## cast semi-transparent shadows (in conjuction with [IVDynamicLight] instances).
## Shadow casting is disabled for Compatibility renderer (see comments in
## [IVDynamicLight]).[br][br]
##
## With [constant USE_ANALYTIC_SURFACE_SHADOW], the shadow casters are replaced
## by an analytic ring-shadow term this node feeds to the parent body's surface
## shader each frame (see [code]shaders/_sun_occlusion.gdshaderinc[/code]).[br][br]
##
## All properties are set from data table rings.tsv.[br][br]
##
## These classes use rings.shader and rings_shadow_caster.shader. See comments
## in shader files for graphics issues and commentary.[br][br]
##
## Not persisted. [IVBodyFinisher] adds when [IVBody] is added to the tree.[br][br]

const ShadowMask := IVGlobal.ShadowMask

## Experiment toggle: shadow the parent body's surface analytically (per-fragment
## ring-plane transmission in the surface shader) instead of via the shadow-map
## caster rig. Unlike the casters, this path also works with the Compatibility
## renderer.
const USE_ANALYTIC_SURFACE_SHADOW := true

const END_PADDING := 0.05 # must be same as ivbinary_maker that generated images
const RENDER_MARGIN := 0.01 # render outside of image data for smoothing
const LOD_LEVELS := 9 # must agree w/ assets, body.gd and rings.shader


# All built from table rings.tsv (shadow_lod is used by asset_preloader.gd).
## Asset file prefix used to locate ring textures.
var file_prefix: String
## Inner edge of the ring system, in simulator units.
var inner_radius: float
## Outer edge of the ring system, in simulator units.
var outer_radius: float
## Quadratic noise coefficient (in camera distance) used to break shadow
## banding artifacts.
var shadow_radial_noise_a: float # breaks banding artifact (with camera distance squared)
## Linear noise coefficient (in camera distance) used to break shadow banding
## artifact patterns.
var shadow_radial_noise_b: float  # breaks banding artifact pattern (with camera distance)
## Constant noise coefficient used to break shadow banding artifacts.
var shadow_radial_noise_c: float  # breaks banding artifact (constant)
## Name of the [IVBody] star casting light through the rings.
var illuminating_star: StringName


var _rings_material := ShaderMaterial.new()
var _texture_arrays: Array[Texture2DArray] # backscatter/forwardscatter/unlitside for each LOD
var _texture_start: float
var _inner_margin: float
var _outer_margin: float
var _inner_texture: float # texture-range inner radius (inside inner_radius by END_PADDING)
var _outer_texture: float # texture-range outer radius (edge of plane)
var _shadow_caster_texture: Texture2D
var _shadow_caster_shared: Array[float] = [1.0, 0.005] # alpha_exponent, noise_strength
var _shadow_profile_texture: Texture2D
var _surface_material: ShaderMaterial # analytic ring-shadow target (parent body's shell 0)
var _blue_noise_1024: Texture2D
var _body: IVBody
var _illuminating_star: IVBody
var _camera: Camera3D

var _has_shadows := !IVGlobal.is_gl_compatibility and not USE_ANALYTIC_SURFACE_SHADOW


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
	_shadow_profile_texture = asset_preloader.get_rings_shadow_profile_texture(name)
	_blue_noise_1024 = asset_preloader.get_blue_noise_1024()
	cast_shadow = SHADOW_CASTING_SETTING_OFF # semi-transparancy can't cast shadows
	mesh = IVGlobal.resources[&"plane_mesh"] # shared subdivided 2x2 plane (farwarp needs subdivision)
	rotation.x = PI / 2.0 # z up astronomy


func _ready() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVGlobal.current_camera_changed.connect(_set_camera)
	_set_camera(get_viewport().get_camera_3d())
	
	_illuminating_star = IVBody.bodies.get(illuminating_star)
	assert(_illuminating_star, "Could not find illuminating star '%s'" % illuminating_star)
	
	# distances in sim scale
	var ring_span := outer_radius - inner_radius
	_outer_texture = outer_radius + END_PADDING * ring_span # edge of plane
	_inner_texture = inner_radius - END_PADDING * ring_span # texture start from center

	# normalized distances from center of 2x2 plane
	_texture_start = _inner_texture / _outer_texture
	_inner_margin = (inner_radius - RENDER_MARGIN * ring_span) / _outer_texture # render boundary
	_outer_margin = (outer_radius + RENDER_MARGIN * ring_span) / _outer_texture # render boundary

	scale = Vector3(_outer_texture, 1.0, _outer_texture)

	if USE_ANALYTIC_SURFACE_SHADOW:
		# The shadow uniforms carry global positions, so they must be read after
		# IVCamera (0) origin-shifts the Universe - same reason IVFarwarpManager
		# processes late.
		process_priority = 100
	visibility_range_end = outer_radius * IVCoreSettings.radius_multiplier_visibility_range_end
	if IVCoreSettings.apply_farwarp:
		# Frustum culling tests the true-scale AABB against the far plane, but the farwarp
		# vertex remap keeps the ring on-screen even when that test fails; make it always pass.
		var extent := IVCoreSettings.max_camera_distance
		custom_aabb = AABB(-Vector3.ONE * extent, 2.0 * Vector3.ONE * extent)

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

	if USE_ANALYTIC_SURFACE_SHADOW:
		_update_surface_shadow()

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
	_surface_material = null


func _set_camera(camera: Camera3D) -> void:
	_camera = camera


# Feeds the analytic ring-shadow uniforms on the parent body's surface material
# (see _sun_occlusion.gdshaderinc). The material is fetched lazily: the sibling
# spheroid model may not exist yet when this node enters the tree.
func _update_surface_shadow() -> void:
	if not _surface_material:
		_surface_material = _find_surface_material()
		if not _surface_material:
			return
		_surface_material.set_shader_parameter(&"ring_alpha_r8", _shadow_profile_texture)
		_surface_material.set_shader_parameter(&"ring_alpha_width",
				float(_shadow_profile_texture.get_width()))
		_surface_material.set_shader_parameter(&"ring_texture_inner", _inner_texture)
		_surface_material.set_shader_parameter(&"ring_texture_outer", _outer_texture)
	var star_vector := _illuminating_star.global_position - global_position
	var star_distance := star_vector.length()
	_surface_material.set_shader_parameter(&"ring_center", global_position)
	_surface_material.set_shader_parameter(&"ring_normal", global_basis.y.normalized())
	_surface_material.set_shader_parameter(&"sun_direction", star_vector / star_distance)
	_surface_material.set_shader_parameter(&"sun_angular_radius",
			_illuminating_star.mean_radius / star_distance)


func _find_surface_material() -> ShaderMaterial:
	# IVBodyFinisher adds this node to IVBodyVisual, the spheroid model's parent.
	var spheroid_model := get_node_or_null(^"../SpheroidModel") as MeshInstance3D
	if not spheroid_model:
		return null
	return spheroid_model.get_surface_override_material(0) as ShaderMaterial


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
			_blue_noise_1024, outer_radius)
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
			shadow_caster_shared: Array[float], blue_noise_1024: Texture2D,
			outer_radius: float) -> void:
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
		mesh = IVGlobal.resources[&"plane_mesh"] # shared subdivided 2x2 plane (farwarp needs subdivision)
		name = "RingsShadowCaster" + str(low_alpha).replace(".", "p")
		visibility_range_end = outer_radius * IVCoreSettings.radius_multiplier_visibility_range_end
		if IVCoreSettings.apply_farwarp:
			# Match the visible ring so the caster's past-far-plane geometry isn't frustum-culled.
			var extent := IVCoreSettings.max_camera_distance
			custom_aabb = AABB(-Vector3.ONE * extent, 2.0 * Vector3.ONE * extent)


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
