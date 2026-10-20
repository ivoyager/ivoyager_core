# table_composition_builder.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield
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
class_name IVTableCompositionBuilder
extends RefCounted

## Builds [IVComposition] instances from data tables.
##
## A composition cell lists species by their [code]chemicals.tsv[/code] entity names,
## without the table's prefix, each optionally after an amount:
## "78.08% NITROGEN, ~1% WATER_VAPOR, trace ARGON, HELIUM".


var _regex := RegEx.new()



func _init() -> void:
	_regex.compile("(?:([~\\d\\.]+%|trace) )?(.+)")



func add_compositions_from_table(components: Dictionary[StringName, RefCounted],
		table_name: StringName, row: int) -> void:
	var atmosphere_composition_str := IVTableData.get_db_string(table_name,
			&"atmosphere_composition", row)
	if atmosphere_composition_str:
		var atmosphere_composition := make_composition_from_string(atmosphere_composition_str)
		components[&"atmosphere"] = atmosphere_composition
	var trace_atmosphere_composition_str := IVTableData.get_db_string(table_name,
			&"trace_atmosphere_composition", row)
	if trace_atmosphere_composition_str:
		var trace_atmosphere_composition := make_composition_from_string(trace_atmosphere_composition_str)
		components[&"trace_atmosphere"] = trace_atmosphere_composition
	var photosphere_composition_str := IVTableData.get_db_string(table_name,
			&"photosphere_composition", row)
	if photosphere_composition_str:
		var photosphere_composition := make_composition_from_string(photosphere_composition_str)
		components[&"photosphere"] = photosphere_composition


func make_composition_from_string(string: String) -> IVComposition:
	var composition := IVComposition.new()
	var prefix := IVTableData.get_entity_prefix(&"chemicals")
	for item in string.split(", "):
		var item_match := _regex.search(item)
		var species := StringName(prefix + item_match.strings[2])
		assert(IVTableData.has_entity_name(&"chemicals", species),
				"'%s' in composition '%s' is not in chemicals.tsv" % [species, string])
		var amount := item_match.strings[1]
		if amount == "trace":
			amount = "TXT_TRACE"
		composition.species.append(species)
		composition.amounts.append(amount)
	return composition
