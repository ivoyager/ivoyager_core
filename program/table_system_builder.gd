# table_system_builder.gd
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
class_name IVTableSystemBuilder
extends RefCounted

## Builds the star system(s) from data tables and (if applicable)
## table-referenced binaries.
##
## For new game, this class uses [IVBodyTableBuilder] and [IVSBGTableBuilder]
## to build [IVBody] and [IVSmallBodiesGroup] instances, respectively, and adds
## them to the scene tree. 
##
## Unless disabled, adds camera at Body defined by IVCoreSettings.home_name.
## The script used for camera instantiation is defined by
## IVCoreInitializer.procedural_objects[&"Camera"]


# project vars
var add_small_bodies_groups := true
var add_camera := true

# private
var _body_builder: IVTableBodyBuilder
var _sbg_builder: IVTableSBGBuilder


func _ivcore_init() -> void:
	_body_builder = IVGlobal.program[&"TableBodyBuilder"]
	_sbg_builder = IVGlobal.program[&"TableSBGBuilder"]


func build_system_tree() -> void:
	_add_bodies()
	if add_small_bodies_groups:
		_add_small_bodies_groups()
	if add_camera:
		_add_camera()


func _add_bodies() -> void:
	for table_name in IVCoreSettings.body_tables:
		for row in IVTableData.get_n_rows(table_name):
			var parent: IVBody
			var parent_name := IVTableData.get_db_string_name(table_name, &"parent", row) # "" top
			if parent_name:
				parent = IVGlobal.bodies[parent_name]
			var body := _body_builder.build_from_table(table_name, row, parent)
			body.hide() # Bodies set their own visibility as needed
			if parent:
				parent.add_child(body)
				parent.satellites.append(body)
			else: # top body
				var universe: Node3D = IVGlobal.program.Universe
				universe.add_child(body)


func _add_small_bodies_groups() -> void:
	for row in IVTableData.get_n_rows(&"small_bodies_groups"):
		_sbg_builder.build_from_table(row)


func _add_camera() -> void:
	var CameraScript: Script = IVGlobal.procedural_classes[&"Camera"]
	@warning_ignore("unsafe_method_access")
	var camera: Camera3D = CameraScript.new()
	var start_body: IVBody = IVGlobal.bodies[IVCoreSettings.home_name]
	start_body.add_child(camera)

