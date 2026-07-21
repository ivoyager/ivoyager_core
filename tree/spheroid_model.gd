# spheroid_model.gd
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
class_name IVSpheroidModel
extends MeshInstance3D

## A generic spheroid model (shared sphere mesh) that also orchestrates its own
## concentric "shells".
##
## The model used for stars and planetary-mass objects that have no packed-scene
## model. It is "shell 0" (the surface) and the parent of optional overlay shells
## 1..N (cloud deck, atmospheric haze, limb), each a child [IVSpheroidModel]. Created
## by [IVBodyVisual].[br][br]
##
## A body's shells are listed in its body-table [code]shells[/code] field
## ([code]ARRAY[STRING][/code], e.g. [code]SURFACE;CLOUDS;LIMB[/code]); each tag names
## a row [code]SHELL_<body_name>_<tag>[/code] in shells.tsv. The surface (shell 0) is the
## shell flagged [code]shell0[/code] (mutually exclusive with [code]scale[/code]); it always
## exists, defaulting from the body's [code]spheroids.tsv[/code] type when it has no shells.tsv
## row. Each shells.tsv row sets:[br]
## - [code]scale[/code] ([float]): radius multiplier; required for an overlay (surface
## ranks 1.0; a value < 1.0 places the shell under the surface).[br]
## - [code]file_tag[/code] ([StringName], optional): texture filename token
## ([code]<file_prefix>.<file_tag>.<channel>[/code]); blank for a textureless shell and
## for the surface, whose textures use [code]file_prefix[/code] alone.[br]
## - [code]shader[/code] ([StringName]): give the shell a [ShaderMaterial] using the
## named [Shader] in [member IVGlobal.resources], instead of a [StandardMaterial3D].[br]
## - [code]process[/code] ([StringName]): name a [member process_methods] entry called on the
## shell each frame as [code]method(delta, ...process_args)[/code] (e.g. [method _rotate]).[br]
## - [code]process_args[/code] ([code]ARRAY[VARIANT][/code]): extra arguments bound after
## [code]delta[/code] in the [code]process[/code] call (shells.tsv only).[br]
## - [code]transparency[/code] ([enum BaseMaterial3D.Transparency]): per-shell material
## override, no shell-0 assumption. (Shadow-casting is the separate [code]cast_shadow[/code] column.)[br]
## - any other column: set directly as the named [StandardMaterial3D] property (e.g.
## [code]albedo_color[/code], [code]roughness[/code]). When the body has no shells.tsv shell-0
## row, shell 0 instead takes its whole spec from its [code]spheroids.tsv[/code] type row. A uniform
## shell needs only [code]albedo_color[/code] (RGBA) — no texture.[br][br]
##
## Overlapping translucent shells auto-order back-to-front by scale (outer on top,
## via material [code]render_priority[/code]); give shells distinct scales (equal
## scales z-fight).[br][br]
##
## Developer note: Process methods must gate themselves on [member IVStateManager.paused_tree]
## as needed. This is because some methods need to run in a project setup where
## the camera is able to move during pause.


## Texture channel → the [enum BaseMaterial3D.Feature] enabled when that channel is
## applied (channels absent here are always active). Used by [method _apply_channels_to_material].
const CHANNEL_FEATURES := {
	BaseMaterial3D.TEXTURE_EMISSION: BaseMaterial3D.FEATURE_EMISSION,
	BaseMaterial3D.TEXTURE_NORMAL: BaseMaterial3D.FEATURE_NORMAL_MAPPING,
	BaseMaterial3D.TEXTURE_BENT_NORMAL: BaseMaterial3D.FEATURE_BENT_NORMAL_MAPPING,
	BaseMaterial3D.TEXTURE_RIM: BaseMaterial3D.FEATURE_RIM,
	BaseMaterial3D.TEXTURE_CLEARCOAT: BaseMaterial3D.FEATURE_CLEARCOAT,
	BaseMaterial3D.TEXTURE_FLOWMAP: BaseMaterial3D.FEATURE_ANISOTROPY,
	BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION: BaseMaterial3D.FEATURE_AMBIENT_OCCLUSION,
	BaseMaterial3D.TEXTURE_HEIGHTMAP: BaseMaterial3D.FEATURE_HEIGHT_MAPPING,
	BaseMaterial3D.TEXTURE_SUBSURFACE_SCATTERING: BaseMaterial3D.FEATURE_SUBSURFACE_SCATTERING,
	BaseMaterial3D.TEXTURE_SUBSURFACE_TRANSMITTANCE: BaseMaterial3D.FEATURE_SUBSURFACE_TRANSMITTANCE,
	BaseMaterial3D.TEXTURE_BACKLIGHT: BaseMaterial3D.FEATURE_BACKLIGHT,
	BaseMaterial3D.TEXTURE_REFRACTION: BaseMaterial3D.FEATURE_REFRACTION,
	BaseMaterial3D.TEXTURE_DETAIL_ALBEDO: BaseMaterial3D.FEATURE_DETAIL,
}

