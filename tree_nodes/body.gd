# body.gd
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
class_name IVBody
extends Node3D

## An object that orbits or is orbited, including stars, planets, moons,
## instantiated asteroids, and spacecrafts (TODO: and barycenters).
##         
## [member Node.name] is always the data table row name: "PLANET_VENUS",
## "MOON_EUROPA", "SPACECRAFT_ISS", etc.[br][br]
##
## The structure of the scene tree is:
## [codeblock]
## IVUniverse
##    |- IVBody (e.g., the Sun)
##        |- IVBody (Earth)
##            |- IVBody (ISS)
##            |- IVBody (Moon)
##                |- IVBody (a spacecraft orbiting the Moon)
## [/codeblock]
##
## IVBody nodes are NEVER scaled or rotated. Hence, local distances and
## directions are always in the ecliptic basis at any level of the "body tree".[br][br]
##
## This node adds its own [IVModelSpace] if needed.
## IVBody maintains orientation and rotation of IVModelSpace. IVModelSpace
## instantiates and scales a model (visual representation) for this body.
## If this body has table value [param lazy_model] = TRUE, then IVModelSpace
## won't be added until the camera visits this body or a closely associated
## lazy body. This is generally set for spacecrafts (with large models)
## and for the 100s of outer moons of the gas giants (but not inner moons, as
## these need to be visible from nearby). See [IVLazyModelInitializer].[br][br]
##
## Some bodies (particularly moons and spacecrafts) have table value
## [param can_sleep] = TRUE. If [IVSleepManager] is present, these bodies will
## only [code]_process()[/code] when the camera is in the same planet system.
## IVBody API methods will return current values even if the body is not
## currently processing (but [code]position[/code] will not be current).[br][br]
##
## Many body-associated "graphic" nodes are added by [IVBodyFinisher] including
## rings, lights and HUD elements. IVBody class code has no references to these
## nodes.[br][br]
##
## IVBody properties are core information required for all bodies. Specialized
## information is contained in dictionary [member characteristics]. For
## example all bodies have [member mean_radius], but oblate spheroid bodies
## (most planets and stars) also have characteristics keys [param equatorial_radius]
## and [param polar_radius]. API methods provide access to many of these
## characteristics with sensible fallbacks for missing keys.[br][br]
## 
## See also [IVSmallBodiesGroup] for handling 1000s or 100000s of orbiting bodies
## without individual instantiation (e.g., asteroids).[br][br]
##
## [b]Roadmap[/b][br][br]
##
## TODO: Special mechanics for tumbling asteroids and outer moons. There
## are 4 kinds of rotations with increasing implementation difficulty:[br]
## 1. Rotation around 1 axis (this is what we have now).[br]
## 2. Axisymmetric wobbling (easy). I1 == I2 != I3. This may be a reasonable
##    approximation for many elongated asteroids. (It's also applicable for north
##    precession in planets, but the time scale for that is very long.)[br]
## 3. Asymmetric tumbling (quasi-periodic, non-chaotic; hard). I1 != I2 != I3.
##    The math is difficult (need Jacobi elliptic functions) but the rotations
##    are fully deterministic.[br]
## 4. Chaotic tumbling (harder). Above with perturbations. E.g., Hyperion.[br]
## (Even #2 would be an asthetic improvement for bodies that are really #4.)[br][br]
## 
## TODO: Public API for changing orbit context or "identity". E.g., a spacecraft
## becomes BODYFLAGS_STAR_ORBITER, or an asteroid is captured to become a moon.[br][br]
##
## TODO: (Ongoing) Make this node more "drag-and_drop" and editable at editor runtime.[br][br]
##
## TODO: Barycenters! They orbit and are orbited. This will make Pluto system
## (especially) more accurate, and allow things like twin planets. We probably
## won't add them where they are not visually obvious (e.g., Earth-Moon).[br][br]
##
## TODO: Implement network sync! This will mainly involve synching IVOrbit
## anytime it changes in an extrinsic way (e.g., impulse from a rocket
## engine). Same for rotations: we only sync when an extrinsic force changes
## the current rotation.

signal orbit_changed(orbit: IVOrbit, is_intrinsic: bool)
signal huds_visibility_changed(is_visible: bool)


## Bits to 1 << 39 are reserved for ivoyager_core future use. Higher bits are
## safe to use for external projects. Max bit shift is 1 << 63.
enum BodyFlags {
	
