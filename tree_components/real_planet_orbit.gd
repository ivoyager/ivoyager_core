# real_planet_orbit.gd
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
class_name IVRealPlanetOrbit
extends IVOrbit

## Extended [IVOrbit] class that implements JPL-specified corrections to better
## approximate real planet positions.
##
## This subclass can be used for realistic (though still approximate) planet
## positions for date ranges 3000 BC - 3000 AD or 1800 AD - 2050 AD following
## [url]https://ssd.jpl.nasa.gov/planets/approx_pos.html[/url].[br][br]
##
## It's probably not needed for most game usage and limits the flexibility of
## the [IVOrbit] class. Orbit elements cannot be set for this subclass at editor
## runtime.[br][br]
##
## Use of this subclass is enabled by setting
## [code]IVTableOrbitBuilder.use_real_planet_orbits = true[/code] and
## [code]orbits.tsv[/code] field [code]real_planet_orbit[/code] = TRUE. It then
## reads the additional orbits.tsv fields "semi_major_axis_rate",
## "eccentricity_rate", "inclination_rate" and "mean_anomaly_correction_b",
## "..._c", "..._s" and "..._f".[br][br]
## 
## We changed implementation from the JPL reference page. In particular, we use
## b, c, s and f corrections to evolve time of periapsis passage (t₀, a defining
## element) rather than correcting the mean anomoly (M) during position
## calculation. By doing it this way, the orbital elements (alone) specify
## orbit and position in the orbit all times.[br][br]
##
## Our data table [b]tables/orbits.tsv[/b] contains corrections for Pluto that
## were previously on the JPL page but subsequently removed (due to its
## unfortunate demotion).


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

	&"_signaled_semi_major_axis",
	&"_signaled_eccentricity",
	&"_signaled_inclination",
	&"_signaled_semi_parameter",
	&"_signaled_time_periapsis",
]

# redirect public
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

# Hysteresis detectors for the changed signal only. a/e/i/p/t₀ evolve in this subclass, so it needs its
# own last-signaled snapshot (the base's Ω/ω detectors still cover precession). Updated in update() when
# accumulated change crosses CHANGED_THRESHOLD; these LAG the true elements — the current value is always
# get_<element>_at_time(). The base's _semi_major_axis/_eccentricity/_inclination/_semi_parameter/
# _time_periapsis fields are the base's current-element store and stay at their epoch values in this subclass.
var _signaled_semi_major_axis: float
var _signaled_eccentricity: float
var _signaled_inclination: float
var _signaled_semi_parameter: float
var _signaled_time_periapsis: float


