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
## [code]shell<N>[/code] name column (also the texture file token) is set. The
## [b]suffix[/b] selects what it sets:[br]
## - [code]_scale[/code]: overlay radius multiplier (the surface is 1.0).[br]
## - [code]_shader[/code] ([StringName]): give the shell a [ShaderMaterial] using
## the named [Shader] in [member IVGlobal.resources], instead of a [StandardMaterial3D].[br]
## - [code]_process[/code] ([code]ARRAY[VARIANT][/code] of [code][method, ...args][/code]):
## call that [IVSpheroidModel] method on the shell each frame as
## [code]method(delta, ...args)[/code] (e.g. [method _dynamic_star]).[br]
## - any element of [member material_fields] (e.g. [code]_roughness[/code],
## [code]_rim[/code]): set that [StandardMaterial3D] property. Shell 0 also takes
## these as per-[code]model_type[/code] defaults from models.tsv, which a body-table
## [code]shell<N>_<field>[/code] overrides. Overlays also accept [code]_opacity[/code]
## (alpha).[br][br]
##
## Not persisted.

## [StandardMaterial3D] properties that shells set from data tables: per-[code]model_type[/code]
## defaults (models.tsv) for shell 0, and per-shell [code]shell<N>_<field>[/code]
## overrides (body tables). Append before bodies build to data-drive any other
## StandardMaterial3D property.
static var material_fields: Array[StringName] = [
	&"metallic",
	&"roughness",
	&"rim_enabled",
	&"rim",
	&"rim_tint"
]


var _shell: int # 0 is the surface and orchestrator; 1..N are child shells
var _body_name: StringName
var _model_type: int
var _mean_radius: float
var _reference_basis: Basis # this shell's base basis (before any process scaling)
var _process_callable: Callable



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
	_build_material(spec, asset_preloader)
	_set_cast_shadow()
	_set_visibility_and_layers()
	_resolve_process(process_spec)
	if _shell == 0:
		_build_child_shells(shell_specs)


func _process(delta: float) -> void:
	_process_callable.call(delta)



func _build_material(spec: Dictionary, asset_preloader: IVAssetPreloader) -> void:
	var channels: Dictionary = spec[&"channels"]
	var shader_name: StringName = spec[&"shader"]
	if shader_name:
		_build_shader_material(shader_name, channels, asset_preloader)
		return
	var material := StandardMaterial3D.new()
	if _shell == 0:
		IVTableData.db_build_object(material, &"models", _model_type, material_fields)
	else:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Optional per-shell opacity scales the texture's alpha. Unset (NAN) leaves
		# the texture's own alpha untouched. (Every other StandardMaterial3D field —
		# rim_enabled/rim/rim_tint included — is set explicitly via a shell<N>_<field>
		# column in material_fields.)
		var opacity: float = spec.get(&"opacity", NAN)
		if not is_nan(opacity):
			material.albedo_color.a = opacity
	# Body-table shell<N>_<field> values override the model_type material defaults.
	var overrides: Dictionary = spec[&"overrides"]
	for field: StringName in overrides:
		material.set(field, overrides[field])
	IVAssetPreloader.apply_channels_to_material(material, channels)
	if _shell == 0 and channels.has(BaseMaterial3D.TEXTURE_EMISSION):
		material.emission_energy_multiplier = IVTableData.get_db_float(&"models",
				&"emission_energy_multiplier", _model_type)
	set_surface_override_material(0, material)


func _build_shader_material(shader_name: StringName, channels: Dictionary,
		asset_preloader: IVAssetPreloader) -> void:
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
	asset_preloader.apply_channels_to_shader_material(material, channels)
	set_surface_override_material(0, material)


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
	# larger radius, inheriting the body's oblateness, orientation and spin.
	for shell_index in range(1, shell_specs.size()):
		var spec: Dictionary = shell_specs[shell_index]
		var channels: Dictionary = spec[&"channels"]
		if channels.is_empty():
			push_warning("Body %s shell '%s' has no textures; skipping" % [_body_name, spec[&"name"]])
			continue
		var shell_scale: float = spec.get(&"scale", NAN)
		if is_nan(shell_scale):
			push_warning("Body %s shell '%s' has no scale; skipping" % [_body_name, spec[&"name"]])
			continue
		var child_basis := Basis().scaled(Vector3.ONE * shell_scale)
		add_child(IVSpheroidModel.new(_body_name, _model_type, _mean_radius, child_basis, shell_index))


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
