# orbit.gd
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
class_name IVOrbit
extends RefCounted

## Represents an elliptic, parabolic or hyperbolic orbit in a specified
## reference basis. Orbits may have nodal and apsidal precessions.
##
## See Wikipedia for [url=https://en.wikipedia.org/wiki/Orbital_elements]orbital
## elements[/url] and other technical terms. "Elements" refer to the parameters
## needed to specify an orbit (including position in an orbit given time). Two
## elements (Ω and ω) evolve over time in this base class (i.e., the orbit
## evolves) and others evolve in IVOrbit subclasses. Evolution of orbit elements
## is [b]VERY SLOW[/b] relative to change in position in an orbit.[br][br]
##
## Position and velocity in this class are always relative to the parent body
## or barycenter. The [member reference_basis] is the basis in which this orbit
## is defined, where the xy axes define the reference plane about which this
## orbit precesses. See also [member reference_plane_type].[br][br]
##
## In addition to epoch time (always J2000), seven elements are needed to
## define an unpurturbed (osculating) orbit. The following elements are used
## here because they are valid for elliptic, parabolic and hyperbolic orbits:[br][br]
##
## [member semi_parameter] (p).[br]
## [member eccentricity] (e).[br]
## [member inclination] (i).[br]
## [member longitude_ascending_node] (Ω). Precesses.[br]
## [member argument_periapsis] (ω). ω = ϖ - Ω, where ϖ is longitude of periapsis. Precesses.[br]
## [member time_periapsis] (t₀).[br]
## [member gravitational_parameter] (GM, μ).[br][br]
##
## Additional elements are derived from above and maintained for
## convenience:[br][br]
##
## [member semi_major_axis] (a).[br]
## [member mean_motion] (n).[br]
## [member specific_energy] (ε).[br]
## [member specific_angular_momentum] (h).[br][br]
##
## Other commonly used elements can be obtained from the API.[br][br]
##
## Real orbits have nodal and apsidal precessions resulting from orbital
## perturbations. (E.g., the most important perturbation for near satellites is
## oblateness of the parant body.) These are represented here by evolution of
## Ω and ω over time, calculated from the following properties:[br][br]
##
## [member longitude_ascending_node_at_epoch] (Ω₀).[br]
## [member longitude_ascending_node_rate] (dΩ/dt). Nodal precession *.[br]
## [member argument_periapsis_at_epoch] (ω₀).[br]
## [member argument_periapsis_rate] (dω/dt). dω/dt = dϖ/dt - dΩ/dt, where dϖ/dt
##   is apsidal precession *.[br]
## (* Sign is ... complicated. Positive nodal precession is in the opposite
## direction of orbit. Positive apsidal is in the direction of orbit.)[br][br]
##
## Because orbital elements can evolve over time, some properties and some method
## returns require a preceding [method update] call to be current. However, all
## methods that follow naming convention "get_..._at_time()" (and all static
## methods) are valid without [method update]. Note that subclasses may evolve
## other elements in addition to the two precessing elements. Hence, many get
## functions require [param time] for parameters that are not time-dependent in
## this base class (but may be time-dependent in subclasses).[br][br]
##
## Note: property setters are implemented in this class mainly for playing
## around at editor runtime. The setters generally hold e and GM fixed and
## update other elements as needed, but see methods for specific cases. Code
## based changes to elements should be implemented in a subclass (see Roadmap
## below).[br][br]
##
## Get methods are generally threadsafe, but element values may be inconsistant
## if an orbit change is being set concurently. Set methods cause [signal changed]
## signal so are NOT threadsafe.[br][br][br]
##
## [b]Method naming conventions (gets/sets)[/b][br][br]
##
## Elements:
##
## [codeblock]
## get_element() # getter; at last update() if this element evolves
## get_element_at_time(time)
## get_element_at_epoch() # getter
## get_element_rate() # getter
##
## set_element(value) # setter
## set_element_at_epoch(value) # setter; Ω and ω only
## set_element_rate(value) # setter; Ω and ω only
## set_element_rate_at_time(value, time) # set w/out state change at time; Ω and ω only
##
## # Only Ω and ω evolve in this base class, but others evolve in IVOrbit subclasses.
## # All get methods above are present for all elements (and return sensible results
## # for elements that don't evolve in this base class). However, only the relevant
## # set methods are present in IVOrbit. 
## [/codeblock]
##
## Derivable elements (ϖ, M₀, etc.) and derivable spatials (normal, basis, etc.):
##
## [codeblock]
## get_derivable() # at last update() if relevant elements evolve
## get_derivable_at_time(time)
## get_derivable_rate() # elements only
## get_derivable_from_elements(...) # static; spatials only
## [/codeblock]
##
## State parameters (anomalies, longitudes, radius, position, velocity):
##
## [codeblock]
## # Naming is changed from above to stress volatility of state parameters; 
## # "_at_time" is redundant.
## get_parameter_at_update() # at last update() call
## get_parameter(time)
## get_parameter_from_something(...) # static
## [/codeblock][br]
##
##
## [b]Roadmap[/b][br][br]
##
## TODO: Multiplayer RPC. We REALLY don't want to make this a Node. The reason
## is that IVOrbit is supposed to be a cheap data container that can be instanced
## in different contexts (e.g., for patched conic trajectory planning). What we
## want are serialization/deserialization methods here, and then IVBody does the
## RPC sync on [signal changed]. We only need network sync when the change is
## extrinsic (e.g., thrust).[br][br]
##
## TODO:
## [codeblock]
## create_from_state_vectors_and_precessions(p, v, gm, ref_basis, nodal_precession, apsidal_precession)
## create_from_state_vectors_and_environment(p, v, gm, j2, ...)
## [/codeblock]
## The primary "environment" parameter for near satellites is parent oblateness (J2
## or whatever). Other environment parameters will be needed to at least roughly
## estimate realistic precessions. E.g., Relativity for Mercury, something else
## (not Earth's oblateness!) for the Moon, etc. We can also calculate a correct
## reference_basis. This is mainly for game applications so we don't need
## perfection.[br][br]
##
## TODO: Subclass [code]IVResonantOrbit[/code]. Enables Lagrange and (possibly)
## other resonant orbits. A body in L-point "orbit" is really still orbiting
## the primary body. The secondary body only causes evolution of orbital
## elements so that the body oscillates around the stability point.[br][br]
##
## TODO: Subclass [code]IVManeuveringOrbit[/code]. Adds impulse and constant
## thrust options. It will be a subclass of IVResonantOrbit so it can experience
## resonant effects and hold station at an L-point. However, it could be
## implemented initially as a direct extension of IVOrbit (if IVResonantOrbit
## isn't ready yet).[br][br]


## Signal emitted when orbital elements are set or evolve by a threshold amount.
## [param is_intrinsic] is true if the cause is internally specified (e.g.,
## precessions) and is false if external (e.g., due to thrust in an IVOrbit
## subclass).
signal changed(is_intrinsic: bool, precession_only: bool)


## Type of orbit reference plane. (An orbit's specific reference plane is
## defined by [member reference_basis].)
enum ReferencePlane {
	REFERENCE_PLANE_ECLIPTIC, ## XY axes of the ecliptic basis.
	REFERENCE_PLANE_EQUATORIAL, ## With respect to parent body (NOT equatorial coordinates!).
	REFERENCE_PLANE_LAPLACE, ## A specified intermediate Laplace plane.
}


const ECLIPTIC_SPACE := Basis.IDENTITY
## Minimum accumulated element change for update and [signal changed] signal.
const CHANGED_THRESHOLD := 0.005