## Material value property → the [enum BaseMaterial3D.Feature] enabled when that
## property is set from a data table — the non-texture analog of [constant CHANNEL_FEATURES],
## so setting e.g. [code]rim[/code] enables [code]rim_enabled[/code] automatically.
const PROPERTY_FEATURES := {
	&"emission": BaseMaterial3D.FEATURE_EMISSION,
	&"normal_scale": BaseMaterial3D.FEATURE_NORMAL_MAPPING,
	&"rim": BaseMaterial3D.FEATURE_RIM,
	&"rim_tint": BaseMaterial3D.FEATURE_RIM,
	&"clearcoat": BaseMaterial3D.FEATURE_CLEARCOAT,
	&"clearcoat_roughness": BaseMaterial3D.FEATURE_CLEARCOAT,
	&"anisotropy": BaseMaterial3D.FEATURE_ANISOTROPY,
	&"ao_light_affect": BaseMaterial3D.FEATURE_AMBIENT_OCCLUSION,
	&"heightmap_scale": BaseMaterial3D.FEATURE_HEIGHT_MAPPING,
	&"subsurf_scatter_strength": BaseMaterial3D.FEATURE_SUBSURFACE_SCATTERING,
	&"subsurf_scatter_transmittance_color": BaseMaterial3D.FEATURE_SUBSURFACE_TRANSMITTANCE,
	&"backlight": BaseMaterial3D.FEATURE_BACKLIGHT,
	&"refraction_scale": BaseMaterial3D.FEATURE_REFRACTION,
}

# sun-mode LOD ramp (see the sun-mode section). Solved per star rather than authored, then
# pushed to both sun shaders, which resolve the on-screen pixel radius against their own
# VIEWPORT_SIZE. Kept here as the single source: the disc's fade-out and the point's fade-in
# are two ends of one crossfade.
const _SUN_HANDOFF_LOW_RATIO := 0.4 # fade span, as a fraction of the solved handoff (was 1.0/2.5)
const _SUN_HANDOFF_FALLBACK := 2.5 # px radius, if the star never saturates (see the solver)


## Registry of 'process' methods, keyed by the name used in the spheroids.tsv or shells.tsv
## 'process' field. Each [Callable] runs on the shell every frame as
## [code]method(spheroid_model, delta, ...process_args)[/code]. Register entries in
## [method _static_init] or from project code to add a process method without subclassing.
static var process_methods: Dictionary[StringName, Callable] = {}

# Debug-only caches for the per-shell override asserts in _build_material; built
# lazily and kept for the session. Unused unless OS.is_debug_build().
static var _material_property_names: Dictionary[StringName, bool] = {}
static var _shader_uniform_names: Dictionary = {} # Shader -> Dictionary[StringName, bool]

var _shell: int # 0 is the surface and orchestrator; 1..N are child shells
var _body_name: StringName
var _spheroid_type: int
var _mean_radius: float
var _reference_basis: Basis # this shell's base basis (before any process scaling)
var _process_callable: Callable
var _star_body: IVBody # sun-mode: owning body, for its true (un-farwarped) position and photometry
var _is_sun: bool # sun-mode (shell 0 with is_sun): dual disc + point; see the sun-mode section
var _sun_bv := 0.63 # sun-mode: cached B-V (disc/point color); fallback if the characteristic is missing
var _sun_abs_mag := 4.83 # sun-mode: cached V absolute magnitude (for the per-frame apparent magnitude)
var _sun_surface_material: ShaderMaterial # sun-mode: the disc material, angular size driven each frame
var _sun_point: MeshInstance3D # sun-mode: far point sprite, a child of _star_body (freed in _exit_tree)
var _sun_point_material: ShaderMaterial # sun-mode: the point material, driven each frame
var _star_settings: IVStarSettings # sun-mode: shared star photometry; the point's, not the disc's

