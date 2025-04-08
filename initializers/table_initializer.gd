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


static var table_base_path := "res://addons/ivoyager_core/data/solar_system/%s.tsv" 
static var tables: Dictionary[StringName, String] = {
	asset_adjustments = table_base_path % "asset_adjustments",
	asteroids = table_base_path % "asteroids",
	body_classes = table_base_path % "body_classes",
	camera_attributes = table_base_path % "camera_attributes",
	dynamic_lights = table_base_path % "dynamic_lights",
	environments = table_base_path % "environments",
	omni_lights = table_base_path % "omni_lights",
	models = table_base_path % "models",
	moons = table_base_path % "moons",
	planets = table_base_path % "planets",
	rings = table_base_path % "rings",
	small_bodies_groups = table_base_path % "small_bodies_groups",
	spacecrafts = table_base_path % "spacecrafts",
	stars = table_base_path % "stars",
	views = table_base_path % "views",
	visual_groups = table_base_path % "visual_groups",
	wiki_extras = table_base_path % "wiki_extras",
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
static var replacement_missing_values := {}



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
