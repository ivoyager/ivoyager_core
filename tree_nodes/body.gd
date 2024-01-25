# body.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charles Whitfield
# I, Voyager is a registered trademark of Charles Whitfield in the US
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

## Base class for objects that orbit or are orbited, including stars, planets,
## moons, visited asteroids, and spacecrafts.
##
## IVBody nodes are NEVER scaled or rotated. Hence, local and global distances
## and directions are always consistent at any level of the solar system tree.
## For rotation, component nodes can be added to the body's [IVModelSpace] or
## [IVRotatingSpace]. The former rotates with the body (for its model and rings)
## and the later with its orbit (for Lagrange points).[br][br]
## 
## Node name is always the data table row name: 'PLANET_EARTH', 'MOON_EUROPA',
## etc.[br][br]
##
## See also IVSmallBodiesGroup for handling 1000s or 10000s of orbiting bodies
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
signal model_visibility_changed(is_visible: bool)


const math := preload("res://addons/ivoyager_core/static/math.gd") # =IVMath when issue #37529 fixed

const IDENTITY_BASIS := Basis.IDENTITY
const ECLIPTIC_Z := IDENTITY_BASIS.z
const VECTOR2_ZERO := Vector2.ZERO
const VECTOR2_NULL := Vector2(-INF, -INF)
const BodyFlags := IVEnums.BodyFlags
const IS_TOP := BodyFlags.IS_TOP
const IS_STAR := BodyFlags.IS_STAR
const IS_TRUE_PLANET := BodyFlags.IS_TRUE_PLANET
const IS_DWARF_PLANET := BodyFlags.IS_DWARF_PLANET
const IS_MOON := BodyFlags.IS_MOON
const IS_TIDALLY_LOCKED := BodyFlags.IS_TIDALLY_LOCKED
const IS_AXIS_LOCKED := BodyFlags.IS_AXIS_LOCKED
const TUMBLES_CHAOTICALLY := BodyFlags.TUMBLES_CHAOTICALLY
const NEVER_SLEEP := BodyFlags.NEVER_SLEEP
const IS_SERVER = IVEnums.NetworkState.IS_SERVER
const MIN_SYSTEM_M_RADIUS_MULTIPLIER := 15.0

const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL # free & rebuild on load
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
	&"satellites",
]

# class settings
static var min_click_radius := 20.0
static var max_hud_dist_orbit_radius_multiplier := 100.0
static var min_hud_dist_radius_multiplier := 500.0
static var min_hud_dist_star_multiplier := 20.0 # combines w/ above

# persisted
var flags := 0 # see IVEnums.BodyFlags
var m_radius := 0.0 # required; optional e_radius & p_radius in characteristics
var rotation_period := 0.0 # possibly derived (if tidally locked)
var right_ascension := 0.0 # possibly derived (if axis locked)
var declination := 0.0 # possibly derived (if axis locked)
var characteristics := {} # non-object values
var components := {} # objects (persisted only)
var orbit: IVOrbit
var satellites: Array[IVBody] = []

# read-only calculated spatials; change by setting right_ascension, declination, etc.
var rotation_vector := ECLIPTIC_Z # synonymous with 'north'
var rotation_rate := 0.0
var rotation_at_epoch := 0.0
var basis_at_epoch := IDENTITY_BASIS

# read-only!
var huds_visible := false # too far / too close toggle
var model_visible := false
var model_space: Node3D # rotation only, not scaled (lazy init)
var rotating_space: IVRotatingSpace # rotates & translates for L-points (lazy init)
var texture_2d: Texture2D
var texture_slice_2d: Texture2D # GUI navigator graphic for sun only
var model_reference_basis := IDENTITY_BASIS
var max_model_dist := 0.0
var min_hud_dist: float
var sleep := false

# private
static var _is_class_instanced := false
static var _times: Array[float] = IVGlobal.times
static var _world_targeting: Array = IVGlobal.world_targeting
static var _ecliptic_rotation: Basis



func _init() -> void:
	if !_is_class_instanced:
		_is_class_instanced = true
		_ecliptic_rotation = IVCoreSettings.ecliptic_rotation
	hide()