var _times := IVGlobal.times




# *****************************************************************************
# 'process' methods & registry

# process_methods maps a spheroids.tsv/shells.tsv 'process' name to one of the static methods
# below, resolved once per shell in _resolve_process() and called every frame via _process_callable
# as method(spheroid_model, delta, ...process_args). Each method owns the shell's whole per-frame
# behavior (there is no default to fall through to). Add entries without subclassing.

static func _static_init() -> void:
	process_methods[&"_rotate"] = _rotate


## Named by a 'process' field (shells.tsv or spheroids.tsv). Rotates [param spheroid_model]
## at [param deg_per_sec] degrees per second.
static func _rotate(spheroid_model: IVSpheroidModel, delta: float, deg_per_sec: float) -> void:
	const CONVERSION := PI / (180.0 * IVUnits.SECOND)
	if IVStateManager.paused_tree:
		return
	delta *= spheroid_model._times[1] / Engine.time_scale
	spheroid_model.rotate_y(delta * deg_per_sec * CONVERSION) # y up in model self reference


func _init(body_name: StringName, spheroid_type: int, mean_radius: float, model_basis: Basis,
		shell := 0) -> void:
	_body_name = body_name
	_spheroid_type = spheroid_type
	_mean_radius = mean_radius
	_shell = shell
	_reference_basis = model_basis
	name = &"SpheroidModel" if shell == 0 else StringName("Shell_%d" % shell)
	transform.basis = model_basis
	mesh = IVGlobal.resources[&"sphere_mesh"]


func _ready() -> void:
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	var shell_specs := asset_preloader.get_body_shell_specs(_body_name)
	var spec: Dictionary = shell_specs[_shell]
	if _shell == 0:
		spec = _resolve_shell0_spec(asset_preloader, spec)
		_is_sun = spec[&"is_sun"]
	var process_method: StringName = spec[&"process"]
	var process_args: Array = spec[&"process_args"]
	var render_priority := _compute_render_priority(shell_specs)
	_build_material(spec, asset_preloader, render_priority)
	cast_shadow = spec[&"cast_shadow"]
	_set_visibility_and_layers()
	_resolve_process(process_method, process_args)
	if _is_sun:
		_enter_sun_mode()
	if _shell == 0:
		_build_child_shells(shell_specs)


func _process(delta: float) -> void:
	if _process_callable.is_valid():
		_process_callable.call(self, delta)
	if _is_sun:
		_process_sun_lod(delta)


func _exit_tree() -> void:
	# The far point is parented to the body (not this model's subtree), so free it explicitly
	# when this model is torn down while the body lives (e.g. remove_and_disable_body_visual).
	if is_instance_valid(_sun_point):
		_sun_point.queue_free()



# *****************************************************************************
# sun-mode: near disc + far point for an in-scene star (shell 0 with is_sun)

# A star spans many au of viewing distance: near, it is a resolved sphere (this model's disc,
# the sun_surface shader); far, it shrinks below a pixel and must be a point on the same
# photometric footing as the background star field (a child sun_point sprite of the body). The
# two crossfade by the star's on-screen pixel radius, so neither the fake growth of the old
# hack nor a vanishing sub-pixel disc occurs. The disc holds a constant surface brightness
# (distance-invariant); the point carries the distance dimming.
#
# Both halves live in the two shaders, which resolve against their own VIEWPORT_SIZE; only
# what distance alone determines stays here (angular size and apparent magnitude). Nothing
# viewport-dependent is left on this side on purpose -- a CPU cull could only ever answer for
# the viewport this node lives in, and would leak that answer into an off-screen capture
# rendered at another size. The shaders drop themselves instead: the disc discards at alpha 0
# (its depth write is why it cannot simply linger) and the point's fade reaches 0 under
# blend_add.


