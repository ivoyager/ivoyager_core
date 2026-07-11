# orbit.gd
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
class_name IVOrbit
extends RefCounted

## Defines an elliptic orbit, or parabolic or hyperbolic trajectory, in a
## specified reference basis. This base class supports nodal and apsidal
## precessions.
##
## See Wikipedia [url=https://en.wikipedia.org/wiki/Orbital_elements]orbital
## elements[/url] for many of the concepts and technical terms used here.
## "Elements" are the parameters needed to specify an orbit and position in an
## orbit given time. Two elements, Ω and ω, can evolve over time in this base
## class, which means this class supports nodal and apsidal precessions
## (which means, for example, that it can define a
## [url=https://en.wikipedia.org/wiki/Sun-synchronous_orbit]Sun-synchronous orbit[/url].)
## Other elements may evolve or change in [IVOrbit] subclasses. Evolution of
## orbit elements is slow relative to change in position in an orbit.[br][br]
##
## Position and velocity in this class are always relative to the parent body
## or barycenter. The [member reference_basis] is the basis in which this orbit
## is defined, where the xy axes define the reference plane about which this
## orbit precesses. See also [member reference_plane_type].[br][br]
##
## In addition to epoch time (always
## [url=https://en.wikipedia.org/wiki/Epoch_(astronomy)#Julian_years_and_J2000]J2000[/url]),
## seven elements are needed to
## define an unpurturbed (osculating) orbit and position. The following elements
## are used here because they are valid for elliptic, parabolic and hyperbolic
## orbits/trajectories:[br][br]
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
## methods that follow naming convention "get_something_at_time()" and all static
## methods are valid without [method update]. Note that subclasses may evolve
## other elements in addition to the two precessing elements. Hence, many get
## functions require [param time] for parameters that are not time-dependent in
## this base class but may be time-dependent in subclasses.[br][br]
##
## Note: property setters are implemented in this class mainly for playing
## around at editor runtime. The setters generally hold eccentricity and GM
## fixed and adjust other elements as needed, but see methods for specific
## cases. Code based changes to elements should be implemented in a subclass
## (see Roadmap below).[br][br]
##
## [b]Thread safety.[/b] All get methods are threadsafe. The 64-bit getters
## [method get_translation] / [method get_state] populate a main-thread-only member buffer and
## return a copy-on-write duplicate on the main thread, or allocate a fresh [PackedFloat64Array]
## from a worker thread. [method update] and all set methods mutate state and/or emit
## [signal changed], so are main-thread only. Get results may be inconsistent if an orbit
## change is being set concurrently.[br][br][br]
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
## # "_at_time" is superfluous.
## get_parameter_at_update() # at last update() call
## get_parameter(time)
## get_parameter_from_something(...) # static
## [/codeblock][br]
##
## [b]Precision idiom (64/32-bit).[/b] Euclidean coordinates for real spatial calculations
## are ALWAYS 64-bit [PackedFloat64Array] (ivoyager does NOT require a 64-bit Godot build). To
## avoid confusion with [member Node3D.position], these are called "translation" (size-3
## [PackedFloat64Array]), "velocity" (size 3), "state" (size 6), and "basis" (size 9; see
## [IVMath64]). Any method that outputs a [Vector3] / [Basis] / [PackedVector3Array] is flagging
## its result as low precision, for graphics or similar use. Compare [method get_translation] /
## [method get_state] (64-bit) with [method get_position_vector] / [method get_state_vectors] /
## [method update] (32-bit).[br][br]
##
## [b]Roadmap[/b][br][br]
##
## TODO: Multiplayer RPC. We REALLY don't want to make this a Node. The reason
## is that IVOrbit is supposed to be a cheap data container that can be instanced
## in different contexts (e.g., for patched conic trajectory planning). What we
## want are serialization/deserialization methods here, and then [IVBody] does the
## RPC sync on [signal changed]. We only need network sync when the change is
## extrinsic (e.g., thrust).[br][br]
##
## TODO:
## [codeblock]
## create_from_state_and_environment(x, y, z, vx, vy, vz, gm, j2, ...)
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
## isn't ready yet).


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

## Dedupe threshold (radians of eccentric anomaly) when merging the two state-path knot families;
## also floors the Hermite interval away from zero. See [method refresh_state_path].
const STATE_PATH_MIN_KNOT_SEPARATION := 1e-4

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"parent_name",
	&"segment_begin",
	&"segment_end",
	&"_reference_plane_type",
	&"_reference_basis",
	&"_semi_parameter",
	&"_eccentricity",
	&"_inclination",
	&"_signaled_longitude_ascending_node",
	&"_signaled_argument_periapsis",
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
	&"_update_time",
]

## Set this script to generate a subclass in place of IVOrbit in create methods.
## Set [code]IVOrbit.replacement_subclass = MyOrbit[/code] for project-wide
## replacement.
static var replacement_subclass: Script


# persist
## Name of the parent body (gravitational primary) about which this orbit is
## defined. Required only if this [IVOrbit] is part of an [IVTrajectory]. Assumed
## to be invariant, so not handled by [method serialize] / [method deserialize].
var parent_name: StringName
## Segment start time (s). When this orbit is a segment in an [IVTrajectory], the
## trajectory uses this and [member segment_end] to select the active segment for
## a given time. Default -INF means no lower bound. Set by [IVTableOrbitBuilder].
var segment_begin := -INF
## Segment end time (s). See [member segment_begin]. Default INF means no upper bound.
var segment_end := INF

# non-persist (only used once in new game table load)
## If true, this cruise segment is re-fitted (via Lambert) through its neighbor
## segments' boundary positions to close patched-conic gaps; see [method
## IVTrajectory._fix_gaps]. Set by [IVTableOrbitBuilder] from orbits.tsv. Transient:
## consumed once during new-game build and intentionally NOT persisted (the fixed
## elements persist; the trigger flag does not).
var fix_gaps := false