## Just under 0.0 so Earth doesn't cause error. (Earth i = -9.48517e-06 at epoch.)
const MIN_INCLINATION := -0.001
## Inclination too near π/2 is bumped a titch to prevent math singularity.
const INCLINATION_RIGHT_ANGLE_BUMP := 0.001

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_reference_plane_type",
	&"_reference_basis",
	&"_semi_parameter",
	&"_eccentricity",
	&"_inclination",
	&"_longitude_ascending_node",
	&"_argument_periapsis",
	&"_time_periapsis",
	&"_gravitational_parameter",
	&"_semi_major_axis",
	&"_mean_motion",
	&"_specific_energy",
	&"_specific_angular_momentum",
	&"_longitude_ascending_node_at_epoch",
	&"_longitude_ascending_node_rate",
	&"_argument_periapsis_at_epoch",
	&"_argument_periapsis_rate",
	&"_mean_anomaly",
	&"_true_anomaly",
]


# Public properties are all "redirect" vars so we can implement side-effects or
# force alternative set methods.

## One of [enum ReferencePlane] types.
var reference_plane_type: ReferencePlane: get = get_reference_plane_type
## The basis in which this orbit is defined. The xy axes define the plane about
## which this orbit precesses, where the x-axis is at ecliptic longitude 0.0.
## Equals the identity basis if [member reference_plane_type] ==
## ReferencePlane.REFERENCE_PLANE_ECLIPTIC.
var reference_basis: Basis: get = get_reference_basis
## Semi-parameter (p). Also called semi-latus rectum. Radial distance to the
## orbiting body when true anomaly = π/2 and -π/2. Valid and positive for
## elliptic, parabolic and hyperbolic orbits.
var semi_parameter: float: get = get_semi_parameter, set = set_semi_parameter
## Eccentricity (e). 0 ≤ e < 1 (elliptic orbit); e = 1 (parabolic); e > 1 (hyperbolic).
var eccentricity: float: get = get_eccentricity, set = set_eccentricity
## Inclination (i). ~0 ≤ i < π/2 (prograde orbit); π/2 < i ≤ π (retrograde).
## Note: Earth in official data sets has i = -9.48517e-06 at epoch (probably
## because no one wants to flip Ω to the other side). Therefore, internal code
## allows a slightly negative inclination; see [constant MIN_INCLINATION].
var inclination: float: get = get_inclination, set = set_inclination
## Longitude of the ascending node (Ω). 0 ≤ Ω < 2π. By convention,
## orbits with no inclination have Ω = 0. Precesses.
var longitude_ascending_node: float:
	get = get_longitude_ascending_node, set = set_longitude_ascending_node
## Argument of periapsis (ω). 0 ≤ ω < 2π. (Note: there is a convention where
## retrograde orbits are wrapped clockwise, -2π < ω ≤ 0, but we don't do that
## here because it adds complexity without changing calculations.)
## ω = ϖ - Ω, where ϖ is longitude of periapsis. By convention, circular orbits
## have ω = 0. Precesses.
var argument_periapsis: float:
	get = get_argument_periapsis, set = set_argument_periapsis
## Time of periapsis passage (t₀). By convention, nearest to epoch time (+ or -)
## for elliptic orbits.
var time_periapsis: float: get = get_time_periapsis, set = set_time_periapsis
## Standard gravitational parameter (GM, μ). Gravitational constant (G) x parent
## barycenter mass. Note: this is an effective barycenter GM that may differ
## somewhat from parent GM, mainly (but not only) due to excess barycenter mass
## (>+10% for Pluto's moons).
var gravitational_parameter: float:
	get = get_gravitational_parameter, set = set_gravitational_parameter

## Semi-major axis (a). a > 0 (elliptic orbit); a = INF (parabolic); a < 0 (hyperbolic).
var semi_major_axis: float: get = get_semi_major_axis, set = set_semi_major_axis
## Mean motion (n). n > 0 (elliptic and hyperbolic orbits); n = 0 (parabolic).
## For elliptic orbit, period (P) = TAU / n.
var mean_motion: float: get = get_mean_motion, set = set_mean_motion
## Specific energy (ε). ε < 0 (elliptic orbit, i.e., "captured"); ε = 0 (parabolic);
## ε > 0 (hyperbolic).
var specific_energy: float: get = get_specific_energy, set = set_specific_energy
## Magnitude of the specific angular momentum (h). Positive for all orbits.
var specific_angular_momentum: float:
	get = get_specific_angular_momentum, set = set_specific_angular_momentum

## Ω₀ for precession calculations.
var longitude_ascending_node_at_epoch: float:
	get = get_longitude_ascending_node_at_epoch, set = set_longitude_ascending_node_at_epoch
## dΩ/dt. This is nodal precession, possibly with a sign flip. See
## [member argument_periapsis_rate].
var longitude_ascending_node_rate: float:
	get = get_longitude_ascending_node_rate, set = set_longitude_ascending_node_rate
## ω₀ for precession calculations.
var argument_periapsis_at_epoch: float:
	get = get_argument_periapsis_at_epoch, set = set_argument_periapsis_at_epoch
## dω/dt. Note that dω/dt = dϖ/dt - dΩ/dt, where dϖ/dt is apsidal precession*
## and dΩ/dt is nodal precession*. (* Nodal and apsidal precessions may have
## sign flips: positive nodal precession is opposite to the direction of orbit,
## while positive apsidal precession is in the direction of orbit.) See also
## [member longitude_ascending_node_rate].
var argument_periapsis_rate: float:
	get = get_argument_periapsis_rate, set = set_argument_periapsis_rate


# defining elements
var _reference_plane_type: ReferencePlane
var _reference_basis: Basis
var _semi_parameter: float
var _eccentricity: float
var _inclination: float
var _longitude_ascending_node: float
var _argument_periapsis: float
var _time_periapsis: float
var _gravitational_parameter: float

# derived elements & parameters
var _semi_major_axis: float
var _mean_motion: float
var _specific_energy: float
var _specific_angular_momentum: float

# precessions
var _longitude_ascending_node_at_epoch: float
var _longitude_ascending_node_rate: float
var _argument_periapsis_at_epoch: float
var _argument_periapsis_rate: float

# state params from update()
var _mean_anomaly := 0.0
var _true_anomaly := 0.0



# *****************************************************************************
# static methods

