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
## and directions are always consistent at any level of the "body tree".
## For rotation, component nodes can be added to the body's [IVModelSpace] or
## [IVRotatingSpace]. The former tilts and rotates with the body (for its model
## and possibly rings) and the later with its orbit (for Lagrange points).[br][br]
## 
## Node name is always the data table row name: PLANET_EARTH, MOON_EUROPA,
## SPACECRAFT_ISS, etc.[br][br]
##
## This node adds its own [IVModelSpace] (which instantiates a model) if needed.
## If this body has table value `lazy_model == true`, it won't add the model
## space until/unless the camera visits this body or a closely associated
## lazy body. See [IVLazyManager].[br][br]
##
## Some bodies (particularly moons and spacecrafts) have table value
## `can_sleep == true`. These bodies' process state is on only when the camera
## is in the same planet system. See [IVSleepManager].[br][br]
##
## Many body-associated "graphic" nodes are added by [IVBodyFinisher],
## including rings, lights and HUD elements. (IVBody isn't aware of these
## nodes.)[br][br]
##
## See also IVSmallBodiesGroup for handling 1000s or 100000s of orbiting bodies
## without individual instantiation (e.g., asteroids).[br][br]
##
## TODO: (Ongoing) Make this node more 'drag-and_drop'.[br][br]
##
## TODO: Barycenters! They orbit and are orbited. These will make Pluto system
## (especially) more accurate.[br][br]
##
## TODO: Implement network sync! This will mainly involve synching IVOrbit
## anytime it changes in a 'non-schedualed' way (e.g., impulse from a rocket
## engine).

signal huds_visibility_changed(is_visible: bool)

enum BodyFlags {
	
	BODYFLAGS_BARYCENTER = 1, # not implemented yet
	BODYFLAGS_STAR = 1 << 1,
	BODYFLAGS_PLANET = 1 << 2, # includes dwarf planet
	BODYFLAGS_TRUE_PLANET = 1 << 3,
	BODYFLAGS_DWARF_PLANET = 1 << 4,
	BODYFLAGS_MOON = 1 << 5,
	BODYFLAGS_ASTEROID = 1 << 6,
	BODYFLAGS_COMET = 1 << 7,
	BODYFLAGS_SPACECRAFT = 1 << 8,
	
	BODYFLAGS_PLANETARY_MASS_OBJECT = 1 << 9,
	BODYFLAGS_SHOW_IN_NAVIGATION_PANEL = 1 << 10,
	
	BODYFLAGS_CAN_SLEEP = 1 << 11,
	BODYFLAGS_TOP = 1 << 12, # non-orbiting stars; is in IVBody.top_bodies
	BODYFLAGS_PROXY_STAR_SYSTEM = 1 << 13, # top star or barycenter of system
	BODYFLAGS_PRIMARY_STAR = 1 << 14,
	BODYFLAGS_STAR_ORBITING = 1 << 15,
	BODYFLAGS_TIDALLY_LOCKED = 1 << 16,
	BODYFLAGS_AXIS_LOCKED = 1 << 17,
	BODYFLAGS_TUMBLES_CHAOTICALLY = 1 << 18, # e.g., Hyperion (mechanic not implemented yet)
	BODYFLAGS_NAVIGATOR_MOON = 1 << 19, # IVSelectionManager uses for cycling
	BODYFLAGS_PLANETARY_MASS_MOON = 1 << 20,
	BODYFLAGS_NON_PLANETARY_MASS_MOON = 1 << 21,
	
	BODYFLAGS_DISPLAY_M_RADIUS = 1 << 22,
	BODYFLAGS_ATMOSPHERE = 1 << 23,
	BODYFLAGS_GAS_GIANT = 1 << 24,
	BODYFLAGS_NO_ORBIT = 1 << 25, # Hill Sphere is smaller than body radius (e.g., ISS)
	BODYFLAGS_NO_STABLE_ORBIT = 1 << 26, # Hill Sphere is smaller than body radius x 3
	BODYFLAGS_USE_CARDINAL_DIRECTIONS = 1 << 27,
	BODYFLAGS_USE_PITCH_YAW = 1 << 28,
	