# Public properties are all "redirect" vars so we can implement side-effects or
# force alternative set methods. Private counterparts are persisted.

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
var _reference_basis := PackedFloat64Array([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]) # size-9 row-major; see [IVMath64]
var _semi_parameter: float
var _eccentricity: float
var _inclination: float
var _signaled_longitude_ascending_node: float # last-signaled Ω; hysteresis detector for changed (see update()), NOT current Ω
var _signaled_argument_periapsis: float # last-signaled ω; hysteresis detector for changed (see update()), NOT current ω
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
var _update_time := 0.0 # 'time' of the last update(); reference time for no-arg getters: get_element() == get_element_at_time(_update_time)

# Reusable main-thread return buffers for get_translation() / get_state(); see class doc
# thread-safety. Main-thread-exclusive (worker calls allocate fresh), so never shared across threads.
var _translation_buffer := PackedFloat64Array([0.0, 0.0, 0.0])
var _state_buffer := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

# State path for orbit-line display (IVPathVisual), parallel to [member IVTrajectory.path]. One current
# period sampled at fixed curvature-aware density, in the ecliptic basis relative to the parent. Anchored
# on the current time (NOT the J2000 epoch), so an evolving orbit's line stays on its body. Non-persisted;
# (re)built by [method refresh_state_path], invalidated on [signal changed].
var path := PackedFloat64Array() ## Flat orbit-precision stride-7 knots [x, y, z, vx, vy, vz, t]; see [method refresh_state_path].
var _path_dirty := true # rebuild the state path on next refresh_state_path()


func _init() -> void:
	changed.connect(_mark_path_dirty)



# *****************************************************************************
# static methods

## Creates new [IVOrbit] instance from elements. [param from_orbit] can be
## supplied to reuse an existing [IVOrbit] or to parameterize a subclass instance.
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
		from_orbit: IVOrbit = null
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
	
	var orbit := from_orbit
	if !orbit:
		if replacement_subclass:
			@warning_ignore("unsafe_method_access")
			orbit = replacement_subclass.new()
		else:
			orbit = IVOrbit.new()
	
	# defining args
	orbit._reference_plane_type = reference_plane_type
	orbit._reference_basis = IVMath64.from_basis(reference_basis)
	orbit._semi_parameter = semi_parameter
	orbit._eccentricity = eccentricity
	orbit._inclination = inclination
	orbit._longitude_ascending_node_at_epoch = longitude_ascending_node
	orbit._longitude_ascending_node_rate = longitude_ascending_node_rate
	orbit._argument_periapsis_at_epoch = argument_periapsis
	orbit._argument_periapsis_rate = argument_periapsis_rate
	orbit._time_periapsis = time_periapsis
	orbit._gravitational_parameter = gravitational_parameter
	
	# seed the changed-signal hysteresis detectors at epoch
	orbit._signaled_longitude_ascending_node = longitude_ascending_node
	orbit._signaled_argument_periapsis = argument_periapsis
	
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


## Creates an [IVOrbit] from state (x, y, z, vx, vy, vz) at [param time], plus
## the supplied precession rates. This is the inverse of the element→state math:
## it solves for the osculating elements and forwards them to [method create_from_elements]
## (reusing [param from_orbit] when supplied). Inputs are in the [param reference_basis]
## frame (identity for ECLIPTIC) and any consistent length/time units. Not valid
## for a parabolic orbit (eccentricity == 1).[br][br]
##
## Internal calculations amplify imprecision of Vector3 components (float32 in
## standard Godot compilation) even if inputs are derived from single precision.
## We require scalars in the method signature to avoid "up-casting" to float64
## inside the method.
@warning_ignore_start("shadowed_variable")
static func create_from_state_and_precessions(
		x: float,
		y: float,
		z: float,
		vx: float,
		vy: float,
		vz: float,
		gravitational_parameter: float,
		time: float,
		reference_plane_type: ReferencePlane,
		reference_basis: Basis,
		longitude_ascending_node_rate: float,
		argument_periapsis_rate: float,
		from_orbit: IVOrbit = null,
	) -> IVOrbit:

	var radius := sqrt(x * x + y * y + z * z)
	var speed_squared := vx * vx + vy * vy + vz * vz
	var radial_velocity := x * vx + y * vy + z * vz # position.dot(velocity)
	var hx := y * vz - z * vy # specific angular momentum = position.cross(velocity)
	var hy := z * vx - x * vz
	var hz := x * vy - y * vx
	var angular_momentum_length := sqrt(hx * hx + hy * hy + hz * hz)
	var node_x := -hy # ascending node = (0,0,1).cross(angular_momentum) = (-hy, hx, 0)
	var node_y := hx
	var node_length := sqrt(node_x * node_x + node_y * node_y)
	var ecc_coefficient := speed_squared - gravitational_parameter / radius
	var ecc_x := (x * ecc_coefficient - vx * radial_velocity) / gravitational_parameter
	var ecc_y := (y * ecc_coefficient - vy * radial_velocity) / gravitational_parameter
	var ecc_z := (z * ecc_coefficient - vz * radial_velocity) / gravitational_parameter
	var eccentricity := sqrt(ecc_x * ecc_x + ecc_y * ecc_y + ecc_z * ecc_z)
	var inclination := acos(clampf(hz / angular_momentum_length, -1.0, 1.0))

	var longitude_ascending_node: float
	var argument_periapsis: float
	if node_length > 1e-9:
		longitude_ascending_node = acos(clampf(node_x / node_length, -1.0, 1.0))
		if node_y < 0.0:
			longitude_ascending_node = TAU - longitude_ascending_node
		argument_periapsis = acos(clampf((node_x * ecc_x + node_y * ecc_y)
				/ (node_length * eccentricity), -1.0, 1.0))
		if ecc_z < 0.0:
			argument_periapsis = TAU - argument_periapsis
	else: # orbit lies in the reference plane; ascending node undefined
		longitude_ascending_node = 0.0
		argument_periapsis = atan2(ecc_y, ecc_x)

	var true_anomaly := acos(clampf((ecc_x * x + ecc_y * y + ecc_z * z)
			/ (eccentricity * radius), -1.0, 1.0))
	if radial_velocity < 0.0:
		true_anomaly = TAU - true_anomaly

	var semi_parameter := angular_momentum_length * angular_momentum_length / gravitational_parameter
	var semi_major_axis := semi_parameter / (1.0 - eccentricity * eccentricity)
	var mean_anomaly: float
	if eccentricity < 1.0:
		var eccentric_anomaly := 2.0 * atan2(sqrt(1.0 - eccentricity) * sin(true_anomaly / 2.0),
				sqrt(1.0 + eccentricity) * cos(true_anomaly / 2.0))
		mean_anomaly = eccentric_anomaly - eccentricity * sin(eccentric_anomaly)
		var mean_motion := sqrt(gravitational_parameter / semi_major_axis ** 3)
		return create_from_elements(reference_plane_type, reference_basis, semi_parameter,
				eccentricity, inclination, longitude_ascending_node, longitude_ascending_node_rate,
				argument_periapsis, argument_periapsis_rate, time - mean_anomaly / mean_motion,
				gravitational_parameter, from_orbit)
	var tanh_half_anomaly := sqrt((eccentricity - 1.0) / (eccentricity + 1.0)) * tan(true_anomaly / 2.0)
	var hyperbolic_anomaly := log((1.0 + tanh_half_anomaly) / (1.0 - tanh_half_anomaly))
	mean_anomaly = eccentricity * sinh(hyperbolic_anomaly) - hyperbolic_anomaly
	var hyperbolic_mean_motion := sqrt(gravitational_parameter / (-semi_major_axis) ** 3)
	return create_from_elements(reference_plane_type, reference_basis, semi_parameter,
			eccentricity, inclination, longitude_ascending_node, longitude_ascending_node_rate,
			argument_periapsis, argument_periapsis_rate, time - mean_anomaly / hyperbolic_mean_motion,
			gravitational_parameter, from_orbit)
