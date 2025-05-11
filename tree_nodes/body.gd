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
## instantiated asteroids, and spacecrafts. [TODO: and barycenters.]
##
## IVBody nodes are NEVER scaled or rotated. Hence, local and global distances
## and directions are always consistent at any level of the "body tree". To
## share this body's orientation in space, Saturn's [IVRings] are added to its
## [IVModelSpace].[br][br]
## 
## Node name is always the data table row name: PLANET_EARTH, MOON_EUROPA,
## SPACECRAFT_ISS, etc.[br][br]
##
## This node adds its own [IVModelSpace] (which instantiates a model) if needed.
## If this body has table value `lazy_model == true`, it won't add the model
## space until/unless the camera visits this body or a closely associated
## lazy body. See [IVLazyModelInitializer].[br][br]
##
## Some bodies (particularly moons and spacecrafts) have table value
## `can_sleep == true`. These bodies' process state is on only when the camera
## is in the same planet system. See [IVSleepManager].[br][br]
##
## Many body-associated "graphic" nodes are added by [IVBodyFinisher],
## including rings, lights and HUD elements. (IVBody isn't aware of these
## nodes.)[br][br]
##
## IVBody properties are core information required for all bodies. Specialized
## information is contained in dictionary [member characteristics]. For
## example all bodies have [member mean_radius], but oblate spheroid bodies
## (most planets and stars) also have characteristics keys &"equatorial_radius"
## and &"polar_radius".
## 
## See also IVSmallBodiesGroup for handling 1000s or 100000s of orbiting bodies
## without individual instantiation (e.g., asteroids).[br][br]
##
## TODO: Public API for changing orbit context or "identity". E.g., a spacecraft
## becomes BODYFLAGS_STAR_ORBITER, or an asteroid is captured to become a moon.
##
## TODO: (Ongoing) Make this node more 'drag-and_drop'.[br][br]
##
## TODO: Barycenters! They orbit and are orbited. These will make Pluto system
## (especially) more accurate.[br][br]
##
## TODO: Implement network sync! This will mainly involve synching IVOrbit
## anytime it changes in an extrinsic way (e.g., impulse from a rocket
## engine).

signal orbit_changed(orbit: IVOrbit, is_intrinsic: bool)
signal huds_visibility_changed(is_visible: bool)


## Bits to 1 << 39 are reserved for ivoyager_core future use. Higher bits are
## safe to use for external projects. Max bit shift is 1 << 63.
enum BodyFlags {
	
	# orbit context & identity
	BODYFLAGS_GALAXY_ORBITER = 1,
	BODYFLAGS_STAR_ORBITER = 1 << 1,
	BODYFLAGS_BARYCENTER = 1 << 2, ## not implemented yet
	BODYFLAGS_PLANETARY_MASS_OBJECT = 1 << 3,
	BODYFLAGS_STAR = 1 << 4,
	BODYFLAGS_PLANET_OR_DWARF_PLANET = 1 << 5,
	BODYFLAGS_PLANET = 1 << 6,
	BODYFLAGS_DWARF_PLANET = 1 << 7,
	BODYFLAGS_MOON = 1 << 8,
	BODYFLAGS_PLANETARY_MASS_MOON = 1 << 9,
	BODYFLAGS_NON_PLANETARY_MASS_MOON = 1 << 10,
	BODYFLAGS_ASTEROID = 1 << 11,
	BODYFLAGS_COMET = 1 << 12,
	BODYFLAGS_SPACECRAFT = 1 << 13,
	
	# rotation mechanics
	BODYFLAGS_TIDALLY_LOCKED = 1 << 16,
	BODYFLAGS_AXIS_LOCKED = 1 << 17,
	BODYFLAGS_TUMBLES_CHAOTICALLY = 1 << 18, ## e.g., Hyperion (mechanic not implemented)
	
	# program mechanics
	BODYFLAGS_LAZY_MODEL = 1 << 21,
	BODYFLAGS_SLEEP = 1 << 22,
	BODYFLAGS_DISABLE_MODEL_SPACE = 1 << 23,
	BODYFLAGS_EXISTS = 1 << 24, ## @depreciate: (currently set by IVTableBodyBuilder)
	