## Creates a new [IVRealPlanetOrbit] instance. Takes argument of periapsis (ω)
## and its rate, consistent with the base [IVOrbit] element convention.
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
		argument_periapsis: float,
		argument_periapsis_rate: float,
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
	assert(!is_nan(argument_periapsis), "IVRealPlanetOrbit requires 'argument_periapsis'")
	assert(!is_nan(mean_anomaly_at_epoch), "IVRealPlanetOrbit requires 'mean_anomaly_at_epoch'")
	assert(mean_motion > 0.0, "IVRealPlanetOrbit requires 'mean_motion' > 0.0")
	assert(!is_nan(semi_major_axis_rate), "IVRealPlanetOrbit requires 'semi_major_axis_rate'")
	assert(!is_nan(eccentricity_rate), "IVRealPlanetOrbit requires 'eccentricity_rate'")
	assert(!is_nan(inclination_rate), "IVRealPlanetOrbit requires 'inclination_rate'")
	assert(!is_nan(longitude_ascending_node_rate),
			"IVRealPlanetOrbit requires 'longitude_ascending_node_rate'")
	assert(!is_nan(argument_periapsis_rate),
			"IVRealPlanetOrbit requires 'argument_periapsis_rate'")
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
	orbit._reference_basis = IVMath64.from_basis(Basis.IDENTITY)
	orbit._semi_parameter = semi_major_axis * (1.0 - eccentricity * eccentricity)
	orbit._eccentricity = eccentricity
	orbit._inclination = inclination
	orbit._longitude_ascending_node_at_epoch = longitude_ascending_node
	orbit._longitude_ascending_node_rate = longitude_ascending_node_rate
	orbit._argument_periapsis_at_epoch = argument_periapsis
	orbit._argument_periapsis_rate = argument_periapsis_rate
	# Table 'mean_motion' is JPL's mean longitude rate (dL/dt), not the mean
	# anomaly rate. With the periapsis precessing, mean anomaly advances at
	# dM/dt = dL/dt - dϖ/dt (JPL computes M = L - ϖ, both linear in time). This
	# slower rate is the orbit's true (osculating) mean motion; using it for the
	# Kepler relations and M propagation keeps position from drifting ahead by
	# dϖ/dt per unit time (a few degrees over the multi-millennia validity range).
	# Reconstruct ϖ̇ = ω̇ + Ω̇ (prograde planets).
	var mean_anomaly_rate := mean_motion - (argument_periapsis_rate + longitude_ascending_node_rate)
	orbit._time_periapsis = modulo_time_periapsis_elliptic(
			-mean_anomaly_at_epoch / mean_anomaly_rate, mean_anomaly_rate)
	orbit._gravitational_parameter = semi_major_axis ** 3 * mean_anomaly_rate ** 2
	
	# seed the changed-signal hysteresis detectors at epoch (precessing)
	orbit._signaled_longitude_ascending_node = longitude_ascending_node
	orbit._signaled_argument_periapsis = argument_periapsis
	
	# derived
	orbit._semi_major_axis = semi_major_axis
	orbit._mean_motion = mean_anomaly_rate
	orbit._specific_energy = -0.5 * semi_major_axis ** 2 * mean_anomaly_rate ** 2
	orbit._specific_angular_momentum = sqrt(orbit._gravitational_parameter
			* orbit._semi_parameter)
	
	# Subclass members
	
	orbit._semi_major_axis_at_epoch = semi_major_axis
	orbit._semi_major_axis_rate = semi_major_axis_rate
	orbit._eccentricity_at_epoch = eccentricity
	orbit._eccentricity_rate = eccentricity_rate
	orbit._inclination_at_epoch = inclination
	orbit._inclination_rate = inclination_rate
	orbit._time_periapsis_at_epoch = orbit._time_periapsis

	# seed the subclass changed-signal hysteresis detectors at epoch
	orbit._signaled_semi_major_axis = semi_major_axis
	orbit._signaled_eccentricity = eccentricity
	orbit._signaled_inclination = inclination
	orbit._signaled_semi_parameter = orbit._semi_parameter
	orbit._signaled_time_periapsis = orbit._time_periapsis
	
	orbit.m_correction_b = mean_anomaly_correction_b
	orbit.m_correction_f = mean_anomaly_correction_f
	orbit.m_correction_c = mean_anomaly_correction_c
	orbit.m_correction_s = mean_anomaly_correction_s
	
	orbit.validity_begin = validity_begin
	orbit.validity_end = validity_end
	
	return orbit