## Creates new IVOrbit instance from elements. [param existing_orbit can be
## supplied to reuse an existing IVOrbit or to parameterize a subclass instance.]
@warning_ignore("shadowed_variable")
static func create_from_elements(
		reference_plane_type: ReferencePlane,
		reference_basis: Basis,
		semi_parameter: float,
		eccentricity: float,
		inclination: float,
		longitude_ascending_node: float,
		longitude_ascending_node_rate: float,
		argument_periapsis: float,
		argument_periapsis_rate: float,
		time_periapsis: float,
		gravitational_parameter: float,
		existing_orbit: IVOrbit = null
	) -> IVOrbit:
	
	const RIGHT_ANGLE := PI / 2
	
	assert(reference_plane_type != ReferencePlane.REFERENCE_PLANE_ECLIPTIC
			or reference_basis == Basis.IDENTITY)
	assert(reference_basis.is_conformal() and reference_basis.x.is_normalized())
	assert(semi_parameter > 0.0)
	assert(eccentricity >= 0.0)
	
	assert(inclination >= MIN_INCLINATION and inclination <= PI)
	assert(!is_nan(longitude_ascending_node))
	assert(!is_nan(longitude_ascending_node_rate))
	assert(!is_nan(argument_periapsis))
	assert(!is_nan(argument_periapsis_rate))
	assert(!is_nan(time_periapsis))
	assert(gravitational_parameter > 0.0)
	
	# Quietly fix inclination too near RIGHT_ANGLE
	if absf(inclination - RIGHT_ANGLE) < INCLINATION_RIGHT_ANGLE_BUMP:
		inclination = RIGHT_ANGLE - INCLINATION_RIGHT_ANGLE_BUMP
	
	var orbit := existing_orbit
	if !orbit:
		orbit = IVOrbit.new()
	
	# defining args
	orbit._reference_plane_type = reference_plane_type
	orbit._reference_basis = reference_basis
	orbit._semi_parameter = semi_parameter
	orbit._eccentricity = eccentricity
	orbit._inclination = inclination
	orbit._longitude_ascending_node_at_epoch = longitude_ascending_node
	orbit._longitude_ascending_node_rate = longitude_ascending_node_rate
	orbit._argument_periapsis_at_epoch = argument_periapsis
	orbit._argument_periapsis_rate = argument_periapsis_rate
	orbit._time_periapsis = time_periapsis
	orbit._gravitational_parameter = gravitational_parameter
	
	# set evolving parameters to epoch
	orbit._longitude_ascending_node = longitude_ascending_node
	orbit._argument_periapsis = argument_periapsis
	
	# derived
	if eccentricity != 1.0:
		orbit._semi_major_axis = semi_parameter / (1.0 - eccentricity * eccentricity)
		orbit._mean_motion = sqrt(gravitational_parameter / absf(orbit._semi_major_axis) ** 3)
		orbit._specific_energy = -0.5 * gravitational_parameter / orbit._semi_major_axis
	else:
		orbit._semi_major_axis = INF
		orbit._mean_motion = 0.0
		orbit._specific_energy = 0.0
	orbit._specific_angular_momentum = sqrt(gravitational_parameter * semi_parameter)
	
	return orbit


## Creates new IVOrbit instance from state vectors and precession rates.
## @experimental: Not yet implemented.
@warning_ignore("shadowed_variable", "unused_parameter")
static func create_from_state_vectors_and_precessions(
		position: Vector3,
		velocity: Vector3,
		gravitational_parameter: float,
		reference_plane_type: ReferencePlane,
		reference_basis: Basis,
		longitude_ascending_node_rate: float,
		argument_periapsis_rate: float,
	) -> IVOrbit:
	
	return null


## Creates new IVOrbit instance from state vectors and orbit environment.
## @experimental: Not yet implemented.
@warning_ignore("shadowed_variable", "unused_parameter")
static func create_from_state_vectors_and_environment(
		position: Vector3,
		velocity: Vector3,
		gravitational_parameter: float,
		dynamic_form_factor: float, # primary's J2 (oblateness effect, known or estimated)
		primary_orbit: IVOrbit, # includes GM of the grandparent
		grandparent_orbit: IVOrbit, # For a Moon-oribiter, the Earth's orbit
		sibling_gm: float, # for an Earth satellite, the Moon
		sibling_orbit: IVOrbit, # for an Earth satellite, the Moon's orbit
	) -> IVOrbit:
	
	# I think the signature above is complete for very good precession estimates.
	# For LEO satellite, J2 effect >> everything else.
	# For HEO satellite, J2 is dominant (~90%) with small but significant Moon & Sun effects. 
	# For the Moon, Sun perturbation is dominant (>>90%), then J2.
	# For a Moon-orbiter, the Earth is the main effect, then maybe the Sun. (Moon isn't oblate.)
	
	return null


## Static method returns mean anomaly (M) for an elliptic orbit (e < 1). 0 ≤ M < 2π.
@warning_ignore("shadowed_variable")
static func get_mean_anomaly_from_elements_elliptic(time_periapsis: float,
		mean_motion: float, time: float) -> float:
	return fposmod(mean_motion * (time - time_periapsis) + PI, TAU) - PI


## Static method returns mean anomaly (M) for a hyperbolic orbit (e > 1). 0 ≤ M < 2π.
@warning_ignore("shadowed_variable")
static func get_mean_anomaly_from_elements_hyperbolic(time_periapsis: float,
		mean_motion: float, time: float) -> float:
	return mean_motion * (time - time_periapsis) # time_periapsis is singular!


## Static method returns mean anomaly (M) for a parabolic orbit (e = 1). 0 ≤ M < 2π.
## This is a "by convention" M that relates to time of perihelion passage in Barker's equation.
@warning_ignore("shadowed_variable")
static func get_mean_anomaly_from_elements_parabolic(semi_parameter: float,time_periapsis: float,
		gravitational_parameter: float, time: float) -> float:
	# https://en.wikipedia.org/wiki/Parabolic_trajectory
	# M below is a sort of "mean anomaly" by convention.
	var q := semi_parameter / 2.0 # radius at periapsis
	return (time - time_periapsis) * sqrt(gravitational_parameter / (2.0 * q * q * q))


## Static method returns true anomaly (θ; estimated iteratively) for an elliptic
## orbit (e < 1). -π ≤ θ < π.
@warning_ignore("shadowed_variable")
static func get_true_anomaly_from_mean_anomaly_elliptic(eccentricity: float, mean_anomaly: float
		) -> float:
	assert(eccentricity < 1.0)
	const TOLERANCE := 1e-5 # TODO: Bump down
	# TODO: Use alternative (faster) convergence algorithm when e > 0.8.
	var ea := mean_anomaly + eccentricity * sin(mean_anomaly) # eccentric anomaly; initial estimate
	var delta_ea := (ea - eccentricity * sin(ea) - mean_anomaly) / (1.0 - eccentricity * cos(ea))
	ea -= delta_ea
	while absf(delta_ea) > TOLERANCE:
		delta_ea = (ea - eccentricity * sin(ea) - mean_anomaly) / (1.0 - eccentricity * cos(ea))
		ea -= delta_ea
	return 2.0 * atan(sqrt((1.0 + eccentricity) / (1.0 - eccentricity)) * tan(ea / 2.0))


## Static method returns true anomaly (θ; estimated iteratively) for a hyperbolic
## orbit (e > 1). -π ≤ θ < π.
@warning_ignore("shadowed_variable")
static func get_true_anomaly_from_mean_anomaly_hyperbolic(eccentricity: float, mean_anomaly: float
		) -> float:
	assert(eccentricity > 1.0)
	const TOLERANCE := 1e-5 # TODO: Bump down
	var s := -1.0 if mean_anomaly < 0.0 else 1.0
	var ea := s * log(s * 2.0 * mean_anomaly / (eccentricity + 1.0) + 1.0) # initial estimate
	var delta_ea := (eccentricity * sinh(ea) - ea - mean_anomaly) / (eccentricity * cosh(ea) - 1.0)
	ea -= delta_ea
	while absf(delta_ea) > TOLERANCE:
		delta_ea = (eccentricity * sinh(ea) - ea - mean_anomaly) / (eccentricity * cosh(ea) - 1.0)
		ea -= delta_ea
	return 2.0 * atan(sqrt((eccentricity + 1.0) / (eccentricity - 1.0)) * tanh(ea / 2.0))


## Static method returns true anomaly (θ) for a parabolic orbit (e = 1). -π ≤ θ < π.
@warning_ignore("shadowed_variable")
static func get_true_anomaly_from_mean_anomaly_parabolic(mean_anomaly: float) -> float:
	# https://en.wikipedia.org/wiki/Parabolic_trajectory
	return 2.0 * atan(2.0 * sinh(asinh(1.5 * mean_anomaly) / 3.0))