	BODYFLAGS_EXISTS = 1 << 29, # always set by IVTableBodyBuilder
	BODYFLAGS_DISABLE_MODEL_SPACE = 1 << 30,
	
#   I, Voyager reserved to 1 << 45.
#	Higher bits safe for projects.
#	Max bit shift is 1 << 63.
}

const math := preload("uid://csb570a3u1x1k")

const IDENTITY_BASIS := Basis.IDENTITY
const ECLIPTIC_Z := IDENTITY_BASIS.z

const MIN_SYSTEM_M_RADIUS_MULTIPLIER := 15.0

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL # free & rebuild on load
const PERSIST_PROPERTIES: Array[StringName] = [
	&"name",
	&"flags",
	&"m_radius",
	&"rotation_period",
	&"right_ascension",
	&"declination",
	&"characteristics",
	&"components",
	&"orbit",
	&"rotating_space",
]

# class settings
static var max_hud_dist_orbit_radius_multiplier := 100.0
static var min_hud_dist_radius_multiplier := 500.0
static var min_hud_dist_star_multiplier := 20.0 # combines w/ above

# persisted
var flags := 0 # see IVBody.BodyFlags
var m_radius := 0.0 # required; optional e_radius & p_radius in characteristics
var rotation_period := 0.0 # possibly derived (if tidally locked)
var right_ascension := 0.0 # possibly derived (if axis locked)
var declination := 0.0 # possibly derived (if axis locked)
var characteristics: Dictionary[StringName, Variant] = {} # non-object values
var components: Dictionary[StringName, Object] = {} # objects (persisted only)
var orbit: IVOrbit
var rotating_space: IVRotatingSpace # rotates & translates for L-points (lazy init)

# read-only calculated spatials; change by setting right_ascension, declination, etc.
var rotation_vector := ECLIPTIC_Z # synonymous with 'north'
var rotation_rate := 0.0
var rotation_at_epoch := 0.0
var basis_at_epoch := IDENTITY_BASIS

# read-only!
var star: IVBody # above
var star_orbiter: IVBody # this body or star orbiter above or null
var satellites: Array[IVBody] = [] # IVBody children add/remove themselves
var model_space: IVModelSpace # has model axial tilt and rotation (not scale)
var huds_visible := false # too far / too close toggle
var model_visible := false
var texture_2d: Texture2D
var texture_slice_2d: Texture2D # GUI navigator graphic for sun only
var model_reference_basis := IDENTITY_BASIS
var max_model_dist := 0.0
var min_hud_dist: float
var lazy_uninited := false
var sleep := false
var shader_sun_index := -1

## Contains all IVBody instances currently in the tree.
static var bodies: Dictionary[StringName, IVBody] = {}
## Contains IVBody instances that are at the top of an IVBody tree. In normal
## usage this will be stars.
static var top_bodies: Array[IVBody] = []
static var sun_global_positions: Array[Vector3] = [Vector3(), Vector3(), Vector3()]


# localized
@onready var _times: Array[float] = IVGlobal.times
@onready var _ecliptic_rotation: Basis = IVCoreSettings.ecliptic_rotation
@onready var _world_controller: IVWorldController = IVGlobal.program[&"WorldController"]



func _enter_tree() -> void:
	_set_resources()
	_set_relative_bodies()
	if characteristics.get(&"lazy_model") and IVGlobal.program[&"LazyManager"]:
		lazy_uninited = true
	else:
		_add_model_space()
	if orbit:
		orbit.reset_elements_and_interval_update()
		orbit.changed.connect(_on_orbit_changed)
	shader_sun_index = characteristics.get(&"shader_sun_index", -1)
	assert(shader_sun_index >= -1 and shader_sun_index <= 2)
	hide()


func _ready() -> void:
	const BODYFLAGS_TOP := BodyFlags.BODYFLAGS_TOP
	process_mode = PROCESS_MODE_ALWAYS # time will stop, but allow pointy finger on mouseover
	IVGlobal.system_tree_built_or_loaded.connect(_on_system_tree_built_or_loaded, CONNECT_ONE_SHOT)
	IVGlobal.about_to_free_procedural_nodes.connect(_prepare_to_free, CONNECT_ONE_SHOT)
	IVGlobal.setting_changed.connect(_settings_listener)
	var timekeeper: IVTimekeeper = IVGlobal.program[&"Timekeeper"]
	timekeeper.time_altered.connect(_on_time_altered)
	assert(!bodies.has(name))
	bodies[name] = self
	if flags & BODYFLAGS_TOP:
		top_bodies.append(self)
	recalculate_spatials()
	_set_min_hud_dist()
	#_finish_tree_add.call_deferred()


