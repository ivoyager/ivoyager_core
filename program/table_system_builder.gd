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

## Builds the star system(s) from data tables, calling other table-object
## "builders" as needed.
##
## Procedural classes can be replaced with subclasses by replacing or
## subclassing generator classes in [IVCoreInitializer]. IVCamera can be
## replaced via [member replacement_camera_class] with a subclass or a non-
## subclass Camera3D (the latter is more work; watch out for IVCamera-associated
## GUI widgets).[br][br]
##
## This class assembles the "IVBody tree" from data tables. Unless disabled in
## member vars, it will also:[br]
## * add top bodies of the body tree to Universe.[br]
## * add IVSmallBodiesGroup instances.[br]
## * add camera at Body defined by IVCoreSettings.home_name.[br]

const BodyFlags := IVBody.BodyFlags


# project vars
var add_to_universe := true
var add_small_bodies_groups := true
var add_camera := true
var replacement_camera_class: Script

# private
var _bodies := IVBody.bodies
var _body_builder: IVTableBodyBuilder
var _sbg_builder: IVTableSBGBuilder



func _init() -> void:
	IVGlobal.build_system_tree_requested.connect(build_system_tree)


func build_system_tree() -> void:
	_body_builder = IVGlobal.program[&"TableBodyBuilder"]
	_add_bodies()
	if add_small_bodies_groups:
		_sbg_builder = IVGlobal.program[&"TableSBGBuilder"]
		_add_small_bodies_groups()
	if add_camera:
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
	var parent_name := IVTableData.get_db_string_name(table_name, &"parent", row)
	var parent: IVBody
	if parent_name:
		if !_bodies.has(parent_name):
			_add_bodies_from_top(parent_name, table_dict)
		parent = _bodies[parent_name]
	var body := _body_builder.build_body(table_name, row, parent)
	if parent:
		parent.add_child(body)
		return
	assert(body.flags & BodyFlags.BODYFLAGS_GALAXY_ORBITER,
			"body.tsv row with no parent must have galaxy_orbiter == TRUE")
	if add_to_universe:
		var universe: Node3D = IVGlobal.program.Universe
		universe.add_child(body)
		universe.move_child(body, 0)


func _add_small_bodies_groups() -> void:
	for row in IVTableData.get_n_rows(&"small_bodies_groups"):
		if IVTableData.get_db_bool(&"small_bodies_groups", &"skip", row):
			continue
		var sbg := _sbg_builder.build_sbg(&"small_bodies_groups", row)
		var primary_name := IVTableData.get_db_string_name(&"small_bodies_groups", &"primary", row)
		var primary: IVBody = _bodies.get(primary_name)
		assert(primary, "Primary body missing for SmallBodiesGroup")
		primary.add_child(sbg)


func _add_camera() -> void:
	var camera: Camera3D
	if replacement_camera_class:
		@warning_ignore("unsafe_method_access")
		camera = replacement_camera_class.new()
	else:
		camera = IVCamera.new()
	var start_body: IVBody = _bodies[IVCoreSettings.home_name]
	start_body.add_child(camera)