	# orbit context & identity
	BODYFLAGS_GALAXY_ORBITER = 1, ## If set, IVBody instance has no IVOrbit.
	BODYFLAGS_STAR_ORBITER = 1 << 1,
	BODYFLAGS_BARYCENTER = 1 << 2, ## NOT IMPLEMENTED YET.
	BODYFLAGS_PLANETARY_MASS_OBJECT = 1 << 3, ## Includes dwarf planet and larger spheroid moon.
	BODYFLAGS_STAR = 1 << 4,
	BODYFLAGS_PLANET_OR_DWARF_PLANET = 1 << 5,
	BODYFLAGS_PLANET = 1 << 6, ## Does not include dwarf planet.
	BODYFLAGS_DWARF_PLANET = 1 << 7,
	BODYFLAGS_MOON = 1 << 8,
	BODYFLAGS_PLANETARY_MASS_MOON = 1 << 9,
	BODYFLAGS_NON_PLANETARY_MASS_MOON = 1 << 10,
	BODYFLAGS_ASTEROID = 1 << 11,
	BODYFLAGS_COMET = 1 << 12,
	BODYFLAGS_SPACECRAFT = 1 << 13,
	
	# rotation mechanics
	## Keeps same face to parent (usually also axis-locked).
	BODYFLAGS_TIDALLY_LOCKED = 1 << 16,
	## Rotation axis ≈ orbit normal (always also tidally locked).
	## Earth's Moon is the unique case that is tidally locked but has axis
	## significantly tilted to orbit normal. Rotation axes of other tidally
	## locked moons are not [i]exactly[/i] orbit normal, but stay within ~1° (see
	## [url=https://zenodo.org/record/1259023]link[/url]). We approximate this
	## condition by maintaining rotation axis equal to the orbit normal.
	BODYFLAGS_AXIS_LOCKED = 1 << 17,
	BODYFLAGS_AXISYMMETRIC_WOBBLER = 1 << 18, ## NOT IMPLEMENTED YET.
	BODYFLAGS_ASYMMETRIC_TUMBLER = 1 << 19, ## NOT IMPLEMENTED YET.
	BODYFLAGS_CHAOTIC_TUMBLER = 1 << 20, ## NOT IMPLEMENTED YET (e.g., Hyperion).
	
	# program mechanics
	BODYFLAGS_LAZY_MODEL = 1 << 23,
	BODYFLAGS_CAN_SLEEP = 1 << 24,
	BODYFLAGS_DISABLE_MODEL_SPACE = 1 << 25, ## See [method remove_and_disable_model_space]
	BODYFLAGS_EXISTS = 1 << 26, ## Set for all IVBody instances.
	
	# GUI
	BODYFLAGS_SHOW_IN_NAVIGATION_PANEL = 1 << 29, ## Show in GUI "Navigation" panel.
	BODYFLAGS_DISPLAY_EQUATORIAL_POLAR_RADII = 1 << 30, ## Show e, p (instead of m) radii in GUI.
	BODYFLAGS_USE_CARDINAL_DIRECTIONS = 1 << 31, ## Display relative position as N, S, E, W in GUI.
	BODYFLAGS_USE_PITCH_YAW = 1 << 32, ## Display relative position as pitch, yaw in GUI.
	
}





const MIN_SYSTEM_M_RADIUS_MULTIPLIER := 15.0

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL # free & rebuild on load
const PERSIST_PROPERTIES: Array[StringName] = [
	&"name",
	&"flags",
	&"mean_radius",
	&"gravitational_parameter",
	&"basis_at_epoch",
	&"rotation_axis",
	&"rotation_rate",
	&"rotation_at_epoch",
	&"characteristics",
	&"components",
	&"orbit",
]


# persisted
var flags := 0 # BodyFlags
var mean_radius := 0.0
var gravitational_parameter := 0.0 # GM; G x Mass (often more accurate than mass)
var basis_at_epoch := Basis.IDENTITY
var rotation_axis := Vector3(0, 0, 1)
var rotation_rate := 0.0
var rotation_at_epoch := 0.0
var characteristics: Dictionary[StringName, Variant] = {} # non-object values
var components: Dictionary[StringName, RefCounted] = {} # objects (persisted only)
var orbit: IVOrbit