@warning_ignore_restore("shadowed_variable")


## Creates new [IVOrbit] instance from state vectors and orbit environment.
## @experimental: NOT YET IMPLEMENTED.
@warning_ignore("shadowed_variable", "unused_parameter")
static func create_from_state_and_environment(
		x: float,
		y: float,
		z: float,
		vx: float,
		vy: float,
		vz: float,
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


## Solves Lambert's problem: the conic from [param position_1] to [param position_2]
## crossed in [param time_of_flight], about a primary with [param gravitational_parameter].
## Universal-variable (Vallado) formulation; valid for elliptic and hyperbolic transfers
## (not parabolic). Returns the two velocities as double-precision scalars in a
## [PackedFloat64Array] [code][vx1, vy1, vz1, vx2, vy2, vz2][/code] (input frame and units),
## or an empty array if the geometry is degenerate or it fails to converge. [param position_1]
## and [param position_2] are size-3 orbit-precision [PackedFloat64Array]; the result feeds
## [method create_from_state_and_precessions] without a float32 round trip. Pass
## [param prograde] = false for the retrograde (clockwise about +Z) transfer.
@warning_ignore("shadowed_variable")
static func solve_lambert(position_1: PackedFloat64Array, position_2: PackedFloat64Array,
		time_of_flight: float, gravitational_parameter: float, prograde := true) -> PackedFloat64Array:

	var velocities := PackedFloat64Array()
	# Full double precision end to end: a near-180° transfer drives 1+cos_transfer toward 0,
	# where a float32 round trip would lose ~1e4 km at planetary distances.
	var x1 := position_1[0]
	var y1 := position_1[1]
	var z1 := position_1[2]
	var x2 := position_2[0]
	var y2 := position_2[1]
	var z2 := position_2[2]
	var radius_1 := sqrt(x1 * x1 + y1 * y1 + z1 * z1)
	var radius_2 := sqrt(x2 * x2 + y2 * y2 + z2 * z2)
	var sum_radii := radius_1 + radius_2
	var cos_transfer := clampf((x1 * x2 + y1 * y2 + z1 * z2) / (radius_1 * radius_2), -1.0, 1.0)
	var cross_z := x1 * y2 - y1 * x2 # z of position_1.cross(position_2)
	var direction := 1.0 if (cross_z >= 0.0) == prograde else -1.0
	var a_geom := direction * sqrt(radius_1 * radius_2 * (1.0 + cos_transfer))
	if is_zero_approx(a_geom):
		return velocities

	# Time of flight rises monotonically with psi over the zero-revolution range
	# (-inf, 4π²); c2 = 0 at 4π² so cap just below it, and extend the hyperbolic
	# floor downward when the transfer is faster than the default lower bound allows.
	var psi_low := -4.0 * PI * PI
	var psi_up := 4.0 * PI * PI - 1e-6
	for _i in 60:
		var low := _lambert_dt_y(psi_low, sum_radii, a_geom, gravitational_parameter)
		if low.is_empty() or low[0] <= time_of_flight:
			break
		psi_low *= 2.0

	var y_value := 0.0
	for _i in 200:
		var psi := 0.5 * (psi_low + psi_up)
		var result := _lambert_dt_y(psi, sum_radii, a_geom, gravitational_parameter)
		if result.is_empty(): # psi below the valid floor; raise it
			psi_low = psi
			continue
		y_value = result[1]
		if absf(result[0] - time_of_flight) < 1e-3:
			break
		if result[0] < time_of_flight:
			psi_low = psi
		else:
			psi_up = psi
	if y_value <= 0.0:
		return velocities

	var f := 1.0 - y_value / radius_1
	var g := a_geom * sqrt(y_value / gravitational_parameter)
	if is_zero_approx(g):
		return velocities
	var g_dot := 1.0 - y_value / radius_2
	var inverse_g := 1.0 / g
	var vx1 := (x2 - f * x1) * inverse_g
	var vy1 := (y2 - f * y1) * inverse_g
	var vz1 := (z2 - f * z1) * inverse_g
	var vx2 := (g_dot * x2 - x1) * inverse_g
	var vy2 := (g_dot * y2 - y1) * inverse_g
	var vz2 := (g_dot * z2 - z1) * inverse_g
	velocities.resize(6)
	velocities[0] = vx1
	velocities[1] = vy1
	velocities[2] = vz1
	velocities[3] = vx2
	velocities[4] = vy2
	velocities[5] = vz2
	return velocities


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


## Static method returns eccentric anomaly (E; estimated iteratively) from mean
## anomaly (M) for an elliptic orbit (e < 1). Unlike the bounded true-anomaly
## solvers, the result is unwrapped (same revolution as [param mean_anomaly]).
@warning_ignore("shadowed_variable")
static func get_eccentric_anomaly_from_mean_anomaly_elliptic(eccentricity: float,
		mean_anomaly: float) -> float:
	assert(eccentricity < 1.0)
	const TOLERANCE := 1e-10
	var ea := mean_anomaly + eccentricity * sin(mean_anomaly) # initial estimate
	var delta_ea := (ea - eccentricity * sin(ea) - mean_anomaly) / (1.0 - eccentricity * cos(ea))
	ea -= delta_ea
	while absf(delta_ea) > TOLERANCE:
		delta_ea = (ea - eccentricity * sin(ea) - mean_anomaly) / (1.0 - eccentricity * cos(ea))
		ea -= delta_ea
	return ea


## Static method returns hyperbolic anomaly (H; estimated iteratively) from mean
## anomaly (M) for a hyperbolic orbit (e > 1).
@warning_ignore("shadowed_variable")
static func get_hyperbolic_anomaly_from_mean_anomaly_hyperbolic(eccentricity: float,
		mean_anomaly: float) -> float:
	assert(eccentricity > 1.0)
	const TOLERANCE := 1e-10
	var s := -1.0 if mean_anomaly < 0.0 else 1.0
	var ha := s * log(s * 2.0 * mean_anomaly / (eccentricity + 1.0) + 1.0) # initial estimate
	var delta_ha := (eccentricity * sinh(ha) - ha - mean_anomaly) / (eccentricity * cosh(ha) - 1.0)
	ha -= delta_ha
	while absf(delta_ha) > TOLERANCE:
		delta_ha = (eccentricity * sinh(ha) - ha - mean_anomaly) / (eccentricity * cosh(ha) - 1.0)
		ha -= delta_ha
	return ha


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
	var vz := c * z + angular_v * (cos_ap_nu * sin_i)
	
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


# Universal-variable time of flight for trial [param psi]: returns [dt, y] (seconds,
# length), or an empty array when psi is invalid (y < 0 below the floor, or the
# Stumpff terms degenerate/overflow). Helper for [method solve_lambert].
@warning_ignore("shadowed_variable")
static func _lambert_dt_y(psi: float, sum_radii: float, a_geom: float,
		gravitational_parameter: float) -> Array[float]:
	var out: Array[float] = []
	var c2: float
	var c3: float
	if psi > 1e-6:
		var sqrt_psi := sqrt(psi)
		c2 = (1.0 - cos(sqrt_psi)) / psi
		c3 = (sqrt_psi - sin(sqrt_psi)) / (sqrt_psi * sqrt_psi * sqrt_psi)
	elif psi < -1e-6:
		var sqrt_psi := sqrt(-psi)
		c2 = (1.0 - cosh(sqrt_psi)) / psi
		c3 = (sinh(sqrt_psi) - sqrt_psi) / (sqrt_psi * sqrt_psi * sqrt_psi)
	else:
		c2 = 0.5
		c3 = 1.0 / 6.0
	if c2 <= 0.0 or not is_finite(c2) or not is_finite(c3):
		return out
	var y := sum_radii + a_geom * (psi * c3 - 1.0) / sqrt(c2)
	if y < 0.0:
		return out
	var chi := sqrt(y / c2)
	out.append((chi * chi * chi * c3 + a_geom * sqrt(y)) / sqrt(gravitational_parameter))
	out.append(y)
	return out


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

	_update_time = time

	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)

	# signal if accumulated precession since the last emit crosses the threshold
	if (absf(lan - _signaled_longitude_ascending_node) > CHANGED_ANGLE_THRESHOLD
			or absf(ap - _signaled_argument_periapsis) > CHANGED_ANGLE_THRESHOLD):
		_signaled_longitude_ascending_node = lan
		_signaled_argument_periapsis = ap
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
		return IVMath64.to_basis(_reference_basis) * position
	return position


