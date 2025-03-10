# table_system_builder.gd
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
class_name IVTableSystemBuilder
extends RefCounted

## Builds the star system(s) from data tables and (if applicable)
## table-referenced binaries.
##
## Builds [IVBody] instances and attaches each to its parent. 
##
## Unless disabled in project vars below,[br]
## * adds top bodies of the body tree to Universe.[br]
## * adds IVSmallBodiesGroup instances.[br]
## * adds camera at Body defined by IVCoreSettings.home_name.[br]
##
## Scripts for IVBody, IVSmallBodiesGroup, and Camera3D are defined in
## IVCoreInitializer.procedural_objects. These can be overriden by subclasses.

# project vars
var attach_to_universe := true
var add_small_bodies_groups := true
var add_camera := true

# private
var _bodies: Dictionary[StringName, Object] = IVGlobal.bodies
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
	var table_dict: Dictionary[StringName, StringName] = {}
	for table_name in IVCoreSettings.body_tables:
		for row in IVTableData.get_n_rows(table_name):
			var name := IVTableData.get_db_entity_name(table_name, row)
			table_dict[name] = table_name
	for name: StringName in table_dict:
		if !_bodies.has(name):
			_add_bodies_from_top(name, table_dict)


func _add_bodies_from_top(name: StringName, table_dict: Dictionary[StringName, StringName]) -> void:
	# Add ancestors recursively from top, then this one.
	var table_name: StringName = table_dict[name]
	var row := IVTableData.get_row(name)
	var parent_name := IVTableData.get_db_string_name(table_name, &"parent", row) # &"" top
	var parent: IVBody
	if parent_name:
		if !_bodies.has(parent_name):
			_add_bodies_from_top(parent_name, table_dict)
		parent = _bodies[parent_name]
	@warning_ignore("unsafe_method_access")
	var body: IVBody = _body_script.new()
	_body_builder.build_body_from_table(body, table_name, row, parent)
	body.hide() # Bodies set their own visibility as needed
	if parent:
		parent.add_child(body)
		parent.satellites.append(body)
	elif attach_to_universe: # top body
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
		var primary: IVBody = _bodies.get(primary_name)
		assert(primary, "Primary body missing for SmallBodiesGroup")
		primary.add_child(sbg)


func _add_camera() -> void:
	@warning_ignore("unsafe_method_access")
	var camera: Camera3D = _camera_script.new()
	var start_body: IVBody = _bodies[IVCoreSettings.home_name]
	start_body.add_child(camera)