# read-only!
var star: IVBody # this body or above
var star_orbiter: IVBody # this body or star orbiter above or null
var satellites: Array[IVBody] = [] # IVBody children add/remove themselves
var model_space: IVModelSpace # has model axial tilt and rotation (not scale)
var huds_visible := false # too far / too close toggle
var model_visible := false
var texture_2d: Texture2D
var texture_slice_2d: Texture2D # navigation panel graphic for sun only
var max_model_dist := 0.0
var min_hud_dist: float
var lazy_model_uninited := false
var sleep := false


## Set this Script to generate a subclass in place of IVBody in all create
## methods. Assigned Script must be a subclass of IVBody!
static var replacement_subclass: Script

static var max_hud_dist_orbit_radius_multiplier := 100.0 ## class setting
static var min_hud_dist_radius_multiplier := 500.0 ## class setting
static var min_hud_dist_star_multiplier := 20.0 ## class setting

## Contains all added IVBody instances.
static var bodies: Dictionary[StringName, IVBody] = {}
## Contains IVBody instances that are at the top of an IVBody tree, i.e., the
## system star or the primary star for multi-star system.
static var galaxy_orbiters: Array[IVBody] = [] # TODO: Make dictionary to future-proof


# localized
@onready var _times: Array[float] = IVGlobal.times
@onready var _world_controller: IVWorldController = IVGlobal.program[&"WorldController"]



func _enter_tree() -> void:
	const BODYFLAGS_LAZY_MODEL := BodyFlags.BODYFLAGS_LAZY_MODEL
	_set_resources()
	_set_relative_bodies()
	if flags & BODYFLAGS_LAZY_MODEL and IVGlobal.program.has(&"LazyManager"):
		lazy_model_uninited = true
	else:
		_add_model_space()
	if orbit:
		orbit.changed.connect(_on_orbit_changed)
	hide()


func _ready() -> void:
	const BODYFLAGS_GALAXY_ORBITER := BodyFlags.BODYFLAGS_GALAXY_ORBITER
	process_mode = PROCESS_MODE_ALWAYS # time will stop, but allow pointy finger on mouseover
	IVGlobal.system_tree_built_or_loaded.connect(_on_system_tree_built_or_loaded, CONNECT_ONE_SHOT)
	IVGlobal.about_to_free_procedural_nodes.connect(_prepare_to_free, CONNECT_ONE_SHOT)
	IVGlobal.setting_changed.connect(_settings_listener)
	assert(!bodies.has(name))
	bodies[name] = self
	if flags & BODYFLAGS_GALAXY_ORBITER:
		galaxy_orbiters.append(self)
	_set_min_hud_dist()


func _exit_tree() -> void:
	const BODYFLAGS_GALAXY_ORBITER := BodyFlags.BODYFLAGS_GALAXY_ORBITER
	bodies.erase(name)
	if flags & BODYFLAGS_GALAXY_ORBITER:
		galaxy_orbiters.erase(self)
	_clear_relative_bodies()


func _process(_delta: float) -> void:
	# _process() is disabled while in sleep mode (sleep == true). When in sleep
	# mode, API assumes that any properties updated here are stale and must be
	# calculated (hence the `time` parameter).
	
	var time := _times[0]
	
	if orbit:
		position = orbit.update(time)
	
	var camera_dist := _world_controller.update_world_target(self, mean_radius)
	
	# update model space
	if model_space:
		var rotation_angle := wrapf(time * rotation_rate, 0.0, TAU)
		model_space.basis = basis_at_epoch.rotated(rotation_axis, rotation_angle)
		model_space.visible = camera_dist < max_model_dist
	
	# set HUDs visibility
	var show_huds := camera_dist > min_hud_dist # Is camera far enough?
	if show_huds and orbit:
		# Is body far enough from it parent?
		var orbit_radius := position.length()
		show_huds = orbit_radius * max_hud_dist_orbit_radius_multiplier > camera_dist
	if huds_visible != show_huds:
		huds_visible = show_huds
		huds_visibility_changed.emit(huds_visible)
	
	show()


# *****************************************************************************
# create methods


#@warning_ignore("shadowed_variable")
#static func create(name: StringName, flags: int, mean_radius: float, gravitational_parameter: float,
		#basis_at_epoch: Basis, rotation_axis: Vector3, rotation_at_epoch: float,
		#rotation_rate: float, orbit: IVOrbit, characteristics: Dictionary,
		#components: Dictionary, exisiting_body: IVBody = null) -> IVBody:
	#
	#
	#
	#var body := exisiting_body
	#if !body:
		#body = IVBody.new()
	#
	#
	#
	#return body


	#&"right_ascension",
	#&"declination",
	#&"rotation_period",



