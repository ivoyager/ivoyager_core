# table_orbit_builder.gd
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
class_name IVTableOrbitBuilder
extends RefCounted

## Builds [IVOrbit] instances from data tables.

const MIN_ECCENTRICITY_FOR_APSIDAL_PRECESSION := 0.001
const MIN_INCLINATION_FOR_NODAL_PRECESSION := 0.001 # ~0.06 deg


var _oribti_script: Script = IVGlobal.procedural_classes[&"Orbit"]
var _dynamic_orbits: bool = IVCoreSettings.dynamic_orbits
var _ecliptic_rotation: Basis = IVCoreSettings.ecliptic_rotation


var _orbit_fields: Array[StringName] = [
	# table fields dict reset & resused for each row
	
	# common specification
	&"epoch_jd", # optional; hard-coded default if missing
	&"semi_major_axis",
	&"eccentricity",
	&"inclination",
	&"longitude_ascending_node",
	&"argument_of_periapsis", # or longitude_of_periapsis (planet variant)
	&"mean_anomaly_at_epoch",
	&"mean_motion", # optional; calculate from parant GM if missing
	
	# satellite specifics
	&"nodal_period",
	&"apsidal_period",
	&"orbit_reference",
	&"orbit_right_ascension",
	&"orbit_declination",
	
	# planet variants & specifics
	&"longitude_of_periapsis", # = longitude_ascending_node + argument_of_periapsis
	&"semi_major_axis_rate",
	&"eccentricity_rate",
	&"inclination_rate",
	&"longitude_ascending_node_rate",
	&"longitude_of_periapsis_rate",
	&"mean_anomaly_correction_b",
	&"mean_anomaly_correction_c",
	&"mean_anomaly_correction_s",
	&"mean_anomaly_correction_f",
	
]