## Returns instantaneous position at [param time] as a 32-bit [Vector3] (graphics idiom;
## see [method get_translation] for orbit precision). Return can be in the ecliptic basis
## or the orbit [member reference_basis] (the former by default). Position is relative to
## the parent body regardless of basis conversion.
func get_position_vector(time: float, rotate_to_ecliptic := true) -> Vector3:
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	var nu := get_true_anomaly(time)
	var position := get_position_from_elements_at_true_anomaly(_semi_parameter, _eccentricity,
			_inclination, lan, ap, nu)
	if rotate_to_ecliptic and _reference_plane_type != ReferencePlane.REFERENCE_PLANE_ECLIPTIC:
		return IVMath64.to_basis(_reference_basis) * position
	return position


## Returns instantaneous position [x, y, z] at [param time] as an orbit-precision (64-bit)
## [PackedFloat64Array]. Return can be in the ecliptic basis or the orbit
## [member reference_basis] (the former by default). Position is relative to the parent
## body regardless of basis conversion. Threadsafe (see class doc).
func get_translation(time: float, rotate_to_ecliptic := true) -> PackedFloat64Array:
	if Thread.is_main_thread():
		_write_translation(time, rotate_to_ecliptic, _translation_buffer, 0)
		return _translation_buffer.duplicate()
	var out := PackedFloat64Array()
	out.resize(3)
	_write_translation(time, rotate_to_ecliptic, out, 0)
	return out


## Returns instantaneous state [x, y, z, vx, vy, vz] at [param time] as an orbit-precision
## (64-bit) [PackedFloat64Array]. Return can be in the ecliptic basis or the orbit
## [member reference_basis] (the former by default). State is relative to the parent body
## regardless of basis conversion. Threadsafe (see class doc).
func get_state(time: float, rotate_to_ecliptic := true) -> PackedFloat64Array:
	if Thread.is_main_thread():
		_write_state(time, rotate_to_ecliptic, _state_buffer, 0)
		return _state_buffer.duplicate()
	var out := PackedFloat64Array()
	out.resize(6)
	_write_state(time, rotate_to_ecliptic, out, 0)
	return out