## Creates new IVOrbit instance (or specified [member replacement_subclass]).
## [param right_ascension] and [param declination] define "North" for this body.
## If [param rotation_period] is negative, then this body has retrograde
## rotation (e.g., Venus). If [param flags] & BODYFLAGS_TIDALLY_LOCKED, then
## [param rotation_period] doesn't matter. If [param flags] & BODYFLAGS_AXIS_LOCKED,
## then [param right_ascension] and [param declination] don't matter. (In our
## solar system, only the Moon is tidally locked but not "axis locked". All
## other moons that are tidally locked have axis of rotation that varies within
## 1° of their orbit normal.)
@warning_ignore("shadowed_variable", "shadowed_variable_base_class")
static func create_from_astronomy_specs(
		name: StringName,
		mean_radius: float,
		gravitational_parameter: float,
		right_ascension: float,
		declination: float,
		rotation_period: float,
		rotation_at_epoch: float,
		characteristics: Dictionary[StringName, Variant],
		components: Dictionary[StringName, RefCounted],
		orbit: IVOrbit,
		flags: int,
		exisiting_body: IVBody = null
	) -> IVBody:
	
	assert(name)
	assert(mean_radius > 0.0, "IVBody requires mean_radius > 0.0")
	assert(!is_nan(gravitational_parameter), "Use 0.0 if missing or unknown")
	assert(!is_nan(right_ascension), "Use 0.0 if missing or n/a")
	assert(!is_nan(declination), "Use 0.0 if missing or n/a")
	assert(!is_nan(rotation_period), "Use 0.0 if missing or n/a")
	assert(!is_nan(rotation_at_epoch), "IVBody requires 'rotation_at_epoch'")
	assert(flags > 0, "IVBody requires non-zero flags")
	
	rotation_at_epoch = fposmod(rotation_at_epoch, TAU)
	flags |= BodyFlags.BODYFLAGS_EXISTS
	
	assert(bool(flags & BodyFlags.BODYFLAGS_GALAXY_ORBITER) == (orbit == null))
	assert(!(flags & BodyFlags.BODYFLAGS_AXIS_LOCKED) or flags & BodyFlags.BODYFLAGS_TIDALLY_LOCKED,
			"Axis-locked bodies must also be tidally locked")
	# TODO: More flags asserts.
	
	var body := exisiting_body
	if !body:
		if replacement_subclass:
			@warning_ignore("unsafe_method_access")
			body = replacement_subclass.new()
		else:
			body = IVBody.new()
	
	
	body.name = name
	body.mean_radius = mean_radius
	body.gravitational_parameter = gravitational_parameter
	body.rotation_at_epoch = rotation_at_epoch
	body.characteristics = characteristics
	body.components = components
	body.orbit = orbit
	body.flags = flags
	
	# Rotations will be updated if tidally or axis locked, so these might not matter...
	var body_basis_at_epoch := IVAstronomy.get_ecliptic_basis_from_equatorial_north(
		right_ascension, declination)
	var body_rotation_axis := body_basis_at_epoch.z
	var body_rotation_rate := TAU / rotation_period if rotation_period else 0.0
	body_basis_at_epoch = body_basis_at_epoch.rotated(body_rotation_axis, rotation_at_epoch)
	body.rotation_axis = body_rotation_axis
	body.rotation_rate = body_rotation_rate
	body.basis_at_epoch = body_basis_at_epoch
	
	if flags & BodyFlags.BODYFLAGS_TIDALLY_LOCKED:
		# Note: most moons are not tidally locked (although all big moons are).
		characteristics[&"locked_rotation_at_epoch"] = rotation_at_epoch
	
	return body


# *****************************************************************************
# getters, setters and time gets, sets


func get_mean_radius() -> float:
	return mean_radius


func set_mean_radius(value: float) -> void:
	mean_radius = value


func has_orbit() -> bool:
	return orbit != null


func get_characteristic(characteristic_name: StringName) -> Variant:
	return characteristics.get(characteristic_name)


func set_characteristic(characteristic_name: StringName, value: Variant) -> void:
	characteristics[characteristic_name] = value


