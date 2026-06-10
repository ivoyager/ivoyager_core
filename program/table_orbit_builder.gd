# table_orbit_builder.gd
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
class_name IVTableOrbitBuilder
extends RefCounted

## Builds [IVOrbit] and [IVRealPlanetOrbit] instances from data tables.
##
## To use [IVRealPlanetOrbit] class, set [member use_real_planet_orbits] here.
## Otherwise, all orbits are created as [IVOrbit] instances with evolution of
## precessing elements only.

## Minimum inclination (radians) for which a nodal period is treated as
## meaningful when computing precession.
var min_inclination_for_nodal_period := 0.001 # ~0.06 deg
## Minimum eccentricity for which an apsidal period is treated as meaningful.
var min_eccentricity_for_apsidal_period := 0.001

## Set true to implement [IVRealPlanetOrbit] subclass for planets with data
## table [param real_planet_orbit] == TRUE.
var use_real_planet_orbits := false

## Table column names read by [method make_orbit] when constructing an orbit.
## Missing fields or values are simply absent from the working dictionary.
var orbit_fields: Array[StringName] = [
	# Missing table fields or values will be absent in the data dictionary.
	
	# alternative epoch (IVAstronomy.EPOCH_JULIAN_DAY if missing)
	&"epoch_jd",
	
	# reference plane (ecliptic if missing)
	&"reference_plane_type",
	&"orbit_right_ascension",
	&"orbit_declination",
	
	# defining elements (assumed at epoch)
	&"semi_parameter",
	&"eccentricity",
	&"inclination",
	&"longitude_ascending_node",
	&"argument_periapsis",
	&"time_periapsis",
	&"orbit_gravitational_parameter", # if provided, cross check with parent GM
	
	# alternative elements
	&"semi_major_axis",
	&"longitude_periapsis",
	&"mean_anomaly_at_epoch",
	&"mean_motion", # sidereal (dL/dt) convention; cross check with parent GM
	
	# precession data variations
	&"longitude_ascending_node_rate",
	&"argument_periapsis_rate",
	&"longitude_periapsis_rate",
	&"nodal_rate",
	&"apsidal_rate",
	&"nodal_period",
	&"apsidal_period",
	
	# IVRealPlanetOrbit specs
	&"real_planet_orbit",
	&"semi_major_axis_rate",
	&"eccentricity_rate",
	&"inclination_rate",
	&"mean_anomaly_correction_b",
	&"mean_anomaly_correction_c",
	&"mean_anomaly_correction_s",
	&"mean_anomaly_correction_f",
	&"validity_begin",
	&"validity_end",
	
	# only for warnings/asserts
	&"name",
	
]