func _enter_sun_mode() -> void:
	const DISC_BRIGHTNESS := 3.0 # HDR-capable; reads as a blinding disc, blooms once glow is enabled
	_star_body = IVBody.bodies.get(_body_name)
	if _star_body:
		var color_bv: float = _star_body.characteristics.get(&"color_b_v", _sun_bv)
		var absolute_magnitude: float = _star_body.characteristics.get(&"absolute_magnitude", _sun_abs_mag)
		_sun_bv = color_bv
		_sun_abs_mag = absolute_magnitude
	# Connected here rather than with the far point, which is built lazily and rebuilt if this
	# model is torn down and re-added -- _ready() would not fire again, so connecting there
	# would stack a second connection onto the same settings object.
	_star_settings = IVGlobal.program[&"StarSettings"]
	_star_settings.changed.connect(_on_star_settings_changed)
	var surface_material := get_surface_override_material(0)
	if surface_material is ShaderMaterial:
		_sun_surface_material = surface_material
		_sun_surface_material.set_shader_parameter(&"color_bv", _sun_bv)
		_sun_surface_material.set_shader_parameter(&"brightness", DISC_BRIGHTNESS)
		_star_settings.apply_color_to(_sun_surface_material)
	_refresh_sun_handoff() # solved from _sun_abs_mag / _mean_radius, so it must follow both
	# The empty 'process' column leaves idle processing off; the LOD driver needs it on.
	set_process(true)


func _process_sun_lod(_delta: float) -> void:
	const FIVE_OVER_LN10 := 2.1714724095162594 # 5 / ln(10), for m = M + 5*log10(d / 10pc)
	var viewport := get_viewport()
	if not viewport:
		return
	var camera := viewport.get_camera_3d()
	if not camera:
		return
	if not _star_body:
		return
	if not _sun_point:
		_build_sun_point()
	# True (un-farwarped) distance: the model sits at the body's true position (farwarp is a
	# per-vertex shader remap), so the body's own global_position gives the real distance.
	var camera_distance := _star_body.global_position.distance_to(camera.global_position)
	if camera_distance <= 0.0:
		return
	# Angular size and apparent magnitude (m = M + 5*log10(d / 10pc)) are functions of distance
	# alone, so they are the same for every viewport. Each shader scales angular_radius by its
	# own VIEWPORT_SIZE to get pixels and runs the crossfade from there.
	var angular_radius := _mean_radius / camera_distance
	if _sun_surface_material:
		_sun_surface_material.set_shader_parameter(&"angular_radius", angular_radius)
	if _sun_point_material:
		var apparent_magnitude := _sun_abs_mag + FIVE_OVER_LN10 * log(camera_distance / (10.0 * IVUnits.PARSEC))
		_sun_point_material.set_shader_parameter(&"angular_radius", angular_radius)
		_sun_point_material.set_shader_parameter(&"apparent_magnitude", apparent_magnitude)


func _build_sun_point() -> void:
	# A 1-vertex points mesh mirroring IVStarsVisual: farwarp is applied in-shader, so the
	# true-position AABB fails the frustum test -- size it to always contain the camera. Parented
	# to the body (never rotated or scaled) so it sits at the true position; freed in _exit_tree.
	var vertices := PackedVector3Array([Vector3.ZERO])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var points_mesh := ArrayMesh.new()
	points_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var half_extent := IVCoreSettings.max_camera_distance
	points_mesh.custom_aabb = AABB(-Vector3.ONE * half_extent, 2.0 * Vector3.ONE * half_extent)
	var shader: Shader = IVGlobal.resources.get(&"sun_point_shader")
	_sun_point_material = ShaderMaterial.new()
	_sun_point_material.shader = shader
	_sun_point_material.set_shader_parameter(&"color_bv", _sun_bv)
	# Past the handoff this point is a field star, so it images through the same camera the
	# star field does -- one settings object, or the two drift apart on the first edit.
	_star_settings.apply_to(_sun_point_material)
	_refresh_sun_handoff() # the point material exists now and takes the same ramp as the disc
	_sun_point = MeshInstance3D.new()
	_sun_point.name = &"SunPoint"
	_sun_point.mesh = points_mesh
	_sun_point.material_override = _sun_point_material
	_sun_point.cast_shadow = SHADOW_CASTING_SETTING_OFF
	_star_body.add_child(_sun_point)