## Available only if IVCoreSettings.enable_precisions == true. Gets the
## precision (significant digits) of a float value as it was entered in the
## data table file or as calculated. [param path] can be a path to a property,
## a method, or a component property or method. See [IVSelectionData] for
## usage. Used by Planetarium.
func get_float_precision(path: String) -> int:
	if !characteristics.has(&"float_precisions"):
		return -1
	var float_precisions: Dictionary = characteristics[&"float_precisions"]
	return float_precisions.get(path, -1)


func get_rotation_period() -> float:
	return TAU / rotation_rate



## Returns north in equatorial coordinates as Vector2(right_ascention, declination).
func get_equatorial_north() -> Vector2:
	var eq_coord := IVAstronomy.get_equatorial_coordinates_from_ecliptic_vector(rotation_axis)
	return Vector2(eq_coord[0], eq_coord[1])



func get_mass() -> float:
	const G := IVAstronomy.G
	var mass: float = characteristics.get(&"mass", 0.0)
	if mass:
		return mass
	return gravitational_parameter / G


func get_gravitational_parameter() -> float:
	return gravitational_parameter


func get_equatorial_radius() -> float:
	var equatorial_radius: float = characteristics.get(&"equatorial_radius", 0.0)
	if equatorial_radius:
		return equatorial_radius
	return mean_radius


func get_polar_radius() -> float:
	var polar_radius: float = characteristics.get(&"polar_radius", 0.0)
	if polar_radius:
		return polar_radius
	return mean_radius


func get_hud_name() -> String:
	return characteristics.get(&"hud_name", name)


func set_hud_name(value: String) -> void:
	if value != name:
		characteristics[&"hud_name"] = value


func get_symbol() -> String:
	return characteristics.get(&"symbol", "\u25CC") # default is dashed circle


func set_symbol(value: String) -> void:
	if value != "\u25CC":
		characteristics[&"symbol"] = value


func get_body_class() -> int: # body_classes.tsv
	return characteristics.get(&"body_class", -1)


func set_body_class(value: int) -> void:
	characteristics[&"body_class"] = value


func get_system_radius() -> float:
	# From data table or set to outermost satellite semi-major axis.
	return characteristics.get(&"system_radius", 0.0)


func set_system_radius(value: float) -> void:
	characteristics[&"system_radius"] = value


func get_perspective_radius() -> float:
	# For camera perspective distancing. Same as mean_radius unless something
	# different is needed.
	var perspective_radius: float = characteristics.get(&"perspective_radius", 0.0)
	if perspective_radius:
		return perspective_radius
	return mean_radius


func set_perspective_radius(value: float) -> void:
	assert(value > 0.0)
	if value != get_perspective_radius():
		characteristics[&"perspective_radius"] = value





# get onlys below; set is invalid or may need some work to do

func get_model_type() -> int: # models.tsv
	return characteristics.get(&"model_type", -1)


func has_light() -> bool:
	return characteristics.get(&"has_light", false)


func has_rings() -> bool:
	return characteristics.get(&"has_rings", false)


func get_file_prefix() -> String:
	return characteristics.get(&"file_prefix", "")


func get_latitude_longitude(at_translation: Vector3, time := NAN) -> Vector2:
	const math := preload("res://addons/ivoyager_core/static/math.gd")
	var ground_basis := get_ground_tracking_basis(time)
	var spherical := math.get_rotated_spherical3(at_translation, ground_basis)
	var latitude: float = spherical[1]
	var longitude: float = wrapf(spherical[0], -PI, PI)
	return Vector2(latitude, longitude)


## Returns this body's north in ecliptic coordinates. This is messy because
## IAU defines "north" only for true planets and their satellites, defined
## as the pole pointing above the invariable plane. Other bodies technically
## don't have north and are supposed to use "positive pole", which has a
## precise definition. See 
## [url]https://en.wikipedia.org/wiki/Poles_of_astronomical_bodies[/url].[br][br]
##
## However, it is common usage to assign north to Pluto and Charon's positive
## poles, which is flipped from above if Pluto were a planet (which it is
## not, of course). Also, we want a "north" for all bodies for camera
## orientation. We attempt to sort this out as follows:[br][br]
##
##  * Star - Same as true planet.[br]
##  * True planets and their satellites - Use pole in the same hemisphere as
##    ecliptic north. This is almost per IAU, 
##    except for use of ecliptic rather than invarient plane (the
##    difference is ~1° and will affect very few if any objects).[br]
##  * Other star-orbiting bodies - Use positive pole, following Pluto.[br]
##  * All others (e.g., satellites of dwarf planets) - Use pole in same
##    hemisphere as parent positive pole.[br][br]
##
## Note that [member rotation_axis] and [member rotation_rate] will be flipped
## if needed during system build so that rotation_axis is always north, following
## rules above.
func get_north_axis(_time := NAN) -> Vector3:
	return rotation_axis