func _exit_tree() -> void:
	const BODYFLAGS_TOP := BodyFlags.BODYFLAGS_TOP
	bodies.erase(name)
	if flags & BODYFLAGS_TOP:
		top_bodies.erase(self)
	_clear_relative_bodies()


func _on_system_tree_built_or_loaded(is_new_game: bool) -> void:
	if !is_new_game:
		return
	if !characteristics.get(&"system_radius"):
		var system_radius := m_radius * MIN_SYSTEM_M_RADIUS_MULTIPLIER
		for satellite in satellites:
			var a: float = satellite.get_orbit_semi_major_axis()
			if system_radius < a:
				system_radius = a
		characteristics[&"system_radius"] = system_radius
	# non-table flags
	var hill_sphere := get_hill_sphere()
	if hill_sphere < m_radius:
		flags |= BodyFlags.BODYFLAGS_NO_ORBIT
	if hill_sphere / 3.0 < m_radius:
		flags |= BodyFlags.BODYFLAGS_NO_STABLE_ORBIT


func _prepare_to_free() -> void:
	satellites.clear()


func _process(_delta: float) -> void:
	# _process() is disabled while in sleep mode (sleep == true). When in sleep
	# mode, API assumes that any properties updated here are stale and must be
	# calculated in-function.
	
	var camera_dist := _world_controller.process_world_target(self, m_radius)
	
	# update translation and reference frame 'spaces'
	if orbit:
		position = orbit.get_position()
		if rotating_space:
			var orbit_dist := position.length()
			var x_axis := -position / orbit_dist
			var z_axis := orbit.get_normal()
			var y_axis := z_axis.cross(x_axis)
			rotating_space.basis = Basis(x_axis, y_axis, z_axis)
			rotating_space.position.x = orbit_dist - rotating_space.characteristic_length
	
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


func get_float_precision(path: String) -> int:
	# Available only if IVCoreSettings.enable_precisions == true. Gets the
	# precision (significant digits) of a real value as it was entered in the
	# table *.tsv file. Used by Planetarium.
	if !characteristics.has(&"real_precisions"):
		return -1
	var real_precisions: Dictionary = characteristics[&"real_precisions"]
	return real_precisions.get(path, -1)


func get_characteristic(characteristic_name: StringName) -> Variant:
	match characteristic_name:
		&"m_radius":
			return m_radius
		&"rotation_period":
			return rotation_period
		&"right_ascension":
			return right_ascension
		&"declination":
			return declination
	return characteristics.get(characteristic_name)


func set_characteristic(characteristic_name: StringName, value: Variant,
		supress_recalculation := false) -> void:
	# Set supress_recalculation == true only if you are doing many changes and
	# will call recalculate_spatials() manually.
	match characteristic_name:
		&"m_radius":
			m_radius = value
			return
		&"rotation_period":
			var float_value: float = value
			set_rotation_period(float_value, supress_recalculation)
			return
		&"right_ascension":
			var float_value: float = value
			set_right_ascension(float_value, supress_recalculation)
			return
		&"declination":
			var float_value: float = value
			set_declination(float_value, supress_recalculation)
			return
	characteristics[characteristic_name] = value


func get_mean_radius() -> float:
	return m_radius


func set_mean_radius(value: float) -> void:
	m_radius = value


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


func get_mass() -> float:
	return characteristics.get(&"mass", 0.0)


func set_mass(value: float) -> void:
	characteristics[&"mass"] = value


func get_standard_gravitational_parameter() -> float:
	return characteristics.get(&"GM", 0.0)


func set_standard_gravitational_parameter(value: float) -> void:
	characteristics[&"GM"] = value


func get_system_radius() -> float:
	# From data table or set to outermost satellite semi-major axis.
	return characteristics.get(&"system_radius", 0.0)