## Static method returns position for specified orbit elements at [param true_anomaly].
## Reference basis is intrinsic.
@warning_ignore("shadowed_variable")
static func get_position_from_elements_at_true_anomaly(semi_parameter: float, eccentricity: float,
		inclination: float, longitude_ascending_node: float, argument_periapsis: float,
		true_anomaly: float) -> Vector3:
	
	var r := semi_parameter / (1.0 + eccentricity * cos(true_anomaly))
	var sin_i := sin(inclination)
	var cos_i := cos(inclination)
	var sin_lan := sin(longitude_ascending_node)
	var cos_lan := cos(longitude_ascending_node)
	var sin_ap_nu := sin(argument_periapsis + true_anomaly)
	var cos_ap_nu := cos(argument_periapsis + true_anomaly)
	var x := r * (cos_lan * cos_ap_nu - sin_lan * sin_ap_nu * cos_i)
	var y := r * (sin_lan * cos_ap_nu + cos_lan * sin_ap_nu * cos_i)
	var z := r * (sin_ap_nu * sin_i)
	
	return Vector3(x, y, z)


## Static method returns position and velocity for specified orbit elements at
## [param true_anomaly]. Reference basis is intrinsic.
## @experimental: Velocity result has not been tested.
@warning_ignore("shadowed_variable")
static func get_state_vectors_from_elements_at_true_anomaly(semi_parameter: float,
		eccentricity: float, inclination: float, longitude_ascending_node: float,
		argument_periapsis: float, specific_angular_momentum: float,
		true_anomaly: float) -> Array[Vector3]:
	
	# COPIED FROM ABOVE (BEGIN)
	var r := semi_parameter / (1.0 + eccentricity * cos(true_anomaly))
	var sin_i := sin(inclination)
	var cos_i := cos(inclination)
	var sin_lan := sin(longitude_ascending_node)
	var cos_lan := cos(longitude_ascending_node)
	var sin_ap_nu := sin(argument_periapsis + true_anomaly)
	var cos_ap_nu := cos(argument_periapsis + true_anomaly)
	var x := r * (cos_lan * cos_ap_nu - sin_lan * sin_ap_nu * cos_i)
	var y := r * (sin_lan * cos_ap_nu + cos_lan * sin_ap_nu * cos_i)
	var z := r * (sin_ap_nu * sin_i)
	# COPIED FROM ABOVE (END)
	
	var c := specific_angular_momentum * eccentricity * sin(true_anomaly) / (r * semi_parameter)
	var angular_v := specific_angular_momentum / r
	var vx := c * x - angular_v * (cos_lan * sin_ap_nu + sin_lan * cos_ap_nu * cos_i)
	var vy := c * y - angular_v * (sin_lan * sin_ap_nu - cos_lan * cos_ap_nu * cos_i)
	var vz := c * z - angular_v * (cos_ap_nu * sin_i)
	
	return [Vector3(x, y, z), Vector3(vx, vy, vz)]


## Static method returns the instantaneous orbit normal. Reference basis is intrinsic.
@warning_ignore("shadowed_variable")
static func get_normal_from_elements(inclination: float, longitude_ascending_node: float,
		flip_retrograde := false) -> Vector3:
	const RIGHT_ANGLE := PI / 2
	var sin_i := sin(inclination)
	var cos_i := cos(inclination)
	var sin_lan := sin(longitude_ascending_node)
	var cos_lan := cos(longitude_ascending_node)
	if flip_retrograde and inclination > RIGHT_ANGLE:
		return -Vector3(sin_i * sin_lan, -sin_i * cos_lan, cos_i)
	return Vector3(sin_i * sin_lan, -sin_i * cos_lan, cos_i)


## Static method returns the instantaneous orbit basis, where z-axis is normal
## to the orbit plane and x-axis is in the direction of periapsis. Reference
## basis is intrinsic.
@warning_ignore("shadowed_variable")
static func get_basis_from_elements(inclination: float, longitude_ascending_node: float,
		argument_periapsis: float) -> Basis:
	var sin_i := sin(inclination)
	var cos_i := cos(inclination)
	var sin_lan := sin(longitude_ascending_node)
	var cos_lan := cos(longitude_ascending_node)
	var sin_ap := sin(argument_periapsis)
	var cos_ap := cos(argument_periapsis)
	var sin_lan_cos_i := sin_lan * cos_i
	var cos_lan_cos_i := cos_lan * cos_i
	
	return Basis(
		Vector3(
			cos_lan * cos_ap - sin_lan_cos_i * sin_ap,
			sin_lan * cos_ap + cos_lan_cos_i * sin_ap,
			sin_i * sin_ap
		),
		Vector3(
			-cos_lan * sin_ap - sin_lan_cos_i * cos_ap,
			-sin_lan * sin_ap + cos_lan_cos_i * cos_ap,
			sin_i * cos_ap
		),
		Vector3(
			sin_i * sin_lan,
			-sin_i * cos_lan,
			cos_i
		)
	)


## Static method returns a Transform3D that can convert a unit circle into the
## specified orbit's path, if the specified orbit is closed (e < 1).
@warning_ignore("shadowed_variable")
static func get_unit_circle_transform_from_elements(semi_major_axis: float, eccentricity: float,
		inclination: float, longitude_ascending_node: float, argument_periapsis: float,
		reference_basis := Basis.IDENTITY) -> Transform3D:
	if eccentricity >= 1.0:
		return Transform3D()
	var b := sqrt(semi_major_axis * semi_major_axis * (1.0 - eccentricity * eccentricity))
	var orbit_basis := reference_basis * get_basis_from_elements(inclination,
			longitude_ascending_node, argument_periapsis)
	var basis := orbit_basis * Basis().scaled(Vector3(semi_major_axis, b, 1.0))
	return Transform3D(basis, -eccentricity * basis.x)


## Static method returns a Transform3D that can convert a unit rectangular hyperbola
## into the specified orbit's path, if the specified orbit is hyperbolic (e > 1).
@warning_ignore("shadowed_variable")
static func get_unit_rectangular_hyperbola_transform_from_elements(semi_major_axis: float,
		eccentricity: float, inclination: float, longitude_ascending_node: float,
		argument_periapsis: float, reference_basis := Basis.IDENTITY) -> Transform3D:
	const SQRT2 := sqrt(2.0) # rectangular hyperbola has e = sqrt(2)
	if eccentricity <= 1.0:
		return Transform3D()
	var b := sqrt(semi_major_axis * semi_major_axis * (eccentricity * eccentricity - 1.0))
	var orbit_basis := reference_basis * get_basis_from_elements(inclination,
			longitude_ascending_node, argument_periapsis)
	var basis := orbit_basis * Basis().scaled(Vector3(-semi_major_axis, b, 1.0))
	return Transform3D(basis, (eccentricity - SQRT2) * basis.x)


## Static method returns a Transform3D that can convert a unit parabola into the
## specified orbit's path, if the specified orbit is parabolic (e = 1).
@warning_ignore("shadowed_variable")
static func get_unit_parabola_transform_from_elements(semi_parameter: float, inclination: float,
		longitude_ascending_node: float, argument_periapsis: float,
		reference_basis := Basis.IDENTITY) -> Transform3D:
	var orbit_basis := reference_basis * get_basis_from_elements(inclination,
			longitude_ascending_node, argument_periapsis)
	var basis := orbit_basis * Basis().scaled(Vector3(semi_parameter, semi_parameter, 1.0))
	return Transform3D(basis, Vector3.ZERO)


## Static method returns time of periapsis passage (t₀) modulo orbit period (P)
## such that -P/2 ≤ t₀ < +P/2. Only elliptic orbits repeat!
@warning_ignore("shadowed_variable")
static func modulo_time_periapsis_elliptic(time_periapsis: float, mean_motion: float) -> float:
	# Watch out for comet with million year period! We don't want to add and
	# then subtract 1.5e13 seconds!
	var half_period := PI / mean_motion
	if time_periapsis > -half_period and time_periapsis <= half_period:
		return time_periapsis
	return fposmod(time_periapsis + half_period, 2.0 * half_period) - half_period


