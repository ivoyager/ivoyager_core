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


const ECLIPTIC_Z := Vector3(0.0, 0.0, 1.0)
const G := IVUnits.GRAVITATIONAL_CONSTANT
const BodyFlags := IVBody.BodyFlags

var enable_precisions := IVCoreSettings.enable_precisions

var characteristics_fields: Array[StringName] = [
	# Added to characteristics only if exists in table.
	&"symbol",
	&"hud_name",
	&"body_class",
	&"model_type",
	&"lazy_model",
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
	&"GM",
	&"mass",
	&"surface_gravity",
	&"esc_vel",
	&"m_radius",
	&"e_radius",
	&"system_radius",
	&"perspective_radius",
	&"right_ascension",
	&"declination",
	&"longitude_at_epoch",
	&"rotation_period",
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
]

var move_from_characteristics_to_property: Array[StringName] = [
	&"m_radius",
	&"rotation_period",
	&"right_ascension",
	&"declination",
]


var field_flags: Dictionary[StringName, int] = {
	&"star" : BodyFlags.BODYFLAGS_STAR,
	&"planet" : BodyFlags.BODYFLAGS_PLANET,
	&"true_planet" : BodyFlags.BODYFLAGS_TRUE_PLANET,
	&"dwarf_planet" : BodyFlags.BODYFLAGS_DWARF_PLANET,
	&"moon" : BodyFlags.BODYFLAGS_MOON,
	&"can_sleep" : BodyFlags.BODYFLAGS_CAN_SLEEP,
	&"tidally_locked" : BodyFlags.BODYFLAGS_TIDALLY_LOCKED,
	&"axis_locked" : BodyFlags.BODYFLAGS_AXIS_LOCKED,
	&"tumbles_chaotically" : BodyFlags.BODYFLAGS_TUMBLES_CHAOTICALLY,
	&"atmosphere" : BodyFlags.BODYFLAGS_ATMOSPHERE,
	&"gas_giant" : BodyFlags.BODYFLAGS_GAS_GIANT,
	&"asteroid" : BodyFlags.BODYFLAGS_ASTEROID,
	&"comet" : BodyFlags.BODYFLAGS_COMET,
	&"spacecraft" : BodyFlags.BODYFLAGS_SPACECRAFT,
	&"planetary_mass_object" : BodyFlags.BODYFLAGS_PLANETARY_MASS_OBJECT,
	&"show_in_nav_panel" : BodyFlags.BODYFLAGS_SHOW_IN_NAVIGATION_PANEL,
}

var _orbit_builder: IVTableOrbitBuilder
var _composition_builder: IVCompositionBuilder
var _table_name: StringName
var _row: int
var _real_precisions := {}



func _init() -> void:
	IVGlobal.project_objects_instantiated.connect(_on_project_objects_instantiated)


func _on_project_objects_instantiated() -> void:
	_orbit_builder = IVGlobal.program[&"TableOrbitBuilder"]
	_composition_builder = IVGlobal.program.get(&"CompositionBuilder")


func build_body_from_table(body: IVBody, table_name: String, row: int, parent: IVBody) -> void:
	_table_name = table_name
	_row = row
	body.name = IVTableData.get_db_entity_name(table_name, row)
	_set_flags_from_table(body, parent)
	_set_orbit_from_table(body, parent)
	_set_characteristics_from_table(body)
	if _composition_builder:
		_composition_builder.add_compositions_from_table(body, table_name, row)
	if enable_precisions:
		body.characteristics[&"real_precisions"] = _real_precisions
		_real_precisions = {} # reset for next body


func _set_flags_from_table(body: IVBody, parent: IVBody) -> void:
	# flags
	var flags := IVTableData.db_get_flags(_table_name, _row, field_flags)
	# All below are constructed (non-table) flags.
	# TODO: Below should be in IVBody to facilitate non-table construction, but
	# we would need to fix subsequent usage and setting in this class.
	
	flags |= BodyFlags.BODYFLAGS_EXISTS
	if !parent:
		flags |= BodyFlags.BODYFLAGS_TOP # will add self to IVBody.top_bodies
		flags |= BodyFlags.BODYFLAGS_PRIMARY_STAR
		flags |= BodyFlags.BODYFLAGS_PROXY_STAR_SYSTEM
	if flags & BodyFlags.BODYFLAGS_STAR:
		flags |= BodyFlags.BODYFLAGS_USE_CARDINAL_DIRECTIONS
	if flags & BodyFlags.BODYFLAGS_PLANET:
		flags |= BodyFlags.BODYFLAGS_STAR_ORBITING
		flags |= BodyFlags.BODYFLAGS_USE_CARDINAL_DIRECTIONS
	if flags & BodyFlags.BODYFLAGS_MOON:
		if flags & BodyFlags.BODYFLAGS_SHOW_IN_NAVIGATION_PANEL:
			flags |= BodyFlags.BODYFLAGS_NAVIGATOR_MOON
		if flags & BodyFlags.BODYFLAGS_PLANETARY_MASS_OBJECT:
			flags |= BodyFlags.BODYFLAGS_PLANETARY_MASS_MOON
		else:
			flags |= BodyFlags.BODYFLAGS_NON_PLANETARY_MASS_MOON
		flags |= BodyFlags.BODYFLAGS_USE_CARDINAL_DIRECTIONS
	if flags & BodyFlags.BODYFLAGS_ASTEROID:
		flags |= BodyFlags.BODYFLAGS_STAR_ORBITING
	if flags & BodyFlags.BODYFLAGS_SPACECRAFT:
		flags |= BodyFlags.BODYFLAGS_USE_PITCH_YAW
	body.flags = flags