## Returns the axis of rotation pointing in the direction of the positive pole,
## using the right-hand-rule.
func get_positive_axis(_time := NAN) -> Vector3:
	if rotation_rate < 0.0:
		return -rotation_axis
	return rotation_axis


func get_orbit_mean_longitude(time := NAN) -> float:
	if !orbit:
		return 0.0
	if is_nan(time):
		if !sleep:
			return orbit.get_mean_longitude_at_update()
		time = _times[0]
	return orbit.get_mean_longitude(time)


func get_orbit_true_longitude(time := NAN) -> float:
	if !orbit:
		return 0.0
	if is_nan(time):
		if !sleep:
			return orbit.get_true_longitude_at_update()
		time = _times[0]
	return orbit.get_true_longitude(time)


func is_orbit_retrograde(time := NAN) -> bool:
	if !orbit:
		return false
	if is_nan(time):
		if !sleep:
			return orbit.is_retrograde()
		time = _times[0]
	return orbit.is_retrograde_at_time(time)


func get_orbit_semi_parameter(time := NAN) -> float:
	if !orbit:
		return 0.0
	if is_nan(time):
		if !sleep:
			return orbit.get_semi_parameter()
		time = _times[0]
	return orbit.get_semi_parameter_at_time(time)


func get_orbit_semi_major_axis(time := NAN) -> float:
	if !orbit:
		return 0.0
	if is_nan(time):
		if !sleep:
			return orbit.get_semi_major_axis()
		time = _times[0]
	return orbit.get_semi_major_axis_at_time(time)


func get_orbit_eccentricity(time := NAN) -> float:
	if !orbit:
		return 0.0
	if is_nan(time):
		if !sleep:
			return orbit.get_eccentricity()
		time = _times[0]
	return orbit.get_eccentricity_at_time(time)


func get_orbit_inclination(time := NAN) -> float:
	if !orbit:
		return 0.0
	if is_nan(time):
		if !sleep:
			return orbit.get_inclination()
		time = _times[0]
	return orbit.get_inclination_at_time(time)


func get_orbit_normal(time := NAN, flip_retrograde := false) -> Vector3:
	const ECLIPTIC_NORTH := Vector3(0, 0, 1)
	if !orbit:
		return ECLIPTIC_NORTH
	if is_nan(time):
		if !sleep:
			return orbit.get_normal(flip_retrograde)
		time = _times[0]
	return orbit.get_normal_at_time(time, flip_retrograde)


func is_rotation_retrograde() -> bool:
	return rotation_rate < 0.0


func get_axial_tilt_to_orbit(time := NAN) -> float:
	if !orbit:
		return NAN
	var orbit_normal: Vector3
	if is_nan(time):
		if !sleep:
			orbit_normal = orbit.get_normal()
		else:
			time = _times[0]
			orbit_normal = orbit.get_normal_at_time(time)
	else:
		orbit_normal = orbit.get_normal_at_time(time)
	var positive_axis := get_positive_axis(time)
	return positive_axis.angle_to(orbit_normal)


func get_axial_tilt_to_ecliptic(time := NAN) -> float:
	const ECLIPTIC_NORTH := Vector3(0, 0, 1)
	var positive_axis := get_positive_axis(time)
	return positive_axis.angle_to(ECLIPTIC_NORTH)


## Returns a basis that rotates with the ground (i.e, with the body model).
func get_ground_tracking_basis(time := NAN) -> Basis:
	if is_nan(time):
		if model_space and !sleep:
			return model_space.basis
		time = _times[0]
	var rotation_angle := wrapf(time * rotation_rate, 0.0, TAU)
	return basis_at_epoch.rotated(rotation_axis, rotation_angle)