# *****************************************************************************
# update and get state (position, velocity) methods

# WARNING: For subclassing, many methods need override if additional elements
# evolve.

## Updates evolving elements to [param time] and emits [signal changed] if
## orbit has evolved a significant amount. Returns instantaneous position.
## Return can be in the ecliptic basis or the orbit [member reference_basis]
## (the former by default).
func update(time: float, rotate_to_ecliptic := true) -> Vector3:
	const CHANGED_ANGLE_THRESHOLD := CHANGED_THRESHOLD / TAU
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	
	# update & signal if accumulated change is significant
	if (absf(lan - _longitude_ascending_node) > CHANGED_ANGLE_THRESHOLD
			or absf(ap - _argument_periapsis) > CHANGED_ANGLE_THRESHOLD):
		_longitude_ascending_node = lan
		_argument_periapsis = ap
		changed.emit(true, true)
	
	# some inline static methods below...
	if _eccentricity < 1.0:
		_mean_anomaly = fposmod(_mean_motion * (time - _time_periapsis) + PI, TAU) - PI
		_true_anomaly = get_true_anomaly_from_mean_anomaly_elliptic(_eccentricity, _mean_anomaly)
	elif _eccentricity > 1.0:
		_mean_anomaly = _mean_motion * (time - _time_periapsis)
		_true_anomaly = get_true_anomaly_from_mean_anomaly_hyperbolic(_eccentricity, _mean_anomaly)
	else:
		_mean_anomaly = get_mean_anomaly_from_elements_parabolic(_semi_parameter, _time_periapsis,
				_gravitational_parameter, time)
		_true_anomaly = get_true_anomaly_from_mean_anomaly_parabolic(_mean_anomaly)
	
	var position := get_position_from_elements_at_true_anomaly(_semi_parameter, _eccentricity,
			_inclination, lan, ap, _true_anomaly)
	
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return _reference_basis * position
	return position


## Returns instantaneous position at [param time]. Return can be in the ecliptic
## basis or the orbit [member reference_basis] (the former by default).
## Position is relative to the parent body regardless of basis conversion.
func get_position(time: float, rotate_to_ecliptic := true) -> Vector3:
	
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	
	# some inline static methods below...
	var nu: float # true anomaly
	if _eccentricity < 1.0:
		var m := fposmod(_mean_motion * (time - _time_periapsis) + PI, TAU) - PI
		nu = get_true_anomaly_from_mean_anomaly_elliptic(_eccentricity, m)
	elif _eccentricity > 1.0:
		var m := _mean_motion * (time - _time_periapsis)
		nu = get_true_anomaly_from_mean_anomaly_hyperbolic(_eccentricity, m)
	else:
		var m := get_mean_anomaly_from_elements_parabolic(_semi_parameter, _time_periapsis,
				_gravitational_parameter, time)
		nu = get_true_anomaly_from_mean_anomaly_parabolic(m)
	
	var position := get_position_from_elements_at_true_anomaly(_semi_parameter, _eccentricity,
			_inclination, lan, ap, nu)
	
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return _reference_basis * position
	return position


## Returns instantaneous position and velocity at [param time]. Return can be in
## the ecliptic basis or the orbit [member reference_basis] (the former by default).
## Position and velocity are relative to the parent body regardless of basis conversion.
## @experimental: The velocity component has not been tested yet!
func get_state_vectors(time: float, rotate_to_ecliptic := true) -> Array[Vector3]:
	
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	
	# some inline static methods below...
	var nu: float # true anomaly
	if _eccentricity < 1.0:
		var m := fposmod(_mean_motion * (time - _time_periapsis) + PI, TAU) - PI
		nu = get_true_anomaly_from_mean_anomaly_elliptic(_eccentricity, m)
	elif _eccentricity > 1.0:
		var m := _mean_motion * (time - _time_periapsis)
		nu = get_true_anomaly_from_mean_anomaly_hyperbolic(_eccentricity, m)
	else:
		var m := get_mean_anomaly_from_elements_parabolic(_semi_parameter, _time_periapsis,
				_gravitational_parameter, time)
		nu = get_true_anomaly_from_mean_anomaly_parabolic(m)
	
	var vectors := get_state_vectors_from_elements_at_true_anomaly(_semi_parameter, _eccentricity,
			_inclination, lan, ap, _specific_angular_momentum, nu)
	
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return [_reference_basis * vectors[0], _reference_basis * vectors[1]]
	return vectors


## Returns mean anomaly (M) at [param time]. -π ≤ M < π. Valid for any orbit.
## (For parabolic orbit, this is a "by convention" M that relates to time of
## perihelion passage in Barker's equation.)
func get_mean_anomaly(time: float) -> float:
	if _eccentricity < 1.0:
		return fposmod(_mean_motion * (time - _time_periapsis) + PI, TAU) - PI
	if _eccentricity > 1.0:
		return _mean_motion * (time - _time_periapsis)
	return get_mean_anomaly_from_elements_parabolic(_semi_parameter, _time_periapsis,
			_gravitational_parameter, time)


## Returns mean anomaly (M) after the last [method update] call. -π ≤ M < π.
## Valid for any orbit. (For parabolic orbit, this is a "by convention" M that
## relates to time of perihelion passage in Barker's equation.)
func get_mean_anomaly_at_update() -> float:
	return _mean_anomaly


## Returns mean longitude (L) at [param time]. 0 ≤ L < 2π. L = M + Ω + ω, where
## M is mean anomaly, Ω is longitude of the ascending node, and ω is argument
## of periapsis.
func get_mean_longitude(time: float) -> float:
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	
	return fposmod(get_mean_anomaly(time) + lan + ap, TAU)


## Returns mean longitude (L) after the last [method update] call. 0 ≤ L < 2π.
## L = M + Ω + ω, where M is mean anomaly, Ω is longitude of the ascending node,
## and ω is argument of periapsis.
func get_mean_longitude_at_update() -> float:
	return fposmod(_mean_anomaly + _longitude_ascending_node + _argument_periapsis, TAU)


## Returns true anomaly (θ) at [param time]. -π ≤ θ < π.
func get_true_anomaly(time: float) -> float:
	
	var m: float # mean anomaly
	if _eccentricity < 1.0:
		m = fposmod(_mean_motion * (time - _time_periapsis) + PI, TAU) - PI
		return get_true_anomaly_from_mean_anomaly_elliptic(_eccentricity, m)
	if _eccentricity > 1.0:
		m = _mean_motion * (time - _time_periapsis)
		return get_true_anomaly_from_mean_anomaly_hyperbolic(_eccentricity, m)
	m = get_mean_anomaly_from_elements_parabolic(_semi_parameter, _time_periapsis,
				_gravitational_parameter, time)
	return get_true_anomaly_from_mean_anomaly_parabolic(m)


## Returns true anomaly (θ) after the last [method update] call. -π ≤ θ < π.
func get_true_anomaly_at_update() -> float:
	return _true_anomaly


## Returns true longitude (l) at [param time]. 0 ≤ l < 2π. l = θ + Ω + ω, where
## θ is true anomaly, Ω is longitude of the ascending node, and ω is argument
## of periapsis.
func get_true_longitude(time: float) -> float:
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	
	return fposmod(get_true_anomaly(time) + lan + ap, TAU)