	# GUI
	BODYFLAGS_SHOW_IN_NAVIGATION_PANEL = 1 << 26,
	BODYFLAGS_DISPLAY_EQUATORIAL_POLAR_RADII = 1 << 27,
	BODYFLAGS_USE_CARDINAL_DIRECTIONS = 1 << 28,
	BODYFLAGS_USE_PITCH_YAW = 1 << 29,
	
}


const math := preload("uid://csb570a3u1x1k")

const ECLIPTIC_BASIS := Basis.IDENTITY
const ECLIPTIC_NORTH := ECLIPTIC_BASIS.z

const MIN_SYSTEM_M_RADIUS_MULTIPLIER := 15.0

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL # free & rebuild on load
const PERSIST_PROPERTIES: Array[StringName] = [
	&"name",
	&"flags",
	&"mean_radius",
	&"rotation_period",
	&"right_ascension",
	&"declination",
	&"gm",
	&"mass",
	&"characteristics",
	&"components",
	&"orbit",
]

# persisted
var flags := 0 # BodyFlags
var mean_radius := 0.0
var rotation_period := INF # updated if tidally locked
var right_ascension := 0.0 # updated if axis locked
var declination := PI / 2.0 # updated if axis locked
var gm := 0.0 # G x Mass; standard gravitational parameter (often more accurate than mass!)
var mass := 0.0
var characteristics: Dictionary[StringName, Variant] = {} # non-object values
var components: Dictionary[StringName, Object] = {} # objects (persisted only)
var orbit: IVOrbit


# read-only calculated spatials
var rotation_vector := ECLIPTIC_NORTH
var rotation_rate := 0.0
var rotation_at_epoch := 0.0
var basis_at_epoch := ECLIPTIC_BASIS

# read-only!
var star: IVBody # this body or above
var star_orbiter: IVBody # this body or star orbiter above or null
var satellites: Array[IVBody] = [] # IVBody children add/remove themselves
var model_space: IVModelSpace # has model axial tilt and rotation (not scale)
var huds_visible := false # too far / too close toggle
var model_visible := false
var texture_2d: Texture2D
var texture_slice_2d: Texture2D # navigation panel graphic for sun only
var model_reference_basis := ECLIPTIC_BASIS
var max_model_dist := 0.0
var min_hud_dist: float
var lazy_model_uninited := false
var sleep := false
var shader_sun_index := -1


static var max_hud_dist_orbit_radius_multiplier := 100.0 ## class setting
static var min_hud_dist_radius_multiplier := 500.0 ## class setting
static var min_hud_dist_star_multiplier := 20.0 ## class setting

## Contains all added IVBody instances.
static var bodies: Dictionary[StringName, IVBody] = {}
## Contains IVBody instances that are at the top of an IVBody tree, i.e., the
## system star or the primary star for multi-star system.
static var galaxy_orbiters: Array[IVBody] = [] # TODO: Make dictionary to future-proof
## This is used by shaders and is currently limited to 3 elements because we
## can't have array shader globals (this is converted to mat3). FIXME: Don't use
## a shader global, but have rings.gd know what sun affects it and send that
## to shader on _process().
static var sun_global_positions: Array[Vector3] = [Vector3(), Vector3(), Vector3()]


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
	shader_sun_index = characteristics.get(&"shader_sun_index", -1)
	assert(shader_sun_index >= -1 and shader_sun_index <= 2)
	hide()


func _ready() -> void:
	const BODYFLAGS_GALAXY_ORBITER := BodyFlags.BODYFLAGS_GALAXY_ORBITER
	process_mode = PROCESS_MODE_ALWAYS # time will stop, but allow pointy finger on mouseover
	IVGlobal.system_tree_built_or_loaded.connect(_on_system_tree_built_or_loaded, CONNECT_ONE_SHOT)
	IVGlobal.about_to_free_procedural_nodes.connect(_prepare_to_free, CONNECT_ONE_SHOT)
	IVGlobal.setting_changed.connect(_settings_listener)
	var timekeeper: IVTimekeeper = IVGlobal.program[&"Timekeeper"]
	timekeeper.time_altered.connect(_on_time_altered)
	assert(!bodies.has(name))
	bodies[name] = self
	if flags & BODYFLAGS_GALAXY_ORBITER:
		galaxy_orbiters.append(self)
	recalculate_spatials()
	_set_min_hud_dist()


func _exit_tree() -> void:
	const BODYFLAGS_GALAXY_ORBITER := BodyFlags.BODYFLAGS_GALAXY_ORBITER
	bodies.erase(name)
	if flags & BODYFLAGS_GALAXY_ORBITER:
		galaxy_orbiters.erase(self)
	_clear_relative_bodies()


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


