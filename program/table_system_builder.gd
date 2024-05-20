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
var _body_script: Script
var _small_bodies_group_script: Script
var _camera_script: Script



func build_system_tree() -> void:
	_body_builder = IVGlobal.program[&"TableBodyBuilder"]
	_body_script = IVGlobal.procedural_classes[&"Body"]
	_add_bodies()
	if add_small_bodies_groups:
		_sbg_builder = IVGlobal.program[&"TableSBGBuilder"]
		_small_bodies_group_script = IVGlobal.procedural_classes[&"SmallBodiesGroup"]
		_add_small_bodies_groups()
	if add_camera:
		_camera_script = IVGlobal.procedural_classes[&"Camera"]
		_add_camera()


func _add_bodies() -> void:
	# TODO: Remove order dependence
	
	for table_name in IVCoreSettings.body_tables:
		for row in IVTableData.get_n_rows(table_name):
			var parent: IVBody
			var parent_name := IVTableData.get_db_string_name(table_name, &"parent", row) # "" top
			if parent_name:
				parent = IVGlobal.bodies[parent_name]
			@warning_ignore("unsafe_method_access")
			var body: IVBody = _body_script.new()
			_body_builder.build_body_from_table(body, table_name, row, parent)
			body.hide() # Bodies set their own visibility as needed
			if parent:
				parent.add_child(body)
				parent.satellites.append(body)
			else: # top body
				var universe: Node3D = IVGlobal.program.Universe
				universe.add_child(body)


func _add_small_bodies_groups() -> void:
	for row in IVTableData.get_n_rows(&"small_bodies_groups"):
		if IVTableData.get_db_bool(&"small_bodies_groups", &"skip", row):
			continue
		@warning_ignore("unsafe_method_access")
		var sbg: IVSmallBodiesGroup = _small_bodies_group_script.new()
		_sbg_builder.build_sbg_from_table(sbg, &"small_bodies_groups", row)
		var primary_name := IVTableData.get_db_string_name(&"small_bodies_groups", &"primary", row)
		var primary: IVBody = IVGlobal.bodies.get(primary_name)
		assert(primary, "Primary body missing for SmallBodiesGroup")
		primary.add_child(sbg)


func _add_camera() -> void:
	@warning_ignore("unsafe_method_access")
	var camera: Camera3D = _camera_script.new()
	var start_body: IVBody = IVGlobal.bodies[IVCoreSettings.home_name]
	start_body.add_child(camera)

