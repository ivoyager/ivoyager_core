# asset_preloader.gd
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
class_name IVAssetPreloader
extends RefCounted

## Loads and/or generates resources dynamically from data table specification
## for several procedural classes, including IVBody and IVRings.
##
## Loads resources at signal `IVGlobal.project_builder_finished` (just after
## splash screen showing in typical game usage) and emits
## `IVGlobal.asset_preloader_finished` when finished.

const files := preload("res://addons/ivoyager_core/static/files.gd")

var _body_resources: Dictionary[StringName, Array] = {}




func _init() -> void:
	IVGlobal.project_builder_finished.connect(_load_body_resources)


func get_body_texture_2d(body_name: StringName) -> Texture2D:
	return _body_resources[body_name][0]


func get_body_texture_slice_2d(body_name: StringName) -> Texture2D:
	return _body_resources[body_name][1]


func get_body_model_type(body_name: StringName) -> int:
	return _body_resources[body_name][2]


func get_body_packed_model(body_name: StringName) -> PackedScene:
	return _body_resources[body_name][3]


func get_body_model_asset_row(body_name: StringName) -> int:
	return _body_resources[body_name][4]


func get_body_albedo_map(body_name: StringName) -> Texture2D:
	return _body_resources[body_name][5]


func get_body_albedo_asset_row(body_name: StringName) -> int:
	return _body_resources[body_name][6]


func get_body_emission_map(body_name: StringName) -> Texture2D:
	return _body_resources[body_name][7]


func get_body_emission_asset_row(body_name: StringName) -> int:
	return _body_resources[body_name][8]





func _load_body_resources() -> void:
	
	var bodies_2d_search := IVCoreSettings.bodies_2d_search
	var models_search := IVCoreSettings.models_search
	var maps_search := IVCoreSettings.maps_search
	
	for table in IVCoreSettings.body_tables:
		for row in IVTableData.get_n_rows(table):
			
			var entity_name := IVTableData.get_db_entity_name(table, row)
			var file_prefix := IVTableData.get_db_string(table, &"file_prefix", row)
			assert(file_prefix)
			
			var texture_2d: Texture2D = files.find_and_load_resource(bodies_2d_search, file_prefix)
			if !texture_2d:
				texture_2d = IVGlobal.assets[&"fallback_body_2d"]
			
			var texture_slice_2d: Texture2D = null
			if IVTableData.get_db_bool(table, &"star", row):
				texture_slice_2d = files.find_and_load_resource(bodies_2d_search,
						file_prefix + "_slice")
			
			var model_type := IVTableData.get_db_int(table, &"model_type", row)
			
			var packed_model: PackedScene = null
			var model_asset_row := -1
			var model_path := files.find_resource_file(models_search, file_prefix)
			if model_path:
				packed_model = load(model_path)
				model_asset_row = IVTableData.db_find(&"asset_adjustments", &"file_name",
						model_path.get_file())
			
			var albedo_map: Texture2D = null
			var albedo_asset_row := -1
			var albedo_path := files.find_resource_file(maps_search, file_prefix + ".albedo")
			if albedo_path:
				albedo_map = load(albedo_path)
				albedo_asset_row = IVTableData.db_find(&"asset_adjustments", &"file_name",
						albedo_path.get_file())
			
			var emission_map: Texture2D = null
			var emission_asset_row := -1
			var emission_path := files.find_resource_file(maps_search, file_prefix + ".emission")
			if emission_path:
				emission_map = load(emission_path)
				emission_asset_row = IVTableData.db_find(&"asset_adjustments", &"file_name",
						emission_path.get_file())
			
			var resources := [
				texture_2d,
				texture_slice_2d,
				model_type,
				packed_model,
				model_asset_row,
				albedo_map,
				albedo_asset_row,
				emission_map,
				emission_asset_row]
			
			_body_resources[entity_name] = resources