## Builds and returns an [IVOrbit] (or [IVRealPlanetOrbit] subclass when
## [member use_real_planet_orbits] is enabled and the row's
## [code]real_planet_orbit[/code] flag is set) from row [param row] of
## [param table], parented gravitationally to [param parent].
func make_orbit(table: String, row: int, parent: IVBody) -> IVOrbit:
	const ReferencePlane := IVOrbit.ReferencePlane
	const DAY := IVUnits.DAY
	const RIGHT_ANGLE := PI / 2.0
	const EPOCH_JULIAN_DAY := IVAstronomy.EPOCH_JULIAN_DAY
	const WARNING_EXCESS_BARYCENTER_GM := 0.16 # ballpark only test; Pluto moons ~0.11-0.15
	const WARNING_SHORTFALL_BARYCENTER_GM := -0.07 # -0.01 passes all but a few odd moons
	const MIN_INCLINATION := IVOrbit.MIN_INCLINATION
	
	var data: Dictionary[StringName, Variant] = {}
	IVTableData.db_build_dictionary(data, table, row, orbit_fields)
	
	if use_real_planet_orbits and data.get(&"real_planet_orbit"):
		return _make_real_planet_orbit(data)
	
	# reference plane type and basis
	var reference_plane_type: int = data.get(&"reference_plane_type",
			ReferencePlane.REFERENCE_PLANE_ECLIPTIC) # default ecliptic
	# For equatorial and Laplace reference planes, the basis x-axis (the zero
	# point for longitude of the ascending node) is the ascending node of the
	# reference plane on the ICRF equator, following JPL satellite mean
	# elements convention (https://ssd.jpl.nasa.gov/sats/elem/).
	var reference_basis := Basis.IDENTITY
	if reference_plane_type == ReferencePlane.REFERENCE_PLANE_EQUATORIAL:
		assert(!data.has(&"orbit_right_ascension"),
			"'orbit_right_ascension' specified for non-Laplace orbit")
		assert(!data.has(&"orbit_declination"),
			"'orbit_declination' specified for non-Laplace orbit")
		var positive_axis := parent.get_positive_axis()
		reference_basis = IVAstronomy.get_basis_from_z_axis_and_icrf_equator_node(positive_axis)
	elif reference_plane_type == ReferencePlane.REFERENCE_PLANE_LAPLACE:
		assert(data.has(&"orbit_right_ascension"),
				"Expected 'orbit_right_ascension' for ORBIT_REFERENCE_LAPLACE")
		assert(data.has(&"orbit_declination"),
				"Expected 'orbit_declination' for ORBIT_REFERENCE_LAPLACE")
		var orbit_ra: float = data[&"orbit_right_ascension"]
		var orbit_dec: float = data[&"orbit_declination"]
		var laplace_north := IVAstronomy.get_ecliptic_unit_vector_from_equatorial_angles(
				orbit_ra, orbit_dec)
		reference_basis = IVAstronomy.get_basis_from_z_axis_and_icrf_equator_node(laplace_north)
	else:
		assert(!data.has(&"orbit_right_ascension"),
			"'orbit_right_ascension' specified for non-Laplace orbit")
		assert(!data.has(&"orbit_declination"),
			"'orbit_declination' specified for non-Laplace orbit")
	
	# defining (at epoch) elements
	
	var semi_parameter: float = data.get(&"semi_parameter", NAN)
	var eccentricity: float = data.get(&"eccentricity", NAN)
	var inclination: float = data.get(&"inclination", NAN)
	var longitude_ascending_node: float = data.get(&"longitude_ascending_node", NAN) # at epoch
	var argument_periapsis: float = data.get(&"argument_periapsis", NAN) # at epoch
	var time_periapsis: float = data.get(&"time_periapsis", NAN)
	assert(eccentricity >= 0.0, "Table must specify 'eccentricity' >= 0.0")
	assert(inclination >= MIN_INCLINATION and inclination <= PI,
			"Table must specify 'inclination'")
	assert(!is_nan(longitude_ascending_node), "Table must specify 'longitude_ascending_node'")
	
	# alternative/optional derivations
	
	if data.has(&"semi_major_axis"):
		assert(is_nan(semi_parameter), "Don't specify 'semi_parameter' AND 'semi_major_axis'")
		assert(eccentricity < 1.0, "Expected 'semi_parameter' for parabolic or hyperbolic orbit")
		semi_parameter = data[&"semi_major_axis"] * (1.0 - eccentricity * eccentricity)
	assert(!is_nan(semi_parameter), "Table must specify 'semi_parameter' or 'semi_major_axis'")
	
	if data.has(&"longitude_periapsis"):
		assert(is_nan(argument_periapsis),
				"Don't specify 'argument_periapsis' AND 'longitude_periapsis'")
		argument_periapsis = data[&"longitude_periapsis"] - longitude_ascending_node
	assert(!is_nan(argument_periapsis),
			"Table must specify 'argument_periapsis' or 'longitude_periapsis'")
	
	# precessions; either "rates" or "periods" (format must be consistant for this row)
	
	var longitude_ascending_node_rate := 0.0
	var argument_periapsis_rate := 0.0
	
	if data.has(&"longitude_ascending_node_rate"):
		assert(data.has(&"argument_periapsis_rate") or data.has(&"longitude_periapsis_rate"))
		assert(!data.has(&"nodal_period"))
		assert(!data.has(&"apsidal_period"))
		longitude_ascending_node_rate = data[&"longitude_ascending_node_rate"]
		if data.has(&"argument_periapsis_rate"):
			argument_periapsis_rate = data[&"argument_periapsis_rate"]
		else:
			argument_periapsis_rate = data[&"longitude_periapsis_rate"] - longitude_ascending_node_rate
	
	if data.has(&"nodal_period"):
		assert(data.has(&"apsidal_period"))
		assert(!data.has(&"longitude_ascending_node_rate"))
		assert(!data.has(&"argument_periapsis_rate"))
		assert(!data.has(&"longitude_periapsis_rate"))
		var nodal_period: float = data[&"nodal_period"] # zeros ok (disables rate)
		var apsidal_period: float = data[&"apsidal_period"] # zeros ok (disables rate)
		if inclination < min_inclination_for_nodal_period:
			nodal_period = 0.0 # disables
		if eccentricity < min_eccentricity_for_apsidal_period:
			apsidal_period = 0.0 # disables
		var retrograde := inclination > RIGHT_ANGLE
		var rates := _get_precession_rates_from_periods(nodal_period, apsidal_period, retrograde)
		longitude_ascending_node_rate = rates[0]
		argument_periapsis_rate = rates[1]
	
	# The advance rate of the periapsis along the direction of orbital motion,
	# in inertial terms (dϖ/dt for a prograde orbit). Needed to convert
	# 'mean_motion' below from source-data convention to mean anomaly rate.
	var periapsis_drift_rate := argument_periapsis_rate
	if inclination < RIGHT_ANGLE:
		periapsis_drift_rate += longitude_ascending_node_rate
	else:
		periapsis_drift_rate -= longitude_ascending_node_rate
	
	var gravitational_parameter := parent.get_gravitational_parameter()
	if data.has(&"orbit_gravitational_parameter"):
		var orbit_gm: float = data[&"orbit_gravitational_parameter"]
		var excess_gm := (orbit_gm - gravitational_parameter) / gravitational_parameter
		if excess_gm > WARNING_EXCESS_BARYCENTER_GM or excess_gm < WARNING_SHORTFALL_BARYCENTER_GM:
			push_warning("%s 'orbit_gravitational_parameter' (%s) differs from parent GM (%s)" %
					[data[&"name"], String.num_scientific(orbit_gm),
					String.num_scientific(gravitational_parameter)]
					+ " more than expected")
		gravitational_parameter = orbit_gm
	if data.has(&"mean_motion"):
		assert(!data.has(&"orbit_gravitational_parameter"),
				"Don't specify 'mean_motion' AND 'orbit_gravitational_parameter'")
		assert(eccentricity < 1.0, "'mean_motion' specified for parabolic or hyperbolic orbit")
		# Table 'mean_motion' is the sidereal rate (of mean longitude, dL/dt),
		# following source-data convention (e.g., JPL satellite mean elements).
		# Internal Kepler propagation needs the mean anomaly rate dM/dt, which
		# is slower by the periapsis drift rate (equal if no apsidal precession).
		var n: float = data[&"mean_motion"] - periapsis_drift_rate
		var a := semi_parameter / (1.0 - eccentricity * eccentricity)
		var derived_gm := a ** 3 * n ** 2
		var excess_gm := (derived_gm - gravitational_parameter) / gravitational_parameter
		if excess_gm > WARNING_EXCESS_BARYCENTER_GM or excess_gm < WARNING_SHORTFALL_BARYCENTER_GM:
			push_warning("%s derived orbit GM (%s) differs from parent GM (%s)" %
					[data[&"name"], String.num_scientific(derived_gm),
					String.num_scientific(gravitational_parameter)]
					+ " more than expected")
		gravitational_parameter = derived_gm
	
	if data.has(&"mean_anomaly_at_epoch"):
		assert(is_nan(time_periapsis),
				"Don't specify 'time_periapsis' AND 'mean_anomaly_at_epoch'")
		assert(eccentricity < 1.0,
				"'mean_anomaly_at_epoch' specified for parabolic or hyperbolic orbit")
		var m0: float = data[&"mean_anomaly_at_epoch"]
		var a := semi_parameter / (1.0 - eccentricity * eccentricity)
		var n := sqrt(gravitational_parameter / a ** 3)
		time_periapsis = IVOrbit.modulo_time_periapsis_elliptic(-m0 / n, n)
	assert(!is_nan(time_periapsis),
			"Table must specify 'time_periapsis' or 'mean_anomaly_at_epoch'")
	
	# convert to internal J2000 epoch
	
	var epoch_delta := 0.0
	if data.has(&"epoch_jd") and data[&"epoch_jd"] != EPOCH_JULIAN_DAY:
		epoch_delta = (data[&"epoch_jd"] - EPOCH_JULIAN_DAY) * DAY
	
		# time_periapsis
		time_periapsis += epoch_delta
		if eccentricity < 1.0:
			var a := semi_parameter / (1.0 - eccentricity * eccentricity)
			var n := sqrt(gravitational_parameter / a ** 3)
			time_periapsis = IVOrbit.modulo_time_periapsis_elliptic(time_periapsis, n)
	
		# Table Ω and ω are values at epoch_jd; internal "at epoch" values are
		# anchored at J2000 (rate propagation in IVOrbit runs from J2000), so
		# back-propagate by epoch_delta.
		longitude_ascending_node -= epoch_delta * longitude_ascending_node_rate
		longitude_ascending_node = fposmod(longitude_ascending_node, TAU)
		argument_periapsis -= epoch_delta * argument_periapsis_rate
		argument_periapsis = fposmod(argument_periapsis, TAU)
	
	# standard orbit
	var orbit := IVOrbit.create_from_elements(
		reference_plane_type,
		reference_basis,
		semi_parameter,
		eccentricity,
		inclination,
		longitude_ascending_node,
		longitude_ascending_node_rate,
		argument_periapsis,
		argument_periapsis_rate,
		time_periapsis,
		gravitational_parameter
	)
	
	return orbit


