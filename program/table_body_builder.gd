# table_body_builder.gd
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
class_name IVTableBodyBuilder
extends RefCounted

## Builds [IVBody] instances from data tables.

const BodyFlags := IVBody.BodyFlags

## Set IVBody property if non-missing value in table.
var property_fields: Array[StringName] = [
	&"name",
	&"mean_radius",
	&"rotation_period",
	&"right_ascension",
	&"declination",
	&"gm",
	&"mass",
]

## Add to IVBody.characteristics if non-missing value in table.
var characteristics_fields: Array[StringName] = [
	&"symbol",
	&"hud_name",
	&"body_class",
	&"model_type",
	&"has_light",
	&"shader_sun_index",
	&"file_prefix",
	&"has_rings",
	&"n_kn_planets",
	&"n_kn_dwf_planets",
	&"n_kn_minor_planets",
	&"n_kn_comets",
	&"n_nat_satellites",
	&"n_kn_nat_satellites",
	&"n_kn_quasi_satellites",
	&"surface_gravity",
	&"esc_vel",
	&"equatorial_radius",
	&"polar_radius",
	&"system_radius",
	&"perspective_radius",
	&"longitude_at_epoch",
	&"mean_density",
	&"hydrostatic_equilibrium",
	&"albedo",
	&"surf_t",
	&"min_t",
	&"max_t",
	&"temp_center",
	&"temp_photosphere",
	&"temp_corona",
	&"surf_pres",
	&"trace_pres",
	&"trace_pres_low",
	&"trace_pres_high",
	&"one_bar_t",
	&"half_bar_t",
	&"tenth_bar_t",
	&"galactic_orbital_speed",
	&"velocity_vs_cmb",
	&"velocity_vs_near_stars",
	&"dist_galactic_core",
	&"galactic_period",
	&"stellar_classification",
	&"absolute_magnitude",
	&"luminosity",
	&"color_b_v",
	&"metallicity",
	&"age",
	&"atmosphere",
	&"gas_giant",
]

var flag_fields: Dictionary[StringName, int] = {
	&"galaxy_orbiter" : BodyFlags.BODYFLAGS_GALAXY_ORBITER,
	&"star_orbiter" : BodyFlags.BODYFLAGS_STAR_ORBITER,
	&"planetary_mass_object" : BodyFlags.BODYFLAGS_PLANETARY_MASS_OBJECT,
	&"star" : BodyFlags.BODYFLAGS_STAR,
	&"planet_or_dwarf_planet" : BodyFlags.BODYFLAGS_PLANET_OR_DWARF_PLANET,
	&"planet" : BodyFlags.BODYFLAGS_PLANET,
	&"dwarf_planet" : BodyFlags.BODYFLAGS_DWARF_PLANET,
	&"moon" : BodyFlags.BODYFLAGS_MOON,
	&"planetary_mass_moon" : BodyFlags.BODYFLAGS_PLANETARY_MASS_MOON,
	&"non_planetary_mass_moon" : BodyFlags.BODYFLAGS_NON_PLANETARY_MASS_MOON,
	&"asteroid" : BodyFlags.BODYFLAGS_ASTEROID,
	&"comet" : BodyFlags.BODYFLAGS_COMET,
	&"spacecraft" : BodyFlags.BODYFLAGS_SPACECRAFT,
	
	&"tidally_locked" : BodyFlags.BODYFLAGS_TIDALLY_LOCKED,
	&"axis_locked" : BodyFlags.BODYFLAGS_AXIS_LOCKED,
	&"tumbles_chaotically" : BodyFlags.BODYFLAGS_TUMBLES_CHAOTICALLY,
	
	&"lazy_model" : BodyFlags.BODYFLAGS_LAZY_MODEL,
	&"sleep" : BodyFlags.BODYFLAGS_SLEEP,
	
	&"show_in_nav_panel" : BodyFlags.BODYFLAGS_SHOW_IN_NAVIGATION_PANEL,
	&"display_equatorial_polar_radii" : BodyFlags.BODYFLAGS_DISPLAY_EQUATORIAL_POLAR_RADII,
	&"use_cardinal_directions" : BodyFlags.BODYFLAGS_USE_CARDINAL_DIRECTIONS,
	&"use_pitch_yaw" : BodyFlags.BODYFLAGS_USE_PITCH_YAW,
}


var _enable_precisions := IVCoreSettings.enable_precisions
var _orbit_builder: IVTableOrbitBuilder
var _composition_builder: IVCompositionBuilder


func _init() -> void:
	IVGlobal.project_objects_instantiated.connect(_on_project_objects_instantiated)


func _on_project_objects_instantiated() -> void:
	_orbit_builder = IVGlobal.program[&"TableOrbitBuilder"]
	_composition_builder = IVGlobal.program.get(&"CompositionBuilder")


func build_body(body: IVBody, table_name: String, row: int, parent: IVBody) -> void:
	_set_table_data(body, table_name, row)
	if _enable_precisions:
		var precisions: Dictionary[String, int] = {}
		_set_table_data_precisions(table_name, row, precisions)
		body.characteristics[&"float_precisions"] = precisions
	_set_orbit(body, table_name, row, parent)
	if _composition_builder:
		_composition_builder.add_compositions_from_table(body, table_name, row)


func _set_table_data(body: IVBody, table_name: StringName, row: int) -> void:
	IVTableData.db_build_object(body, table_name, row, property_fields)
	IVTableData.db_build_dictionary(body.characteristics, table_name, row, characteristics_fields)
	body.flags = IVTableData.db_get_flags(table_name, row, flag_fields)
	body.flags |= BodyFlags.BODYFLAGS_EXISTS
	assert(body.mean_radius)


func _set_table_data_precisions(table_name: StringName, row: int,
		precisions: Dictionary[String, int]) -> void:
	var precision_array := IVTableData.get_db_float_precisions(property_fields, table_name, row)
	for i in property_fields.size():
		if precision_array[i] != -1:
			precisions["body/" + property_fields[i]] = precision_array[i]
	precision_array = IVTableData.get_db_float_precisions(characteristics_fields, table_name, row)
	for i in characteristics_fields.size():
		if precision_array[i] != -1:
			precisions["body/characteristics/" + characteristics_fields[i]] = precision_array[i]


func _set_orbit(body: IVBody, table_name: String, row: int, parent: IVBody) -> void:
	if body.flags & BodyFlags.BODYFLAGS_GALAXY_ORBITER:
		return
	var orbit := _orbit_builder.make_orbit(table_name, row, parent)
	body.set_orbit(orbit)