## Returns a basis that rotates with the body's orbit around its parent, with
## parent in the -x direction and orbit normal in the z direction. Returns
## identity basis if this IVBody has no IVOrbit. This is a different basis than
## IVOrbit.get_basis().
func get_orbit_tracking_basis(time := NAN) -> Basis:
	const ECLIPTIC_BASIS := Basis.IDENTITY
	if !orbit:
		return ECLIPTIC_BASIS
	var x_axis: Vector3
	var y_axis: Vector3
	var z_axis: Vector3
	if is_nan(time):
		if !sleep:
			x_axis = -position.normalized()
			z_axis = orbit.get_normal(true, true)
			y_axis = z_axis.cross(x_axis)
			return Basis(x_axis, y_axis, z_axis)
		time = _times[0]
	x_axis = -orbit.get_position(time).normalized()
	z_axis = orbit.get_normal_at_time(time, true, true)
	y_axis = z_axis.cross(x_axis)
	return Basis(x_axis, y_axis, z_axis)


## See https://en.wikipedia.org/wiki/Hill_sphere.
## Currently returns INF if this is a top body in simulation.
func get_hill_sphere(eccentricity := 0.0) -> float:
	const BODYFLAGS_GALAXY_ORBITER := BodyFlags.BODYFLAGS_GALAXY_ORBITER
	if flags & BODYFLAGS_GALAXY_ORBITER:
		return INF
	var a := get_orbit_semi_major_axis()
	var parent: IVBody = get_parent_node_3d()
	var parent_mass: float = parent.get_mass()
	var mass := get_mass()
	if !a or !mass or !parent_mass:
		return 0.0
	return a * (1.0 - eccentricity) * pow(mass / (3.0 * parent_mass), 0.33333333)


# special mechanics below

func add_child_to_model_space(spatial: Node3D) -> void:
	assert(not flags & BodyFlags.BODYFLAGS_DISABLE_MODEL_SPACE)
	if !model_space:
		_add_model_space()
	model_space.add_child(spatial)


func remove_child_from_model_space(spatial: Node3D) -> void:
	model_space.remove_child(spatial)


## This method is implemented for a specific use case, where a body is "removed"
## but we want HUD elements to see where it would be if it was still present.
## (This is for the author's Dyson Sphere construction project...)
func remove_and_disable_model_space() -> void:
	# Removes model(s) but everything else remains (label & orbit HUDs, etc.).
	# Unsets BodyFlags.BODYFLAGS_EXISTS.
	const BODYFLAGS_DISABLE_MODEL_SPACE := BodyFlags.BODYFLAGS_DISABLE_MODEL_SPACE
	flags |= BODYFLAGS_DISABLE_MODEL_SPACE
	flags &= ~BodyFlags.BODYFLAGS_EXISTS
	if model_space:
		model_space.queue_free()
	model_space = null


func set_orbit(new_orbit: IVOrbit) -> void:
	assert(new_orbit)
	if orbit:
		orbit.changed.disconnect(_on_orbit_changed)
	orbit = new_orbit
	if !is_inside_tree():
		return # below happens on _enter_tree()
	new_orbit.changed.connect(_on_orbit_changed)


func lazy_model_init() -> void:
	_add_model_space()


## Only [IVSleepManager] should call this.
func set_sleep(sleep_: bool) -> void:
	const BODYFLAGS_CAN_SLEEP := BodyFlags.BODYFLAGS_CAN_SLEEP
	if sleep == sleep_ or not flags & BODYFLAGS_CAN_SLEEP:
		return
	sleep = sleep_
	if sleep_:
		hide()
		set_process(false)
		_world_controller.remove_world_target(self)
	else:
		set_process(true)


func get_fragment_data(_fragment_type: int) -> Array:
	# Only FRAGMENT_BODY_ORBIT at this time.
	return [get_instance_id()]


func get_fragment_text(_data: Array) -> String:
	# Only FRAGMENT_BODY_ORBIT at this time.
	return tr(name) + " (" + tr("LABEL_ORBIT").to_lower() + ")"




# *****************************************************************************
# private


func _prepare_to_free() -> void:
	satellites.clear()


func _on_system_tree_built_or_loaded(is_new_game: bool) -> void:
	if !is_new_game:
		return
	if !characteristics.get(&"system_radius"):
		var system_radius := mean_radius * MIN_SYSTEM_M_RADIUS_MULTIPLIER
		for satellite in satellites:
			var a: float = satellite.get_orbit_semi_major_axis()
			if system_radius < a:
				system_radius = a
		characteristics[&"system_radius"] = system_radius