func _get_precession_rates_from_periods(nodal_period: float, apsidal_period: float,
		retrograde: bool) -> Array[float]:
	# Moons have precessions expressed as positive value periods (except a few
	# zeros). We should expect apsidal precession in the direction of orbit and
	# nodal in the opposite direction.
	#
	# Period meanings follow JPL satellite mean elements
	# (https://ssd.jpl.nasa.gov/sats/elem/): 'apsidal_period' (Pw) is the cycle
	# period of the argument of periapsis ω itself — measured from the moving
	# node, so nodal regression is already folded in (which is why the Moon's
	# Pw is 5.997 yr while its longitude-of-periapsis ϖ cycles in 8.85 yr).
	# 'nodal_period' (Pnode) is the cycle period of Ω.
	#
	# Precessions tests:
	# 1. Observe Earth's prograde (counter-clockwise-orbiting) Moon with apsidal
	#    precession in direction of orbit (counter-clockwise) and nodal
	#    precession in opposite direction (clockwise), with roughly ~6 and ~18.5
	#    year periods (respectively).
	# 2. Observe retrograde (clockwise orbiting) outer moons of Jupiter with
	#    apsidal precessions in direction of orbits (clockwise) and nodal
	#    precessions in opposite direction (counter-clockwise), with roughly
	#    ~80 year(ish) periods.
	var lan_rate := -TAU / nodal_period if nodal_period else 0.0
	var ap_rate := TAU / apsidal_period if apsidal_period else 0.0
	if retrograde:
		# This is confusing, but longitude of the node is measured in the
		# reference plane, so needs sign flip for retrograde. However, argument
		# of periapsis is measured in the orbit plane, so doesn't need flip.
		# In any case, it passes tests above...
		return [-lan_rate, ap_rate]
	return [lan_rate, ap_rate]



