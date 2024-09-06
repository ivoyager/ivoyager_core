# world_environment.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charlie Whitfield
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
class_name IVWorldEnvironment
extends WorldEnvironment

## Default WorldEnvironment that incudes an Environment and CameraAttributes.
##
## This node and its resources are added as a scene by [IVCoreInitializer] to
## facilitate experimentation during Editor run. The starmap (Environment.sky)
## is set by code so ivoyager_core is valid without assets.
##
## It's possible to create override tables that modify Environment and
## CameraAttributes properties by setting override table and row names here.

## For scene instantiation by [IVCoreInitializer].
const SCENE := "res://addons/ivoyager_core/tree_nodes/world_environment.tscn"

var add_starmap := true
var fallback_starmap := &"starmap_8k" ## IVCoreSettings.asset_paths index; must exist
var environment_override_table := &""
var environment_override_table_row_name := &"ENVIRONMENT_IVOYAGER"
var camera_attributes_override_table := &""
var camera_attributes_override_table_row_name := &"CAMERA_ATTRIBUTES_IVOYAGER"



func _ready() -> void:
	if add_starmap:
		_add_starmap_as_environment_sky()
	if environment_override_table:
		var row := IVTableData.get_row(environment_override_table_row_name)
		assert(row >= 0)
		IVTableData.db_build_object_all_fields(environment, environment_override_table, row)
	if camera_attributes_override_table:
		var row := IVTableData.get_row(camera_attributes_override_table_row_name)
		assert(row >= 0)
		IVTableData.db_build_object_all_fields(camera_attributes, camera_attributes_override_table,
				row)


func _add_starmap_as_environment_sky() -> void:
	var settings: Dictionary = IVGlobal.settings
	var asset_paths: Dictionary = IVCoreSettings.asset_paths
	var starmap_file: String
	match settings.starmap:
		IVEnums.StarmapSize.STARMAP_8K:
			starmap_file = asset_paths.starmap_8k
		IVEnums.StarmapSize.STARMAP_16K:
			starmap_file = asset_paths.starmap_16k
	if !ResourceLoader.exists(starmap_file):
		starmap_file = asset_paths[fallback_starmap]
	var starmap: Texture2D = load(starmap_file)
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = starmap
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
