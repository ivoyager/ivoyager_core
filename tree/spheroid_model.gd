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
## 1..N (cloud deck, atmospheric haze), each a child [IVSpheroidModel]. Created by
## [IVPhysicalBody].[br][br]
##
## Configured by body-table columns named [code]shell<N>_<suffix>[/code]. The
## [b]number[/b] selects the shell: [code]shell0[/code] is the base surface, while
## [code]shell1[/code], [code]shell2[/code]… are overlays — each built only if its
## [code]shell<N>_scale[/code] is set. The [b]suffix[/b] selects what it sets:[br]
## - [code]_scale[/code]: radius multiplier; required for an overlay (surface = 1.0;
## a value < 1.0 places the shell under the surface).[br]
## - [code]_file_tag[/code] ([StringName], optional): texture filename token
## ([code]<file_prefix>.<file_tag>.<channel>[/code]); omit for a textureless shell.
## Suffix invalid on shell 0, whose textures use [code]file_prefix[/code] alone.[br]
## - [code]_shader[/code] ([StringName]): give the shell a [ShaderMaterial] using
## the named [Shader] in [member IVGlobal.resources], instead of a [StandardMaterial3D].[br]
## - [code]_process[/code] ([code]ARRAY[VARIANT][/code] of [code][method, ...args][/code]):
## call that [IVSpheroidModel] method on the shell each frame as
## [code]method(delta, ...args)[/code] (e.g. [method _rotate]).[br]
## - any element of [member material_fields] (e.g. [code]_albedo_color[/code],
## [code]_roughness[/code]): set that [StandardMaterial3D] property. Shell 0 takes
## these as per-[code]model_type[/code] defaults from models.tsv, overridden per body.
## A uniform shell needs only [code]_albedo_color[/code] (RGBA) — no texture.[br][br]
##
## Overlapping translucent shells auto-order back-to-front by scale (outer on top,
## via material [code]render_priority[/code]); give shells distinct scales (equal
## scales z-fight).[br][br]
##
## Not persisted.

## [StandardMaterial3D] properties that shells set from data tables: per-[code]model_type[/code]
## defaults (models.tsv) for shell 0, and per-shell [code]shell<N>_<field>[/code]
## overrides (body tables). List only value properties — a feature's [code]*_enabled[/code]
## toggle is auto-set via [constant PROPERTY_FEATURES] when its value is set. Append
## before bodies build to data-drive any other StandardMaterial3D property.
static var material_fields: Array[StringName] = [
	&"albedo_color",
	&"metallic",
	&"roughness",
	&"rim",
	&"rim_tint"
]

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
var _model_type: int
var _mean_radius: float
var _reference_basis: Basis # this shell's base basis (before any process scaling)
var _process_callable: Callable

var _times := IVGlobal.times



func _init(body_name: StringName, model_type: int, mean_radius: float, model_basis: Basis,
		shell := 0) -> void:
	_body_name = body_name
	_model_type = model_type
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
	var process_spec: Array = spec[&"process"]
	var render_priority := _compute_render_priority(shell_specs)
	_build_material(spec, asset_preloader, render_priority)
	_set_cast_shadow()
	_set_visibility_and_layers()
	_resolve_process(process_spec)
	if _shell == 0:
		_build_child_shells(shell_specs)


func _process(delta: float) -> void:
	_process_callable.call(delta)



func _build_material(spec: Dictionary, asset_preloader: IVAssetPreloader,
		render_priority: int) -> void:
	var channels: Dictionary = spec[&"channels"]
	var shader_name: StringName = spec[&"shader"]
	if shader_name:
		_build_shader_material(shader_name, channels, asset_preloader, render_priority)
		return
	var material := StandardMaterial3D.new()
	material.render_priority = render_priority
	if _shell == 0:
		var defaults: Dictionary = {}
		IVTableData.db_build_dictionary(defaults, &"models", _model_type, material_fields)
		_apply_material_fields(material, defaults)
	else:
		# An overlay is translucent; its color/alpha come from a texture
		# (shell<N>_file_tag), a shell<N>_albedo_color, or both (color tints texture).
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Body-table shell<N>_<field> values override the model_type material defaults.
	var overrides: Dictionary = spec[&"overrides"]
	_apply_material_fields(material, overrides)
	_apply_channels_to_material(material, channels)
	if _shell == 0 and channels.has(BaseMaterial3D.TEXTURE_EMISSION):
		material.emission_energy_multiplier = IVTableData.get_db_float(&"models",
				&"emission_energy_multiplier", _model_type)
	set_surface_override_material(0, material)


func _build_shader_material(shader_name: StringName, channels: Dictionary,
		asset_preloader: IVAssetPreloader, render_priority: int) -> void:
	# A shell may opt into a ShaderMaterial (shell<N>_shader naming a Shader in
	# IVGlobal.resources). Discovered channel textures feed it as named uniforms;
	# the StandardMaterial3D fields (material_fields, overrides) don't apply.
	var resource: Resource = IVGlobal.resources.get(shader_name)
	var shader := resource as Shader
	if not shader:
		push_warning("Body %s shell %d: shell%d_shader '%s' not in IVGlobal.resources"
				% [_body_name, _shell, _shell, shader_name])
		return
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = render_priority
	_apply_channels_to_shader_material(material, channels, asset_preloader)
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


func _apply_material_fields(material: BaseMaterial3D, fields: Dictionary) -> void:
	# Set each property, then auto-enable its feature so a table never needs a
	# *_enabled toggle (setting e.g. rim enables rim_enabled). See PROPERTY_FEATURES.
	for property: StringName in fields:
		material.set(property, fields[property])
		if PROPERTY_FEATURES.has(property):
			var feature: int = PROPERTY_FEATURES[property]
			material.set_feature(feature, true)


func _set_cast_shadow() -> void:
	# Stars and overlay shells don't cast shadows; opaque surfaces do.
	if _shell == 0 and not IVTableData.get_db_bool(&"models", &"is_star", _model_type):
		cast_shadow = SHADOW_CASTING_SETTING_ON
	else:
		cast_shadow = SHADOW_CASTING_SETTING_OFF


func _set_visibility_and_layers() -> void:
	# Each shell self-configures (vs. a parent recursing) so [IVPhysicalBody] need
	# not know the shell structure. Mirrors the packed-model path's settings.
	if not IVTableData.get_db_bool(&"models", &"inf_visibility", _model_type):
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
		add_child(IVSpheroidModel.new(_body_name, _model_type, _mean_radius, child_basis, shell_index))


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


# process methods (named by a shell<N>_process column)

func _rotate(delta: float, deg_per_sec: float) -> void:
	const CONVERSION := PI / (180.0 * IVUnits.SECOND)
	delta *= _times[1] / Engine.time_scale
	rotate_y(delta * deg_per_sec * CONVERSION) # y up in model self reference


func _dynamic_star(_delta: float) -> void:
	# Grow the star past GROW_DIST so it stays visible and prominent relative to the
	# star field at great distances. Grow settings are subjective.
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
