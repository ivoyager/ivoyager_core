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
## Loads resources at signal IVGlobal.project_builder_finished (just after
## splash screen showing in typical game usage) and emits
## IVGlobal.asset_preloader_finished when finished.
##
## TODO: On thread.

const files := preload("res://addons/ivoyager_core/static/files.gd")

const RINGS_LOD_LEVELS := 9 # must agree w/ assets, body.gd and rings.shader

var _body_resources: Dictionary[StringName, Array] = {}
var _rings_resources: Dictionary[String, Array] = {}



func _init() -> void:
	IVGlobal.project_builder_finished.connect(_load_resources)



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


func get_rings_texture_arrays(rings_name: StringName) -> Array[Texture2DArray]:
	return _rings_resources[rings_name][0]


func get_rings_shadow_caster_texture(rings_name: StringName) -> Texture2D:
	return _rings_resources[rings_name][1]



func _load_resources() -> void:
	_load_body_resources()
	_load_rings_resources()
	IVGlobal.asset_preloader_finished.emit()


func _load_body_resources() -> void:
	
	var bodies_2d_search := IVCoreSettings.bodies_2d_search
	var models_search := IVCoreSettings.models_search
	var maps_search := IVCoreSettings.maps_search
	
	for table in IVCoreSettings.body_tables:
		for row in IVTableData.get_n_rows(table):
			
			var body_name := IVTableData.get_db_entity_name(table, row)
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
			
			_body_resources[body_name] = resources


func _load_rings_resources() -> void:
	
	const BACKSCATTER_FILE_FORMAT := "%s.backscatter.%s"
	const FORWARDSCATTER_FILE_FORMAT := "%s.forwardscatter.%s"
	const UNLITSIDE_FILE_FORMAT := "%s.unlitside.%s"
	
	var rings_search := IVCoreSettings.rings_search
	
	for row in IVTableData.get_n_rows(&"rings"):
		var rings_name := IVTableData.get_db_entity_name(&"rings", row)
		var file_prefix := IVTableData.get_db_string(&"rings", &"file_prefix", row)
		var shadow_lod := IVTableData.get_db_int(&"rings", &"shadow_lod", row)
		shadow_lod = mini(shadow_lod, RINGS_LOD_LEVELS - 1)
		
		var texture_arrays: Array[Texture2DArray] = []
		var shadow_image_rgba: Image
		for lod in RINGS_LOD_LEVELS:
			var file_elements := [file_prefix, lod]
			var backscatter_file := BACKSCATTER_FILE_FORMAT % file_elements
			var backscatter: Texture2D = files.find_and_load_resource(rings_search, backscatter_file)
			assert(backscatter, "Failed to load '%s'" % backscatter_file)
			var forwardscatter_file := FORWARDSCATTER_FILE_FORMAT % file_elements
			var forwardscatter: Texture2D = files.find_and_load_resource(rings_search, forwardscatter_file)
			assert(forwardscatter, "Failed to load '%s'" % forwardscatter_file)
			var unlitside_file := UNLITSIDE_FILE_FORMAT % file_elements
			var unlitside: Texture2D = files.find_and_load_resource(rings_search, unlitside_file)
			assert(unlitside, "Failed to load '%s'" % unlitside_file)
			
			# We load as textures, convert to images, then reconvert back to
			# texture arrays. This is not ideal, but I was unable to save
			# Texture2DArray as a file resource as of Godot 4.2 (it's a
			# Resource, so it should be saveable).
			var backscatter_image := backscatter.get_image()
			var forwardscatter_image := forwardscatter.get_image()
			var unlitside_image := unlitside.get_image()
			var lod_images: Array[Image] = [backscatter_image, forwardscatter_image, unlitside_image]
			var texture_array := Texture2DArray.new() # backscatter/forwardscatter/unlitside for LOD
			texture_array.create_from_images(lod_images)
			texture_arrays.append(texture_array)
			if lod == shadow_lod:
				shadow_image_rgba = backscatter_image # all have the same alpha channel
		
		# Rebuild the shadow caster texture as smaller FORMAT_R8, alpha only.
		# We could have this premade in ivoyager_assets, but it gives us
		# flexibility with LOD to do here.
		var shadow_width := shadow_image_rgba.get_width()
		var shadow_image_r8 := Image.create_empty(shadow_width, 1, false, Image.FORMAT_R8)
		for x in shadow_width:
			var color := shadow_image_rgba.get_pixel(x, 0)
			color.r = color.a
			shadow_image_r8.set_pixel(x, 0, color)
		var shadow_caster_texture := ImageTexture.create_from_image(shadow_image_r8)
		
		_rings_resources[rings_name] = [texture_arrays, shadow_caster_texture]
