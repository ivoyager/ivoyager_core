# table_sbg_builder.gd
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
class_name IVTableSBGBuilder
extends RefCounted

## Builds [IVSmallBodiesGroup] instances from table data.
##
## This class may supply SBG to a BinaryXxxxBuilder to set binary data.
##
## For now, we only have asteroids as binaries. But there may be more in the
## future (e.g., artificial satellites) and they likely will have different
## binary formats.


var _binary_asteroids_builder: IVBinaryAsteroidsBuilder
var _small_bodies_group_script: Script


func _ivcore_init() -> void:
	_binary_asteroids_builder = IVGlobal.program[&"BinaryAsteroidsBuilder"]
	_small_bodies_group_script = IVGlobal.procedural_classes[&"SmallBodiesGroup"]


func build_from_table(row: int) -> void:
	if IVTableData.get_db_bool(&"small_bodies_groups", &"skip", row):
		return
	
	# get required table data for any SBG
	var name := IVTableData.get_db_entity_name(&"small_bodies_groups", row)
	var sbg_alias := IVTableData.get_db_string_name(&"small_bodies_groups", &"sbg_alias", row)
	var sbg_class := IVTableData.get_db_int(&"small_bodies_groups", &"sbg_class", row)
	
	match sbg_class:
		IVEnums.SBGClass.SBG_CLASS_ASTEROIDS:
			build_asteroids_sbg(row, name, sbg_alias, sbg_class)
		_:
			assert(false, "No implimentation for sbg_class %s" % sbg_class)


func build_asteroids_sbg(row: int, name: StringName, sbg_alias: StringName, sbg_class: int) -> void:
	
	var binary_dir := IVTableData.get_db_string(&"small_bodies_groups", &"binary_dir", row)
	var mag_cutoff := 100.0
	var sbg_mag_cutoff_override: float = IVCoreSettings.sbg_mag_cutoff_override
	if sbg_mag_cutoff_override != INF:
		mag_cutoff = sbg_mag_cutoff_override
	else:
		mag_cutoff = IVTableData.get_db_float(&"small_bodies_groups", &"mag_cutoff", row)
	var primary_name := IVTableData.get_db_string_name(&"small_bodies_groups", &"primary", row)
	var primary: IVBody = IVGlobal.bodies.get(primary_name)
	assert(primary, "Primary body missing for SmallBodiesGroup")
	var lp_integer := IVTableData.get_db_int(&"small_bodies_groups", &"lp_integer", row)
	var secondary: IVBody
	if lp_integer != -1:
		assert(lp_integer == 4 or lp_integer == 5, "Only L4, L5 supported at this time!")
		var secondary_name := IVTableData.get_db_string_name(&"small_bodies_groups", &"secondary", row)
		secondary = IVGlobal.bodies.get(secondary_name)
		assert(secondary, "Secondary body missing for Lagrange point SmallBodiesGroup")
	
	# init
	@warning_ignore("unsafe_method_access")
	var sbg: IVSmallBodiesGroup = _small_bodies_group_script.new()
	sbg.init(name, sbg_alias, sbg_class, lp_integer, secondary)
	
	_binary_asteroids_builder.build_sbg_from_binaries(sbg, mag_cutoff, binary_dir)
	

	primary.add_child(sbg)