# The far point is lazy, so this fires before there is a material to push to.
func _on_star_settings_changed() -> void:
	if _sun_surface_material:
		_star_settings.apply_color_to(_sun_surface_material) # the disc shares only the B-V ramp
	if _sun_point_material:
		_star_settings.apply_to(_sun_point_material)
	_refresh_sun_handoff()


func _refresh_sun_handoff() -> void:
	var handoff_high := _solve_sun_handoff_high()
	var handoff_low := handoff_high * _SUN_HANDOFF_LOW_RATIO
	if _sun_surface_material:
		_sun_surface_material.set_shader_parameter(&"handoff_low", handoff_low)
		_sun_surface_material.set_shader_parameter(&"handoff_high", handoff_high)
	if _sun_point_material:
		_sun_point_material.set_shader_parameter(&"handoff_low", handoff_low)
		_sun_point_material.set_shader_parameter(&"handoff_high", handoff_high)


# On-screen pixel radius where the far point's saturated core matches the disc's diameter,
# i.e. where the two can trade places without stepping in size. Both are orders of magnitude
# above saturation throughout the handoff, so brightness is not what the eye has to go on --
# size is, and a crossfade that steps it reads as the abrupt shrink this ramp exists to
# prevent. Solving it also retires a hand-tuned constant that only ever suited one star at
# one psf_sigma: the answer moves with psf_sigma roughly linearly (0.5 -> 3.8 px, 1.0 -> 7.8),
# so a literal would silently go stale the first time that shared slider moved.
#
# Viewport-independence is what lets this live on this side at all, and it is not luck: hold
# pixel_radius fixed and a taller render puts the star proportionally farther, so the flux it
# loses to 1/d^2 is exactly what the shader's resolution law returns; fov cancels the same way
# against fov_compensation. So there is no viewport answer here to leak into an off-screen
# capture (see the section note). Both cancellations are exact only at the calibrated
# intensity_gamma 1.0 / fov_compensation 1.0, which is why this evaluates at the reference
# height and fov; off-nominal it drifts a few percent, well inside the ~9% that star surface
# brightness moves the match across Proxima-to-Sirius-B anyway.
func _solve_sun_handoff_high() -> float:
	const FIVE_OVER_LN10 := 2.1714724095162594 # 5 / ln(10), for m = M + 5*log10(d / 10pc)
	const ITERATIONS := 8 # p <- sigma*sqrt(2*ln I(p)) contracts by ~2*sigma^2/p^2 per step
	var reference_height := _get_reference_viewport_height()
	var reference_proj_11 := 1.0 / tan(deg_to_rad(_star_settings.fov_reference_deg) * 0.5)
	var distance_numerator := _mean_radius * reference_proj_11 * reference_height * 0.5
	var pixels := 1.0
	for _iteration in ITERATIONS:
		var camera_distance := distance_numerator / pixels
		var apparent_magnitude := _sun_abs_mag + FIVE_OVER_LN10 * log(
				camera_distance / (10.0 * IVUnits.PARSEC))
		var flux := pow(10.0, -0.4 * (apparent_magnitude - _star_settings.intensity_faint_mag))
		var intensity := _star_settings.intensity_scale * pow(flux, _star_settings.intensity_gamma)
		if intensity <= 1.0:
			return _SUN_HANDOFF_FALLBACK # no saturated core to match; the disc is always bigger
		pixels = _star_settings.psf_sigma * sqrt(2.0 * log(intensity))
	return pixels


# The height the shaders' resolution law is normalized to, read from the setting the editor
# plugin writes from ivoyager_core.cfg -- the same one the shaders take as a global, so the
# two cannot disagree. RenderingServer.global_shader_parameter_get() would be the obvious
# reader and is a trap: it is editor-only, and in a running project it warns and hands back
# null rather than the value.
static func _get_reference_viewport_height() -> float:
	const FALLBACK := 1080.0
	var setting: Variant = ProjectSettings.get_setting(
			"shader_globals/iv_reference_viewport_height")
	if setting is Dictionary:
		var setting_dict: Dictionary = setting
		var value: Variant = setting_dict.get("value")
		if value is float:
			return value
	push_warning("IVSpheroidModel: no iv_reference_viewport_height shader global; using %s"
			% FALLBACK)
	return FALLBACK