## Returns instantaneous position and velocity at [param time] as a 32-bit
## [PackedVector3Array] [code][position, velocity][/code] (graphics idiom; see
## [method get_state] for orbit precision). Return can be in the ecliptic basis or the
## orbit [member reference_basis] (the former by default). Relative to the parent body
## regardless of basis conversion.
func get_state_vectors(time: float, rotate_to_ecliptic := true) -> PackedVector3Array:
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	var nu := get_true_anomaly(time)
	var vectors := get_state_vectors_from_elements_at_true_anomaly(_semi_parameter, _eccentricity,
			_inclination, lan, ap, _specific_angular_momentum, nu)
	if rotate_to_ecliptic and _reference_plane_type != ReferencePlane.REFERENCE_PLANE_ECLIPTIC:
		var basis := IVMath64.to_basis(_reference_basis)
		return PackedVector3Array([basis * vectors[0], basis * vectors[1]])
	return PackedVector3Array(vectors)


# Writes ecliptic (or reference-basis) translation [x, y, z] into [param out] at [param offset]
# (out must be pre-sized). 64-bit core shared by get_translation() and sample_arc().
func _write_translation(time: float, rotate_to_ecliptic: bool, out: PackedFloat64Array,
		offset: int) -> void:
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	var nu := get_true_anomaly(time)
	var r := _semi_parameter / (1.0 + _eccentricity * cos(nu))
	var sin_i := sin(_inclination)
	var cos_i := cos(_inclination)
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


# Writes ecliptic (or reference-basis) state [x, y, z, vx, vy, vz] into [param out] at
# [param offset] (out must be pre-sized). 64-bit core for get_state().
func _write_state(time: float, rotate_to_ecliptic: bool, out: PackedFloat64Array,
		offset: int) -> void:
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	var ap := fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)
	var nu := get_true_anomaly(time)
	var r := _semi_parameter / (1.0 + _eccentricity * cos(nu))
	var sin_i := sin(_inclination)
	var cos_i := cos(_inclination)
	var sin_lan := sin(lan)
	var cos_lan := cos(lan)
	var sin_ap_nu := sin(ap + nu)
	var cos_ap_nu := cos(ap + nu)
	var x := r * (cos_lan * cos_ap_nu - sin_lan * sin_ap_nu * cos_i)
	var y := r * (sin_lan * cos_ap_nu + cos_lan * sin_ap_nu * cos_i)
	var z := r * (sin_ap_nu * sin_i)
	var c := _specific_angular_momentum * _eccentricity * sin(nu) / (r * _semi_parameter)
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


## Returns a curvature-weighted polyline sampling of this orbit between
## [param begin_time] and [param end_time] as [flat [PackedFloat64Array] positions
## (orbit precision; [x, y, z] per vertex, size 3 * [param n_vertices]),
## [PackedFloat64Array] times]. Positions are relative to the parent body in the ecliptic
## basis (via [method get_translation], so precession-correct). Vertices are
## spaced by uniform eccentric / hyperbolic / parabolic anomaly to concentrate near
## periapsis, mirroring the unit orbit meshes. An unbounded end (±INF) clamps to one
## full period (closed orbit) or to [param max_radius], in units of [member semi_parameter]
## (open orbit). Used by [IVTrajectory] to build its path. Requires [param n_vertices] >= 2.
func sample_arc(begin_time: float, end_time: float, n_vertices: int, max_radius: float) -> Array:
	assert(n_vertices >= 2)
	var positions := PackedFloat64Array()
	var times := PackedFloat64Array()
	positions.resize(3 * n_vertices)
	times.resize(n_vertices)
	var t_p := _time_periapsis
	if _eccentricity < 1.0: # elliptic; step uniform eccentric anomaly
		var e := _eccentricity
		var n := _mean_motion
		var period := TAU / n
		var begin := begin_time
		var end := end_time
		if is_inf(begin) and is_inf(end):
			begin = t_p - 0.5 * period
			end = t_p + 0.5 * period
		elif is_inf(begin):
			begin = end - period
		elif is_inf(end):
			end = begin + period
		var ea_begin := get_eccentric_anomaly_from_mean_anomaly_elliptic(e, n * (begin - t_p))
		var ea_end := get_eccentric_anomaly_from_mean_anomaly_elliptic(e, n * (end - t_p))
		for k in n_vertices:
			var ea := lerpf(ea_begin, ea_end, float(k) / (n_vertices - 1))
			var time := t_p + (ea - e * sin(ea)) / n
			_write_translation(time, true, positions, 3 * k)
			times[k] = time
	elif _eccentricity > 1.0: # hyperbolic; step uniform hyperbolic anomaly
		var e := _eccentricity
		var n := _mean_motion
		var arg := (max_radius * (e * e - 1.0) + 1.0) / e
		var ha_limit := log(arg + sqrt(arg * arg - 1.0)) # acosh(arg); H at max_radius
		var ha_begin := -ha_limit
		if !is_inf(begin_time):
			ha_begin = get_hyperbolic_anomaly_from_mean_anomaly_hyperbolic(e, n * (begin_time - t_p))
		var ha_end := ha_limit
		if !is_inf(end_time):
			ha_end = get_hyperbolic_anomaly_from_mean_anomaly_hyperbolic(e, n * (end_time - t_p))
		for k in n_vertices:
			var ha := lerpf(ha_begin, ha_end, float(k) / (n_vertices - 1))
			var time := t_p + (e * sinh(ha) - ha) / n
			_write_translation(time, true, positions, 3 * k)
			times[k] = time
	else: # parabolic; step uniform parabolic anomaly D (Barker's equation)
		var q := 0.5 * _semi_parameter
		var factor := sqrt(_gravitational_parameter / (2.0 * q * q * q))
		var nu_max := acos(clampf(1.0 / max_radius - 1.0, -1.0, 1.0))
		var d_begin := -tan(0.5 * nu_max)
		if !is_inf(begin_time):
			d_begin = tan(0.5 * get_true_anomaly(begin_time))
		var d_end := tan(0.5 * nu_max)
		if !is_inf(end_time):
			d_end = tan(0.5 * get_true_anomaly(end_time))
		for k in n_vertices:
			var d := lerpf(d_begin, d_end, float(k) / (n_vertices - 1))
			var time := t_p + (d + d * d * d / 3.0) / factor
			_write_translation(time, true, positions, 3 * k)
			times[k] = time
	return [positions, times]