func set_system_radius(value: float) -> void:
	characteristics[&"system_radius"] = value


func get_perspective_radius() -> float:
	# For camera perspective distancing. Same as m_radius unless something
	# different is needed.
	var perspective_radius: float = characteristics.get(&"perspective_radius", 0.0)
	if perspective_radius:
		return perspective_radius
	return m_radius


func set_perspective_radius(value: float) -> void:
	assert(value > 0.0)
	if value != get_perspective_radius():
		characteristics[&"perspective_radius"] = value


func get_equatorial_radius() -> float:
	var e_radius: float = characteristics.get(&"e_radius", 0.0)
	if e_radius:
		return e_radius
	return m_radius


func set_equatorial_radius(value: float) -> void:
	# Will also modify p_radius so that:
	# m_radius = (p_radius + 2.0 * e_radius) / 3.0.
	if value != get_equatorial_radius():
		characteristics[&"e_radius"] = value
		characteristics[&"p_radius"] = 3.0 * m_radius - 2.0 * value


func get_polar_radius() -> float:
	var p_radius: float = characteristics.get(&"p_radius", 0.0)
	if p_radius:
		return p_radius
	return m_radius


func set_polar_radius(value: float) -> void:
	# Will also modify e_radius so that:
	# m_radius = (p_radius + 2.0 * e_radius) / 3.0.
	if value != get_polar_radius():
		characteristics[&"p_radius"] = value
		characteristics[&"e_radius"] = (3.0 * m_radius - value) / 2.0


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
	var ground_basis := get_ground_basis(time)
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


func is_orbit_retrograde(time := NAN) -> bool:
	if !orbit:
		return false
	return orbit.is_retrograde(time)


func get_orbit_semi_major_axis(time := NAN) -> float:
	if !orbit:
		return 0.0
	return orbit.get_semimajor_axis(time)


func get_orbit_normal(time := NAN, flip_retrograde := false) -> Vector3:
	if !orbit:
		return ECLIPTIC_Z
	return orbit.get_normal(time, flip_retrograde)


func get_orbit_inclination_to_equator(time := NAN) -> float:
	const BODYFLAGS_TOP := BodyFlags.BODYFLAGS_TOP
	if !orbit or flags & BODYFLAGS_TOP:
		return NAN
	var orbit_normal := orbit.get_normal(time)
	var parent: IVBody = get_parent_node_3d()
	var positive_pole: Vector3 = parent.get_positive_pole(time)
	return orbit_normal.angle_to(positive_pole)


func is_rotation_retrograde() -> bool:
	return rotation_rate < 0.0


func get_axial_tilt_to_orbit(time := NAN) -> float:
	if !orbit:
		return NAN
	var positive_pole := get_positive_pole(time)
	var orbit_normal := orbit.get_normal(time)
	return positive_pole.angle_to(orbit_normal)


func get_axial_tilt_to_ecliptic(time := NAN) -> float:
	var positive_pole := get_positive_pole(time)
	return positive_pole.angle_to(ECLIPTIC_Z)


func get_ground_basis(time := NAN) -> Basis:
	# Returns a rotating basis referenced to ground (i.e, the Body model).
	if model_space and is_nan(time):
		return model_space.transform.basis
	else:
		if is_nan(time):
			time = _times[0]
		var rotation_angle := wrapf(time * rotation_rate, 0.0, TAU)
		return basis_at_epoch.rotated(rotation_vector, rotation_angle)


func get_orbit_basis(time := NAN) -> Basis:
	# Returns a rotating basis with Body parent in the -x direction.
	if rotating_space and is_nan(time):
		return rotating_space.transform.basis
	if !orbit:
		return IDENTITY_BASIS
	var x_axis := -orbit.get_position(time).normalized()
	var z_axis := orbit.get_normal(time, true)
	var y_axis := z_axis.cross(x_axis)
	return Basis(x_axis, y_axis, z_axis)


func get_hill_sphere(eccentricity := 0.0) -> float:
	# returns INF if this is a top body in simulation
	# see: https://en.wikipedia.org/wiki/Hill_sphere
	const BODYFLAGS_TOP := BodyFlags.BODYFLAGS_TOP
	if flags & BODYFLAGS_TOP:
		return INF
	var a := get_orbit_semi_major_axis()
	var mass := get_mass()
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