func _make_real_planet_orbit(data: Dictionary[StringName, Variant]) -> IVOrbit:
	# Requires all fields in the create signature, except b, f, c, s corrections.
	const REFERENCE_PLANE_ECLIPTIC := IVOrbit.ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	const EPOCH_JULIAN_DAY := IVAstronomy.EPOCH_JULIAN_DAY
	
	var semi_major_axis: float = data.get(&"semi_major_axis", NAN)
	var semi_major_axis_rate: float = data.get(&"semi_major_axis_rate", NAN)
	var eccentricity: float = data.get(&"eccentricity", NAN)
	var eccentricity_rate: float = data.get(&"eccentricity_rate", NAN)
	var inclination: float = data.get(&"inclination", NAN)
	var inclination_rate: float = data.get(&"inclination_rate", NAN)
	var longitude_ascending_node: float = data.get(&"longitude_ascending_node", NAN)
	var longitude_ascending_node_rate: float = data.get(&"longitude_ascending_node_rate", NAN)
	var longitude_periapsis: float = data.get(&"longitude_periapsis", NAN)
	var longitude_periapsis_rate: float = data.get(&"longitude_periapsis_rate", NAN)
	var mean_anomaly_at_epoch: float = data.get(&"mean_anomaly_at_epoch", NAN)
	var mean_motion: float = data.get(&"mean_motion", NAN)
	var mean_anomaly_correction_b: float = data.get(&"mean_anomaly_correction_b", 0.0)
	var mean_anomaly_correction_f: float = data.get(&"mean_anomaly_correction_f", 0.0)
	var mean_anomaly_correction_c: float = data.get(&"mean_anomaly_correction_c", 0.0)
	var mean_anomaly_correction_s: float = data.get(&"mean_anomaly_correction_s", 0.0)
	var validity_begin: float = data.get(&"validity_begin", NAN)
	var validity_end: float = data.get(&"validity_end", NAN)
	
	assert(data.get(&"reference_plane_type", REFERENCE_PLANE_ECLIPTIC) == REFERENCE_PLANE_ECLIPTIC)
	assert(data.get(&"epoch_jd", EPOCH_JULIAN_DAY) == EPOCH_JULIAN_DAY)
	
	# Create method has all other asserts we need.
	
	var orbit := IVRealPlanetOrbit.create_real_planet_orbit(
		semi_major_axis,
		semi_major_axis_rate,
		eccentricity,
		eccentricity_rate,
		inclination,
		inclination_rate,
		longitude_ascending_node,
		longitude_ascending_node_rate,
		longitude_periapsis,
		longitude_periapsis_rate,
		mean_anomaly_at_epoch,
		mean_motion,
		mean_anomaly_correction_b,
		mean_anomaly_correction_f,
		mean_anomaly_correction_c,
		mean_anomaly_correction_s,
		validity_begin,
		validity_end,
	)
	
	return orbit