# Marks the cached state path (see [method refresh_state_path]) for rebuild. Connected to [signal changed]
# so any element evolution or set invalidates the line; a fixed (non-evolving) orbit builds once.
func _mark_path_dirty(_is_intrinsic: bool, _precession_only: bool) -> void:
	_path_dirty = true


## (Re)builds [member path] if dirty — flat stride-7 knots [x, y, z, vx, vy, vz, t]: one period
## (closed orbit, knotted by the union of uniform eccentric anomaly and uniform tangent-turn —
## [param base_vertices] each, so up to ~2x total at high eccentricity and exactly [param base_vertices]
## when circular) or an open arc out to [member IVCoreSettings.open_conic_max_radius] (uniform anomaly),
## anchored on [param time] (current sim time) so the line brackets the body's present position, not the
## J2000 epoch. Parallel to how [IVTrajectory] builds its path; consumed and smoothed by [IVPathVisual].
## Main-thread only (mutates members).
func refresh_state_path(time: float, base_vertices: int) -> void:
	assert(base_vertices >= 2)
	if not _path_dirty and not path.is_empty():
		return
	if _eccentricity < 1.0:
		_build_elliptic_state_path(time, base_vertices)
	else:
		_build_open_state_path(base_vertices)
	_path_dirty = false


# Closed-orbit state path: sweeps the CURRENT osculating ellipse (fixed elements from the last update, the
# same ellipse the coarse unit mesh draws) over the merged knot families of [method _merge_elliptic_knots].
# The body sits exactly on this ellipse and the osculating velocity is its exact tangent, so the Hermite
# line has no precession/evolution residual (unlike sampling each vertex at its own evolving time).
# Per-vertex time is the passage time on this fixed ellipse (for Hermite parameterization), anchored on
# the periapsis nearest [param time].
func _build_elliptic_state_path(time: float, base_vertices: int) -> void:
	# Fresh (time-evaluated) osculating elements, NOT the cached members: those lag by up to the changed
	# threshold, and scaled by an outer planet's orbit radius that lag reads as the body sitting a few radii
	# off its own line. The body's position (get_translation) likewise evaluates its elements fresh at [time].
	var p := get_semi_parameter_at_time(time)
	var e := get_eccentricity_at_time(time)
	var incl := get_inclination_at_time(time)
	var lan := get_longitude_ascending_node_at_time(time)
	var ap := get_argument_periapsis_at_time(time)
	var n := _mean_motion
	var h := sqrt(_gravitational_parameter * p)
	var sin_i := sin(incl)
	var cos_i := cos(incl)
	var sin_lan := sin(lan)
	var cos_lan := cos(lan)
	var rotate := _reference_plane_type != ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	var period := TAU / n
	var t_p_near := _time_periapsis + roundf((time - _time_periapsis) / period) * period
	var sqrt_1_plus_e := sqrt(1.0 + e)
	var sqrt_1_minus_e := sqrt(1.0 - e)
	var axis_ratio := sqrt_1_minus_e * sqrt_1_plus_e # b/a
	var knots := _merge_elliptic_knots(base_vertices, axis_ratio)
	var n_knots := knots.size()
	path.resize(7 * n_knots)
	for k in n_knots:
		var ea := knots[k]
		var nu := 2.0 * atan2(sqrt_1_plus_e * sin(0.5 * ea), sqrt_1_minus_e * cos(0.5 * ea))
		var r := p / (1.0 + e * cos(nu))
		var sin_ap_nu := sin(ap + nu)
		var cos_ap_nu := cos(ap + nu)
		var x := r * (cos_lan * cos_ap_nu - sin_lan * sin_ap_nu * cos_i)
		var y := r * (sin_lan * cos_ap_nu + cos_lan * sin_ap_nu * cos_i)
		var z := r * (sin_ap_nu * sin_i)
		var c := h * e * sin(nu) / (r * p)
		var angular_v := h / r
		var vx := c * x - angular_v * (cos_lan * sin_ap_nu + sin_lan * cos_ap_nu * cos_i)
		var vy := c * y - angular_v * (sin_lan * sin_ap_nu - cos_lan * cos_ap_nu * cos_i)
		var vz := c * z + angular_v * (cos_ap_nu * sin_i)
		var base := 7 * k
		if rotate:
			IVMath64.rotate_into(_reference_basis, x, y, z, path, base)
			IVMath64.rotate_into(_reference_basis, vx, vy, vz, path, base + 3)
		else:
			path[base] = x
			path[base + 1] = y
			path[base + 2] = z
			path[base + 3] = vx
			path[base + 4] = vy
			path[base + 5] = vz
		path[base + 6] = t_p_near + (ea - e * sin(ea)) / n


# Knot eccentric anomalies for [method _build_elliptic_state_path]: the sorted, deduplicated union of
# uniform eccentric anomaly and uniform tangent-turn (turn from periapsis = atan2(a sin E, b cos E),
# inverted per knot), [param base_vertices] of each, with exact endpoints at ±PI. Two families because the
# time-parameterized cubic Hermite has two error terms: uniform anomaly bounds the time/speed-chirp error,
# which peaks BETWEEN the apsides where speed changes fastest across a knot interval; uniform turn bounds
# the geometric bend (and the apsidal time step), which peaks AT the apsides by a/b. Either family alone
# fails the other's region at high eccentricity — meters to kilometers for e ~ 0.98. Fully deduplicated
# (identical sets) when e = 0.
func _merge_elliptic_knots(base_vertices: int, axis_ratio: float) -> PackedFloat64Array:
	var knots := PackedFloat64Array()
	var anomaly_index := 0
	var turn_index := 0
	while anomaly_index < base_vertices or turn_index < base_vertices:
		var anomaly_next := INF
		if anomaly_index < base_vertices:
			anomaly_next = -PI + TAU * float(anomaly_index) / (base_vertices - 1)
		var turn_next := INF
		if turn_index < base_vertices:
			var turn := -PI + TAU * float(turn_index) / (base_vertices - 1)
			turn_next = atan2(axis_ratio * sin(turn), cos(turn))
		var ea: float
		if anomaly_next <= turn_next:
			ea = anomaly_next
			anomaly_index += 1
		else:
			ea = turn_next
			turn_index += 1
		if knots.is_empty() or ea - knots[knots.size() - 1] >= STATE_PATH_MIN_KNOT_SEPARATION:
			knots.append(ea)
	knots[knots.size() - 1] = PI # exact closure (the last accepted knot is within a step of PI)
	return knots