func _prepare_to_free() -> void:
	satellites.clear()


func _process(_delta: float) -> void:
	# _process() is disabled while in sleep mode (sleep == true). When in sleep
	# mode, API assumes that any properties updated here are stale and must be
	# obtained using time parameter.
	
	var camera_dist := _world_controller.process_world_target(self, mean_radius)
	
	if orbit:
		position = orbit.update(_times[0])
	
	# update model space
	if model_space:
		var rotation_angle := wrapf(_times[0] * rotation_rate, 0.0, TAU)
		model_space.basis = basis_at_epoch.rotated(rotation_vector, rotation_angle)
		model_space.visible = camera_dist < max_model_dist
	
	# set HUDs visibility
	var hud_dist_ok := camera_dist > min_hud_dist or !model_space # not too close to camera
	if hud_dist_ok and orbit:
		var orbit_radius := position.length()
		# is body too close to its parent for camera distance?
		hud_dist_ok = orbit_radius * max_hud_dist_orbit_radius_multiplier > camera_dist
	if huds_visible != hud_dist_ok:
		huds_visible = hud_dist_ok
		huds_visibility_changed.emit(huds_visible)
	
	# sun position(s) for shader global
	if shader_sun_index != -1 and sun_global_positions[shader_sun_index] != global_position:
		sun_global_positions[shader_sun_index] = global_position
		var as_basis := Basis(sun_global_positions[0], sun_global_positions[1],
				sun_global_positions[2])
		RenderingServer.global_shader_parameter_set( &"iv_sun_global_positions", as_basis)
	show()


# *****************************************************************************
# public API

func has_orbit() -> bool:
	return orbit != null


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


func get_characteristic(characteristic_name: StringName) -> Variant:
	return characteristics.get(characteristic_name)


func set_characteristic(characteristic_name: StringName, value: Variant) -> void:
	characteristics[characteristic_name] = value


func get_mean_radius() -> float:
	return mean_radius


func set_mean_radius(value: float) -> void:
	mean_radius = value


func get_rotation_period() -> float:
	return rotation_period


func set_rotation_period(value: float, supress_recalculation := false) -> void:
	rotation_period = value
	if !supress_recalculation:
		recalculate_spatials()


func get_right_ascension() -> float:
	return right_ascension


func set_right_ascension(value: float, supress_recalculation := false) -> void:
	right_ascension = value
	if !supress_recalculation:
		recalculate_spatials()


func get_declination() -> float:
	return declination


func set_declination(value: float, supress_recalculation := false) -> void:
	declination = value
	if !supress_recalculation:
		recalculate_spatials()


func get_mass() -> float:
	return mass


func set_mass(value: float) -> void:
	mass = value


func get_standard_gravitational_parameter() -> float:
	return gm


func set_standard_gravitational_parameter(value: float) -> void:
	gm = value


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
	var ground_basis := get_ground_tracking_basis(time)
	var spherical := math.get_rotated_spherical3(at_translation, ground_basis)
	var latitude: float = spherical[1]
	var longitude: float = wrapf(spherical[0], -PI, PI)
	return Vector2(latitude, longitude)

## Returns this body's north in ecliptic coordinates. This is messy because
## IAU defines 'north' only for true planets and their satellites (defined
## as the pole pointing above invariable plane). Other bodies technically
## don't have 'north' and are supposed to use 'positive pole', which has a
## precise definition. See 
## https://en.wikipedia.org/wiki/Poles_of_astronomical_bodies.[br][br]
##
## However, it is common usage to assign 'north' to Pluto and Charon's positive
## poles, which is reversed from above if Pluto were a planet (which it is
## not, of course). Also, we want a north for all bodies for camera
## orientation. We attempt to sort this out as follows:[br][br]
##
##  * Star - Same as true planet.[br]
##  * True planets and their satellites - Use pole pointing in positive z-
##    axis direction in ecliptic (our sim reference coordinates). This is
##    per IAU except the use of ecliptic rather than invarient plane; the
##    difference is ~1 degree and will affect very few if any objects.[br]
##  * Other star-orbiting bodies - Use positive pole, following Pluto.[br]
##  * All others (e.g., satellites of dwarf planets) - Use pole in same
##    hemisphere as parent positive pole.[br][br]
##
## Note that rotation_vector (and rotation_rate) will be flipped if needed
## during system build (following above rules) so that rotation_vector is
## always 'north'.[br][br]
##
## TODO: North precession; this will require 'time' arg.
func get_north_pole(_time := NAN) -> Vector3:
	return rotation_vector