## See [method IVOrbit.update]. This subclass additionally evolves a, e,
## [therefore p], i and t₀ (if M corrections). The JPL reference uses a fixed
## mean longitude rate dL/dt, hence a fixed mean anomaly rate dM/dt = dL/dt -
## dϖ/dt (= [member mean_motion] here; see [method create_real_planet_orbit]).
## Given orbit shape change with a fixed mean motion, we should technically
## update GM, ε and h. My guess is the shape changes cross cancel to a good
## approximation, since GM shouldn't evolve. Or in any case, the energy changes
## should be tiny. So we don't update these.
func update(time: float, rotate_to_ecliptic := true) -> Vector3:
	
	const CHANGED_ANGLE_THRESHOLD := CHANGED_THRESHOLD / TAU
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	
	_update_time = time

	# evolve orbit (precession only)
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	
	# signal if accumulated precession since the last emit crosses the threshold
	if (absf(lan - _signaled_longitude_ascending_node) > CHANGED_ANGLE_THRESHOLD
			or absf(ap - _signaled_argument_periapsis) > CHANGED_ANGLE_THRESHOLD):
		_signaled_longitude_ascending_node = lan
		_signaled_argument_periapsis = ap
		changed.emit(true, true)
	
	# Note: a double changed signal is possible here, but is only an edge-case
	# (planet precession is sloooowwww and non-precession change is slower).
	
	# evolve orbit (non-precession)
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
	
	# signal if accumulated element change since the last emit crosses the threshold
	if (absf(a - _signaled_semi_major_axis) / a > CHANGED_THRESHOLD
			or absf(e - _signaled_eccentricity) > CHANGED_THRESHOLD
			or absf(i - _signaled_inclination) > CHANGED_ANGLE_THRESHOLD
			or absf(p - _signaled_semi_parameter) / p > CHANGED_THRESHOLD
			or absf(t0 - _signaled_time_periapsis) * _mean_motion > CHANGED_ANGLE_THRESHOLD):
		_signaled_semi_major_axis = a
		_signaled_eccentricity = e
		_signaled_inclination = i
		_signaled_semi_parameter = p
		_signaled_time_periapsis = t0
		changed.emit(true, false)
	
	# BELOW COPIED FROM BASE W/ SUBSTITUTIONS
	
	# some inline static methods below...
	if e < 1.0:
		_mean_anomaly = fposmod(_mean_motion * (time - t0) + PI, TAU) - PI
		_true_anomaly = get_true_anomaly_from_mean_anomaly_elliptic(e, _mean_anomaly)
	elif e > 1.0:
		_mean_anomaly = _mean_motion * (time - t0)
		_true_anomaly = get_true_anomaly_from_mean_anomaly_hyperbolic(e, _mean_anomaly)
	else:
		_mean_anomaly = get_mean_anomaly_from_elements_parabolic(p, t0,
				_gravitational_parameter, time)
		_true_anomaly = get_true_anomaly_from_mean_anomaly_parabolic(_mean_anomaly)
	
	var position := get_position_from_elements_at_true_anomaly(p, e, i, lan, ap, _true_anomaly)

	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return IVMath64.to_basis(_reference_basis) * position
	return position


## See [method IVOrbit.get_position_vector].
func get_position_vector(time: float, rotate_to_ecliptic := true) -> Vector3:
	var out := PackedFloat64Array([0.0, 0.0, 0.0])
	_write_translation(time, rotate_to_ecliptic, out, 0)
	return Vector3(out[0], out[1], out[2])


## See [method IVOrbit.get_state_vectors].
func get_state_vectors(time: float, rotate_to_ecliptic := true) -> PackedVector3Array:
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	_write_state(time, rotate_to_ecliptic, out, 0)
	return PackedVector3Array([Vector3(out[0], out[1], out[2]), Vector3(out[3], out[4], out[5])])


# Overrides the base 64-bit translation core to inject this subclass's a/e/i/t₀ evolution.
# The base get_translation() / get_state() / sample_arc() and (via delegation) get_position_vector()
# / get_state_vectors() all route through _write_translation() / _write_state(), so overriding
# these two keeps every position/state path (32- and 64-bit) evolution-correct.
func _write_translation(time: float, rotate_to_ecliptic: bool, out: PackedFloat64Array,
		offset: int) -> void:
	var clamp_time := clampf(time, validity_begin, validity_end)
	var a := _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	var e := _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	var incl := _inclination_at_epoch + _inclination_rate * clamp_time
	var p := a * (1.0 - e * e)
	var t0 := _evolved_time_periapsis(time)
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	var nu := _evolved_true_anomaly(e, p, t0, time)
	var r := p / (1.0 + e * cos(nu))
	var sin_i := sin(incl)
	var cos_i := cos(incl)
	var sin_lan := sin(lan)
	var cos_lan := cos(lan)
	var sin_ap_nu := sin(ap + nu)
	var cos_ap_nu := cos(ap + nu)
	var x := r * (cos_lan * cos_ap_nu - sin_lan * sin_ap_nu * cos_i)
	var y := r * (sin_lan * cos_ap_nu + cos_lan * sin_ap_nu * cos_i)
	var z := r * (sin_ap_nu * sin_i)
	if rotate_to_ecliptic and _reference_plane_type != ReferencePlane.REFERENCE_PLANE_ECLIPTIC:
		IVMath64.rotate_into(_reference_basis, x, y, z, out, offset)
	else:
		out[offset] = x
		out[offset + 1] = y
		out[offset + 2] = z


