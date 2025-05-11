# real_planet_orbit.gd
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
class_name IVRealPlanetOrbit
extends IVOrbit

## Extended IVOrbit class that implements JPL-specified corrections to
## approximate real planet positions.
##
## This subclass can be used for realistic (though still approximate) planet
## positions for date ranges 3000 BC - 3000 AD or 1800 AD - 2050 AD following
## [url]https://ssd.jpl.nasa.gov/planets/approx_pos.html[/url].[br][br]
##
## It's probably not needed for most game usage and limits the flexibility of
## the IVOrbit class. Orbit elements cannot be set for this subclass at editor
## runtime.[br][br]
##
## Use of this subclass is allowed by setting
## [code]IVTableOrbitBuilder.allow_real_planet_orbits = true[/code] and data
## table field value [param use_real_planet_orbit] = TRUE. This will implement
## table fields: "semi_major_axis_rate", "eccentricity_rate", "inclination_rate"
## and "mean_anomaly_correction_b", "..._c", "..._s" and "..._f".[br][br]
## 
## We changed implementation slightly from the JPL reference page. In
## particular, we use b, c, s and f corrections to evolve time of periapsis
## passage ([member IVOrbit.time_periapsis], an osculating element) rather
## than correcting the mean anomoly (M) during position calculation. By doing
## it this way, the osculating orbital elements correctly determine the orbit
## state at all times.[br][br]
##
## Our data table [b]planets.tsv[/b] also contains corrections for Pluto that
## were subsequently removed from the JPL page. (It's censorship, I say!)


const PERSIST_PROPERTIES2: Array[StringName] = [
	&"m_correction_b",
	&"m_correction_f",
	&"m_correction_c",
	&"m_correction_s",
	&"validity_begin",
	&"validity_end",
	
	&"_semi_major_axis_at_epoch",
	&"_semi_major_axis_rate",
	&"_eccentricity_at_epoch",
	&"_eccentricity_rate",
	&"_inclination_at_epoch",
	&"_inclination_rate",
	&"_time_periapsis_at_epoch",
]

# dummy vars
## a₀ for orbit evolution.
var semi_major_axis_at_epoch: float: get = get_semi_major_axis_at_epoch
## da/dt.
var semi_major_axis_rate: float: get = get_semi_major_axis_rate
## e₀ for orbit evolution.
var eccentricity_at_epoch: float: get = get_eccentricity_at_epoch
## de/dt.
var eccentricity_rate: float: get = get_eccentricity_rate
## i₀ for orbit evolution.
var inclination_at_epoch: float: get = get_inclination_at_epoch
## di/dt.
var inclination_rate: float: get = get_inclination_rate
## (t₀)₀ for orbit evolution (t₀ without M corrections).
var time_periapsis_at_epoch: float: get = get_time_periapsis_at_epoch

# real
var m_correction_b: float ## M correction (b) for outer planets, Jupiter - Pluto.
var m_correction_f: float ## M correction (f) for outer planets, Jupiter - Pluto.
var m_correction_c: float ## M correction (c) for outer planets, Jupiter - Pluto.
var m_correction_s: float ## M correction (s) for outer planets, Jupiter - Pluto.
var validity_begin: float ## 3000 BC or 1800 AD, depending on data set.
var validity_end: float ## 3000 AD or 2050 AD, depending on data set.

# private
var _semi_major_axis_at_epoch: float
var _semi_major_axis_rate: float
var _eccentricity_at_epoch: float
var _eccentricity_rate: float
var _inclination_at_epoch: float
var _inclination_rate: float
var _time_periapsis_at_epoch: float


# TODO: setters, getters attacments above