func get_up_pole(_time := NAN) -> Vector3:
	# Synonymous with "north".
	return rotation_vector


func get_positive_pole(_time := NAN) -> Vector3:
	# Right-hand-rule! This is exactly defined, unlike "north".
	if rotation_rate < 0.0:
		return -rotation_vector
	return rotation_vector


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


func get_orbit_normal(time := NAN, flip_retrograde := false) -> Vector3:
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
	var positive_pole := get_positive_pole(time)
	return positive_pole.angle_to(orbit_normal)


func get_axial_tilt_to_ecliptic(time := NAN) -> float:
	var positive_pole := get_positive_pole(time)
	return positive_pole.angle_to(ECLIPTIC_NORTH)


## Returns a basis that rotates with the ground (i.e, with the body model).
func get_ground_tracking_basis(time := NAN) -> Basis:
	if is_nan(time):
		if model_space and !sleep:
			return model_space.basis
		time = _times[0]
	var rotation_angle := wrapf(time * rotation_rate, 0.0, TAU)
	return basis_at_epoch.rotated(rotation_vector, rotation_angle)


## Returns a basis that rotates with the body's orbit, with the parent in the
## -x direction and orbit normal in the z direction. Returns identity basis if
## this IVBody has no IVOrbit. This is a different basis than IVOrbit.get_basis().
func get_orbit_tracking_basis(time := NAN) -> Basis:
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
	const BODYFLAGS_SLEEP := BodyFlags.BODYFLAGS_SLEEP
	if sleep == sleep_ or not flags & BODYFLAGS_SLEEP:
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



func recalculate_spatials() -> void:
	
	# TODO: Make this internal to ModelSpace. (But don't make ModelSpace
	# persistant!)
	
	# Sets 'rotation_rate', 'rotation_vector' and 'rotation_at_epoch' and
	# (possibly) associated values in 'characteristics'. For planets, these are
	# fixed values determined by table-loaded 'characteristics.RA', '.dec' and
	# '.period'. If we have tidal and/or axis lock, then IVOrbit determines
	# rotation and/or orientation. If so, we use IVOrbit to set the three
	# IVBody properties and to back-calclulate 'characteristics.RA', '.dec' and
	# '.period'.
	#
	# Note: Earth's Moon is the unique case that is tidally locked but has axis
	# significantly tilted to orbit normal. Axis of other tidally-locked moons
	# are not exactly orbit normal but stay within ~1 degree (see:
	# https://zenodo.org/record/1259023) which we approximate as zero (i.e,
	# 'axis-locked').
	#
	# TODO: We still need rotation precession for Bodies with axial tilt.
	# TODO: Some special mechanic for tumblers like Hyperion.
	const BODYFLAGS_GALAXY_ORBITER := BodyFlags.BODYFLAGS_GALAXY_ORBITER
	const BODYFLAGS_STAR := BodyFlags.BODYFLAGS_STAR
	const BODYFLAGS_PLANET := BodyFlags.BODYFLAGS_PLANET
	const BODYFLAGS_TIDALLY_LOCKED := BodyFlags.BODYFLAGS_TIDALLY_LOCKED
	const BODYFLAGS_AXIS_LOCKED := BodyFlags.BODYFLAGS_AXIS_LOCKED
	const BODYFLAGS_TUMBLES_CHAOTICALLY := BodyFlags.BODYFLAGS_TUMBLES_CHAOTICALLY
	
	var new_rotation_vector: Vector3
	var new_rotation_rate: float
	
	# rotation_rate
	if flags & BODYFLAGS_TIDALLY_LOCKED:
		new_rotation_rate = orbit.get_mean_motion()
		rotation_period = TAU / new_rotation_rate
	else:
		new_rotation_rate = TAU / rotation_period
	
	# rotation_vector
	if flags & BODYFLAGS_AXIS_LOCKED:
		new_rotation_vector = orbit.get_normal_at_time(_times[0]) # ecliptic
		var ra_dec := IVAstronomy.get_equatorial_coordinates_from_ecliptic_vector(
				new_rotation_vector)
		right_ascension = ra_dec[0]
		declination = ra_dec[1]
		
	elif flags & BODYFLAGS_TUMBLES_CHAOTICALLY:
		# TODO: something sensible for Hyperion and outer gas giant moons
		new_rotation_vector = IVAstronomy.ECLIPTIC_NORTH
	else:
		new_rotation_vector = IVAstronomy.get_ecliptic_unit_vector_from_equatorial_angles(
				right_ascension, declination)
	var new_rotation_at_epoch: float = characteristics.get(&"longitude_at_epoch", 0.0)
	
	if orbit:
		if flags & BODYFLAGS_TIDALLY_LOCKED:
			new_rotation_at_epoch += orbit.get_mean_longitude(0.0) - PI
		else:
			new_rotation_at_epoch += orbit.get_true_longitude(0.0) - PI
	
	# possible polarity reversal; see comments under get_north_pole()
	var reverse_polarity := false
	var parent := get_parent_node_3d() as IVBody
	if (flags & BODYFLAGS_GALAXY_ORBITER or flags & BODYFLAGS_STAR or flags & BODYFLAGS_PLANET
			or parent.flags & BODYFLAGS_PLANET):
		if ECLIPTIC_NORTH.dot(new_rotation_vector) < 0.0:
			reverse_polarity = true
	elif parent.flags & BODYFLAGS_STAR: # any other star-orbiter (dwarf planets, asteroids, etc.)
		if new_rotation_rate < 0.0:
			reverse_polarity = true
	else: # moons of not-true-planet star-orbiters
		var parent_positive_pole: Vector3 = parent.get_positive_pole()
		if parent_positive_pole.dot(new_rotation_vector) < 0.0:
			reverse_polarity = true
	if reverse_polarity:
		new_rotation_rate = -new_rotation_rate
		new_rotation_vector = -new_rotation_vector # this defines "north"!
		new_rotation_at_epoch = -new_rotation_at_epoch
	
	rotation_rate = new_rotation_rate
	rotation_vector = new_rotation_vector
	rotation_at_epoch = new_rotation_at_epoch
	
	var new_basis := IVAstronomy.get_basis_from_north_vector(rotation_vector)
	basis_at_epoch = new_basis.rotated(rotation_vector, rotation_at_epoch)