func _enter_tree() -> void:
	if orbit:
		orbit.reset_elements_and_interval_update()
		orbit.changed.connect(_on_orbit_changed)


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS # time will stop, but allow pointy finger on mouseover
	IVGlobal.system_tree_built_or_loaded.connect(_on_system_tree_built_or_loaded, CONNECT_ONE_SHOT)
	IVGlobal.about_to_free_procedural_nodes.connect(_prepare_to_free, CONNECT_ONE_SHOT)
	IVGlobal.setting_changed.connect(_settings_listener)
	var timekeeper: IVTimekeeper = IVGlobal.program.Timekeeper
	timekeeper.time_altered.connect(_on_time_altered)
	assert(!IVGlobal.bodies.has(name))
	IVGlobal.bodies[name] = self
	if flags & BodyFlags.IS_TOP:
		IVGlobal.top_bodies.append(self)
	_set_min_hud_dist()


func _exit_tree() -> void:
	IVGlobal.bodies.erase(name)
	if flags & BodyFlags.IS_TOP:
		IVGlobal.top_bodies.erase(self)


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
		flags |= BodyFlags.NO_ORBIT
	if hill_sphere / 3.0 < m_radius:
		flags |= BodyFlags.NO_STABLE_ORBIT


func _prepare_to_free() -> void:
	satellites.clear()


func _process(_delta: float) -> void:
	# _process() is disabled while in sleep mode (sleep == true). When in sleep
	# mode, API assumes that any properties updated here are stale and must be
	# calculated in-function.
	
	# get camera distance and check mouse proximity
	var camera: Camera3D = _world_targeting[2]
	if !camera:
		return
	var camera_dist := global_position.distance_to(camera.global_position)
	var is_in_mouse_click_radius := false
	if !camera.is_position_behind(global_position):
		var pos2d := camera.unproject_position(global_position)
		var mouse_position: Vector2 = _world_targeting[0]
		var mouse_dist := pos2d.distance_to(mouse_position)
		var click_radius := min_click_radius
		var divisor: float = _world_targeting[3] * camera_dist # fov * dist
		if divisor > 0.0:
			var screen_radius: float = 55.0 * m_radius * _world_targeting[1] / divisor
			if click_radius < screen_radius:
				click_radius = screen_radius
		if mouse_dist < click_radius:
			is_in_mouse_click_radius = true
	
	# set/unset this body as mouse target
	if is_in_mouse_click_radius:
		if camera_dist < _world_targeting[5]: # make self the mouse target
			_world_targeting[4] = self
			_world_targeting[5] = camera_dist
	elif _world_targeting[4] == self: # remove self as mouse target
		_world_targeting[4] = null
		_world_targeting[5] = INF

	# update translation and reference frame 'spaces'
	if orbit:
		position = orbit.get_position()
		if rotating_space:
			var orbit_dist := position.length()
			var x_axis := -position / orbit_dist
			var z_axis := orbit.get_normal()
			var y_axis := z_axis.cross(x_axis)
			rotating_space.transform.basis = Basis(x_axis, y_axis, z_axis)
			rotating_space.position.x = orbit_dist - rotating_space.characteristic_length
	if model_space:
		var rotation_angle := wrapf(_times[0] * rotation_rate, 0.0, TAU)
		model_space.transform.basis = basis_at_epoch.rotated(rotation_vector, rotation_angle)
	
	# check HUD and model visibility
	var hud_dist_ok := min_hud_dist < camera_dist # not too close to camera
	if hud_dist_ok and orbit:
		var orbit_radius := position.length()
		# is body too close to its parent for camera distance?
		hud_dist_ok = orbit_radius * max_hud_dist_orbit_radius_multiplier > camera_dist
	if huds_visible != hud_dist_ok:
		huds_visible = hud_dist_ok
		huds_visibility_changed.emit(huds_visible)
		
	if model_visible != (camera_dist < max_model_dist):
		model_visible = !model_visible
		model_visibility_changed.emit(model_visible)
	
	show()



# public API

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


func has_omni_light() -> bool:
	return characteristics.get(&"omni_light_type", -1) != -1


func get_omni_light_type() -> int:
	return characteristics.get(&"omni_light_type", -1)


func get_file_prefix() -> String:
	return characteristics.get(&"file_prefix", "")


func has_rings() -> bool:
	return characteristics.has(&"rings_radius")


func get_rings_file_prefix() -> String:
	return characteristics.get(&"rings_file_prefix", "")


func get_rings_inner_radius() -> float:
	return characteristics.get(&"rings_inner_radius", 0.0)


