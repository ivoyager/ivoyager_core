# model_space.gd
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
class_name IVModelSpace
extends Node3D

## Provides a model reference frame and instantiates a body's model. 
##
## This Node3D is tilted and rotated by [IVBody], but is not scaled.[br][br]
##
## This node is not persisted. It is created by [IVBody] only if/when needed,
## and then remains for the remainder of the user session (lazy init).[br][br]
## 
## Children can be added that share the model's axial tilt and rotation.
## In base Solar System setup, IVBodyFinisher adds IVRings for Saturn.[br][br]


const MODEL_MAX_DISTANCE_MULTIPLIER := 3e3

var reference_basis: Basis

## FIXME: Use VisualInstance3D properties!
var max_distance: float

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
	name = &"ModelSpace"
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


func _build_packed_model(asset_preloader: IVAssetPreloader, packed_model: PackedScene) -> void:
	const METER := IVUnits.METER
	const RIGHT_ANGLE := PI / 2
	var asset_row := asset_preloader.get_body_model_asset_row(_body_name)
	var model_scale := METER
	if asset_row != -1:
		model_scale *= IVTableData.get_db_float(&"asset_adjustments", &"model_scale", asset_row)
	
	reference_basis = Basis().scaled(model_scale * Vector3.ONE)
	reference_basis = reference_basis.rotated(Vector3(1.0, 0.0, 0.0), RIGHT_ANGLE) # z-up in astronomy!
	
	_model = packed_model.instantiate()
	_model.basis = reference_basis
	_set_max_distance()
	_set_layers()


func _build_spheroid_model(asset_preloader: IVAssetPreloader) -> void:
	const RIGHT_ANGLE := PI / 2
	
	# If albedo_map and emission_map both exist and both are in asset_adjustments.tsv,
	# they are expected to have all the same table row values.
	var asset_row := -1
	var albedo_map := asset_preloader.get_body_albedo_map(_body_name)
	if albedo_map:
		asset_row = asset_preloader.get_body_albedo_asset_row(_body_name)
	var emission_map := asset_preloader.get_body_emission_map(_body_name)
	if emission_map:
		asset_row = asset_preloader.get_body_emission_asset_row(_body_name)
	
	var polar_radius: = 3.0 * _m_radius - 2.0 * _e_radius
	reference_basis = Basis().scaled(Vector3(_e_radius, polar_radius, _e_radius))
	var longitude_offset := RIGHT_ANGLE # centered prime meridian
	if asset_row != -1:
		# longitude_offset same in albedo_map and emission_map, if both exist
		longitude_offset += IVTableData.get_db_float(&"asset_adjustments", &"longitude_offset", asset_row)
	reference_basis = reference_basis.rotated(Vector3(0.0, 1.0, 0.0), -longitude_offset)
	reference_basis = reference_basis.rotated(Vector3(1.0, 0.0, 0.0), RIGHT_ANGLE) # z-up in astronomy!
	
	if replacement_spheroid_model_class:
		@warning_ignore("unsafe_method_access")
		_model = replacement_spheroid_model_class.new(_model_type, reference_basis, albedo_map, emission_map)
	else:
		_model = IVSpheroidModel.new(_model_type, reference_basis, albedo_map, emission_map)
	_set_max_distance()
	_set_layers()


func _build_fallback_nonspheroid_model(asset_preloader: IVAssetPreloader) -> void:
	# TODO: We need a fallback asteroid/comet PackedScene model here
	_build_spheroid_model(asset_preloader) 


func _set_max_distance() -> void:
	if IVTableData.get_db_bool(&"models", &"inf_visibility", _model_type):
		max_distance = INF
	else:
		max_distance = _m_radius * MODEL_MAX_DISTANCE_MULTIPLIER


func _set_layers() -> void:
	var layers := IVCoreSettings.get_visualinstance3d_layers_for_size(_m_radius)
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