## Returns true longitude (l) after the last [method update] call. 0 ≤ l < 2π.
## l = θ + Ω + ω, where θ is true anomaly, Ω is longitude of the ascending node,
## and ω is argument of periapsis.
func get_true_longitude_at_update() -> float:
	return fposmod(_true_anomaly + _longitude_ascending_node + _argument_periapsis, TAU)


## Returns radius (r) at [param time].
func get_radius(time: float) -> float:
	var nu := get_true_anomaly(time)
	return _semi_parameter / (1.0 + _eccentricity * cos(nu))


## Returns radius (r) after the last [method update] call.
func get_radius_at_update() -> float:
	return _semi_parameter / (1.0 + _eccentricity * cos(_true_anomaly))


# *****************************************************************************
# Element gets and sets


func get_reference_plane_type() -> ReferencePlane:
	return _reference_plane_type


func get_reference_basis() -> Basis:
	return _reference_basis


func set_reference_plane_and_basis(plane_type: ReferencePlane, basis: Basis) -> void:
	assert(plane_type != ReferencePlane.REFERENCE_PLANE_ECLIPTIC or basis == Basis.IDENTITY)
	assert(basis.is_conformal() and basis.x.is_normalized())
	_reference_plane_type = plane_type
	_reference_basis = basis
	changed.emit(false, false)


func get_semi_parameter() -> float:
	return _semi_parameter


## Note: semi-parameter (p) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_semi_parameter_at_time(_time: float) -> float:
	return _semi_parameter


## Note: semi-parameter (p) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_semi_parameter_at_epoch() -> float:
	return _semi_parameter


## Note: semi-parameter (p) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_semi_parameter_rate() -> float:
	return 0.0


## Keeps e and GM fixed; changes other parameters as needed.
func set_semi_parameter(value: float) -> void:
	if value <= 0.0:
		return
	_semi_parameter = value
	if _eccentricity != 1.0:
		_semi_major_axis = _semi_parameter / (1.0 - _eccentricity * _eccentricity)
		_mean_motion = sqrt(_gravitational_parameter / absf(_semi_major_axis) ** 3)
		_specific_energy = -0.5 * _gravitational_parameter / _semi_major_axis
	else:
		_semi_major_axis = INF
		_mean_motion = 0.0
		_specific_energy = 0.0
	_specific_angular_momentum = sqrt(_gravitational_parameter * _semi_parameter)
	changed.emit(false, false)


func get_eccentricity() -> float:
	return _eccentricity


## Note: eccentricity (e) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_eccentricity_at_time(_time: float) -> float:
	return _eccentricity


## Note: eccentricity (e) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_eccentricity_at_epoch() -> float:
	return _eccentricity


## Note: eccentricity (e) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_eccentricity_rate() -> float:
	return 0.0


## Keeps p and GM fixed; changes other parameters as needed.
func set_eccentricity(value: float) -> void:
	value = maxf(value, 0.0)
	_eccentricity = value
	if _eccentricity != 1.0:
		_semi_major_axis = _semi_parameter / (1.0 - _eccentricity * _eccentricity)
		_mean_motion = sqrt(_gravitational_parameter / absf(_semi_major_axis) ** 3)
		_specific_energy = -0.5 * _gravitational_parameter / _semi_major_axis
	else:
		_semi_major_axis = INF
		_mean_motion = 0.0
		_specific_energy = 0.0
	changed.emit(false, false)


func get_inclination() -> float:
	return _inclination


## Note: inclination (i) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_inclination_at_time(_time: float) -> float:
	# evolve orbit (override)
	return _inclination


## Note: inclination (i) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_inclination_at_epoch() -> float:
	return _inclination


## Note: inclination (i) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_inclination_rate() -> float:
	return 0.0


func set_inclination(value: float) -> void:
	const RIGHT_ANGLE := PI / 2
	value = clampf(value, MIN_INCLINATION, PI)
	if absf(value - RIGHT_ANGLE) < INCLINATION_RIGHT_ANGLE_BUMP:
		value = RIGHT_ANGLE - INCLINATION_RIGHT_ANGLE_BUMP
	_inclination = value
	changed.emit(false, false)


# Subclass overrides:
# Follow Ω pattern below for evolving elements with _at_epoch & _rate.

func get_longitude_ascending_node() -> float:
	return _longitude_ascending_node


func get_longitude_ascending_node_at_time(time: float) -> float:
	return fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)


func get_longitude_ascending_node_at_epoch() -> float:
	return _longitude_ascending_node_at_epoch


func get_longitude_ascending_node_rate() -> float:
	return _longitude_ascending_node_rate


func set_longitude_ascending_node(value: float) -> void:
	set_longitude_ascending_node_at_epoch(value - _longitude_ascending_node)


func set_longitude_ascending_node_at_epoch(value: float) -> void:
	_longitude_ascending_node_at_epoch = fposmod(value, TAU)
	changed.emit(false, false)


func set_longitude_ascending_node_rate(value: float) -> void:
	# Prevent instantaneous change in current position...
	set_longitude_ascending_node_rate_at_time(value, IVGlobal.times[0])


## Sets Ωr and resets Ω₀ such that there is no instantaneous change in Ω at [param time].
func set_longitude_ascending_node_rate_at_time(value: float, time: float) -> void:
	_longitude_ascending_node_rate = value
	if !time:
		changed.emit(false, false)
		return
	set_longitude_ascending_node_at_epoch(_longitude_ascending_node - value * time)


func get_argument_periapsis() -> float:
	return _argument_periapsis


func get_argument_periapsis_at_time(time: float) -> float:
	return fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)


func get_argument_periapsis_at_epoch() -> float:
	return _argument_periapsis_at_epoch


func get_argument_periapsis_rate() -> float:
	return _argument_periapsis_rate


func set_argument_periapsis(value: float) -> void:
	set_argument_periapsis_at_epoch(value - _argument_periapsis)


func set_argument_periapsis_at_epoch(value: float) -> void:
	_argument_periapsis_at_epoch = fposmod(value, TAU)
	changed.emit(false, false)


func set_argument_periapsis_rate(value: float) -> void:
	# Prevent instantaneous change in current position...
	set_argument_periapsis_rate_at_time(value, IVGlobal.times[0])


## Sets ωr and resets ω₀ such that there is no instantaneous change in ω at [param time].
func set_argument_periapsis_rate_at_time(value: float, time: float) -> void:
	_argument_periapsis_rate = value
	if !time:
		changed.emit(false, false)
		return
	set_argument_periapsis_at_epoch(_argument_periapsis - value * time)



func get_time_periapsis() -> float:
	return _time_periapsis


## Note: time periapsis (t₀) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_time_periapsis_at_time(_time: float) -> float:
	return _time_periapsis


## Note: time periapsis (t₀) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_time_periapsis_at_epoch() -> float:
	return _time_periapsis


## Note: time periapsis (t₀) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_time_periapsis_rate() -> float:
	return 0.0


func set_time_periapsis(value: float) -> void:
	if _eccentricity < 1.0:
		value = modulo_time_periapsis_elliptic(value, _mean_motion)
	_time_periapsis = value
	changed.emit(false, false)


func get_gravitational_parameter() -> float:
	return _gravitational_parameter


## Note: standard gravitational parameter (GM) does not evolve in the base
## IVOrbit class, but it may in a subclass.
func get_gravitational_parameter_at_time(_time: float) -> float:
	return _gravitational_parameter


## Note: standard gravitational parameter (GM) does not evolve in the base
## IVOrbit class, but it may in a subclass.
func get_gravitational_parameter_at_epoch() -> float:
	return _gravitational_parameter