# Open-orbit (hyperbolic/parabolic) state path: reuses [method sample_arc]'s max-radius clamping for
# positions and times (anchored on periapsis; an open orbit has a single passage), then fills velocities.
func _build_open_state_path(base_vertices: int) -> void:
	var arc := sample_arc(-INF, INF, base_vertices, IVCoreSettings.open_conic_max_radius)
	var positions: PackedFloat64Array = arc[0]
	var times: PackedFloat64Array = arc[1]
	var n_knots := times.size()
	path.resize(7 * n_knots)
	var state := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for k in n_knots:
		_write_state(times[k], true, state, 0)
		var base := 7 * k
		path[base] = positions[3 * k]
		path[base + 1] = positions[3 * k + 1]
		path[base + 2] = positions[3 * k + 2]
		path[base + 3] = state[3]
		path[base + 4] = state[4]
		path[base + 5] = state[5]
		path[base + 6] = times[k]


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
	return fposmod(_mean_anomaly + get_longitude_ascending_node() + get_argument_periapsis(), TAU)


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
	return fposmod(_true_anomaly + get_longitude_ascending_node() + get_argument_periapsis(), TAU)


## Returns radius (r) at [param time].
func get_radius(time: float) -> float:
	var nu := get_true_anomaly(time)
	return _semi_parameter / (1.0 + _eccentricity * cos(nu))


## Returns radius (r) after the last [method update] call.
func get_radius_at_update() -> float:
	return get_semi_parameter() / (1.0 + get_eccentricity() * cos(_true_anomaly))


# *****************************************************************************
# Element gets and sets


func get_reference_plane_type() -> ReferencePlane:
	return _reference_plane_type


## Returns the reference basis as a 32-bit [Basis] (graphics idiom). The 64-bit
## backing store is used internally; see [IVMath64].
func get_reference_basis() -> Basis:
	return IVMath64.to_basis(_reference_basis)


func set_reference_plane_and_basis(plane_type: ReferencePlane, basis: Basis) -> void:
	assert(plane_type != ReferencePlane.REFERENCE_PLANE_ECLIPTIC or basis == Basis.IDENTITY)
	assert(basis.is_conformal() and basis.x.is_normalized())
	_reference_plane_type = plane_type
	_reference_basis = IVMath64.from_basis(basis)
	changed.emit(false, false)


func get_semi_parameter() -> float:
	return get_semi_parameter_at_time(_update_time)


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
	return get_eccentricity_at_time(_update_time)


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
	return get_inclination_at_time(_update_time)


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
	return get_longitude_ascending_node_at_time(_update_time)


func get_longitude_ascending_node_at_time(time: float) -> float:
	return fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)


func get_longitude_ascending_node_at_epoch() -> float:
	return _longitude_ascending_node_at_epoch


func get_longitude_ascending_node_rate() -> float:
	return _longitude_ascending_node_rate


func set_longitude_ascending_node(value: float) -> void:
	# Reset Ω₀ so Ω at the last update() equals value (independent of the signaled detector).
	set_longitude_ascending_node_at_epoch(value - _longitude_ascending_node_rate * _update_time)


func set_longitude_ascending_node_at_epoch(value: float) -> void:
	_longitude_ascending_node_at_epoch = fposmod(value, TAU)
	changed.emit(false, false)


func set_longitude_ascending_node_rate(value: float) -> void:
	# Prevent instantaneous change in current position...
	set_longitude_ascending_node_rate_at_time(value, IVGlobal.times[0])


## Sets Ωr and resets Ω₀ such that there is no instantaneous change in Ω at [param time].
func set_longitude_ascending_node_rate_at_time(value: float, time: float) -> void:
	var current_lan := get_longitude_ascending_node_at_time(time) # capture Ω(time) with the old rate
	_longitude_ascending_node_rate = value
	if !time:
		changed.emit(false, false)
		return
	set_longitude_ascending_node_at_epoch(current_lan - value * time)


func get_argument_periapsis() -> float:
	return get_argument_periapsis_at_time(_update_time)


func get_argument_periapsis_at_time(time: float) -> float:
	return fposmod(_argument_periapsis_at_epoch + _argument_periapsis_rate * time, TAU)


func get_argument_periapsis_at_epoch() -> float:
	return _argument_periapsis_at_epoch


func get_argument_periapsis_rate() -> float:
	return _argument_periapsis_rate


func set_argument_periapsis(value: float) -> void:
	# Reset ω₀ so ω at the last update() equals value (independent of the signaled detector).
	set_argument_periapsis_at_epoch(value - _argument_periapsis_rate * _update_time)


func set_argument_periapsis_at_epoch(value: float) -> void:
	_argument_periapsis_at_epoch = fposmod(value, TAU)
	changed.emit(false, false)


func set_argument_periapsis_rate(value: float) -> void:
	# Prevent instantaneous change in current position...
	set_argument_periapsis_rate_at_time(value, IVGlobal.times[0])


## Sets ωr and resets ω₀ such that there is no instantaneous change in ω at [param time].
func set_argument_periapsis_rate_at_time(value: float, time: float) -> void:
	var current_ap := get_argument_periapsis_at_time(time) # capture ω(time) with the old rate
	_argument_periapsis_rate = value
	if !time:
		changed.emit(false, false)
		return
	set_argument_periapsis_at_epoch(current_ap - value * time)