func set_orbit(orbit_: IVOrbit) -> void:
	assert(orbit_)
	orbit = orbit_
	if !is_inside_tree():
		return # do below on _enter_tree()
	orbit_.reset_elements_and_interval_update()
	orbit_.changed.connect(_on_orbit_changed)


func lazy_init() -> void:
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


func get_lagrange_point_local_space(lp_integer: int) -> Vector3:
	# Returns Vector3.ZERO if we don't have parameters to calculate.
	assert(lp_integer >=1 and lp_integer <= 5)
	if !rotating_space:
		_add_rotating_space()
		if !rotating_space:
			return Vector3.ZERO
	return rotating_space.get_lagrange_point_local_space(lp_integer)


func get_lagrange_point_global_space(lp_integer: int) -> Vector3:
	# Returns Vector3.ZERO if we don't have parameters to calculate.
	assert(lp_integer >=1 and lp_integer <= 5)
	if !rotating_space:
		_add_rotating_space()
		if !rotating_space:
			return Vector3.ZERO
	return rotating_space.get_lagrange_point_global_space(lp_integer)


func get_lagrange_point_node3d(lp_integer: int) -> IVLagrangePoint:
	# Returns null if we don't have parameters to calculate.
	assert(lp_integer >=1 and lp_integer <= 5)
	if !rotating_space:
		_add_rotating_space()
		if !rotating_space:
			return null
	return rotating_space.get_lagrange_point_node3d(lp_integer)


func get_fragment_data(_fragment_type: int) -> Array:
	# Only FRAGMENT_BODY_ORBIT at this time.
	return [get_instance_id()]


func get_fragment_text(_data: Array) -> String:
	# Only FRAGMENT_BODY_ORBIT at this time.
	return tr(name) + " (" + tr("LABEL_ORBIT").to_lower() + ")"