# Shell 0 takes its whole spec from the body's spheroids.tsv [member _spheroid_type] row
# (shader, process, is_sun, cast_shadow, material columns) unless a shells.tsv shell-0 row
# overrides it wholly (never a merge). The body's discovered surface channels are kept either way.
func _resolve_shell0_spec(asset_preloader: IVAssetPreloader, surface_spec: Dictionary) -> Dictionary:
	if surface_spec.get(&"from_shells", false):
		return surface_spec
	var shadow_setting: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if IVTableData.db_has_value(&"spheroids", &"cast_shadow", _spheroid_type):
		shadow_setting = IVTableData.get_db_int(&"spheroids", &"cast_shadow", _spheroid_type)
	return {
		&"channels": surface_spec[&"channels"],
		&"shader": IVTableData.get_db_string_name(&"spheroids", &"shader", _spheroid_type),
		&"process": IVTableData.get_db_string_name(&"spheroids", &"process", _spheroid_type),
		&"process_args": [],
		&"is_sun": IVTableData.get_db_bool(&"spheroids", &"is_sun", _spheroid_type),
		&"cast_shadow": shadow_setting,
		&"overrides": asset_preloader.read_material_fields(&"spheroids", _spheroid_type,
				IVAssetPreloader.spheroids_nonmaterial_fields),
	}


func _build_material(spec: Dictionary, asset_preloader: IVAssetPreloader,
		render_priority: int) -> void:
	var channels: Dictionary = spec[&"channels"]
	var overrides: Dictionary = spec[&"overrides"]
	var shader_name: StringName = spec[&"shader"]
	if shader_name:
		_build_shader_material(shader_name, channels, overrides, asset_preloader, render_priority)
		return
	var material := StandardMaterial3D.new()
	material.render_priority = render_priority
	# spec already holds the resolved shell-0 (or overlay) material columns; no merge.
	_assert_overrides_are_properties(overrides)
	_apply_material_fields(material, overrides)
	_apply_channels_to_material(material, channels)
	set_surface_override_material(0, material)


func _build_shader_material(shader_name: StringName, channels: Dictionary,
		overrides: Dictionary, asset_preloader: IVAssetPreloader, render_priority: int) -> void:
	# A shell may opt into a ShaderMaterial (its shells.tsv "shader" column naming a
	# Shader in IVGlobal.resources). Discovered channel textures feed it as named
	# uniforms, and each shells.tsv override column feeds the uniform of the same name
	# (so e.g. a "clouds_detail_strength" column tunes the shader per body); a column
	# that isn't a uniform is ignored. The shader owns its own blending.
	# When the discovered channels are Cubemaps, swap the table-named shader for its
	# cubemap variant (the asset format decides; the tables stay format-agnostic).
	if _channels_are_cube(channels):
		if asset_preloader.cube_shader_variants.has(shader_name):
			shader_name = asset_preloader.cube_shader_variants[shader_name]
		else:
			push_warning("Body %s shell %d: Cubemap channels but shader '%s' has no cube variant"
					% [_body_name, _shell, shader_name])
	var resource: Resource = IVGlobal.resources.get(shader_name)
	var shader := resource as Shader
	if not shader:
		push_warning("Body %s shell %d: shader '%s' not in IVGlobal.resources"
				% [_body_name, _shell, shader_name])
		return
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = render_priority
	_apply_channels_to_shader_material(material, channels, asset_preloader)
	_assert_overrides_are_uniforms(overrides, shader)
	_apply_overrides_to_shader_material(material, overrides)
	set_surface_override_material(0, material)


func _channels_are_cube(channels: Dictionary) -> bool:
	# A shell's channels are all one texture format — a shader is samplerCube or
	# sampler2D, not both. Return whether they are cubemaps; a mix is a bake/asset error.
	# Test TextureLayered, NOT Cubemap: an imported cubemap is a CompressedCubemap, which
	# derives from CompressedTextureLayered and is not a Cubemap (they are siblings), so
	# `is Cubemap` silently misses every imported cubemap and routes it to the 2D shader.
	var any_cube := false
	var any_2d := false
	for param: int in channels:
		if channels[param] is TextureLayered:
			any_cube = true
		else:
			any_2d = true
	assert(not (any_cube and any_2d),
			"Body %s shell %d: channels mix cubemap and Texture2D (a shell must be all one format)"
			% [_body_name, _shell])
	return any_cube


