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
## FIXME: Static table parameters can be modified on [signal
## IVStateManager.about_to_run_initializers].
##
## Alternatively, parameters can be modified by intercepting this object on signal
## IVStateManager.core_init_object_instantiated(object: Object).
##
## After all initializers have been instantiated, this class will call
## IVTableData.postprocess_tables() and then remove itself.


static var table_base_path := "res://addons/ivoyager_core/data/tables/%s.tsv" 
static var tables: Dictionary[StringName, String] = {
	file_adjustments = table_base_path % "file_adjustments",
	asteroids = table_base_path % "asteroids",
	body_classes = table_base_path % "body_classes",
	dynamic_lights = table_base_path % "dynamic_lights",
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

## Table fields used to build [member IVTableData.wiki_page_titles_by_field].
## Empty by default. Append &"wikipedia.en" to use English Wikipedia
## page titles present in base I, Voyager tables (these are target page titles
## for English language Wikipedia.org).
static var wiki_page_title_fields: Array[StringName] = []


static var merge_overwrite_table_constants: Dictionary[StringName, Variant] = {
	&"3000_BC" : -50.0 * IVUnits.CENTURY,
	&"3000_AD" : +10.0 * IVUnits.CENTURY,
	&"1800_AD" : -2.0 * IVUnits.CENTURY,
	&"2050_AD" : +0.5 * IVUnits.CENTURY,
}
static var merge_overwrite_missing_values: Dictionary[int, Variant] = {} # use is not recommended



func _init() -> void:
	IVStateManager.core_init_init_refcounteds_instantiated.connect(_on_init_refcounteds_instantiated)


func _on_init_refcounteds_instantiated() -> void:
	
	IVTableData.postprocess_tables(
			tables.values(),
			IVQConvert.to_internal,
			wiki_page_title_fields,
			IVCoreSettings.enable_precisions,
			merge_overwrite_table_constants,
			merge_overwrite_missing_values,
	)
	
	# signal done
	IVGlobal.data_tables_postprocessed.emit()
	IVStateManager.core_init_program_objects_instantiated.connect(_remove_self)


func _remove_self() -> void:
	IVGlobal.program.erase(&"TableInitializer")