func make_orbit(table: String, row: int, parent: IVBody) -> IVOrbit:
	# We use a common set of 7 orbital elements always in this order:
	#  [0] a,  semimajor axis (in UnitDef.KM) [TODO: allow negative for hyperbolic!]
	#  [1] e,  eccentricity (0.0 - 1.0)
	#  [2] i,  inclination (rad)
	#  [3] ln, longitude of the ascending node (rad)
	#  [4] ap,  argument of periapsis (rad)
	#  [5] m0, mean anomaly at epoch (rad)
	#  [6] n,  mean motion (rad/s)
	#
	# Elements 0-5 completely define an orbit assuming we know mu
	# (= GM of parent body) and there are no perturbations. Mean motion (n) is
	# specified to account for perturbations or to make a "proper orbit" 
	# (a synthetic orbit stable over millions of years).
	#
	# TODO: Deal with moons (!) that have weird epoch: transform all to J2000.
	#
	# TODO: 
	# We should find a planet data source valid outside of 3000BC-3000AD.
	# Then we can implement 3 user options for planet data: "1800-2050AD (most
	# accurate now)", "3000BC-3000AD", "millions of years (least accurate now)".
	# For now, everything is calculated for 3000BC-3000AD range and (TODO:) we
	# stop applying a, e, i rates outside of 3000BC-3000AD.
	# Or better, dynamically fit to either 1800-2050AD or 3000BC-3000AD range.
	# Alternatively, we could build orbit from an Ephemerides object.
	
	const math := preload("uid://csb570a3u1x1k")
	const OrbitReference := IVOrbit.OrbitReference
	const DAY := IVUnits.DAY
	const RIGHT_ANGLE := PI / 2.0
	const J2000_JD := 2451545.0
	
	var data: Dictionary[StringName, Variant] = {}
	IVTableData.db_build_dictionary(data, table, row, _orbit_fields)
	
	# standard orbital elements [a, e, i, lan, aop, m0, n]
	var a: float = data.get(&"semi_major_axis", 0.0)
	var e: float = data.get(&"eccentricity", NAN)
	var i: float = data.get(&"inclination", NAN)
	var lan: float = data.get(&"longitude_ascending_node", NAN)
	var aop: float = data.get(&"argument_of_periapsis", NAN)
	var m0: float = data.get(&"mean_anomaly_at_epoch", NAN)
	var n: float = data.get(&"mean_motion", NAN)
	# alt
	var lop: float = data.get(&"longitude_of_periapsis", NAN)
	
	assert(a, "Table must specify non-zero 'semi_major_axis'")
	assert(!is_nan(e), "Table must specify 'eccentricity'")
	assert(!is_nan(i), "Table must specify 'inclination'")
	assert(!is_nan(lan), "Table must specify 'longitude_ascending_node'")
	assert(is_nan(aop) != is_nan(lop),
		"Table must specify 'argument_of_periapsis' or 'longitude_of_periapsis' (not both)")
	assert(!is_nan(m0), "Table must specify 'mean_anomaly_at_epoch'")
	
	# lop = lan + (polarity * aop).
	# Note: polarity is never included in Wikipedia equations, but is clearly
	# needed for retrograde orbits in visual diagrams. See:
	# https://en.wikipedia.org/wiki/Longitude_of_periapsis
	var polarity := signf(RIGHT_ANGLE - i) # prograde +1.0; retrograde -1.0
	if is_nan(aop):
		aop = polarity * (lop - lan)
	
	# TODO: Test and warn if table n inconsistant with parent GM...
	if is_nan(n):
		var mu := parent.get_standard_gravitational_parameter()
		assert(mu)
		n = sqrt(mu / (a * a * a))
	
	var epoch_jd: float = data.get(&"epoch_jd", NAN)
	if !is_nan(epoch_jd):
		var epoch_offset := (J2000_JD - epoch_jd) * DAY # J2000
		m0 += n * epoch_offset
		m0 = wrapf(m0, 0.0, TAU)
	
	var elements := Array([a, e, i, lan, aop, m0, n], TYPE_FLOAT, &"", null)
	
	@warning_ignore("unsafe_method_access") # Possible replacement class
	var orbit: IVOrbit = _oribti_script.new()
	orbit.elements_at_epoch = elements
	
	if _dynamic_orbits:
		# Element rates are optional. For planets, we get these as "x_rate" for
		# a, e, i, lan & ap.
		# For moons, we get these as nodal period and apsidal period,
		# corresponding to rotational period of ln & ap, respectively.
		# TODO: in asteroid data, these are g & s, I think...
		# Rate info (if given) must match one or the other format.
		var element_rates: Array[float] # optional
		var m_modifiers: Array[float] # optional (only if element_rates exists)
		
		# planet format
		var a_rate: float = data.get(&"semi_major_axis_rate", NAN)
		var e_rate: float = data.get(&"eccentricity_rate", NAN)
		var i_rate: float = data.get(&"inclination_rate", NAN)
		var lan_rate: float = data.get(&"longitude_ascending_node_rate", NAN)
		var lop_rate: float = data.get(&"longitude_of_periapsis_rate", NAN)
		
		# satellite format
		var nodal_period: float = data.get(&"nodal_period", NAN)
		var apsidal_period: float = data.get(&"apsidal_period", NAN)
		
		if !is_nan(a_rate): # planet format
			assert(!is_nan(e_rate) and !is_nan(i_rate) and !is_nan(lan_rate) and !is_nan(lop_rate)
					and is_nan(nodal_period) and is_nan(apsidal_period),
					"Expected dynamic orbit parameters in either planet format (5 rates) or " +
					"satellite format (nodal_period, apsidal_period)")
			
			var aop_rate := polarity * (lop_rate - lan_rate) # convert rates as elements above
			element_rates = Array([a_rate, e_rate, i_rate, lan_rate, aop_rate], TYPE_FLOAT, &"", null)
			
			# mean anomaly corrections for Jupiter to Pluto (expect all or none)
			var b: float = data.get(&"mean_anomaly_correction_b", NAN)
			var c: float = data.get(&"mean_anomaly_correction_c", NAN)
			var s: float = data.get(&"mean_anomaly_correction_s", NAN)
			var f: float = data.get(&"mean_anomaly_correction_f", NAN)
			if !is_nan(b): # must also have c, s, f
				assert(!is_nan(c) and !is_nan(s) and !is_nan(f),
						"Expected all or none: 'mean_anomaly_correction_b', '_c', '_s' and '_f'")
				m_modifiers = Array([b, c, s, f], TYPE_FLOAT, &"", null)
			else:
				assert(is_nan(c) and is_nan(s) and is_nan(f),
						"Expected all or none: 'mean_anomaly_correction_b', '_c', '_s' and '_f'")
				
		elif !is_nan(nodal_period): # satellite format
			
			assert(!is_nan(apsidal_period) and is_nan(e_rate) and is_nan(i_rate) and is_nan(lan_rate)
					and is_nan(lop_rate),
					"Expected dynamic orbit parameters in either planet format (5 rates) or " +
					"satellite format (nodal_period, apsidal_period)")
			
			# Nearly non-inclined and near-circular orbits lead to tiny nodal
			# and apsidal periods, leading to excessive updates or div/0. In
			# the extreme, lan and aop become technically undefined and updates
			# are irrelevant. We use thresholds here to set undefined periods
			# (=0.0) which will result in 0.0 rates below. 
			if i < MIN_INCLINATION_FOR_NODAL_PRECESSION:
				nodal_period = 0.0
			if e < MIN_ECCENTRICITY_FOR_APSIDAL_PRECESSION:
				apsidal_period = 0.0
			
			# For satellites around an oblique body, apsidal precession is in
			# the direction of orbit and nodal precession is in the opposite
			# direction for prograde orbits, and reverse for retrograde.
			lan_rate = 0.0
			if nodal_period:
				# Positive nodal_period means negative lan_rate, unless retrograde.
				lan_rate = -polarity * TAU / nodal_period
			# Apsidal period determines *longitude* of periapsis rate (lop_rate)...
			# aop_rate = polarity * (lop_rate - lan_rate)
			var aop_rate := -polarity * lan_rate
			if apsidal_period:
				# Positive apsidal_period means positive lop_rate, unless retrograde.
				var prograde_lop_rate := TAU / apsidal_period # = polarity * lop_rate
				aop_rate += prograde_lop_rate
				
				# Sanity test:
				# 1. Observed Earth's prograde Moon w/ apsidal precession in
				#    direction of orbit and nodal precession in opposite
				#    direction, with roughly correct periods.
				# 2. Observed retrograde outer moons of Jupiter w/ apsidal
				#    precessions in direction of orbits (i.e., retrograde) and
				#    nodal precessions in opposite direction (i.e., prograde),
				#    with ~80 year(ish) periods.
				
			if lan_rate or aop_rate:
				element_rates = Array([0.0, 0.0, 0.0, lan_rate, aop_rate], TYPE_FLOAT, &"", null)
		
		else:
			assert(is_nan(e_rate) and is_nan(i_rate) and is_nan(lan_rate) and is_nan(lop_rate)
					and is_nan(nodal_period) and is_nan(apsidal_period),
					"Expected dynamic orbit parameters in either planet format (5 rates) or " +
					"satellite format (nodal_period, apsidal_period)")
		
		# add orbit rates/corrections, if any
		if element_rates:
			orbit.element_rates = element_rates
			if m_modifiers:
				orbit.m_modifiers = m_modifiers
	
	# reference plane (moons!)
	var orbit_reference: int = data.get(&"orbit_reference", -1)
	if orbit_reference == OrbitReference.ORBIT_REFERENCE_EQUATORIAL:
		orbit.reference_normal = parent.get_positive_pole()
	elif orbit_reference == OrbitReference.ORBIT_REFERENCE_LAPLACE:
		var orbit_ra: float = data.get(&"orbit_right_ascension", NAN)
		var orbit_dec: float = data.get(&"orbit_declination", NAN)
		assert(!is_nan(orbit_ra), "Expected 'orbit_right_ascension' for ORBIT_REFERENCE_LAPLACE")
		assert(!is_nan(orbit_dec), "Expected 'orbit_declination' for ORBIT_REFERENCE_LAPLACE")
		var ref_normal := math.convert_spherical2(orbit_ra, orbit_dec)
		ref_normal = _ecliptic_rotation * ref_normal
		orbit.reference_normal = ref_normal
	else:
		assert(orbit_reference == -1 or orbit_reference == OrbitReference.ORBIT_REFERENCE_ECLIPTIC)
	
	return orbit