## Generator signature matches planet specification in data table planets.tsv.
@warning_ignore("shadowed_variable", "shadowed_variable_base_class")
static func create_real_planet_orbit(
		semi_major_axis: float,
		semi_major_axis_rate: float,
		eccentricity: float,
		eccentricity_rate: float,
		inclination: float,
		inclination_rate: float,
		longitude_ascending_node: float,
		longitude_ascending_node_rate: float,
		longitude_periapsis: float,
		longitude_periapsis_rate: float,
		mean_anomaly_at_epoch: float,
		mean_motion: float,
		mean_anomaly_correction_b: float,
		mean_anomaly_correction_f: float,
		mean_anomaly_correction_c: float,
		mean_anomaly_correction_s: float,
		validity_begin: float,
		validity_end: float,
	) -> IVRealPlanetOrbit:
	
	const RIGHT_ANGLE := PI / 2
	
	assert(semi_major_axis > 0.0, "IVRealPlanetOrbit requires 'semi_major_axis' > 0.0")
	assert(eccentricity >= 0.0 and eccentricity < 1.0,
		"IVRealPlanetOrbit requires 'eccentricity' >= 0.0 and < 1.0")
	assert(inclination >= MIN_INCLINATION and inclination <= PI and inclination != RIGHT_ANGLE,
			"IVRealPlanetOrbit requires allowed 'inclination' value")
	assert(!is_nan(longitude_ascending_node),
			"IVRealPlanetOrbit requires 'longitude_ascending_node'")
	assert(!is_nan(longitude_periapsis), "IVRealPlanetOrbit requires 'longitude_periapsis'")
	assert(!is_nan(mean_anomaly_at_epoch), "IVRealPlanetOrbit requires 'mean_anomaly_at_epoch'")
	assert(mean_motion > 0.0, "IVRealPlanetOrbit requires 'mean_motion' > 0.0")
	assert(!is_nan(semi_major_axis_rate), "IVRealPlanetOrbit requires 'semi_major_axis_rate'")
	assert(!is_nan(eccentricity_rate), "IVRealPlanetOrbit requires 'eccentricity_rate'")
	assert(!is_nan(inclination_rate), "IVRealPlanetOrbit requires 'inclination_rate'")
	assert(!is_nan(longitude_ascending_node_rate),
			"IVRealPlanetOrbit requires 'longitude_ascending_node_rate'")
	assert(!is_nan(longitude_periapsis_rate),
			"IVRealPlanetOrbit requires 'longitude_periapsis_rate'")
	assert(!is_nan(mean_anomaly_correction_b), "Use 0.0 for missing")
	assert(!is_nan(mean_anomaly_correction_f), "Use 0.0 for missing")
	assert(!is_nan(mean_anomaly_correction_c), "Use 0.0 for missing")
	assert(!is_nan(mean_anomaly_correction_s), "Use 0.0 for missing")
	assert(!is_nan(validity_begin), "IVRealPlanetOrbit requires 'validity_begin'")
	assert(!is_nan(validity_end), "IVRealPlanetOrbit requires 'validity_end'")
	
	var orbit := IVRealPlanetOrbit.new()
	
	# Follow IVOrbit below, then init subclass members...
	
	# defining args
	orbit._reference_plane_type = ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	orbit._reference_basis = Basis.IDENTITY
	orbit._semi_parameter = semi_major_axis * (1.0 - eccentricity * eccentricity)
	orbit._eccentricity = eccentricity
	orbit._inclination = inclination
	orbit._longitude_ascending_node_at_epoch = longitude_ascending_node
	orbit._longitude_ascending_node_rate = longitude_ascending_node_rate
	orbit._argument_periapsis_at_epoch = longitude_periapsis - longitude_ascending_node
	orbit._argument_periapsis_rate = longitude_periapsis_rate - longitude_ascending_node_rate
	orbit._time_periapsis = modulo_time_periapsis_elliptic(-mean_anomaly_at_epoch / mean_motion,
			mean_motion)
	orbit._standard_gravitational_parameter = semi_major_axis ** 3 * mean_motion ** 2
	
	# set evolving parameters to epoch (precessing)
	orbit._longitude_ascending_node = longitude_ascending_node
	orbit._argument_periapsis = longitude_periapsis - longitude_ascending_node
	
	# derived
	orbit._semi_major_axis = semi_major_axis
	orbit._mean_motion = mean_motion
	orbit._specific_energy = -0.5 * semi_major_axis ** 2 * mean_motion ** 2
	orbit._specific_angular_momentum = sqrt(orbit._standard_gravitational_parameter
			* orbit._semi_parameter)
	
	# Subclass members
	
	orbit._semi_major_axis_at_epoch = semi_major_axis
	orbit._semi_major_axis_rate = semi_major_axis_rate
	orbit._eccentricity_at_epoch = eccentricity
	orbit._eccentricity_rate = eccentricity_rate
	orbit._inclination_at_epoch = inclination
	orbit._inclination_rate = inclination_rate
	orbit._time_periapsis_at_epoch = orbit._time_periapsis
	
	orbit.m_correction_b = mean_anomaly_correction_b
	orbit.m_correction_f = mean_anomaly_correction_f
	orbit.m_correction_c = mean_anomaly_correction_c
	orbit.m_correction_s = mean_anomaly_correction_s
	
	orbit.validity_begin = validity_begin
	orbit.validity_end = validity_end
	
	return orbit



