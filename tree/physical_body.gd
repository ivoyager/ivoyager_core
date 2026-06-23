# physical_body.gd
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
class_name IVPhysicalBody
extends Node3D

## Provides a model reference frame and instantiates a body's model. 
##
## This node is oriented and rotated by [IVBody], but is not scaled.[br][br]
##
## This node is not persisted. If "lazy init" is applicable, it is created by
## [IVBody] only if/when needed and remains through the current user session.
## (Lazy init is applicable if [IVLazyModelInitializer] is present and [IVBody]
## has [enum IVBody.BodyFlags].BODYFLAGS_LAZY_MODEL.)[br][br]
## 
## Children can be added that share the model's axial tilt and rotation.
## In base Solar System setup, [IVBodyFinisher] adds [IVRings] for Saturn.[br][br]
##
## Note: It's not planned to implement collisions in ivoyager_core. Perhaps a
## subclass of [IVPhysicalBody] would be the best approach for that. We could
## accept changes to this class that help facilitate collisions (as long as
## they don't cost much when not used).


## Body-frame reference basis used for orienting the model and rings.
var reference_basis: Basis
## Optional Script used in place of [IVSpheroidModel] when no PackedScene model
## is present. Must extend [IVSpheroidModel] and share its
## [code]_init(model_type, reference_basis, surface_channels)[/code] signature.
var replacement_spheroid_model_class: Script


var _body_name: StringName
var _m_radius: float
var _e_radius: float
var _model_type: int
var _model: Node3D



func _init(body_name: StringName, mean_radius: float, equatorial_radius: float) -> void:
	_body_name = body_name
	_m_radius = mean_radius
	_e_radius = equatorial_radius
	name = &"PhysicalBody"
	# Always use PackedScene model if there is one. Otherwise, generate
	# a spheroid model w/ maps or use a fallback.
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	_model_type = asset_preloader.get_body_model_type(_body_name)
	var packed_model := asset_preloader.get_body_packed_model(_body_name)
	if packed_model:
		_build_packed_model(asset_preloader, packed_model)
		return
	if IVTableData.get_db_bool(&"models", &"spheroid", _model_type):
		_build_spheroid_model(asset_preloader)
		return
	_build_fallback_nonspheroid_model(asset_preloader)


func _ready() -> void:
	add_child(_model)


## Returns the body-frame reference [Basis] for a packed-scene model: uniformly
## scaled by [param model_scale] and rotated so the model's z-up axis becomes
## y-up. Shared by [method _build_packed_model] and the editor icon capturer so a
## captured 2D icon matches the in-sim model orientation.
static func get_packed_model_reference_basis(model_scale: float) -> Basis:
	const RIGHT_ANGLE := PI / 2
	return Basis().scaled(model_scale * Vector3.ONE).rotated(Vector3(1.0, 0.0, 0.0), RIGHT_ANGLE)


func _build_packed_model(asset_preloader: IVAssetPreloader, packed_model: PackedScene) -> void:
	var model_scale := asset_preloader.get_body_model_scale(_body_name)
	reference_basis = get_packed_model_reference_basis(model_scale)
	_model = packed_model.instantiate()
	_model.basis = reference_basis
	# The disable_auto_visual_range flag opts a packed scene out entirely, preserving any
	# visibility values authored in the .glb/.tscn.
	var disable_auto_visual_range := asset_preloader.get_body_disable_auto_visual_range(_body_name)
	if not disable_auto_visual_range:
		_set_visibility_ranges()
	_set_layers()


func _build_spheroid_model(asset_preloader: IVAssetPreloader) -> void:
	const RIGHT_ANGLE := PI / 2
	var polar_radius: = 3.0 * _m_radius - 2.0 * _e_radius
	reference_basis = Basis().scaled(Vector3(_e_radius, polar_radius, _e_radius))
	var map_offset := asset_preloader.get_body_map_offset(_body_name)
	reference_basis = reference_basis.rotated(Vector3(0.0, 1.0, 0.0), -RIGHT_ANGLE - map_offset)
	reference_basis = reference_basis.rotated(Vector3(1.0, 0.0, 0.0), RIGHT_ANGLE) # z-up!
	var shell_channels := asset_preloader.get_body_shell_channels(_body_name)
	var surface_channels: Dictionary = shell_channels.get(&"surface", {})
	if replacement_spheroid_model_class:
		@warning_ignore("unsafe_method_access")
		_model = replacement_spheroid_model_class.new(_model_type, reference_basis, surface_channels)
	else:
		_model = IVSpheroidModel.new(_model_type, reference_basis, surface_channels)
	_build_shells(asset_preloader, shell_channels)
	_set_visibility_ranges()
	_set_layers()