func get_time_periapsis() -> float:
	return get_time_periapsis_at_time(_update_time)


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
	return get_semi_major_axis_at_time(_update_time)


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
	return get_longitude_periapsis_at_time(_update_time)


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
# Derivable other


func is_retrograde() -> bool:
	const RIGHT_ANGLE := PI / 2
	return _inclination > RIGHT_ANGLE


## Note: inclination (i) does not evolve in the base IVOrbit class, but it may in a subclass.
func is_retrograde_at_time(_time: float) -> bool:
	const RIGHT_ANGLE := PI / 2
	return _inclination > RIGHT_ANGLE


func get_periapsis() -> float:
	return get_periapsis_at_time(_update_time)


## Note: periapsis does not evolve in the base IVOrbit class, but it may in a subclass.
func get_periapsis_at_time(_time: float) -> float:
	return _semi_parameter / (1.0 + _eccentricity)


func get_apoapsis() -> float:
	return get_apoapsis_at_time(_update_time)


## Note: periapsis does not evolve in the base IVOrbit class, but it may in a subclass.
func get_apoapsis_at_time(_time: float) -> float:
	if _eccentricity < 1.0:
		return _semi_parameter / (1.0 - _eccentricity)
	return INF


func get_period() -> float:
	if _eccentricity < 1.0:
		return TAU / _mean_motion
	return INF


## Note: period does not evolve in the base IVOrbit class, but it may in a subclass.
func get_period_at_time(_time: float) -> float:
	if _eccentricity < 1.0:
		return TAU / _mean_motion
	return INF


## Returns the instantaneous orbit normal. Return can be in the ecliptic basis or the orbit
## [member reference_basis] (the former by default).
## Requires preceding [method update] call to be current if orbit is evolving.
func get_normal(rotate_to_ecliptic := true, flip_retrograde := false) -> Vector3:
	return get_normal_at_time(_update_time, rotate_to_ecliptic, flip_retrograde)


## Returns the instantaneous orbit normal. Return can be in the ecliptic basis
## or the orbit [member reference_basis] (the former by default).
func get_normal_at_time(time: float, rotate_to_ecliptic := true, flip_retrograde := false) -> Vector3:
	const REFERENCE_PLANE_ECLIPTIC := ReferencePlane.REFERENCE_PLANE_ECLIPTIC
	
	# evolve orbit
	var lan := fposmod(_longitude_ascending_node_at_epoch + _longitude_ascending_node_rate * time, TAU)
	
	var normal := get_normal_from_elements(_inclination, lan, flip_retrograde)
	if rotate_to_ecliptic and _reference_plane_type != REFERENCE_PLANE_ECLIPTIC:
		return IVMath64.to_basis(_reference_basis) * normal
	return normal


## Returns the instantaneous orbit basis, where z-axis is normal to the orbit
## plane and x-axis is in the direction of periapsis. Return can be in the ecliptic
## basis or the orbit [member reference_basis] (the former by default).
## Requires preceding [method update] call to be current if orbit is evolving.
func get_basis(rotate_to_ecliptic := true) -> Basis:
	return get_basis_at_time(_update_time, rotate_to_ecliptic)


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
		return IVMath64.to_basis(_reference_basis) * basis
	return basis


## Returned Transform3D can convert a unit circle into this orbit's path, if
## this orbit is closed (e < 1).
func get_unit_circle_transform(rotate_to_ecliptic := true) -> Transform3D:
	return get_unit_circle_transform_at_time(_update_time, rotate_to_ecliptic)


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
	return get_unit_rectangular_hyperbola_transform_at_time(_update_time, rotate_to_ecliptic)


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
	return get_unit_parabola_transform_at_time(_update_time, rotate_to_ecliptic)


## Returned Transform3D can convert a unit parabola into this orbit's path, if
## this orbit is parabolic (e = 1).
func get_unit_parabola_transform_at_time(time: float, rotate_to_ecliptic := true) -> Transform3D:
	var orbit_basis := get_basis_at_time(time, rotate_to_ecliptic)
	var basis := orbit_basis * Basis().scaled(Vector3(_semi_parameter, _semi_parameter, 1.0))
	return Transform3D(basis, Vector3.ZERO)


# *****************************************************************************
# serialize/deserialize
#
# These pack defining + derived elements as floats only. parent_name (a
# StringName) is intentionally absent and has no float representation; if these
# methods are revived for network sync, parent_name needs separate handling.


func serialize() -> PackedFloat64Array:
	var data := PackedFloat64Array()
	data.resize(30)
	data[0] = float(_reference_plane_type)
	data[1] = _reference_basis[0]
	data[2] = _reference_basis[1]
	data[3] = _reference_basis[2]
	data[4] = _reference_basis[3]
	data[5] = _reference_basis[4]
	data[6] = _reference_basis[5]
	data[7] = _reference_basis[6]
	data[8] = _reference_basis[7]
	data[9] = _reference_basis[8]
	data[10] = _semi_parameter
	data[11] = _eccentricity
	data[12] = _inclination
	data[13] = _signaled_longitude_ascending_node
	data[14] = _signaled_argument_periapsis
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
	data[27] = segment_begin
	data[28] = segment_end
	data[29] = _update_time
	return data


func deserialize(data: PackedFloat64Array) -> void:
	_reference_plane_type = int(data[0]) as ReferencePlane
	_reference_basis[0] = data[1]
	_reference_basis[1] = data[2]
	_reference_basis[2] = data[3]
	_reference_basis[3] = data[4]
	_reference_basis[4] = data[5]
	_reference_basis[5] = data[6]
	_reference_basis[6] = data[7]
	_reference_basis[7] = data[8]
	_reference_basis[8] = data[9]
	_semi_parameter = data[10]
	_eccentricity = data[11]
	_inclination = data[12]
	_signaled_longitude_ascending_node = data[13]
	_signaled_argument_periapsis = data[14]
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
	segment_begin = data[27]
	segment_end = data[28]
	_update_time = data[29]