## See [method IVOrbit.update]. This subclass additionally evolves a, e,
## [therefore p], i and t₀ (if M corrections). The JPL reference indicates a
## fixed mean motion (= dL/dt). Given orbit shape change with a fixed mean
## motion, we should technically update GM, ε and h. My guess is the shape
## changes cross cancel to a good approximation, since GM shouldn't evolve. Or
## in any case, the energy changes should be tiny. So we don't update these.
func update(time: float, rotate_to_ecliptic := true) -> Vector3:
	
	# orbit evolution not in base class
	var clamp_time := clampf(time, validity_begin, validity_end)
	_semi_major_axis = _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	_eccentricity = _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	_inclination = _inclination_at_epoch + _inclination_rate * clamp_time
	_semi_parameter = _semi_major_axis * (1.0 - _eccentricity * _eccentricity)
	if m_correction_b:
		var ft := m_correction_f * time # no reason to clamp cyclic effect
		var correction := m_correction_b * clamp_time * clamp_time
		correction += m_correction_c * cos(ft) + m_correction_s * sin(ft)
		_time_periapsis = _time_periapsis_at_epoch - correction / _mean_motion
	
	# FIXME: Needs changed emission here based on above
	
	return super(time, rotate_to_ecliptic)


## See [method IVOrbit.get_position].
func get_position(time: float, rotate_to_ecliptic := true) -> Vector3:
	
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	
	# orbit evolution not in base class
	var clamp_time := clampf(time, validity_begin, validity_end)
	var a := _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	var e := _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	var i := _inclination_at_epoch + _inclination_rate * clamp_time
	var p := a * (1.0 - e * e)
	var t0 := _time_periapsis_at_epoch
	if m_correction_b:
		var ft := m_correction_f * time # no reason to clamp cyclic effect
		var correction := m_correction_b * clamp_time * clamp_time
		correction += m_correction_c * cos(ft) + m_correction_s * sin(ft)
		t0 = _time_periapsis_at_epoch - correction / _mean_motion
	
	# BELOW COPIED FROM BASE W/ SUBSTITUTIONS
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	
	# some inline static methods below...
	var nu: float # true anomaly
	if e < 1.0:
		var m := fposmod(_mean_motion * (time - t0) + PI, TAU) - PI
		nu = get_true_anomaly_from_mean_anomaly_elliptic(e, m)
	elif e > 1.0:
		var m := _mean_motion * (time - t0)
		nu = get_true_anomaly_from_mean_anomaly_hyperbolic(e, m)
	else:
		var m := get_mean_anomaly_from_elements_parabolic(p, t0,
				_standard_gravitational_parameter, time)
		nu = get_true_anomaly_from_mean_anomaly_parabolic(m)
	
	var position := get_position_from_elements_at_true_anomaly(p, e, i, lan, ap, nu)
	
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return _reference_basis * position
	return position


## See [method IVOrbit.get_state_vectors].
func get_state_vectors(time: float, rotate_to_ecliptic := true) -> Array[Vector3]:
	
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	
	# orbit evolution
	var clamp_time := clampf(time, validity_begin, validity_end)
	var a := _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	var e := _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	var i := _inclination_at_epoch + _inclination_rate * clamp_time
	var p := a * (1.0 - e * e)
	var t0 := _time_periapsis_at_epoch
	if m_correction_b:
		var ft := m_correction_f * time # no reason to clamp cyclic effect
		var correction := m_correction_b * clamp_time * clamp_time
		correction += m_correction_c * cos(ft) + m_correction_s * sin(ft)
		t0 = _time_periapsis_at_epoch - correction / _mean_motion
	
	# BELOW COPIED FROM BASE W/ SUBSTITUTIONS
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	
	# some inline static methods below...
	var nu: float # true anomaly
	if e < 1.0:
		var m := fposmod(_mean_motion * (time - t0) + PI, TAU) - PI
		nu = get_true_anomaly_from_mean_anomaly_elliptic(e, m)
	elif e > 1.0:
		var m := _mean_motion * (time - t0)
		nu = get_true_anomaly_from_mean_anomaly_hyperbolic(e, m)
	else:
		var m := get_mean_anomaly_from_elements_parabolic(p, t0,
				_standard_gravitational_parameter, time)
		nu = get_true_anomaly_from_mean_anomaly_parabolic(m)
	
	var vectors := get_state_vectors_from_elements_at_true_anomaly(p, e,
			i, lan, ap, _specific_angular_momentum, nu)
	
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return [_reference_basis * vectors[0], _reference_basis * vectors[1]]
	return vectors