func _apply_channels_to_material(material: BaseMaterial3D, channels: Dictionary) -> void:
	for param: int in channels:
		var texture: Texture2D = channels[param]
		if not texture:
			continue
		material.set_texture(param, texture)
		if CHANNEL_FEATURES.has(param):
			var feature: int = CHANNEL_FEATURES[param]
			material.set_feature(feature, true)


func _apply_channels_to_shader_material(material: ShaderMaterial, channels: Dictionary,
		asset_preloader: IVAssetPreloader) -> void:
	# Feed each discovered channel texture as a shader uniform named by its
	# asset_preloader.texture_channels tag (e.g. &"albedo", &"normal").
	var texture_channels: Dictionary[int, StringName] = asset_preloader.texture_channels
	for param: int in channels:
		var texture: Texture = channels[param] # Texture2D (equirect) or TextureLayered (cube)
		if texture and texture_channels.has(param):
			var tag: StringName = texture_channels[param]
			material.set_shader_parameter(tag, texture)
			# Presence flag so a cube shader can fall back for absent optional channels
			# (no-op on shaders without the uniform, e.g. the equirect path).
			material.set_shader_parameter(StringName("has_%s" % tag), true)


func _apply_overrides_to_shader_material(material: ShaderMaterial, overrides: Dictionary) -> void:
	# Each shells.tsv override column sets the shader uniform of the same name. An
	# override that isn't a uniform is a silent no-op (debug builds flag it first; see
	# _assert_overrides_are_uniforms).
	for property: StringName in overrides:
		material.set_shader_parameter(property, overrides[property])


func _apply_material_fields(material: BaseMaterial3D, fields: Dictionary) -> void:
	# Set each property, then auto-enable its feature so a table never needs a
	# *_enabled toggle (setting e.g. rim enables rim_enabled). See PROPERTY_FEATURES.
	for property: StringName in fields:
		material.set(property, fields[property])
		if PROPERTY_FEATURES.has(property):
			var feature: int = PROPERTY_FEATURES[property]
			material.set_feature(feature, true)


func _assert_overrides_are_properties(overrides: Dictionary) -> void:
	# Debug guard for a non-shader shell: its override columns are set() blindly on a
	# StandardMaterial3D, which no-ops an unknown property — so catch a typo'd or
	# unsupported spheroids.tsv/shells.tsv column here. This per-shell check (with the
	# resolved shader available) is why there is no table-wide material validation.
	if not OS.is_debug_build():
		return
	if _material_property_names.is_empty():
		for property: Dictionary in StandardMaterial3D.new().get_property_list():
			var usage: int = property[&"usage"]
			if usage & PROPERTY_USAGE_DEFAULT:
				var property_name: String = property[&"name"]
				_material_property_names[StringName(property_name)] = true
	for field: StringName in overrides:
		assert(_material_property_names.has(field),
				"Body %s shell %d: shells.tsv column '%s' is not a StandardMaterial3D property"
				% [_body_name, _shell, field])


func _assert_overrides_are_uniforms(overrides: Dictionary, shader: Shader) -> void:
	# Debug guard for a shader shell: its override columns set_shader_parameter()
	# blindly, a silent no-op for an unknown uniform — so catch a typo'd shells.tsv
	# column against this specific shader's uniforms.
	if not OS.is_debug_build():
		return
	if not _shader_uniform_names.has(shader):
		var names: Dictionary[StringName, bool] = {}
		for uniform: Dictionary in shader.get_shader_uniform_list():
			var uniform_name: String = uniform[&"name"]
			names[StringName(uniform_name)] = true
		_shader_uniform_names[shader] = names
	var uniform_names: Dictionary = _shader_uniform_names[shader]
	for field: StringName in overrides:
		assert(uniform_names.has(field),
				"Body %s shell %d: shells.tsv column '%s' is not a uniform of shader '%s'"
				% [_body_name, _shell, field, shader.resource_path.get_file()])