func get_rings_outer_radius() -> float:
	return characteristics.get(&"rings_outer_radius", 0.0)


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
	if !orbit or flags & IS_TOP:
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
	if flags & BodyFlags.IS_TOP:
		return INF
	var a := get_orbit_semi_major_axis()
	var mass := get_mass()
	var parent: IVBody = get_parent_node_3d()
	var parent_mass: float = parent.get_mass()
	if !a or !mass or !parent_mass:
		return 0.0
	return a * (1.0 - eccentricity) * pow(mass / (3.0 * parent_mass), 0.33333333)


# ivoyager mechanics below

func set_model_parameters(reference_basis: Basis, max_dist: float) -> void:
	model_reference_basis = reference_basis
	max_model_dist = max_dist


func add_child_to_model_space(spatial: Node3D) -> void:
	if !model_space:
		var ModelSpaceScript: Script = IVGlobal.procedural_classes[&"ModelSpace"]
		@warning_ignore("unsafe_method_access")
		model_space = ModelSpaceScript.new()
		add_child(model_space)
	model_space.add_child(spatial)


func remove_child_from_model_space(spatial: Node3D) -> void:
	model_space.remove_child(spatial)
	if model_space.get_child_count() == 0:
		model_space.queue_free()
		model_space = null


func set_orbit(orbit_: IVOrbit) -> void:
	assert(orbit_)
	orbit = orbit_
	if !is_inside_tree():
		return # do below on _enter_tree()
	orbit_.reset_elements_and_interval_update()
	orbit_.changed.connect(_on_orbit_changed)


func set_sleep(sleep_: bool) -> void: # called by IVSleepManager
	if flags & NEVER_SLEEP or sleep_ == sleep:
		return
	if sleep_:
		sleep = true
		hide()
		set_process(false)
		if _world_targeting[4] == self: # remove self as mouse target
			_world_targeting[4] = null
			_world_targeting[5] = INF
	else:
		sleep = false
		_process(0.0) # update position, etc., now; will show()
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

	# rotation_rate
	var new_rotation_rate: float
	if flags & IS_TIDALLY_LOCKED:
		new_rotation_rate = orbit.get_mean_motion()
		rotation_period = TAU / new_rotation_rate
	else:
		new_rotation_rate = TAU / rotation_period
	# rotation_vector
	var new_rotation_vector: Vector3
	if flags & IS_AXIS_LOCKED:
		new_rotation_vector = orbit.get_normal()
		var ra_dec := math.get_spherical2(new_rotation_vector)
		right_ascension = ra_dec[0]
		declination = ra_dec[1]
	elif flags & TUMBLES_CHAOTICALLY:
		# TODO: something sensible for Hyperion
		new_rotation_vector = _ecliptic_rotation * math.convert_spherical2(0.0, 0.0)
	else:
		new_rotation_vector = _ecliptic_rotation * math.convert_spherical2(
				right_ascension, declination)
	var new_rotation_at_epoch: float = characteristics.get(&"longitude_at_epoch", 0.0)
	
	if orbit:
		if flags & IS_TIDALLY_LOCKED:
			new_rotation_at_epoch += orbit.get_mean_longitude(0.0) - PI
		else:
			new_rotation_at_epoch += orbit.get_true_longitude(0.0) - PI
	
	# possible polarity reversal; see comments under get_north_pole()
	var reverse_polarity := false
	var parent := get_parent_node_3d() as IVBody
	if (flags & IS_TOP or flags & IS_STAR or flags & IS_TRUE_PLANET
			or parent.flags & IS_TRUE_PLANET):
		if ECLIPTIC_Z.dot(new_rotation_vector) < 0.0:
			reverse_polarity = true
	elif parent.flags & IS_STAR: # any other star-orbiter (dwarf planets, asteroids, etc.)
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


# private functions

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
	if flags & IS_TIDALLY_LOCKED or flags & IS_AXIS_LOCKED:
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
	if IVGlobal.settings.get(&"hide_hud_when_close", false):
		min_hud_dist = m_radius * min_hud_dist_radius_multiplier
		if flags & IS_STAR:
			min_hud_dist *= min_hud_dist_star_multiplier # just the label
	else:
		min_hud_dist = 0.0


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"hide_hud_when_close":
		_set_min_hud_dist()