func recalculate_spatials() -> void:
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
	const BODYFLAGS_TOP := BodyFlags.BODYFLAGS_TOP
	const BODYFLAGS_STAR := BodyFlags.BODYFLAGS_STAR
	const BODYFLAGS_TRUE_PLANET := BodyFlags.BODYFLAGS_TRUE_PLANET
	const BODYFLAGS_TIDALLY_LOCKED := BodyFlags.BODYFLAGS_TIDALLY_LOCKED
	const BODYFLAGS_AXIS_LOCKED := BodyFlags.BODYFLAGS_AXIS_LOCKED
	const BODYFLAGS_TUMBLES_CHAOTICALLY := BodyFlags.BODYFLAGS_TUMBLES_CHAOTICALLY
	
	# rotation_rate
	var new_rotation_rate: float
	if flags & BODYFLAGS_TIDALLY_LOCKED:
		new_rotation_rate = orbit.get_mean_motion()
		rotation_period = TAU / new_rotation_rate
	else:
		new_rotation_rate = TAU / rotation_period
	# rotation_vector
	var new_rotation_vector: Vector3
	if flags & BODYFLAGS_AXIS_LOCKED:
		new_rotation_vector = orbit.get_normal()
		var ra_dec := math.get_spherical2(new_rotation_vector)
		right_ascension = ra_dec[0]
		declination = ra_dec[1]
	elif flags & BODYFLAGS_TUMBLES_CHAOTICALLY:
		# TODO: something sensible for Hyperion
		new_rotation_vector = _ecliptic_rotation * math.convert_spherical2(0.0, 0.0)
	else:
		new_rotation_vector = _ecliptic_rotation * math.convert_spherical2(
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
	if (flags & BODYFLAGS_TOP or flags & BODYFLAGS_STAR or flags & BODYFLAGS_TRUE_PLANET
			or parent.flags & BODYFLAGS_TRUE_PLANET):
		if ECLIPTIC_Z.dot(new_rotation_vector) < 0.0:
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

	var basis_ := math.rotate_basis_z(Basis(), rotation_vector)
	basis_at_epoch = basis_.rotated(rotation_vector, rotation_at_epoch)


# *****************************************************************************
# private


func _set_resources() -> void:
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	texture_2d = asset_preloader.get_body_texture_2d(name)
	texture_slice_2d = asset_preloader.get_body_texture_slice_2d(name) # usually null


func _add_model_space() -> void:
	const BODYFLAGS_DISABLE_MODEL_SPACE := BodyFlags.BODYFLAGS_DISABLE_MODEL_SPACE
	assert(!model_space)
	lazy_uninited = false
	if flags & BODYFLAGS_DISABLE_MODEL_SPACE:
		return
	var model_space_script: Script = IVGlobal.procedural_classes[&"ModelSpace"]
	@warning_ignore("unsafe_method_access")
	model_space = model_space_script.new(name, m_radius, get_equatorial_radius())
	model_reference_basis = model_space.reference_basis
	max_model_dist = model_space.max_distance
	add_child(model_space)


func _set_relative_bodies() -> void:
	# For multi-star system, star_orbiter and star could be the same body.
	const BODYFLAGS_STAR := BodyFlags.BODYFLAGS_STAR
	star = null
	star_orbiter = null
	var up_tree := self
	while up_tree:
		if !star_orbiter and up_tree.flags & BodyFlags.BODYFLAGS_STAR_ORBITING:
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


func _add_rotating_space() -> void:
	# bail out if we don't have requried parameters
	if !orbit:
		return
	var m2 := get_mass()
	if !m2:
		return
	var parent := get_parent_node_3d() as IVBody
	var m1 := parent.get_mass()
	if !m1:
		return
	var mass_ratio := m1 / m2
	var characteristic_length := orbit.get_semimajor_axis()
	var characteristic_time := orbit.get_orbit_period()
	var RotatingSpaceScript: Script = IVGlobal.procedural_classes[&"RotatingSpace"]
	@warning_ignore("unsafe_method_access")
	rotating_space = RotatingSpaceScript.new()
	rotating_space.init(mass_ratio, characteristic_length, characteristic_time)
	var translation_ := orbit.get_position()
	var orbit_dist := translation_.length()
	var x_axis := -translation_ / orbit_dist
	var z_axis := orbit.get_normal()
	var y_axis := z_axis.cross(x_axis)
	rotating_space.transform.basis = Basis(x_axis, y_axis, z_axis)
	rotating_space.position.x = orbit_dist - rotating_space.characteristic_length


func _on_orbit_changed(_is_scheduled: bool) -> void:
	const BODYFLAGS_TIDALLY_LOCKED := BodyFlags.BODYFLAGS_TIDALLY_LOCKED
	const BODYFLAGS_AXIS_LOCKED := BodyFlags.BODYFLAGS_AXIS_LOCKED
	#const IS_SERVER = IVGlobal.NetworkState.IS_SERVER
	
	if flags & BODYFLAGS_TIDALLY_LOCKED or flags & BODYFLAGS_AXIS_LOCKED:
		recalculate_spatials()
#	if !is_scheduled and _state.network_state == IS_SERVER: # sync clients
#		# scheduled changes happen on client so don't need sync
#		rpc("_orbit_sync", orbit.reference_normal, orbit.elements_at_epoch, orbit.element_rates,
#				orbit.m_modifiers)


#@rpc("any_peer") func _orbit_sync(reference_normal: Vector3, elements_at_epoch: Array,
#		element_rates: Array, m_modifiers: Array) -> void: # client-side network game only
#	# FIXME34: All rpc
#	if _tree.get_remote_sender_id() != 1:
#		return # from server only
#	orbit.orbit_sync(reference_normal, elements_at_epoch, element_rates, m_modifiers)


func _on_time_altered(_previous_time: float) -> void:
	if orbit:
		orbit.reset_elements_and_interval_update()
	recalculate_spatials()


func _set_min_hud_dist() -> void:
	const BODYFLAGS_STAR := BodyFlags.BODYFLAGS_STAR
	if IVGlobal.settings.get(&"hide_hud_when_close", false):
		min_hud_dist = m_radius * min_hud_dist_radius_multiplier
		if flags & BODYFLAGS_STAR:
			min_hud_dist *= min_hud_dist_star_multiplier # just the label
	else:
		min_hud_dist = 0.0


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"hide_hud_when_close":
		_set_min_hud_dist()
