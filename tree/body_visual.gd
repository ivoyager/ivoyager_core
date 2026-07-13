# body_visual.gd
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
class_name IVBodyVisual
extends Node3D

## Provides a model reference frame and instantiates a body's model.
##
## This node is oriented and rotated by [IVBody], but is not itself scaled. It
## scales the model that it instantiates.[br][br]
##
## This node is not persisted. If "lazy init" is applicable, it is created by
## [IVBody] only if/when needed and remains through the current user session.
## (Lazy init is applicable if [IVLazyModelInitializer] is present and [IVBody]
## has [enum IVBody.BodyFlags].BODYFLAGS_LAZY_MODEL.)[br][br]
##
## Children can be added that share the model's axial tilt and rotation.
## In base Solar System setup, [IVBodyFinisher] adds [IVRings] for Saturn.[br][br]
##
## Note: It's not planned to implement collisions in ivoyager_core. It would be
## challenging (to say the least) to feed model shape interactions back to our
## own orbit physics.


## Body-frame reference basis used for orienting the model and rings.
var reference_basis: Basis
## Optional Script used in place of [IVSpheroidModel] when no PackedScene model
## is present. Must extend [IVSpheroidModel] and share its
## [code]_init(body_name, spheroid_type, mean_radius, model_basis, shell)[/code] signature.
var replacement_spheroid_model_class: Script


var _body_name: StringName
var _m_radius: float
var _e_radius: float
var _spheroid_type: int
var _model: Node3D
var _local_shadow_caster := false



func _init(body_name: StringName, mean_radius: float, equatorial_radius: float,
		spheroid_type: int) -> void:
	_body_name = body_name
	_m_radius = mean_radius
	_e_radius = equatorial_radius
	_local_shadow_caster = IVCoreSettings.get_static_local_shadow_caster(mean_radius)
	name = &"BodyVisual"
	# A PackedScene model (self-defining) always wins. Otherwise build a spheroid from the
	# spheroids.tsv type intent; an unspecified type (-1) resolves to row 0 (the fallback).
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	var packed_model := asset_preloader.get_body_packed_model(_body_name)
	if packed_model:
		_build_packed_model(asset_preloader, packed_model)
		return
	_spheroid_type = spheroid_type if spheroid_type >= 0 else 0
	_build_spheroid_model(asset_preloader)


func _ready() -> void:
	add_child(_model)


func is_local_shadow_caster() -> bool:
	return _local_shadow_caster


## Grants/clears [constant IVGlobal.LOCAL_SHADOW_CASTER] on this visual's whole
## tree (see the constant's doc for the granting rules). Called per frame by
## [method IVBody.update_farwarp]; the recursion runs on state change only.
func set_local_shadow_caster(on: bool) -> void:
	if _local_shadow_caster == on:
		return
	_local_shadow_caster = on
	_set_local_shadow_caster_recursive(self, on)


func _set_local_shadow_caster_recursive(node3d: Node3D, on: bool) -> void:
	var visualinstance3d := node3d as VisualInstance3D
	if visualinstance3d:
		if on:
			visualinstance3d.layers |= IVGlobal.LOCAL_SHADOW_CASTER
		else:
			visualinstance3d.layers &= ~IVGlobal.LOCAL_SHADOW_CASTER
	for child in node3d.get_children():
		var child_node3d := child as Node3D
		if child_node3d:
			_set_local_shadow_caster_recursive(child_node3d, on)


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
	# Compute the oblate, map-offset, z-up reference basis; the model self-builds
	# its surface, child shells, visibility ranges and layers from there.
	const RIGHT_ANGLE := PI / 2
	var polar_radius := 3.0 * _m_radius - 2.0 * _e_radius
	reference_basis = Basis().scaled(Vector3(_e_radius, polar_radius, _e_radius))
	var map_offset := asset_preloader.get_body_map_offset(_body_name)
	reference_basis = reference_basis.rotated(Vector3(0.0, 1.0, 0.0), -RIGHT_ANGLE - map_offset)
	reference_basis = reference_basis.rotated(Vector3(1.0, 0.0, 0.0), RIGHT_ANGLE) # z-up!
	if replacement_spheroid_model_class:
		@warning_ignore("unsafe_method_access")
		_model = replacement_spheroid_model_class.new(_body_name, _spheroid_type, _m_radius, reference_basis)
	else:
		_model = IVSpheroidModel.new(_body_name, _spheroid_type, _m_radius, reference_basis)


# Packed-scene models are foreign node trees, so [IVBodyVisual] still recurses
# to set their visibility ranges and layers. Spheroid models self-configure (see
# [IVSpheroidModel]).
func _set_visibility_ranges() -> void:
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	if asset_preloader.get_body_inf_visibility(_body_name):
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
	if _local_shadow_caster:
		layers |= IVGlobal.LOCAL_SHADOW_CASTER
	_set_layers_recursive(_model, layers)


func _set_layers_recursive(node3d: Node3D, layers: int) -> void:
	var visualinstance3d := node3d as VisualInstance3D
	if visualinstance3d:
		visualinstance3d.layers = layers
	for child in node3d.get_children():
		var child_node3d := child as Node3D
		if child_node3d:
			_set_layers_recursive(child_node3d, layers)