## Note: standard gravitational parameter (GM) does not evolve in the base
## IVOrbit class, but it may in a subclass.
func get_gravitational_parameter_rate() -> float:
	return 0.0



## Keeps orbit shape fixed; changes other parameters as needed.
func set_gravitational_parameter(value: float) -> void:
	_gravitational_parameter = value
	if _eccentricity != 1.0:
		_mean_motion = sqrt(_gravitational_parameter / absf(_semi_major_axis) ** 3)
		_specific_energy = -0.5 * _gravitational_parameter / _semi_major_axis
	else:
		_mean_motion = 0.0
		_specific_energy = 0.0
	_specific_angular_momentum = sqrt(_gravitational_parameter * _semi_parameter)
	changed.emit(false, false)


func get_semi_major_axis() -> float:
	return _semi_major_axis


## Note: semi-major axis (a) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_semi_major_axis_at_time(_time: float) -> float:
	return _semi_major_axis


## Note: semi-major axis (a) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_semi_major_axis_at_epoch() -> float:
	return _semi_major_axis


## Note: semi-major axis (a) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_semi_major_axis_rate() -> float:
	return 0.0


## Keeps e and GM fixed; changes other parameters as needed. Must be non-zero
## and non-INF, sign must be consistant with e, and e must not equal 1.0.
func set_semi_major_axis(value: float) -> void:
	if value == 0.0 or is_inf(value):
		return
	if (value > 0.0) != (_eccentricity < 1.0) or _eccentricity == 1.0:
		return
	_semi_major_axis = value
	_semi_parameter = _semi_major_axis * (1.0 - _eccentricity * _eccentricity)
	_mean_motion = sqrt(_gravitational_parameter / absf(_semi_major_axis) ** 3)
	_specific_energy = -0.5 * _gravitational_parameter / _semi_major_axis
	_specific_angular_momentum = sqrt(_gravitational_parameter * _semi_parameter)
	changed.emit(false, false)


func get_mean_motion() -> float:
	return _mean_motion


## Note: mean motion (n) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_mean_motion_at_time(_time: float) -> float:
	return _mean_motion


## Note: mean motion (n) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_mean_motion_at_epoch() -> float:
	return _mean_motion


## Note: mean motion (n) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_mean_motion_rate() -> float:
	return 0.0


## Keeps e and GM fixed; changes other parameters as needed. Must be positive and
## e must not equal 1.0.
func set_mean_motion(value: float) -> void:
	if value <= 0.0 or _eccentricity == 1.0:
		return
	_mean_motion = value
	var s := 1.0 if _eccentricity < 1.0 else -1.0
	_semi_major_axis = s * (sqrt(_gravitational_parameter) / _mean_motion) ** (1.0 / 3.0)
	_semi_parameter = _semi_major_axis * (1.0 - _eccentricity * _eccentricity)
	_specific_energy = -0.5 * _gravitational_parameter / _semi_major_axis
	_specific_angular_momentum = sqrt(_gravitational_parameter * _semi_parameter)
	changed.emit(false, false)


func get_specific_energy() -> float:
	return _specific_energy


## Note: specific energy (ε) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_specific_energy_at_time(_time: float) -> float:
	return _specific_energy


## Note: specific energy (ε) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_specific_energy_at_epoch() -> float:
	return _specific_energy


## Note: specific energy (ε) does not evolve in the base IVOrbit class, but it may in a subclass.
func get_specific_energy_rate() -> float:
	return 0.0


func set_specific_energy(value: float) -> void:
	_specific_energy = value
	
	# TODO: Energy!
	
	changed.emit(false, false)


func get_specific_angular_momentum() -> float:
	return _specific_angular_momentum


## Note: specific angular momentum (h) does not evolve in the base IVOrbit class,
## but it may in a subclass.
func get_specific_angular_momentum_at_time(_time: float) -> float:
	return _specific_angular_momentum


## Note: specific angular momentum (h) does not evolve in the base IVOrbit class,
## but it may in a subclass.
func get_specific_angular_momentum_at_epoch() -> float:
	return _specific_angular_momentum


## Note: specific angular momentum (h) does not evolve in the base IVOrbit class,
## but it may in a subclass.
func get_specific_angular_momentum_rate() -> float:
	return 0.0


## Keeps e and GM fixed; changes other parameters as needed. Must be positive.
func set_specific_angular_momentum(value: float) -> void:
	if value <= 0.0:
		return
	_specific_angular_momentum = value
	_semi_parameter = _specific_angular_momentum ** 2 / _gravitational_parameter
	if _eccentricity != 1.0:
		_semi_major_axis = _semi_parameter / (1.0 - _eccentricity * _eccentricity)
		_mean_motion = sqrt(_gravitational_parameter / absf(_semi_major_axis) ** 3)
		_specific_energy = -0.5 * _gravitational_parameter / _semi_major_axis
	else:
		_semi_major_axis = INF
		_mean_motion = 0.0
		_specific_energy = 0.0
	changed.emit(false, false)


# *****************************************************************************
# Derivable elements


## Returns logitude of periapsis (ϖ). 0 ≤ ϖ < 2π. Requires preceding [method update]
## call to be current if orbit has precessions.
func get_longitude_periapsis() -> float:
	return fposmod(_longitude_ascending_node + _argument_periapsis, TAU)


## Returns logitude of periapsis (ϖ). 0 ≤ ϖ < 2π. 
func get_longitude_periapsis_at_time(time: float) -> float:
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	return fposmod(lan + ap, TAU)


## Returns logitude of periapsis rate (dϖ/dt).
func get_longitude_periapsis_rate() -> float:
	return _longitude_ascending_node_rate + _argument_periapsis_rate


## Returns mean anomaly at epoch (M₀). 0 ≤ M₀ < 2π.
func get_mean_anomaly_at_epoch() -> float:
	return fposmod(-_mean_motion * _time_periapsis, TAU)


## Note: mean anomaly at epoch (M₀) does not evolve in the base IVOrbit class,
## but it may in a subclass.
func get_mean_anomaly_at_epoch_at_time(_time: float) -> float:
	return fposmod(-_mean_motion * _time_periapsis, TAU)


## Note: mean anomaly at epoch (M₀) does not evolve in the base IVOrbit class,
## but it may in a subclass.
func get_mean_anomaly_at_epoch_rate() -> float:
	return 0.0


## Returns mean longitude at epoch (L₀). 0 ≤ L₀ < 2π.
func get_mean_longitude_at_epoch() -> float:
	return fposmod(-_mean_motion * _time_periapsis + _longitude_ascending_node_at_epoch
			+ _argument_periapsis_at_epoch, TAU)


## Returns mean longitude at epoch rate (dL₀/dt).
func get_mean_longitude_at_epoch_rate() -> float:
	return _longitude_ascending_node_rate + _argument_periapsis_rate


## Returns mean longitude rate (dL/dt).
func get_mean_longitude_rate() -> float:
	return _mean_motion + _longitude_ascending_node_rate + _argument_periapsis_rate


# *****************************************************************************
# Orbit spatial derivations


func is_retrograde() -> bool:
	const RIGHT_ANGLE := PI / 2
	return _inclination > RIGHT_ANGLE


## Note: inclination (i) does not evolve in the base IVOrbit class, but it may in a subclass.
func is_retrograde_at_time(_time: float) -> bool:
	const RIGHT_ANGLE := PI / 2
	return _inclination > RIGHT_ANGLE


## Returns the instantaneous orbit normal. Return can be in the ecliptic basis or the orbit
## [member reference_basis] (the former by default).
## Requires preceding [method update] call to be current if orbit is evolving.
func get_normal(rotate_to_ecliptic := true, flip_retrograde := false) -> Vector3:
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	var normal := get_normal_from_elements(_inclination, _longitude_ascending_node, flip_retrograde)
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return _reference_basis * normal
	return normal


