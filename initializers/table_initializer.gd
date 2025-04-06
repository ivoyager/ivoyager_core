# table_initializer.gd
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
class_name IVTableInitializer
extends RefCounted

## Initializes tables using the ivoyager_tables plugin.
##
## Static table parameters can be modified on signal IVGlobal.about_to_run_initializers.
##
## Alternatively, parameters can be modified by intercepting this object on signal
## IVGlobal.project_object_instantiated(object: Object).
##
## After all initializers have been instantiated, this class will call
## IVTableData.postprocess_tables() and then remove itself.

 
static var tables: Dictionary[StringName, String] = {
	asset_adjustments = "res://addons/ivoyager_core/data/solar_system/asset_adjustments.tsv",
	asteroids = "res://addons/ivoyager_core/data/solar_system/asteroids.tsv",
	body_classes = "res://addons/ivoyager_core/data/solar_system/body_classes.tsv",
	dynamic_lights = "res://addons/ivoyager_core/data/solar_system/dynamic_lights.tsv",
	omni_lights = "res://addons/ivoyager_core/data/solar_system/omni_lights.tsv",
	models = "res://addons/ivoyager_core/data/solar_system/models.tsv",
	moons = "res://addons/ivoyager_core/data/solar_system/moons.tsv",
	planets = "res://addons/ivoyager_core/data/solar_system/planets.tsv",
	rings = "res://addons/ivoyager_core/data/solar_system/rings.tsv",
	small_bodies_groups = "res://addons/ivoyager_core/data/solar_system/small_bodies_groups.tsv",
	spacecrafts = "res://addons/ivoyager_core/data/solar_system/spacecrafts.tsv",
	stars = "res://addons/ivoyager_core/data/solar_system/stars.tsv",
	views = "res://addons/ivoyager_core/data/solar_system/views.tsv",
	visual_groups = "res://addons/ivoyager_core/data/solar_system/visual_groups.tsv",
	wiki_extras = "res://addons/ivoyager_core/data/solar_system/wiki_extras.tsv",
}
static var table_project_enums := [
	IVSmallBodiesGroup.SBGClass,
	IVGlobal.Confidence,
	IVBody.BodyFlags,
	IVCamera.CameraFlags,
	IVView.ViewFlags,
	IVGlobal.ShadowMask,
]
static var merge_table_constants := {}
static var replacement_missing_values := {} # not recomended to use this



func _init() -> void:
	IVGlobal.project_initializers_instantiated.connect(_on_project_initializers_instantiated)


func _on_project_initializers_instantiated() -> void:
	IVTableData.postprocess_tables(
			tables.values(),
			IVQConvert.convert_quantity,
			IVCoreSettings.enable_wiki,
			IVCoreSettings.enable_precisions,
			table_project_enums,
			merge_table_constants,
			replacement_missing_values,
	)
	
	# signal done
	IVGlobal.data_tables_imported.emit()
	IVGlobal.project_objects_instantiated.connect(_remove_self)


func _remove_self() -> void:
	IVGlobal.program.erase(&"TableInitializer")