func _set_visibility_and_layers() -> void:
	# Each shell self-configures (vs. a parent recursing) so [IVBodyVisual] need
	# not know the shell structure. Mirrors the packed-model path's settings.
	# Sun-mode owns the disc's visibility via the pixel-radius fade, so it opts out of the fixed
	# distance cull (which is zoom-blind and would clip a still-resolved disc when zooming in).
	if not _is_sun:
		visibility_range_end = _mean_radius * IVCoreSettings.radius_multiplier_visibility_range_end
	var node_layers := IVCoreSettings.get_visualinstance3d_layer_for_size(_mean_radius)
	if _is_local_shadow_caster():
		node_layers |= IVGlobal.LOCAL_SHADOW_CASTER
	layers = node_layers
	if IVCoreSettings.apply_farwarp:
		# Frustum culling tests the true-scale AABB against the far plane, but the farwarp vertex
		# remap keeps the surface on-screen even when that test fails; make it always pass.
		var extent := IVCoreSettings.max_camera_distance
		custom_aabb = AABB(-Vector3.ONE * extent, 2.0 * Vector3.ONE * extent)


# A shell that readies after a dynamic grant would miss the caster bit until
# the next state change (the ancestor's recursion is change-gated), so adopt
# the ancestor IVBodyVisual's current state; static rule when there is none
# (e.g., a replacement body visual class).
func _is_local_shadow_caster() -> bool:
	var node := get_parent()
	while node:
		var ancestor_body_visual := node as IVBodyVisual
		if ancestor_body_visual:
			return ancestor_body_visual.is_local_shadow_caster()
		node = node.get_parent()
	return IVCoreSettings.get_static_local_shadow_caster(_mean_radius)


func _build_child_shells(shell_specs: Array) -> void:
	# Each extra shell is a translucent child reusing the shared sphere mesh at a
	# larger (or smaller) radius, inheriting the body's oblateness, orientation and spin.
	for shell_index in range(1, shell_specs.size()):
		var spec: Dictionary = shell_specs[shell_index]
		var channels: Dictionary = spec[&"channels"]
		var overrides: Dictionary = spec[&"overrides"]
		var shader: StringName = spec[&"shader"]
		# A shell needs an appearance source (texture, material override or shader);
		# otherwise it would render as an opaque white sphere.
		if channels.is_empty() and overrides.is_empty() and not shader:
			push_warning("Body %s shell %d has no texture, material override or shader; skipping"
					% [_body_name, shell_index])
			continue
		var shell_scale: float = spec[&"scale"]
		var child_basis := Basis().scaled(Vector3.ONE * shell_scale)
		add_child(IVSpheroidModel.new(_body_name, _spheroid_type, _mean_radius, child_basis, shell_index))


# Render priority = this shell's rank by scale (ascending; shell index breaks ties),
# so overlapping translucent shells blend back-to-front (outer over inner). The
# surface (shell 0) ranks as scale 1.0.
func _compute_render_priority(shell_specs: Array) -> int:
	var my_spec: Dictionary = shell_specs[_shell]
	var my_scale := _spec_scale(my_spec)
	var priority := 0
	for i in shell_specs.size():
		if i == _shell:
			continue
		var other_spec: Dictionary = shell_specs[i]
		var other_scale := _spec_scale(other_spec)
		if other_scale < my_scale or (other_scale == my_scale and i < _shell):
			priority += 1
	return priority


func _spec_scale(spec: Dictionary) -> float:
	var shell_scale: float = spec.get(&"scale", 1.0) # surface (shell 0) has no scale; rank as 1.0
	return shell_scale


func _resolve_process(method: StringName, process_args: Array) -> void:
	# The 'process' field names a process_methods entry called on this shell each frame as
	# method(spheroid_model, delta, ...process_args) (extra args from the 'process_args' field).
	# Defining _process() enables idle processing by default, so disable it on a shell with no
	# (or an unregistered) process method.
	set_process(false)
	if not method:
		return
	var callable: Callable = process_methods.get(method, Callable())
	if not callable.is_valid():
		push_warning("Body %s shell %d: process names unregistered method '%s'"
				% [_body_name, _shell, method])
		return
	_process_callable = callable.bindv(process_args)
	set_process(true)