## See [method IVOrbit.get_mean_anomaly].
func get_mean_anomaly(time: float) -> float:
	
	# orbit evolution
	var clamp_time := clampf(time, validity_begin, validity_end)
	var a := _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	var e := _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	var p := a * (1.0 - e * e)
	var t0 := _time_periapsis_at_epoch
	if m_correction_b:
		var ft := m_correction_f * time # no reason to clamp cyclic effect
		var correction := m_correction_b * clamp_time * clamp_time
		correction += m_correction_c * cos(ft) + m_correction_s * sin(ft)
		t0 = _time_periapsis_at_epoch - correction / _mean_motion
	
	# BELOW COPIED FROM BASE W/ SUBSTITUTIONS
	
	if e < 1.0:
		return fposmod(_mean_motion * (time - t0) + PI, TAU) - PI
	if e > 1.0:
		return _mean_motion * (time - t0)
	return get_mean_anomaly_from_elements_parabolic(p, t0, _standard_gravitational_parameter, time)


## See [method IVOrbit.get_true_anomaly].
func get_true_anomaly(time: float) -> float:
	
	# orbit evolution
	var clamp_time := clampf(time, validity_begin, validity_end)
	var a := _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	var e := _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	var p := a * (1.0 - e * e)
	var t0 := _time_periapsis_at_epoch
	if m_correction_b:
		var ft := m_correction_f * time # no reason to clamp cyclic effect
		var correction := m_correction_b * clamp_time * clamp_time
		correction += m_correction_c * cos(ft) + m_correction_s * sin(ft)
		t0 = _time_periapsis_at_epoch - correction / _mean_motion
	
	# BELOW COPIED FROM BASE W/ SUBSTITUTIONS
	
	var m: float # mean anomaly
	if e < 1.0:
		m = fposmod(_mean_motion * (time - t0) + PI, TAU) - PI
		return get_true_anomaly_from_mean_anomaly_elliptic(e, m)
	if e > 1.0:
		m = _mean_motion * (time - t0)
		return get_true_anomaly_from_mean_anomaly_hyperbolic(e, m)
	m = get_mean_anomaly_from_elements_parabolic(p, t0, _standard_gravitational_parameter, time)
	return get_true_anomaly_from_mean_anomaly_parabolic(m)


## See [method IVOrbit.get_radius].
func get_radius(time: float) -> float:
	
	# orbit evolution
	var clamp_time := clampf(time, validity_begin, validity_end)
	var a := _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	var e := _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	var p := a * (1.0 - e * e)
	
	# BELOW COPIED FROM BASE W/ SUBSTITUTIONS
	
	var nu := get_true_anomaly(time)
	return p / (1.0 + e * cos(nu))


# *****************************************************************************
# Element gets and sets.
# DISABLE all sets for elements that evolve in this subclass. This is a nitch
# subclass and it's too hard to do.


## DISABLED
func set_reference_plane_and_basis(_plane_type: ReferencePlane, _basis: Basis) -> void:
	pass


## DISABLED
func set_semi_parameter(_value: float) -> void:
	pass


## DISABLED
func set_eccentricity(_value: float) -> void:
	pass


## DISABLED
func set_inclination(_value: float) -> void:
	pass


## DISABLED
func set_time_periapsis(_value: float) -> void:
	pass


## DISABLED
func set_standard_gravitational_parameter(_value: float) -> void:
	pass


## DISABLED
func set_semi_major_axis(_value: float) -> void:
	pass


## DISABLED
func set_mean_motion(_value: float) -> void:
	pass


## DISABLED
func set_specific_energy(_value: float) -> void:
	pass


## DISABLED
func set_specific_angular_momentum(_value: float) -> void:
	pass



func get_semi_parameter_at_time(time: float) -> float:
	var clamp_time := clampf(time, validity_begin, validity_end)
	var a := _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	var e := _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	return a * (1.0 - e * e)


func get_semi_parameter_at_epoch() -> float:
	return _semi_major_axis_at_epoch * (1.0 - _eccentricity_at_epoch * _eccentricity_at_epoch)


func get_semi_parameter_rate() -> float:
	return _semi_major_axis_rate * (1.0 - _eccentricity_rate * _eccentricity_rate)