# As [method _write_translation] but also writes velocity (see base [method IVOrbit._write_state]).
func _write_state(time: float, rotate_to_ecliptic: bool, out: PackedFloat64Array,
		offset: int) -> void:
	var clamp_time := clampf(time, validity_begin, validity_end)
	var a := _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	var e := _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	var incl := _inclination_at_epoch + _inclination_rate * clamp_time
	var p := a * (1.0 - e * e)
	var t0 := _evolved_time_periapsis(time)
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	var nu := _evolved_true_anomaly(e, p, t0, time)
	var r := p / (1.0 + e * cos(nu))
	var sin_i := sin(incl)
	var cos_i := cos(incl)
	var sin_lan := sin(lan)
	var cos_lan := cos(lan)
	var sin_ap_nu := sin(ap + nu)
	var cos_ap_nu := cos(ap + nu)
	var x := r * (cos_lan * cos_ap_nu - sin_lan * sin_ap_nu * cos_i)
	var y := r * (sin_lan * cos_ap_nu + cos_lan * sin_ap_nu * cos_i)
	var z := r * (sin_ap_nu * sin_i)
	var c := _specific_angular_momentum * e * sin(nu) / (r * p)
	var angular_v := _specific_angular_momentum / r
	var vx := c * x - angular_v * (cos_lan * sin_ap_nu + sin_lan * cos_ap_nu * cos_i)
	var vy := c * y - angular_v * (sin_lan * sin_ap_nu - cos_lan * cos_ap_nu * cos_i)
	var vz := c * z + angular_v * (cos_ap_nu * sin_i)
	if rotate_to_ecliptic and _reference_plane_type != ReferencePlane.REFERENCE_PLANE_ECLIPTIC:
		IVMath64.rotate_into(_reference_basis, x, y, z, out, offset)
		IVMath64.rotate_into(_reference_basis, vx, vy, vz, out, offset + 3)
	else:
		out[offset] = x
		out[offset + 1] = y
		out[offset + 2] = z
		out[offset + 3] = vx
		out[offset + 4] = vy
		out[offset + 5] = vz


# Time of periapsis passage (t₀) at [param time], with the M corrections folded in as t₀ evolution.
func _evolved_time_periapsis(time: float) -> float:
	if not m_correction_b:
		return _time_periapsis_at_epoch
	var clamp_time := clampf(time, validity_begin, validity_end)
	var ft := m_correction_f * time # no reason to clamp cyclic effect
	var correction := m_correction_b * clamp_time * clamp_time
	correction += m_correction_c * cos(ft) + m_correction_s * sin(ft)
	return _time_periapsis_at_epoch - correction / _mean_motion


# True anomaly (θ) at [param time] from the passed evolved [param e], [param p] and [param t0].
# Mirrors the elliptic / hyperbolic / parabolic dispatch of the base solvers.
func _evolved_true_anomaly(e: float, p: float, t0: float, time: float) -> float:
	if e < 1.0:
		var m := fposmod(_mean_motion * (time - t0) + PI, TAU) - PI
		return get_true_anomaly_from_mean_anomaly_elliptic(e, m)
	if e > 1.0:
		var m := _mean_motion * (time - t0)
		return get_true_anomaly_from_mean_anomaly_hyperbolic(e, m)
	var mp := get_mean_anomaly_from_elements_parabolic(p, t0, _gravitational_parameter, time)
	return get_true_anomaly_from_mean_anomaly_parabolic(mp)


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
	return get_mean_anomaly_from_elements_parabolic(p, t0, _gravitational_parameter, time)


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
	m = get_mean_anomaly_from_elements_parabolic(p, t0, _gravitational_parameter, time)
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
func set_gravitational_parameter(_value: float) -> void:
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