## Returns the instantaneous orbit normal. Return can be in the ecliptic basis
## or the orbit [member reference_basis] (the former by default).
func get_normal_at_time(time: float, rotate_to_ecliptic := true, flip_retrograde := false) -> Vector3:
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	
	var normal := get_normal_from_elements(_inclination, lan, flip_retrograde)
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return _reference_basis * normal
	return normal


## Returns the instantaneous orbit basis, where z-axis is normal to the orbit
## plane and x-axis is in the direction of periapsis. Return can be in the ecliptic
## basis or the orbit [member reference_basis] (the former by default).
## Requires preceding [method update] call to be current if orbit is evolving.
func get_basis(rotate_to_ecliptic := true) -> Basis:
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	var basis := get_basis_from_elements(_inclination, _longitude_ascending_node, _argument_periapsis)
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return _reference_basis * basis
	return basis


## Returns the instantaneous orbit basis, where z-axis is normal to the orbit
## plane and x-axis is in the direction of periapsis. Return can be in the ecliptic
## basis or the orbit [member reference_basis] (the former by default).
func get_basis_at_time(time: float, rotate_to_ecliptic := true) -> Basis:
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	
	var basis := get_basis_from_elements(_inclination, lan, ap)
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return _reference_basis * basis
	return basis


## Returned Transform3D can convert a unit circle into this orbit's path, if
## this orbit is closed (e < 1).
func get_unit_circle_transform(rotate_to_ecliptic := true) -> Transform3D:
	if _eccentricity >= 1.0:
		return Transform3D()
	var b := sqrt(_semi_major_axis * _semi_major_axis * (1.0 - _eccentricity * _eccentricity))
	var orbit_basis := get_basis(rotate_to_ecliptic)
	var basis := orbit_basis * Basis().scaled(Vector3(_semi_major_axis, b, 1.0))
	return Transform3D(basis, -_eccentricity * basis.x)


## Returned Transform3D can convert a unit circle into this orbit's path, if
## this orbit is closed (e < 1).
func get_unit_circle_transform_at_time(time: float, rotate_to_ecliptic := true) -> Transform3D:
	if _eccentricity >= 1.0:
		return Transform3D()
	var b := sqrt(_semi_major_axis * _semi_major_axis * (1.0 - _eccentricity * _eccentricity))
	var orbit_basis := get_basis_at_time(time, rotate_to_ecliptic)
	var basis := orbit_basis * Basis().scaled(Vector3(_semi_major_axis, b, 1.0))
	return Transform3D(basis, -_eccentricity * basis.x)


## Returned Transform3D can convert a unit rectangular hyperbola into this
## orbit's path, if this orbit is hyperbolic (e > 1).
func get_unit_rectangular_hyperbola_transform(rotate_to_ecliptic := true) -> Transform3D:
	const SQRT2 := sqrt(2.0) # rectangular hyperbola has e = sqrt(2)
	if _eccentricity <= 1.0:
		return Transform3D()
	var b := sqrt(_semi_major_axis * _semi_major_axis * (_eccentricity * _eccentricity - 1.0))
	var orbit_basis := get_basis(rotate_to_ecliptic)
	var basis := orbit_basis * Basis().scaled(Vector3(-_semi_major_axis, b, 1.0))
	return Transform3D(basis, (_eccentricity - SQRT2) * basis.x)


## Returned Transform3D can convert a unit rectangular hyperbola into this
## orbit's path, if this orbit is hyperbolic (e > 1).
func get_unit_rectangular_hyperbola_transform_at_time(time: float, rotate_to_ecliptic := true
		) -> Transform3D:
	const SQRT2 := sqrt(2.0) # rectangular hyperbola has e = sqrt(2)
	if _eccentricity <= 1.0:
		return Transform3D()
	var b := sqrt(_semi_major_axis * _semi_major_axis * (_eccentricity * _eccentricity - 1.0))
	var orbit_basis := get_basis_at_time(time, rotate_to_ecliptic)
	var basis := orbit_basis * Basis().scaled(Vector3(-_semi_major_axis, b, 1.0))
	return Transform3D(basis, (_eccentricity - SQRT2) * basis.x)


## Returned Transform3D can convert a unit parabola into this orbit's path, if
## this orbit is parabolic (e = 1).
func get_unit_parabola_transform(rotate_to_ecliptic := true) -> Transform3D:
	var orbit_basis := get_basis(rotate_to_ecliptic)
	var basis := orbit_basis * Basis().scaled(Vector3(_semi_parameter, _semi_parameter, 1.0))
	return Transform3D(basis, Vector3.ZERO)


## Returned Transform3D can convert a unit parabola into this orbit's path, if
## this orbit is parabolic (e = 1).
func get_unit_parabola_transform_at_time(time: float, rotate_to_ecliptic := true) -> Transform3D:
	var orbit_basis := get_basis_at_time(time, rotate_to_ecliptic)
	var basis := orbit_basis * Basis().scaled(Vector3(_semi_parameter, _semi_parameter, 1.0))
	return Transform3D(basis, Vector3.ZERO)


# *****************************************************************************
# serialize/deserialize


func serialize() -> PackedFloat64Array:
	var data := PackedFloat64Array()
	data.resize(27)
	data[0] = float(_reference_plane_type)
	data[1] = _reference_basis[0][0]
	data[2] = _reference_basis[0][1]
	data[3] = _reference_basis[0][2]
	data[4] = _reference_basis[1][0]
	data[5] = _reference_basis[1][1]
	data[6] = _reference_basis[1][2]
	data[7] = _reference_basis[2][0]
	data[8] = _reference_basis[2][1]
	data[9] = _reference_basis[2][2]
	data[10] = _semi_parameter
	data[11] = _eccentricity
	data[12] = _inclination
	data[13] = _longitude_ascending_node
	data[14] = _argument_periapsis
	data[15] = _time_periapsis
	data[16] = _gravitational_parameter
	data[17] = _semi_major_axis
	data[18] = _mean_motion
	data[19] = _specific_energy
	data[20] = _specific_angular_momentum
	data[21] = _longitude_ascending_node_at_epoch
	data[22] = _longitude_ascending_node_rate
	data[23] = _argument_periapsis_at_epoch
	data[24] = _argument_periapsis_rate
	data[25] = _mean_anomaly
	data[26] = _true_anomaly
	return data


func deserialize(data: PackedFloat64Array) -> void:
	_reference_plane_type = int(data[0]) as ReferencePlane
	_reference_basis[0][0] = data[1]
	_reference_basis[0][1] = data[2]
	_reference_basis[0][2] = data[3]
	_reference_basis[1][0] = data[4]
	_reference_basis[1][1] = data[5]
	_reference_basis[1][2] = data[6]
	_reference_basis[2][0] = data[7]
	_reference_basis[2][1] = data[8]
	_reference_basis[2][2] = data[9]
	_semi_parameter = data[10]
	_eccentricity = data[11]
	_inclination = data[12]
	_longitude_ascending_node = data[13]
	_argument_periapsis = data[14]
	_time_periapsis = data[15]
	_gravitational_parameter = data[16]
	_semi_major_axis = data[17]
	_mean_motion = data[18]
	_specific_energy = data[19]
	_specific_angular_momentum = data[20]
	_longitude_ascending_node_at_epoch = data[21]
	_longitude_ascending_node_rate = data[22]
	_argument_periapsis_at_epoch = data[23]
	_argument_periapsis_rate = data[24]
	_mean_anomaly = data[25]
	_true_anomaly = data[26]
