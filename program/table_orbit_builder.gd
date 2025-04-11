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
var _o: Dictionary[StringName, float] = { # resused for each table row
	&"semi_major_axis" : NAN,
	&"eccentricity" : NAN,
	&"inclination" : NAN,
	&"longitude_ascending_node" : NAN,
	&"argument_of_periapsis" : NAN,
	&"mean_anomaly_at_epoch" : NAN,
	&"mean_motion" : NAN,
	&"semi_major_axis_rate" : NAN,
	&"eccentricity_rate" : NAN,
	&"inclination_rate" : NAN,
	&"longitude_ascending_node_rate" : NAN,
	&"argument_of_periapsis_rate" : NAN,
	&"mean_anomaly_correction_b" : NAN,
	&"mean_anomaly_correction_c" : NAN,
	&"mean_anomaly_correction_s" : NAN,
	&"mean_anomaly_correction_f" : NAN,
	&"nodal_period" : NAN,
	&"apsidal_period" : NAN,
	&"epoch_jd" : NAN,
	&"orbit_right_ascension" : NAN,
	&"orbit_declination" : NAN,
}



func make_orbit(table: String, row: int, parent: IVBody) -> IVOrbit:
	# We use a common set of 7 orbital elements always in this order:
	#  [0] a,  semimajor axis (in UnitDef.KM) [TODO: allow negative for hyperbolic!]
	#  [1] e,  eccentricity (0.0 - 1.0)
	#  [2] i,  inclination (rad)
	#  [3] Om, longitude of the ascending node (rad)
	#  [4] w,  argument of periapsis (rad)
	#  [5] M0, mean anomaly at epoch (rad)
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
	
	IVTableData.db_build_dictionary(_o, table, row, _o.keys())
	var orbit_reference := IVTableData.get_db_int(table, &"orbit_reference", row)

	# standard orbital elements [a, e, i, Om, w, M0, n]
	var a := _o.semi_major_axis
	var e := _o.eccentricity
	var i := _o.inclination
	var Om := _o.longitude_ascending_node
	var w := _o.argument_of_periapsis
	var M0 := _o.mean_anomaly_at_epoch
	var n := _o.mean_motion
	
	assert(!is_nan(a))
	assert(!is_nan(e))
	assert(!is_nan(i))
	assert(!is_nan(Om))
	assert(!is_nan(w))
	assert(!is_nan(M0))
	
	if is_nan(n):
		var mu := parent.get_standard_gravitational_parameter()
		assert(mu)
		n = sqrt(mu / (a * a * a))
	
	var epoch_jd := _o.epoch_jd
	if !is_nan(epoch_jd):
		var epoch_offset := (2451545.0 - epoch_jd) * DAY # J2000
		M0 += n * epoch_offset
		M0 = wrapf(M0, 0.0, TAU)
	
	var elements := Array([a, e, i, Om, w, M0, n], TYPE_FLOAT, &"", null)
	@warning_ignore("unsafe_method_access") # Possible replacement class
	var orbit: IVOrbit = _oribti_script.new()
	orbit.elements_at_epoch = elements
	
	if _dynamic_orbits:
		# Element rates are optional. For planets, we get these as "x_rate" for
		# a, e, i, Om & w.
		# For moons, we get these as nodal period and apsidal period,
		# corresponding to rotational period of Om & w, respectively.
		# TODO: in asteroid data, these are g & s, I think...
		# Rate info (if given) must match one or the other format.
		var element_rates: Array[float] # optional
		var m_modifiers: Array[float] # optional
		
		# planet format
		var a_rate := _o.semi_major_axis_rate
		var e_rate := _o.eccentricity_rate
		var i_rate := _o.inclination_rate
		var Om_rate := _o.longitude_ascending_node_rate # nodal precession
		var w_rate := _o.argument_of_periapsis_rate # apsidal precession
		
		# satellite format
		var nodal_period := _o.nodal_period # nodal precession (possibly w/ sign flip)
		var apsidal_period := _o.apsidal_period # apsidal precession
		
		if !is_nan(a_rate): # planet format
			assert(!is_nan(e_rate) and !is_nan(i_rate) and !is_nan(Om_rate) and !is_nan(w_rate))
			element_rates = Array([a_rate, e_rate, i_rate, Om_rate, w_rate], TYPE_FLOAT, &"", null)
			
			# mean anomaly corrections for Jupiter to Pluto.
			var b := _o.mean_anomaly_correction_b
			if !is_nan(b): # must also have c, s, f
				var c := _o.mean_anomaly_correction_c
				var s := _o.mean_anomaly_correction_s
				var f := _o.mean_anomaly_correction_f
				assert(!is_nan(c) and !is_nan(s) and !is_nan(f))
				m_modifiers = Array([b, c, s, f], TYPE_FLOAT, &"", null)
				
		elif !is_nan(nodal_period): # satellite format
			assert(!is_nan(apsidal_period)) # both or neither
			# For satellites around an oblique body, apsidal precession is in
			# the direction of orbit and nodal precession is in the opposite
			# direction. (Hence, the sign flip for Om_rate.)
			# Some values are tiny leading to div/0 or excessive updating. These
			# correspond to near-circular and/or non-inclined orbits, where Om
			# and w are technically undefined and updates are irrelevant.
			if i < MIN_INCLINATION_FOR_NODAL_PRECESSION:
				nodal_period = 0.0
			if e < MIN_ECCENTRICITY_FOR_APSIDAL_PRECESSION:
				apsidal_period = 0.0
			var orbit_sign := signf(RIGHT_ANGLE - i) # prograde +1.0; retrograde -1.0
			Om_rate = 0.0
			w_rate = 0.0
			if nodal_period != 0.0:
				# FIXME: Looks like this is giving the wrong polarity in Jupiter
				# moons. I.e., the orbit plane is precessing in the same direction
				# as orbit.
				Om_rate = -orbit_sign * TAU / nodal_period # opposite to orbit!
			if apsidal_period != 0.0:
				w_rate = orbit_sign * TAU / apsidal_period
			if Om_rate or w_rate:
				element_rates = Array([0.0, 0.0, 0.0, Om_rate, w_rate], TYPE_FLOAT, &"", null)
		
		else:
			assert(is_nan(e_rate) and is_nan(i_rate) and is_nan(Om_rate) and is_nan(w_rate)
					and is_nan(apsidal_period) and is_nan(nodal_period),
					"Expected dynamic orbit elements in either planet format (5 rates) or " +
					"satellite format (nodal_period, apsidal_period)")
		
		# add orbit rates/corrections, if any
		if element_rates:
			orbit.element_rates = element_rates
			if m_modifiers:
				orbit.m_modifiers = m_modifiers
	
	# reference plane (moons!)
	if orbit_reference == OrbitReference.ORBIT_REFERENCE_EQUATORIAL:
		orbit.reference_normal = parent.get_positive_pole()
	elif orbit_reference == OrbitReference.ORBIT_REFERENCE_LAPLACE:
		assert(!is_nan(_o.orbit_right_ascension))
		assert(!is_nan(_o.orbit_declination))
		var ref_normal := math.convert_spherical2(_o.orbit_right_ascension, _o.orbit_declination)
		ref_normal = _ecliptic_rotation * ref_normal
		orbit.reference_normal = ref_normal
	else:
		assert(orbit_reference == OrbitReference.ORBIT_REFERENCE_ECLIPTIC or orbit_reference == -1)
		
	# reset for next orbit build
	for field: StringName in _o:
		_o[field] = NAN
	
	return orbit