func _set_resources() -> void:
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	texture_2d = asset_preloader.get_body_texture_2d(name)
	texture_slice_2d = asset_preloader.get_body_texture_slice_2d(name) # usually null


func _set_relative_bodies() -> void:
	# For multi-star system, a star could be a star orbiter.
	const BODYFLAGS_STAR := BodyFlags.BODYFLAGS_STAR
	const BODYFLAGS_STAR_ORBITER := BodyFlags.BODYFLAGS_STAR_ORBITER
	star = null
	star_orbiter = null
	var up_tree := self
	while up_tree:
		if !star_orbiter and up_tree.flags & BodyFlags.BODYFLAGS_STAR_ORBITER:
			star_orbiter = up_tree
		if up_tree.flags & BODYFLAGS_STAR:
			star = up_tree
			break
		up_tree = up_tree.get_parent_node_3d() as IVBody
	var parent := get_parent_node_3d() as IVBody
	if parent:
		assert(!parent.satellites.has(self))
		parent.satellites.append(self)


func _clear_relative_bodies() -> void:
	star = null
	star_orbiter = null
	var parent := get_parent_node_3d() as IVBody
	if parent:
		parent.satellites.erase(self)


func _set_min_hud_dist() -> void:
	if !IVGlobal.settings[&"hide_hud_when_close"]:
		min_hud_dist = 0.0
		return
	min_hud_dist = mean_radius * min_hud_dist_radius_multiplier
	if flags & BodyFlags.BODYFLAGS_STAR:
		min_hud_dist *= min_hud_dist_star_multiplier # star grows at distance


func _on_orbit_changed(is_intrinsic: bool) -> void:
	const TIDALLY_LOCKED := BodyFlags.BODYFLAGS_TIDALLY_LOCKED
	if flags & TIDALLY_LOCKED:
		_update_rotations()
	orbit_changed.emit(orbit, is_intrinsic)


func _update_rotations() -> void:
	
	const TIDALLY_LOCKED := BodyFlags.BODYFLAGS_TIDALLY_LOCKED
	const AXIS_LOCKED := BodyFlags.BODYFLAGS_AXIS_LOCKED
	
	if !flags & TIDALLY_LOCKED:
		return
	
	# Code assumes that a body can only be axis-locked if it is also tidally
	# locked.
	
	# rotation
	var new_rotation_rate := orbit.get_mean_longitude_rate()
	var locked_rotation_at_epoch: float = characteristics[&"locked_rotation_at_epoch"]
	var new_rotation_at_epoch := fposmod(locked_rotation_at_epoch
			+ orbit.get_mean_longitude_at_epoch() - PI, TAU)
	
	# axis
	var new_rotation_axis := rotation_axis
	if flags & AXIS_LOCKED:
		new_rotation_axis = orbit.get_normal()
	
		# Possible polarity reversal. See comments under get_north_axis().
		# For any body that is axis-locked, "north" follows parent north,
		# whatever that is. Note that rotation_axis defines "north".
		var parent := get_parent_node_3d() as IVBody
		if parent.rotation_axis.dot(new_rotation_axis) < 0.0:
			# e.g., Triton
			new_rotation_axis *= -1.0
			new_rotation_rate *= -1.0
			new_rotation_at_epoch = fposmod(-new_rotation_at_epoch, TAU)

	rotation_rate = new_rotation_rate
	rotation_axis = new_rotation_axis
	rotation_at_epoch = new_rotation_at_epoch
	
	var new_basis := IVAstronomy.get_basis_from_z_axis_and_vernal_equinox(rotation_axis)
	basis_at_epoch = new_basis.rotated(rotation_axis, rotation_at_epoch)


func _add_model_space() -> void:
	const BODYFLAGS_DISABLE_MODEL_SPACE := BodyFlags.BODYFLAGS_DISABLE_MODEL_SPACE
	assert(!model_space)
	lazy_model_uninited = false
	if flags & BODYFLAGS_DISABLE_MODEL_SPACE:
		return
	var model_space_script: Script = IVGlobal.procedural_classes[&"ModelSpace"]
	@warning_ignore("unsafe_method_access")
	model_space = model_space_script.new(name, mean_radius, get_equatorial_radius())
	max_model_dist = model_space.max_distance
	add_child(model_space)


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"hide_hud_when_close":
		_set_min_hud_dist()
