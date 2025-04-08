# world_environment.gd
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
class_name IVWorldEnvironment
extends WorldEnvironment

## Default WorldEnvironment that sets Environment and CameraAttributes
## properties from data tables.
##
## For projects that supply their own WorldEnvironment, disable this node by
## removing from dictionary program_nodes in [IVCoreInitializer].[br][br]
##
## This node sets its Environment and CameraAttributes from data tables
## environments.tsv and camera_attributes.tsv, respectively. The starmap
## is added by code according to user settings and fallback specification
### (see [IVAssetPreloader]).[br][br]

## For scene instantiation by [IVCoreInitializer].
const SCENE := "res://addons/ivoyager_core/tree_nodes/world_environment.tscn"

var add_starmap := true


func _ready() -> void:
	IVGlobal.asset_preloader_finished.connect(_on_asset_preloader_finished)


func _on_asset_preloader_finished() -> void:
	if IVCoreSettings.camera_attributes:
		var row := IVTableData.get_row(IVCoreSettings.camera_attributes)
		assert(row != -1, "Unknown IVCoreSettings.camera_attributes '%s'"
				% IVCoreSettings.camera_attributes)
		IVTableData.db_build_object(camera_attributes, &"camera_attributes", row)
	if IVCoreSettings.environment:
		var row := IVTableData.get_row(IVCoreSettings.environment)
		assert(row != -1, "Unknown IVCoreSettings.environment '%s'" % IVCoreSettings.environment)
		IVTableData.db_build_object(environment, &"environments", row)
	if add_starmap:
		_add_starmap_as_environment_sky()


func _add_starmap_as_environment_sky() -> void:
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	var starmap := asset_preloader.get_starmap()
	if !starmap:
		return
	
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = starmap
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
