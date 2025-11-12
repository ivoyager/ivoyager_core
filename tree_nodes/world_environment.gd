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

## Default WorldEnvironment.
##
## This node uses default Environment and CameraAttributes resources from
## res://addons/ivoyager_core/resources.[br][br]
##
## The default Environment doesn't have [member Environment.sky] set because
## the starmap textures are in addons/ivoyager_assets/. (The Core plugin needs
## to be stand-alone without assets in the Editor, even if it can't run.)[br][br]
##
## If [member add_starmap] is true (default), this node will add a Sky with
## a starmap from ivoyager_assets at startup.

@export var add_starmap := true


func _ready() -> void:
	IVStateManager.assets_preloaded.connect(_on_asset_preloader_finished)


func _on_asset_preloader_finished() -> void:
	if add_starmap:
		_add_starmap_sky()


func _add_starmap_sky() -> void:
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
