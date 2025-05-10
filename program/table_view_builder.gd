# table_view_builder.gd
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
class_name IVTableViewBuilder
extends RefCounted

## Builds IVView instances from table views.tsv.


var as_is_fields: Array[StringName] = [
	# Can't import dictionaries yet.
	# Member 'view_position' is handled explicitly.
	&"flags",
	&"selection_name",
	&"camera_flags",
	&"view_rotations",
	&"name_visible_flags",
	&"symbol_visible_flags",
	&"orbit_visible_flags",
	&"visible_points_groups",
	&"visible_orbits_groups",
	&"time",
	&"speed_index",
	&"is_reversed",
]

var _view_script: Script


func _init() -> void:
	_view_script = IVGlobal.procedural_classes[&"View"]


func build_all() -> Dictionary[StringName, IVView]:
	var result: Dictionary[StringName, IVView] = {}
	for row in IVTableData.get_n_rows(&"views"):
		var view := build(row)
		var name := IVTableData.get_db_entity_name(&"views", row)
		result[name] = view
	return result


func build(row: int) -> IVView:
	@warning_ignore("unsafe_method_access")
	var view: IVView = _view_script.new()
	IVTableData.db_build_object(view, &"views", row, as_is_fields)
	var view_position_xy := IVTableData.get_db_vector2(&"views", &"view_position_xy", row)
	var view_position_z := IVTableData.get_db_float(&"views", &"view_position_z", row)
	view.view_position = Vector3(view_position_xy.x, view_position_xy.y, view_position_z)
	return view