func get_eccentricity_at_time(time: float) -> float:
	var clamp_time := clampf(time, validity_begin, validity_end)
	return _eccentricity_at_epoch + _eccentricity_rate * clamp_time


func get_eccentricity_at_epoch() -> float:
	return _eccentricity_at_epoch


func get_eccentricity_rate() -> float:
	return _eccentricity_rate


func get_inclination_at_time(time: float) -> float:
	var clamp_time := clampf(time, validity_begin, validity_end)
	return _inclination_at_epoch + _inclination_rate * clamp_time


func get_inclination_at_epoch() -> float:
	return _inclination_at_epoch


func get_inclination_rate() -> float:
	return _inclination_rate


func get_time_periapsis_at_time(time: float) -> float:
	var t0 := _time_periapsis_at_epoch
	if m_correction_b:
		var clamp_time := clampf(time, validity_begin, validity_end)
		var ft := m_correction_f * time # no reason to clamp cyclic effect
		var correction := m_correction_b * clamp_time * clamp_time
		correction += m_correction_c * cos(ft) + m_correction_s * sin(ft)
		t0 = _time_periapsis_at_epoch - correction / _mean_motion
	return t0


func get_time_periapsis_at_epoch() -> float:
	return _time_periapsis_at_epoch


# Note: There is no time_periapsis_rate, as such...


# *****************************************************************************
# Derivable elements


func get_semi_major_axis_at_time(time: float) -> float:
	var clamp_time := clampf(time, validity_begin, validity_end)
	return _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time


func get_semi_major_axis_at_epoch() -> float:
	return _semi_major_axis_at_epoch


func get_semi_major_axis_rate() -> float:
	return _semi_major_axis_rate


# Note: retrograde won't ever change here...


func get_mean_anomaly_at_epoch() -> float:
	return fposmod(-_mean_motion * _time_periapsis_at_epoch, TAU)


func get_mean_anomaly_at_epoch_at_time(time: float) -> float:
	var t0 := _time_periapsis_at_epoch
	if m_correction_b:
		var clamp_time := clampf(time, validity_begin, validity_end)
		var ft := m_correction_f * time # no reason to clamp cyclic effect
		var correction := m_correction_b * clamp_time * clamp_time
		correction += m_correction_c * cos(ft) + m_correction_s * sin(ft)
		t0 = _time_periapsis_at_epoch - correction / _mean_motion
	return fposmod(-_mean_motion * t0, TAU)


func get_mean_anomaly_at_epoch_at_epoch() -> float:
	return fposmod(-_mean_motion * _time_periapsis_at_epoch, TAU)


# Note: There is no mean_anomaly_at_epoch_rate, as such...


# *****************************************************************************
# Orbit spatial derivations


## See [method IVOrbit.get_normal_at_time].
func get_normal_at_time(time: float, rotate_to_ecliptic := true, flip_retrograde := false) -> Vector3:
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	
	var clamp_time := clampf(time, validity_begin, validity_end)
	var i := _inclination_at_epoch + _inclination_rate * clamp_time
	
	# BELOW COPIED FROM BASE W/ SUBSTITUTIONS
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	
	var normal := get_normal_from_elements(i, lan, flip_retrograde)
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return _reference_basis * normal
	return normal


## See [method IVOrbit.get_basis_at_time].
func get_basis_at_time(time: float, rotate_to_ecliptic := true) -> Basis:
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	
	var clamp_time := clampf(time, validity_begin, validity_end)
	var i := _inclination_at_epoch + _inclination_rate * clamp_time
	
	# BELOW COPIED FROM BASE W/ SUBSTITUTIONS
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	
	var basis := get_basis_from_elements(i, lan, ap)
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return _reference_basis * basis
	return basis


## See [method IVOrbit.get_unit_circle_transform_at_time].
func get_unit_circle_transform_at_time(time: float, rotate_to_ecliptic := true) -> Transform3D:
	
	var clamp_time := clampf(time, validity_begin, validity_end)
	var a := _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	var e := _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	
	# BELOW COPIED FROM BASE W/ SUBSTITUTIONS
	
	if e >= 1.0:
		return Transform3D()
	var b := sqrt(a * a * (1.0 - e * e))
	var orbit_basis := get_basis_at_time(time, rotate_to_ecliptic)
	var basis := orbit_basis * Basis().scaled(Vector3(a, b, 1.0))
	return Transform3D(basis, -e * basis.x)