## See [method IVOrbit.get_semi_major_axis_at_time].
func get_semi_major_axis_at_time(time: float) -> float:
	var clamp_time := clampf(time, validity_begin, validity_end)
	return _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time


## See [method IVOrbit.get_semi_major_axis_at_epoch].
func get_semi_major_axis_at_epoch() -> float:
	return _semi_major_axis_at_epoch


## See [method IVOrbit.get_semi_major_axis_rate].
func get_semi_major_axis_rate() -> float:
	return _semi_major_axis_rate


# Note: retrograde won't ever change here...


## See [method IVOrbit.get_mean_anomaly_at_epoch].
func get_mean_anomaly_at_epoch() -> float:
	return fposmod(-_mean_motion * _time_periapsis_at_epoch, TAU)


## See [method IVOrbit.get_mean_anomaly_at_epoch_at_time].
func get_mean_anomaly_at_epoch_at_time(time: float) -> float:
	var t0 := _time_periapsis_at_epoch
	if m_correction_b:
		var clamp_time := clampf(time, validity_begin, validity_end)
		var ft := m_correction_f * time # no reason to clamp cyclic effect
		var correction := m_correction_b * clamp_time * clamp_time
		correction += m_correction_c * cos(ft) + m_correction_s * sin(ft)
		t0 = _time_periapsis_at_epoch - correction / _mean_motion
	return fposmod(-_mean_motion * t0, TAU)


## See [method IVOrbit.get_mean_longitude_at_epoch].
func get_mean_longitude_at_epoch() -> float:
	return fposmod(-mean_motion * _time_periapsis_at_epoch + _longitude_ascending_node_at_epoch
			+ _argument_periapsis_at_epoch, TAU)


# *****************************************************************************
# Orbit spatial derivations

## Periapsis may evolve in this subclass.
func get_periapsis_at_time(time: float) -> float:
	var a := get_semi_major_axis_at_time(time)
	var e := get_eccentricity_at_time(time) # always < 1.0 in this subclass
	return a * (1.0 - e)


## Apoapsis may evolve in this subclass.
func get_apoapsis_at_time(time: float) -> float:
	var a := get_semi_major_axis_at_time(time)
	var e := get_eccentricity_at_time(time) # always < 1.0 in this subclass
	return a * (1.0 + e)


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
		return IVMath64.to_basis(_reference_basis) * normal
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
		return IVMath64.to_basis(_reference_basis) * basis
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


## See [method IVOrbit.get_unit_rectangular_hyperbola_transform_at_time].
func get_unit_rectangular_hyperbola_transform_at_time(time: float, rotate_to_ecliptic := true
		) -> Transform3D:
	
	var clamp_time := clampf(time, validity_begin, validity_end)
	var a := _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	var e := _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	
	# BELOW COPIED FROM BASE W/ SUBSTITUTIONS
	
	const SQRT2 := sqrt(2.0) # rectangular hyperbola has e = sqrt(2)
	if e <= 1.0:
		return Transform3D()
	var b := sqrt(a * a * (e * e - 1.0))
	var orbit_basis := get_basis_at_time(time, rotate_to_ecliptic)
	var basis := orbit_basis * Basis().scaled(Vector3(-a, b, 1.0))
	return Transform3D(basis, (e - SQRT2) * basis.x)


## See [method IVOrbit.get_unit_parabola_transform_at_time].
func get_unit_parabola_transform_at_time(time: float, rotate_to_ecliptic := true) -> Transform3D:
	
	var clamp_time := clampf(time, validity_begin, validity_end)
	var a := _semi_major_axis_at_epoch + _semi_major_axis_rate * clamp_time
	var e := _eccentricity_at_epoch + _eccentricity_rate * clamp_time
	var p := a * (1.0 - e * e)
	
	# BELOW COPIED FROM BASE W/ SUBSTITUTIONS
	
	var orbit_basis := get_basis_at_time(time, rotate_to_ecliptic)
	var basis := orbit_basis * Basis().scaled(Vector3(p, p, 1.0))
	return Transform3D(basis, Vector3.ZERO)
