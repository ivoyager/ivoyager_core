# asset_initializer.gd
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
class_name IVAssetInitializer
extends RefCounted

## Loads assets specified in [IVCoreSettings].

var _asset_replacement_dir: String = IVCoreSettings.asset_replacement_dir
var _asset_paths_for_load: Dictionary[StringName, String] = IVCoreSettings.asset_paths_for_load
var _assets: Dictionary[StringName, Resource] = IVGlobal.assets
var _asset_path_arrays: Array[Array] = [
	IVCoreSettings.models_search,
	IVCoreSettings.maps_search,
	IVCoreSettings.bodies_2d_search,
	IVCoreSettings.rings_search,
]
var _asset_path_dicts: Array[Dictionary] = [
	IVCoreSettings.asset_paths,
	IVCoreSettings.asset_paths_for_load,
]


func _init() -> void:
	_modify_asset_paths()
	_load_assets()
	IVGlobal.initializers_inited.connect(_remove_self)


func _remove_self() -> void:
	IVGlobal.program.erase(&"AssetInitializer")


func _modify_asset_paths() -> void:
	if !_asset_replacement_dir:
		return
	for array in _asset_path_arrays:
		var index := 0
		var array_size: int = array.size()
		while index < array_size:
			var old_path: String = array[index]
			var new_path := old_path.replace("ivoyager_assets", _asset_replacement_dir)
			array[index] = new_path
			index += 1
	for dict in _asset_path_dicts:
		for asset_name: StringName in dict:
			var old_path: String = dict[asset_name]
			var new_path := old_path.replace("ivoyager_assets", _asset_replacement_dir)
			dict[asset_name] = new_path


func _load_assets() -> void:
	for asset_name: StringName in _asset_paths_for_load:
		var path: String = _asset_paths_for_load[asset_name]
		_assets[asset_name] = load(path)
