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

## Builds [IVBody] (or subclass) instances from data tables.
##
## The generator class [IVTableOrbitBuilder] can be replaced with another
## generator class in [IVCoreInitializer]. The replacement class must have
## method compatible with [method IVTableOrbitBuilder.make_orbit].[br][br]
##
## The generator class [IVTableCompositionBuilder] can be removed or replaced
## with another generator class in [IVCoreInitializer]. If replaced, the
## replacement class must have method compatible with
## [method IVTableCompositionBuilder.add_compositions_from_table].

const BodyFlags := IVBody.BodyFlags


## Set IVBody property if non-missing value in table.
var create_fields: Array[StringName] = [
	&"name",
	&"mean_radius",
	&"gravitational_parameter",
	&"right_ascension",
	&"declination",
	&"rotation_period",
	&"rotation_at_epoch",
]

## Add to IVBody.characteristics if non-missing value in table.
var characteristics_fields: Array[StringName] = [
	&"symbol",
	&"hud_name",
	&"body_class",
	&"model_type",
	&"has_light",
	&"file_prefix",
	&"has_rings",
	&"n_kn_planets",
	&"n_kn_dwf_planets",
	&"n_kn_minor_planets",
	&"n_kn_comets",
	&"n_nat_satellites",
	&"substellar_longitude_at_epoch",
	&"mass",
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
	&"tumbles_chaotically" : BodyFlags.BODYFLAGS_CHAOTIC_TUMBLER,
	
	&"lazy_model" : BodyFlags.BODYFLAGS_LAZY_MODEL,
	&"sleep" : BodyFlags.BODYFLAGS_CAN_SLEEP,
	
	&"show_in_nav_panel" : BodyFlags.BODYFLAGS_SHOW_IN_NAVIGATION_PANEL,
	&"display_equatorial_polar_radii" : BodyFlags.BODYFLAGS_DISPLAY_EQUATORIAL_POLAR_RADII,
	&"use_cardinal_directions" : BodyFlags.BODYFLAGS_USE_CARDINAL_DIRECTIONS,
	&"use_pitch_yaw" : BodyFlags.BODYFLAGS_USE_PITCH_YAW,
}

var add_precisions: Dictionary[String, StringName] = {
	"body/orbit/get_semi_major_axis" : &"semi_major_axis",
	"body/orbit/get_periapsis" : &"semi_major_axis", # roughly
	"body/orbit/get_apoapsis" : &"semi_major_axis", # roughly
	"body/orbit/get_eccentricity" : &"eccentricity",
	"body/orbit/get_inclination" : &"inclination",
	"body/orbit/get_period" : &"mean_motion",
	"body/get_rotation_period" : &"rotation_period",
}


var _enable_precisions := IVCoreSettings.enable_precisions
var _orbit_builder: RefCounted
var _composition_builder: RefCounted



func _init() -> void:
	IVGlobal.project_objects_instantiated.connect(_on_project_objects_instantiated)



func build_body(table_name: String, row: int, parent: IVBody) -> IVBody:
	
	var flags := IVTableData.db_get_flags(table_name, row, flag_fields)
	assert(bool(flags & BodyFlags.BODYFLAGS_GALAXY_ORBITER) == (parent == null))
	
	var orbit: IVOrbit = null
	if parent:
		@warning_ignore("unsafe_method_access")
		orbit = _orbit_builder.make_orbit(table_name, row, parent)
	
	var characteristics: Dictionary[StringName, Variant] = {}
	IVTableData.db_build_dictionary(characteristics, table_name, row, characteristics_fields)
	
	if _enable_precisions:
		var precisions: Dictionary[String, int] = {}
		_set_table_data_precisions(table_name, row, precisions)
		characteristics[&"float_precisions"] = precisions
		
	var components: Dictionary[StringName, RefCounted] = {}
	if _composition_builder:
		@warning_ignore("unsafe_method_access")
		_composition_builder.add_compositions_from_table(components, table_name, row)
	
	var create_parameters: Dictionary[StringName, Variant] = {}
	IVTableData.db_build_dictionary(create_parameters, table_name, row, create_fields)
	
	assert(create_parameters.has(&"name"))
	assert(create_parameters.has(&"mean_radius"))
	
	var name: StringName = create_parameters[&"name"]
	var mean_radius: float = create_parameters[&"mean_radius"]
	var gravitational_parameter: float = create_parameters.get(&"gravitational_parameter", 0.0)
	var right_ascension: float = create_parameters.get(&"right_ascension", 0.0)
	var declination: float = create_parameters.get(&"declination", 0.0)
	var rotation_period: float = create_parameters.get(&"rotation_period", 0.0)
	var rotation_at_epoch: float = create_parameters.get(&"rotation_at_epoch", NAN)
	
	if !gravitational_parameter and characteristics.has(&"mass"):
		gravitational_parameter = IVAstronomy.G * characteristics[&"mass"]
	
	if is_nan(rotation_at_epoch):
		if orbit:
			rotation_at_epoch = orbit.get_mean_longitude_at_epoch() - PI
			if characteristics.has(&"substellar_longitude_at_epoch"):
				# This is longitude facing parent at epoch
				rotation_at_epoch += characteristics[&"substellar_longitude_at_epoch"]
		else:
			rotation_at_epoch = 0.0
	
	# Notes:
	#
	# create_from_astronomy_specs() will calculate gravitational_parameter from
	# characteristics.mass, if that is present and gravitational_parameter == 0.0.
	# If not, 0.0 will be ok in most cases. The body can't be orbited if GM is
	# too small anyway.
	#
	# Rotation parameters don't matter if the body is tidally and axis-locked
	# (they will be updated by the orbit). However, we also have hundreds of
	# small outer moons (not tidally locked) that don't have rotation specs.
	# These will get a generic fallback model and have north in ecliptic north
	# direction. (TODO: "Tumbler" code with random inertial axes and rotation
	# rates.)
	
	var body := IVBody.create_from_astronomy_specs(
		name,
		mean_radius,
		gravitational_parameter,
		right_ascension,
		declination,
		rotation_period,
		rotation_at_epoch,
		characteristics,
		components,
		orbit,
		flags
	)
	
	
	return body



func _on_project_objects_instantiated() -> void:
	_orbit_builder = IVGlobal.program[&"TableOrbitBuilder"]
	_composition_builder = IVGlobal.program.get(&"TableCompositionBuilder") # remove to skip


func _set_table_data_precisions(table_name: StringName, row: int,
		precisions: Dictionary[String, int]) -> void:
	var precision_array := IVTableData.get_db_float_precisions(table_name, create_fields, row)
	for i in create_fields.size():
		if precision_array[i] != -1:
			precisions["body/" + create_fields[i]] = precision_array[i]
	precision_array = IVTableData.get_db_float_precisions(table_name, characteristics_fields, row)
	for i in characteristics_fields.size():
		if precision_array[i] != -1:
			precisions["body/characteristics/" + characteristics_fields[i]] = precision_array[i]
	for key in add_precisions:
		var field := add_precisions[key]
		var precision := IVTableData.get_db_float_precision(table_name, field, row)
		if precision != -1:
			precisions[key] = precision