func _set_orbit_from_table(body: IVBody, parent: IVBody) -> void:
	if body.flags & BodyFlags.BODYFLAGS_TOP:
		return
	var orbit := _orbit_builder.make_orbit_from_data(_table_name, _row, parent)
	body.set_orbit(orbit)


func _set_characteristics_from_table(body: IVBody) -> void:
	var characteristics := body.characteristics
	IVTableData.db_build_dictionary(characteristics, _table_name, _row, characteristics_fields)
	assert(characteristics.has(&"m_radius"), "Table must supply 'm_radius'")
	
	for property in move_from_characteristics_to_property:
		if characteristics.has(property):
			body.set(property, characteristics[property])
			characteristics.erase(property)
	
	var m_radius: float = body.m_radius
	#body.m_radius = m_radius
	#characteristics.erase(&"m_radius")
	if enable_precisions:
		var precisions := IVTableData.get_db_float_precisions(characteristics_fields, _table_name, _row)
		var n_fields := characteristics_fields.size()
		var i := 0
		while i < n_fields:
			var precision: int = precisions[i]
			if precision != -1:
				var field: StringName = characteristics_fields[i]
				var index := StringName("body/characteristics/" + field)
				_real_precisions[index] = precision
			i += 1
	# Assign missing characteristics where we can
	if characteristics.has(&"e_radius"):
		characteristics[&"p_radius"] = 3.0 * m_radius - 2.0 * characteristics[&"e_radius"]
		if enable_precisions:
			var precision := IVTableData.get_db_least_float_precision(_table_name, [&"m_radius", &"e_radius"], _row)
			_real_precisions[&"body/characteristics/p_radius"] = precision
	else:
		body.flags |= BodyFlags.BODYFLAGS_DISPLAY_M_RADIUS
	if !characteristics.has(&"mass"): # moons.tsv has GM but not mass
		assert(IVTableData.db_has_float_value(_table_name, &"GM", _row)) # table test
		# We could in principle calculate mass from GM, but small moon GM is poor
		# estimator. Instead use mean_density if we have it; otherwise, assign INF
		# for unknown mass.
		if characteristics.has(&"mean_density"):
			characteristics[&"mass"] = (PI * 4.0 / 3.0) * characteristics[&"mean_density"] * m_radius ** 3
			if enable_precisions:
				var precision := IVTableData.get_db_least_float_precision(_table_name, [&"m_radius", &"mean_density"], _row)
				_real_precisions[&"body/characteristics/mass"] = precision
		else:
			characteristics[&"mass"] = INF # displays "?"
	if !characteristics.has(&"GM"): # planets.tsv has mass, not GM
		assert(IVTableData.db_has_float_value(_table_name, &"mass", _row))
		characteristics[&"GM"] = G * characteristics[&"mass"]
		if enable_precisions:
			var precision := IVTableData.get_db_float_precision(_table_name, &"mass", _row)
			if precision > 6:
				precision = 6 # limited by G
			_real_precisions[&"body/characteristics/GM"] = precision
	
	# Calculate some missing characteristics, but only if we have sufficient precisions
	if enable_precisions and (!characteristics.has(&"esc_vel") or !characteristics.has(&"surface_gravity")):
		if IVTableData.db_has_float_value(_table_name, &"GM", _row):
			# Use GM to calculate missing esc_vel & surface_gravity, but only
			# if precision > 1.
			var precision := IVTableData.get_db_least_float_precision(_table_name, [&"GM", &"m_radius"], _row)
			if precision > 1:
				var GM: float = characteristics[&"GM"]
				if !characteristics.has(&"esc_vel"):
					characteristics[&"esc_vel"] = sqrt(2.0 * GM / m_radius)
					if enable_precisions:
						_real_precisions[&"body/characteristics/esc_vel"] = precision
				if !characteristics.has(&"surface_gravity"):
					characteristics[&"surface_gravity"] = GM / m_radius ** 2
					if enable_precisions:
						_real_precisions[&"body/characteristics/surface_gravity"] = precision
		
		else: # planet w/ mass
			# Use mass to calculate missing esc_vel & surface_gravity, but only
			# if precision > 1.
			var precision := IVTableData.get_db_least_float_precision(_table_name, [&"mass", &"m_radius"], _row)
			if precision > 1:
				var mass: float = characteristics[&"mass"]
				if precision > 6:
					precision = 6 # limited by G
				if !characteristics.has(&"esc_vel"):
					characteristics[&"esc_vel"] = sqrt(2.0 * G * mass / m_radius)
					if enable_precisions:
						_real_precisions[&"body/characteristics/esc_vel"] = precision
				if !characteristics.has(&"surface_gravity"):
					characteristics[&"surface_gravity"] = G * mass / m_radius ** 2
					if enable_precisions:
						_real_precisions[&"body/characteristics/surface_gravity"] = precision
