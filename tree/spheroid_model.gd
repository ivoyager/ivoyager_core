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
## by [IVPhysicalBody].[br][br]
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
## - [code]process[/code] ([code]ARRAY[VARIANT][/code] of [code][method, ...args][/code]):
## call that [IVSpheroidModel] method on the shell each frame as
## [code]method(delta, ...args)[/code] (e.g. [method _rotate]).[br]
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


var _shell: int # 0 is the surface and orchestrator; 1..N are child shells
var _body_name: StringName
var _spheroid_type: int
var _mean_radius: float
var _reference_basis: Basis # this shell's base basis (before any process scaling)
var _process_callable: Callable

var _times := IVGlobal.times

# Debug-only caches for the per-shell override asserts in _build_material; built
# lazily and kept for the session. Unused unless OS.is_debug_build().
static var _material_property_names: Dictionary[StringName, bool] = {}
static var _shader_uniform_names: Dictionary = {} # Shader -> Dictionary[StringName, bool]



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
	var process_spec: Array = spec[&"process"]
	var render_priority := _compute_render_priority(shell_specs)
	_build_material(spec, asset_preloader, render_priority)
	cast_shadow = spec[&"cast_shadow"]
	_set_visibility_and_layers()
	_resolve_process(process_spec)
	if _shell == 0:
		_build_child_shells(shell_specs)


func _process(delta: float) -> void:
	_process_callable.call(delta)



## Shell 0 takes its whole spec from the body's spheroids.tsv [member _spheroid_type] row
## (shader, process, cast_shadow, material columns) unless a shells.tsv shell-0 row overrides
## it wholly (never a merge). The body's discovered surface channels are kept either way.
func _resolve_shell0_spec(asset_preloader: IVAssetPreloader, surface_spec: Dictionary) -> Dictionary:
	if surface_spec.get(&"from_shells", false):
		return surface_spec
	var shadow_setting: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if IVTableData.db_has_value(&"spheroids", &"cast_shadow", _spheroid_type):
		shadow_setting = IVTableData.get_db_int(&"spheroids", &"cast_shadow", _spheroid_type)
	return {
		&"channels": surface_spec[&"channels"],
		&"shader": IVTableData.get_db_string_name(&"spheroids", &"shader", _spheroid_type),
		&"process": IVTableData.get_db_array(&"spheroids", &"process", _spheroid_type),
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
		var texture: Texture2D = channels[param]
		if texture and texture_channels.has(param):
			material.set_shader_parameter(texture_channels[param], texture)


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
	# Each shell self-configures (vs. a parent recursing) so [IVPhysicalBody] need
	# not know the shell structure. Mirrors the packed-model path's settings.
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	if not asset_preloader.get_body_inf_visibility(_body_name):
		visibility_range_end = _mean_radius * IVCoreSettings.radius_multiplier_visibility_range_end
	var node_layers := IVCoreSettings.get_visualinstance3d_layer_for_size(_mean_radius)
	node_layers |= IVGlobal.ShadowMask.SHADOW_MASK_FULL
	layers = node_layers


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


## Render priority = this shell's rank by scale (ascending; shell index breaks ties),
## so overlapping translucent shells blend back-to-front (outer over inner). The
## surface (shell 0) ranks as scale 1.0.
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


func _resolve_process(process_spec: Array) -> void:
	# shell<N>_process is [method_name, arg1, arg2, ...]. The method is called on
	# this shell each frame as method(delta, arg1, arg2, ...). Defining _process()
	# enables idle processing by default, so we must disable it on shells with no
	# (or an invalid) process spec.
	set_process(false)
	if process_spec.is_empty():
		return
	var method_name: Variant = process_spec[0]
	if not (method_name is String or method_name is StringName):
		push_warning("Body %s shell %d: shell%d_process first element must name a method"
				% [_body_name, _shell, _shell])
		return
	var method := StringName(str(method_name))
	if not has_method(method):
		push_warning("Body %s shell %d: shell%d_process names unknown method '%s'"
				% [_body_name, _shell, _shell, method])
		return
	_process_callable = Callable(self, method).bindv(process_spec.slice(1))
	set_process(true)


# process methods named by a 'process' field in shells.tsv or spheroids.tsv

## Named by a 'process' field (shells.tsv or spheroids.tsv). Rotates the shell
## at specified degrees per second.
func _rotate(delta: float, deg_per_sec: float) -> void:
	const CONVERSION := PI / (180.0 * IVUnits.SECOND)
	if IVStateManager.paused_tree:
		return
	delta *= _times[1] / Engine.time_scale
	rotate_y(delta * deg_per_sec * CONVERSION) # y up in model self reference


## Named by a 'process' field (the G_STAR row in spheroids.tsv). Grows a star when
## beyond GROW_DIST so it stays visible relative to the star field at many au.
## Grow settings are subjective: currently calibrated so the Sun is prominant
## at Jupiter and visible at Pluto. 
func _grow_star(_delta: float) -> void:
	const GROW_DIST := 2.0 * IVUnits.AU
	const GROW_FACTOR := 0.3
	var viewport := get_viewport()
	if not viewport:
		return
	var camera := viewport.get_camera_3d()
	if not camera:
		return
	var camera_dist := global_position.distance_to(camera.global_position)
	if camera_dist < GROW_DIST:
		transform.basis = _reference_basis
		return
	var excess := camera_dist / GROW_DIST - 1.0
	var factor := GROW_FACTOR * excess + 1.0
	transform.basis = _reference_basis.scaled(Vector3(factor, factor, factor))
