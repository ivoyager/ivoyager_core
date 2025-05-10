# table_sbg_builder.gd
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
class_name IVTableSBGBuilder
extends RefCounted

## Builds [IVSmallBodiesGroup] instances from table data.
##
## This class may supply SBG to a BinaryXxxxBuilder to set binary data.
##
## For now, we only have asteroids as binaries. But there may be more in the
## future (e.g., artificial satellites) and they likely will have different
## binary formats.

const SBGClass := IVSmallBodiesGroup.SBGClass


var _binary_asteroids_builder: IVBinaryAsteroidsBuilder



func _init() -> void:
	IVGlobal.project_objects_instantiated.connect(_on_project_objects_instantiated)


func _on_project_objects_instantiated() -> void:
	_binary_asteroids_builder = IVGlobal.program[&"BinaryAsteroidsBuilder"]


func build_sbg(sbg: IVSmallBodiesGroup, table_name: StringName, row: int) -> void:
	var name := IVTableData.get_db_entity_name(table_name, row)
	var sbg_alias := IVTableData.get_db_string_name(table_name, &"sbg_alias", row)
	var sbg_class := IVTableData.get_db_int(table_name, &"sbg_class", row) as SBGClass
	
	match sbg_class:
		SBGClass.SBG_CLASS_ASTEROIDS:
			build_asteroids_sbg(sbg, table_name, row, name, sbg_alias, sbg_class)
		_:
			assert(false, "No implimentation for sbg_class %s" % sbg_class)


func build_asteroids_sbg(sbg: IVSmallBodiesGroup, table_name: StringName, row: int,
		name: StringName, sbg_alias: StringName, sbg_class: SBGClass) -> void:
	var binary_dir := IVTableData.get_db_string(table_name, &"binary_dir", row)
	var mag_cutoff := 100.0
	var sbg_mag_cutoff_override: float = IVCoreSettings.sbg_mag_cutoff_override
	if sbg_mag_cutoff_override != INF:
		mag_cutoff = sbg_mag_cutoff_override
	else:
		mag_cutoff = IVTableData.get_db_float(table_name, &"mag_cutoff", row)
	var lp_integer := IVTableData.get_db_int(table_name, &"lp_integer", row)
	var secondary: IVBody
	if lp_integer != -1:
		assert(lp_integer == 4 or lp_integer == 5, "Only L4, L5 supported at this time!")
		var secondary_name := IVTableData.get_db_string_name(table_name, &"secondary", row)
		secondary = IVBody.bodies.get(secondary_name)
		assert(secondary, "Secondary body missing for Lagrange point SmallBodiesGroup")
	sbg.init(name, sbg_alias, sbg_class, lp_integer, secondary)
	_binary_asteroids_builder.build_sbg_from_binaries(sbg, binary_dir, mag_cutoff)
