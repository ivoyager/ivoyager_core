# body_builder.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2023 Charlie Whitfield
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
class_name IVBodyBuilder
extends RefCounted

## Builds [IVBody] instances from data tables.


const ECLIPTIC_Z := Vector3(0.0, 0.0, 1.0)
const G := IVUnits.GRAVITATIONAL_CONSTANT
const BodyFlags := IVEnums.BodyFlags

var enable_precisions := IVCoreSettings.enable_precisions

var characteristics_fields: Array[StringName] = [
	# Added to characteristics only if exists in table.
	&"symbol",
	&"hud_name",
	&"body_class",
	&"model_type",
	&"light_type",
	&"omni_light_type",
	&"file_prefix",
	&"rings_file_prefix",
	&"rings_inner_radius",
	&"rings_outer_radius",
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

var flag_fields := {
	BodyFlags.IS_STAR : &"star",
	BodyFlags.IS_PLANET : &"planet",
	BodyFlags.IS_TRUE_PLANET : &"true_planet",
	BodyFlags.IS_DWARF_PLANET : &"dwarf_planet",
	BodyFlags.IS_MOON : &"moon",
	BodyFlags.IS_TIDALLY_LOCKED : &"tidally_locked",
	BodyFlags.IS_AXIS_LOCKED : &"axis_locked",
	BodyFlags.TUMBLES_CHAOTICALLY : &"tumbles_chaotically",
	BodyFlags.HAS_ATMOSPHERE : &"atmosphere",
	BodyFlags.IS_GAS_GIANT : &"gas_giant",
	BodyFlags.IS_ASTEROID : &"asteroid",
	BodyFlags.IS_COMET : &"comet",
	BodyFlags.IS_SPACECRAFT : &"spacecraft",
	BodyFlags.IS_PLANETARY_MASS_OBJECT : &"planetary_mass_object",
	BodyFlags.SHOW_IN_NAV_PANEL : &"show_in_nav_panel",
}


var BodyScript: Script

var _orbit_builder: IVOrbitBuilder
var _composition_builder: IVCompositionBuilder
var _table_name: StringName
var _row: int
var _real_precisions := {}


func _ivcore_init() -> void:
	BodyScript = IVGlobal.procedural_classes[&"Body"]
	_orbit_builder = IVGlobal.program[&"OrbitBuilder"]
	_composition_builder = IVGlobal.program.get(&"CompositionBuilder")


func build_from_table(table_name: String, row: int, parent: IVBody) -> IVBody: # Main thread!
	_table_name = table_name
	_row = row
	@warning_ignore("unsafe_method_access")
	var body: IVBody = BodyScript.new()
	body.name = IVTableData.get_db_entity_name(table_name, row)
	_set_flags_from_table(body, parent)
	_set_orbit_from_table(body, parent)
	_set_characteristics_from_table(body)
	if _composition_builder:
		_composition_builder.add_compositions_from_table(body, table_name, row)
	if enable_precisions:
		body.characteristics[&"real_precisions"] = _real_precisions
		_real_precisions = {} # reset for next body
	return body


func _set_flags_from_table(body: IVBody, parent: IVBody) -> void:
	# flags
	var flags := IVTableData.db_get_flags(flag_fields, _table_name, _row)
	# All below are constructed (non-table) flags.
	if !parent:
		flags |= BodyFlags.IS_TOP # will add self to IVGlobal.top_bodies
		flags |= BodyFlags.IS_PRIMARY_STAR
		flags |= BodyFlags.PROXY_STAR_SYSTEM
	if flags & BodyFlags.IS_STAR:
		flags |= BodyFlags.NEVER_SLEEP
		flags |= BodyFlags.USE_CARDINAL_DIRECTIONS
	if flags & BodyFlags.IS_PLANET:
		flags |= BodyFlags.IS_STAR_ORBITING
		flags |= BodyFlags.NEVER_SLEEP
		flags |= BodyFlags.USE_CARDINAL_DIRECTIONS
	if flags & BodyFlags.IS_MOON:
		if flags & BodyFlags.SHOW_IN_NAV_PANEL:
			flags |= BodyFlags.IS_NAVIGATOR_MOON
		if flags & BodyFlags.IS_PLANETARY_MASS_OBJECT:
			flags |= BodyFlags.IS_PLANETARY_MASS_MOON
		else:
			flags |= BodyFlags.IS_NON_PLANETARY_MASS_MOON
		flags |= BodyFlags.USE_CARDINAL_DIRECTIONS
	if flags & BodyFlags.IS_ASTEROID:
		flags |= BodyFlags.IS_STAR_ORBITING
		flags |= BodyFlags.NEVER_SLEEP
	if flags & BodyFlags.IS_SPACECRAFT:
		flags |= BodyFlags.USE_PITCH_YAW
	body.flags = flags


func _set_orbit_from_table(body: IVBody, parent: IVBody) -> void:
	if body.flags & BodyFlags.IS_TOP:
		return
	var orbit := _orbit_builder.make_orbit_from_data(_table_name, _row, parent)
	body.set_orbit(orbit)


func _set_characteristics_from_table(body: IVBody) -> void:
	var characteristics := body.characteristics
	IVTableData.db_build_dictionary(characteristics, characteristics_fields, _table_name, _row)
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
		body.flags |= BodyFlags.DISPLAY_M_RADIUS
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