# *****************************************************************************
# private


func _set_resources() -> void:
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	texture_2d = asset_preloader.get_body_texture_2d(name)
	texture_slice_2d = asset_preloader.get_body_texture_slice_2d(name) # usually null


func _add_model_space() -> void:
	const BODYFLAGS_DISABLE_MODEL_SPACE := BodyFlags.BODYFLAGS_DISABLE_MODEL_SPACE
	assert(!model_space)
	lazy_model_uninited = false
	if flags & BODYFLAGS_DISABLE_MODEL_SPACE:
		return
	var model_space_script: Script = IVGlobal.procedural_classes[&"ModelSpace"]
	@warning_ignore("unsafe_method_access")
	model_space = model_space_script.new(name, mean_radius, get_equatorial_radius())
	model_reference_basis = model_space.reference_basis
	max_model_dist = model_space.max_distance
	add_child(model_space)


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


func _on_orbit_changed(is_intrinsic: bool) -> void:
	#prints("_on_orbit_changed", name)
	const BODYFLAGS_TIDALLY_LOCKED := BodyFlags.BODYFLAGS_TIDALLY_LOCKED
	const BODYFLAGS_AXIS_LOCKED := BodyFlags.BODYFLAGS_AXIS_LOCKED
	if flags & BODYFLAGS_TIDALLY_LOCKED or flags & BODYFLAGS_AXIS_LOCKED:
		recalculate_spatials()
	orbit_changed.emit(orbit, is_intrinsic)



func _on_time_altered(_previous_time: float) -> void:
	await get_tree().process_frame
	recalculate_spatials()


func _set_min_hud_dist() -> void:
	const BODYFLAGS_STAR := BodyFlags.BODYFLAGS_STAR
	if IVGlobal.settings.get(&"hide_hud_when_close", false):
		min_hud_dist = mean_radius * min_hud_dist_radius_multiplier
		if flags & BODYFLAGS_STAR:
			min_hud_dist *= min_hud_dist_star_multiplier # just the label
	else:
		min_hud_dist = 0.0


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"hide_hud_when_close":
		_set_min_hud_dist()