func _build_shells(asset_preloader: IVAssetPreloader, shell_channels: Dictionary) -> void:
	# Each extra shell (cloud deck, atmosphere overlay) is a translucent child of the
	# base model, reusing the shared sphere mesh at a larger radius so it inherits the
	# body's oblateness, orientation and spin. Added before the visibility/layer
	# recursion in [method _build_spheroid_model] so those settings propagate to it.
	var shell_params := asset_preloader.get_body_shell_params(_body_name)
	for shell_name: StringName in shell_params:
		var channels: Dictionary = shell_channels.get(shell_name, {})
		if channels.is_empty():
			push_warning("Body %s shell '%s' has no textures; skipping" % [_body_name, shell_name])
			continue
		var params: Dictionary = shell_params[shell_name]
		var height: float = params.get(&"height", NAN)
		if is_nan(height):
			push_warning("Body %s shell '%s' has no height; skipping" % [_body_name, shell_name])
			continue
		var shell := MeshInstance3D.new()
		shell.name = StringName("Shell_" + shell_name)
		shell.mesh = IVGlobal.resources[&"sphere_mesh"]
		shell.transform.basis = Basis().scaled(Vector3.ONE * (1.0 + height))
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var rim: float = params.get(&"rim", 0.0)
		if rim > 0.0:
			# Limb-brighten the haze: rim adds a Fresnel-style glow at grazing angles
			# (the silhouette edge), tinted toward the haze color.
			material.rim_enabled = true
			material.rim = rim
			material.rim_tint = 0.6
		# Optional per-shell opacity scales the texture's alpha. Unset (NAN) leaves
		# the texture's own alpha untouched.
		var opacity: float = params.get(&"opacity", NAN)
		if not is_nan(opacity):
			material.albedo_color.a = opacity
		IVAssetPreloader.apply_channels_to_material(material, channels)
		shell.set_surface_override_material(0, material)
		_model.add_child(shell)


func _build_fallback_nonspheroid_model(asset_preloader: IVAssetPreloader) -> void:
	# TODO: We need a fallback asteroid/comet PackedScene model here, since the
	# vast majority of no-model bodies are probably asteroids or tiny moons.
	# For now, user sees generic grey sphere with grids.
	_build_spheroid_model(asset_preloader)


func _set_visibility_ranges() -> void:
	if IVTableData.get_db_bool(&"models", &"inf_visibility", _model_type):
		return # default 0.0 is no distance cull
	var visibility_range_end := _m_radius * IVCoreSettings.radius_multiplier_visibility_range_end
	_set_visibility_ranges_recursive(_model, visibility_range_end)


func _set_visibility_ranges_recursive(node3d: Node3D, visibility_range_end: float) -> void:
	var geometry := node3d as GeometryInstance3D
	if geometry:
		geometry.visibility_range_end = visibility_range_end
	for child in node3d.get_children():
		var child_node3d := child as Node3D
		if child_node3d:
			_set_visibility_ranges_recursive(child_node3d, visibility_range_end)


func _set_layers() -> void:
	var layers := IVCoreSettings.get_visualinstance3d_layer_for_size(_m_radius)
	layers |= IVGlobal.ShadowMask.SHADOW_MASK_FULL
	_set_layers_recursive(_model, layers)


func _set_layers_recursive(node3d: Node3D, layers: int) -> void:
	var visualinstance3d := node3d as VisualInstance3D
	if visualinstance3d:
		visualinstance3d.layers = layers
	for child in node3d.get_children():
		var child_node3d := child as Node3D
		if child_node3d:
			_set_layers_recursive(child_node3d, layers)
