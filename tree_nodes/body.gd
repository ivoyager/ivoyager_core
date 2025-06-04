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
## Using our Solar System as example, the structure of the scene tree is:
## [codeblock]
## IVUniverse
##    |- IVBody (Sun)
##        |- IVBody (Earth)
##            |- IVBody (ISS)
##            |- IVBody (Moon)
##                |- IVBody (a spacecraft orbiting the Moon)
## [/codeblock]
##
## Note that current core mechanics [i]should[/i] handle a multi-star system,
## but this has not been tested yet. (Also, there is no GUI widget to display
## such a system in a Navigation Panel.)[br][br]
##
## IVBody nodes are NEVER scaled or rotated. Hence, local distances and
## directions are always in the ecliptic basis at any level of the "body tree".[br][br]
##
## This node adds its own [IVModelSpace] if needed.
## IVBody maintains orientation and rotation of IVModelSpace. IVModelSpace
## instantiates and scales a model (visual representation) for this body.
## If this body has table value [param lazy_model] = TRUE, then IVModelSpace
## won't be added until the camera visits this body or a closely associated
## lazy body. This is generally set for spacecrafts (with large models) and for
## the 100s of small outer moons of the gas giants (but not inner moons, as
## these might be visible from nearby). See [IVLazyModelInitializer].[br][br]
##
## Some bodies (particularly moons and spacecrafts) have table value
## [param can_sleep] = TRUE. If [IVSleepManager] is present, these bodies will
## only [code]_process()[/code] when the camera is in the same planet system.
## Note that IVBody API methods such as [method get_position_vector] and
## [method get_state_vectors] will provide current values even if the body is
## not currently processing, but [param postion] will not. These methods also
## take an optional [param time] argument to allow projected results.[br][br]
##
## IVBody properties are core information required for all bodies. Specialized
## information is contained in dictionary [member characteristics]. For
## example all bodies have [member mean_radius], but oblate spheroid bodies
## (most planets and stars) also have characteristics keys [param equatorial_radius]
## and [param polar_radius]. API methods provide access to many of these
## characteristics with sensible fallbacks for missing keys.[br][br]
##
## Many body-associated "graphic" nodes are added by [IVBodyFinisher] including
## rings, lights and HUD elements. The IVBody class has no references to these
## nodes.[br][br]
## 
## See also [IVSmallBodiesGroup] for handling 1000s or 100000s of orbiting bodies
## without individual instantiation (e.g., asteroids).[br][br]
##
## [b]Roadmap[/b][br][br]
##
## TODO: Document threadsafety. Gets for properties are threadsafe, but any that
## involve characteristics dictionary are not.[br][br]
##
## TODO: API for spacecraft attitude control.[br][br]
##
## TODO: Mechanics for wobbling & tumbling asteroids and outer moons. There
## are 4 kinds of rotations with increasing implementation difficulty:[br]
## 1. Rotation around 1 axis (this is what we have now).[br]
## 2. Axisymmetric wobbling (easy). I1 == I2 != I3. This may be a reasonable
##    approximation for many elongated asteroids. (It's also applicable for north
##    precession in planets, but the time scale for that is very long.)[br]
## 3. Asymmetric tumbling (quasi-periodic, non-chaotic; hard). I1 != I2 != I3.
##    The math is difficult (need Jacobi elliptic functions) but the rotations
##    are fully deterministic.[br]
## 4. Chaotic tumbling (harder). Above with perturbations. (E.g., Hyperion.)[br]
## (Even #2 would be an asthetic improvement for bodies that are really #4.)[br][br]
## 
## TODO: API for changing orbit context or "identity". E.g., a spacecraft
## becomes BODYFLAGS_STAR_ORBITER, or an asteroid is captured to become a moon.[br][br]
##
## TODO: (Ongoing) Make this node more "drag-and_drop" and editable at editor runtime.[br][br]
##
## TODO: Barycenters! They orbit and are orbited. This will make Pluto system
## (especially) more accurate, and allow things like twin planets.[br][br]
##
## TODO: Implement network sync! This will mainly involve synching IVOrbit
## anytime it changes in an extrinsic way (e.g., impulse from a rocket
## engine). Same for rotations: we only sync when an extrinsic force changes
## the current rotation.[br][br]
##
## TODO: We want to handle local stars out to some range. Each solitary star or
## system primary star will be a "galaxy orbiter" with some (relative) position
## and velocity. (Any larger scope will require procedural system building and
## scene loading -- that is not in CW's plans.)

signal orbit_changed(orbit: IVOrbit, is_intrinsic: bool, precession_only: bool)
signal rotation_chaged(is_intrinsic: bool)
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
	BODYFLAGS_DISABLE_MODEL_SPACE = 1 << 25, ## @deprecate
	BODYFLAGS_EXISTS = 1 << 26, ## @deprecate
	
	# GUI
	BODYFLAGS_SHOW_IN_NAVIGATION_PANEL = 1 << 29, ## Show in GUI "Navigation" panel.
	BODYFLAGS_DISPLAY_EQUATORIAL_POLAR_RADII = 1 << 30, ## Show e, p (instead of m) radii in GUI.
	BODYFLAGS_USE_CARDINAL_DIRECTIONS = 1 << 31, ## Display relative position as N, S, E, W in GUI.
	BODYFLAGS_USE_PITCH_YAW = 1 << 32, ## Display relative position as pitch, yaw in GUI.
	
}

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL # free & rebuild on load
const PERSIST_PROPERTIES: Array[StringName] = [
	&"name",
	&"flags",
	&"mean_radius",
	&"gravitational_parameter",
	&"orientation_at_epoch",
	&"rotation_axis",
	&"rotation_rate",
	&"rotation_at_epoch",
	&"characteristics",
	&"components",
	
	&"_orbit",
	&"_system_radius",
	&"_hill_sphere",
]


# persisted
## See [member BodyFlags].
var flags := 0
## Mean radius. Must be >0.0 for camera and model mechanics.
var mean_radius := 0.0
## Standard gravitaional parameter (GM) is the gravitational constant (G) x mass.
## It's often more precisely known than mass due to G imprecission. A value of
## 0.0 is allowed for unknown (presumably small) or too-small-to-orbit bodies.
var gravitational_parameter := 0.0
## Orientation at epoch if the current rotation is unwound by time * rotation_rate.
var orientation_at_epoch := Basis.IDENTITY
## Rotation axis that always points toward north or "north" equivalant.
var rotation_axis := Vector3(0, 0, 1)
## Rotation rate. If negative, this body has retrograde rotation.
var rotation_rate := 0.0
var rotation_at_epoch := 0.0
var characteristics: Dictionary[StringName, Variant] = {} # non-object values
var components: Dictionary[StringName, RefCounted] = {} # objects (persisted only)

# redirect
## This body's [IVOrbit]; null if galaxy orbiter.
var orbit: IVOrbit: get = get_orbit, set = set_orbit

# read-only!
## Parent IVBody; null if this is the top star in a system. Read-only!
var parent: IVBody
## This body (if star) or star above. Read-only!
var star: IVBody
## This body (if star-orbiter) or star-orbiter above or null (if none). Read-only!
var star_orbiter: IVBody
## Bodies in orbit around (children of) this body. Read-only!
var satellites: Dictionary[StringName, IVBody]
## If present, the Node3D that has this body's visual
## representation (model). If data table value [param lazy_model] == TRUE, then
## this value will be null until needed. Read-only!
var model_space: Node3D
## Current visibility state for associated HUD elements, including IVBodyLabel
## and IVOrbitVisual. Read-only!
var huds_visible := false
## Current visibility state of this body's model. Read-only!
var model_visible := false
## GUI graphic representation of this body. Read-only!
var texture_2d: Texture2D
## GUI graphic representation of this body as a "slice" for a system star. Read-only!
var texture_slice_2d: Texture2D


## Static class setting. Set this script to generate a subclass in place of
## IVBody in all create methods. Assigned Script must be a subclass of IVBody!
static var replacement_subclass: Script
## Static class setting. Set this script to replace the IVModelSpace class.
static var replacement_model_space_class: Script

## Static class setting. Default value is a dashed circle.
static var default_symbol := "\u25CC"
## Static class setting.
static var system_mean_radius_multiplier := 15.0
## Static class setting.
static var max_hud_dist_orbit_radius_multiplier := 100.0
## Static class setting.
static var min_hud_dist_radius_multiplier := 500.0
## Static class setting.
static var min_hud_dist_star_multiplier := 20.0

## A static class dictionary that contains all added IVBody instances.
static var bodies: Dictionary[StringName, IVBody] = {}
## A static class dictionary that contains IVBody instances that are at the top
## of a system (i.e., the primary star for every star system).
static var galaxy_orbiters: Dictionary[StringName, IVBody] = {}


# private persisted
var _orbit: IVOrbit
var _system_radius: float
var _hill_sphere: float

# private non-persisted
var _lazy_model_uninited := false
var _sleeping := false
var _max_model_dist := 0.0
var _min_hud_dist: float
var _times: Array[float] = IVGlobal.times
var _world_controller: IVWorldController = IVGlobal.program[&"WorldController"]


func _enter_tree() -> void:
	# Happens:
	# 1) During system build from data tables.
	# 2) During system build from game save.
	# 3) When a body changes parent, e.g., in a spacecraft trajectory. 
	const LAZY_MODEL := BodyFlags.BODYFLAGS_LAZY_MODEL
	_set_relative_bodies()
	if is_node_ready(): # existing ready body has changed parent
		return
	if _orbit:
		_orbit.changed.connect(_on_orbit_changed)
	if flags & LAZY_MODEL and IVGlobal.program.has(&"LazyModelInitializer"):
		_lazy_model_uninited = true
	else:
		_add_model_space()


func _exit_tree() -> void:
	_clear_relative_bodies()


func _ready() -> void:
	# Happens once only, but could be during or after whole system build.
	const GALAXY_ORBITER := BodyFlags.BODYFLAGS_GALAXY_ORBITER
	process_mode = PROCESS_MODE_ALWAYS # time will stop, but allows mouseover interaction
	IVGlobal.system_tree_built_or_loaded.connect(_on_system_tree_built_or_loaded, CONNECT_ONE_SHOT)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural, CONNECT_ONE_SHOT)
	IVGlobal.setting_changed.connect(_settings_listener)
	assert(!bodies.has(name))
	bodies[name] = self
	if flags & GALAXY_ORBITER:
		galaxy_orbiters[name] = self
	_set_resources()
	_set_min_hud_dist()
	hide()
	
	if !IVGlobal.state[&"is_system_built"]: # currently building from tables or savefile
		return
	
	_set_system_radius()
	_set_hill_sphere()


func _process(_delta: float) -> void:
	# _process() is disabled while in sleep mode (_sleeping == true). When in
	# sleep mode, API assumes that any properties updated here are stale and
	# must be calculated.
	
	var time := _times[0]
	
	if _orbit:
		position = _orbit.update(time)
	
	var camera_dist := _world_controller.update_world_target(self, mean_radius)
	
	# update model space
	if model_space:
		var rotation_angle := wrapf(time * rotation_rate, 0.0, TAU)
		model_space.basis = orientation_at_epoch.rotated(rotation_axis, rotation_angle)
		model_space.visible = camera_dist < _max_model_dist
	
	# set HUDs visibility
	var show_huds := camera_dist > _min_hud_dist # Is camera far enough?
	if show_huds and _orbit:
		# Is body far enough from it parent?
		var orbit_radius := position.length()
		show_huds = orbit_radius * max_hud_dist_orbit_radius_multiplier > camera_dist
	if huds_visible != show_huds:
		huds_visible = show_huds
		huds_visibility_changed.emit(huds_visible)
	
	show()


# *****************************************************************************
# create & remove methods


## Creates new [IVOrbit] instance (or specified [member replacement_subclass])
## from specified parameters. See also [method create_from_astronomy_specs].
@warning_ignore("shadowed_variable", "shadowed_variable_base_class")
static func create(name: StringName, flags: int, mean_radius: float, gravitational_parameter: float,
		orientation_at_epoch: Basis, rotation_axis: Vector3, rotation_at_epoch: float,
		rotation_rate: float, orbit: IVOrbit, characteristics: Dictionary,
		components: Dictionary, exisiting_body: IVBody = null) -> IVBody:
	
	assert(name)
	assert(mean_radius > 0.0, "IVBody requires mean_radius > 0.0")
	assert(!is_nan(gravitational_parameter), "Use 0.0 if missing or unknown")
	assert(orientation_at_epoch.is_conformal())
	assert(orientation_at_epoch.x.is_normalized())
	assert(rotation_axis.is_normalized())
	assert(!is_nan(rotation_at_epoch), "IVBody requires 'rotation_at_epoch'")
	assert(flags > 0, "IVBody requires non-zero flags")
	
	rotation_at_epoch = fposmod(rotation_at_epoch, TAU)
	flags |= BodyFlags.BODYFLAGS_EXISTS
	
	assert(bool(flags & BodyFlags.BODYFLAGS_GALAXY_ORBITER) == (orbit == null))
	assert(!(flags & BodyFlags.BODYFLAGS_AXIS_LOCKED) or flags & BodyFlags.BODYFLAGS_TIDALLY_LOCKED,
			"Axis-locked bodies must also be tidally locked")
	
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
	body._orbit = orbit
	body.flags = flags
	
	body.rotation_axis = rotation_axis
	body.rotation_rate = rotation_rate
	body.orientation_at_epoch = orientation_at_epoch
	
	if flags & BodyFlags.BODYFLAGS_TIDALLY_LOCKED:
		characteristics[&"locked_rotation_at_epoch"] = rotation_at_epoch
	
	return body


## Creates new [IVOrbit] instance (or specified [member replacement_subclass]).
## from specified parameters [param right_ascension] and [param declination]
## define "North" for this body. If [param rotation_period] is negative, then
## this body has retrograde rotation (e.g., Venus). If [param flags] & BODYFLAGS_TIDALLY_LOCKED,
## then [param rotation_period] doesn't matter. If [param flags] & BODYFLAGS_AXIS_LOCKED,
## then [param right_ascension] and [param declination] don't matter.
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
	body._orbit = orbit
	body.flags = flags
	
	# Rotations will be updated if tidally or axis locked, so these might not matter...
	var orientation_at_epoch_ := IVAstronomy.get_ecliptic_basis_from_equatorial_north(
		right_ascension, declination)
	var rotation_axis_ := orientation_at_epoch_.z
	var rotation_rate_ := TAU / rotation_period if rotation_period else 0.0
	orientation_at_epoch_ = orientation_at_epoch_.rotated(rotation_axis_, rotation_at_epoch)
	body.rotation_axis = rotation_axis_
	body.rotation_rate = rotation_rate_
	body.orientation_at_epoch = orientation_at_epoch_
	
	if flags & BodyFlags.BODYFLAGS_TIDALLY_LOCKED:
		characteristics[&"locked_rotation_at_epoch"] = rotation_at_epoch
	
	return body


func remove() -> void:
	const GALAXY_ORBITER := BodyFlags.BODYFLAGS_GALAXY_ORBITER
	for satellite_name in satellites:
		satellites[satellite_name].remove()
	bodies.erase(name)
	if flags & GALAXY_ORBITER:
		galaxy_orbiters.erase(name)
	if _orbit:
		_orbit.changed.disconnect(_on_orbit_changed)
	_clear_relative_bodies()
	queue_free()


# *****************************************************************************
# properties API


## Sets specified flag(s) in [member flags].
func set_flag(flag: int) -> void:
	flags |= flag


## Unsets specified flag(s) in [member flags].
func unset_flag(flag: int) -> void:
	flags &= ~flag


## Returns [member mean_radius].
func get_mean_radius() -> float:
	return mean_radius


## Sets [member mean_radius].
func set_mean_radius(value: float) -> void:
	mean_radius = value


## Returns [member gravitational_parameter] (GM).
func get_gravitational_parameter() -> float:
	return gravitational_parameter


## Sets [member gravitational_parameter] (GM). This method does
## [b]NOT[/b] update GM for the orbits of satellites. (But that might be
## implemented in the future.)
func set_gravitational_parameter(value: float) -> void:
	gravitational_parameter = value


## Returns [member orientation_at_epoch].
func get_orientation_at_epoch() -> Basis:
	return orientation_at_epoch


## Sets [member orientation_at_epoch].
func set_orientation_at_epoch(value: Basis) -> void:
	orientation_at_epoch = value


## Returns [member rotation_axis].
func get_rotation_axis() -> Vector3:
	return rotation_axis


## Sets [member rotation_axis].
func set_rotation_axis(value: Vector3) -> void:
	rotation_axis = value


## Returns [member rotation_rate].
func get_rotation_rate() -> float:
	return rotation_rate


## Sets [member rotation_rate].
func set_rotation_rate(value: float) -> void:
	rotation_rate = value


## Returns [member rotation_at_epoch].
func get_rotation_at_epoch() -> float:
	return rotation_at_epoch


## Sets [member rotation_at_epoch].
func set_rotation_at_epoch(value: float) -> void:
	rotation_at_epoch = value


func set_component(key: StringName, value: RefCounted) -> void:
	if value == null:
		components.erase(key)
		return
	assert(&"PERSIST_MODE" in value)
	assert(value[&"PERSIST_MODE"] == IVGlobal.PERSIST_PROCEDURAL)
	components[key] = value


func get_component(key: StringName) -> RefCounted:
	return components.get(key)


func has_orbit() -> bool:
	return _orbit != null


func get_orbit() -> IVOrbit:
	return _orbit


func set_orbit(new_orbit: IVOrbit) -> void:
	if _orbit:
		_orbit.changed.disconnect(_on_orbit_changed)
	_orbit = new_orbit
	if is_inside_tree(): # otherwise, connected on _enter_tree()
		new_orbit.changed.connect(_on_orbit_changed)




# *****************************************************************************
# characteristics API...


func set_characteristic(key: StringName, value: Variant) -> void:
	assert(not value is Object)
	if value == null:
		characteristics.erase(key)
		return
	characteristics[key] = value


func get_characteristic(key: StringName) -> Variant:
	match key:
		&"mass":
			return get_mass()
		&"equatorial_radius":
			return get_equatorial_radius()
		&"polar_radius":
			return get_polar_radius()
		&"hud_name":
			return get_hud_name()
		&"symbol":
			return get_symbol()
		&"body_class":
			return get_body_class()
		&"perspective_radius":
			return get_perspective_radius()
		&"model_type":
			return get_model_type()
		&"file_prefix":
			return get_file_prefix()
		&"has_light":
			return has_light()
		&"has_rings":
			return has_rings()
	
	return characteristics.get(key)


## Note: For astronomical objects, standard gravitational parameter (GM) is
## usually known with greater precision than mass. Mass precision is limited
## by our imprecise estimation of the gravitational constant, G.
func get_mass() -> float:
	const G := IVAstronomy.G
	var mass: float = characteristics.get(&"mass", 0.0)
	if mass:
		return mass
	return gravitational_parameter / G


## Has a specific value for oblate spheroids. Otherwise, returns [member mean_radius].
func get_equatorial_radius() -> float:
	var equatorial_radius: float = characteristics.get(&"equatorial_radius", 0.0)
	if equatorial_radius:
		return equatorial_radius
	return mean_radius


## Has a specific value for oblate spheroids. Otherwise, returns [member mean_radius].
func get_polar_radius() -> float:
	var polar_radius: float = characteristics.get(&"polar_radius", 0.0)
	if polar_radius:
		return polar_radius
	return mean_radius


## Returns a specific name for HUD use, if different from [member Node.name].
func get_hud_name() -> String:
	return characteristics.get(&"hud_name", name)


## Returns the symbol used by [IVBodyLabel].
func get_symbol() -> String:
	return characteristics.get(&"symbol", default_symbol) # default is dashed circle


## Returns this body's body_class. See data table [param body_classes.tsv].
func get_body_class() -> int: # body_classes.tsv
	return characteristics.get(&"body_class", -1)


## Returns a "perspective" radius used for camera distancing.
## Same as [member mean_radius] unless something different is needed.
func get_perspective_radius() -> float:
	var perspective_radius: float = characteristics.get(&"perspective_radius", 0.0)
	if perspective_radius:
		return perspective_radius
	return mean_radius


func get_model_type() -> int: # models.tsv
	return characteristics.get(&"model_type", -1)


func get_file_prefix() -> String:
	return characteristics.get(&"file_prefix", "")


func has_light() -> bool:
	return characteristics.get(&"has_light", false)


func has_rings() -> bool:
	return characteristics.get(&"has_rings", false)


## Precisions are available only if [code]IVCoreSettings.enable_precisions == true[/code].
## Gets the precision (significant digits) of a float value as it was entered
## in the data table file or as calculated. [param path] can be a path to a
## property, a method, or a component property or method. See [IVSelectionData]
## for usage. Used by [url=https://github.com/ivoyager/planetarium]Planetarium[/url].
func get_float_precision(path: String) -> int:
	if !characteristics.has(&"float_precisions"):
		return -1
	var float_precisions: Dictionary = characteristics[&"float_precisions"]
	return float_precisions.get(path, -1)


# *****************************************************************************
# orbit API...


## Returns this body's orbital mean longitude (L). Supply [param time] only if
## you don't want the current value. 
func get_orbit_mean_longitude(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_mean_longitude_at_update()
		time = _times[0]
	return _orbit.get_mean_longitude(time)


## Returns this body's orbital true longitude (l). Supply [param time] only if
## you don't want the current value. 
func get_orbit_true_longitude(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_true_longitude_at_update()
		time = _times[0]
	return _orbit.get_true_longitude(time)


## Returns true if this body's orbit is retrograde. Supply [param time] only if
## you don't want the current value. 
func is_orbit_retrograde(time := NAN) -> bool:
	if !_orbit:
		return false
	if is_nan(time):
		if !_sleeping:
			return _orbit.is_retrograde()
		time = _times[0]
	return _orbit.is_retrograde_at_time(time)


## Returns this body's orbital semi-parameter (p). Supply [param time] only if
## you don't want the current value. 
func get_orbit_semi_parameter(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_semi_parameter()
		time = _times[0]
	return _orbit.get_semi_parameter_at_time(time)


## Returns this body's orbital semi-major axis (a). Supply [param time] only if
## you don't want the current value. 
func get_orbit_semi_major_axis(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_semi_major_axis()
		time = _times[0]
	return _orbit.get_semi_major_axis_at_time(time)


## Returns this body's orbital eccentricity. Supply [param time] only if you
## don't want the current value. 
func get_orbit_eccentricity(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_eccentricity()
		time = _times[0]
	return _orbit.get_eccentricity_at_time(time)


## Returns this body's orbital inclination. Supply [param time] only if you
## don't want the current value. 
func get_orbit_inclination(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_inclination()
		time = _times[0]
	return _orbit.get_inclination_at_time(time)


## Returns a unit vector normal to this body's orbit. Supply [param time] only
## if you don't want the current value. 
func get_orbit_normal(time := NAN, flip_retrograde := false) -> Vector3:
	const ECLIPTIC_NORTH := Vector3(0, 0, 1)
	if !_orbit:
		return ECLIPTIC_NORTH
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_normal(flip_retrograde)
		time = _times[0]
	return _orbit.get_normal_at_time(time, flip_retrograde)


# *****************************************************************************
# general API...


## Returns the rotation period of this body. Negative if this body has
## retrograde rotation. INF if this body has [member rotation_rate] == 0.0.
func get_rotation_period() -> float:
	return TAU / rotation_rate if rotation_rate else INF


## Returns north in equatorial coordinates as Vector2(right_ascention, declination).
func get_equatorial_north() -> Vector2:
	var eq_coord := IVAstronomy.get_equatorial_coordinates_from_ecliptic_vector(rotation_axis)
	return Vector2(eq_coord[0], eq_coord[1])


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
## rules above.[br][br]
##
## Note: [param _time] is present in anticipation of rotation precession.
func get_north_axis(_time := NAN) -> Vector3:
	return rotation_axis


## Returns an axis of rotation that points in the direction of the positive pole
## (using the right-hand-rule).[br][br]
##
## Note: [param _time] is present in anticipation of rotation precession.
func get_positive_axis(_time := NAN) -> Vector3:
	if rotation_rate < 0.0:
		return -rotation_axis
	return rotation_axis


## Note: [param _time] is present in anticipation of more complex rotations
## (i.e., tumbling).
func is_rotation_retrograde(_time := NAN) -> bool:
	return rotation_rate < 0.0


## Returns the "system" radius. This value is the maximum of:
## a) semi-major axis of the outermost body orbiting this body (if any),
## b) [member mean_radius] times a multiplier, or
## c) a value set in data table using field name [param system_radius].
func get_system_radius() -> float:
	return _system_radius


## See [url]https://en.wikipedia.org/wiki/Hill_sphere[/url].
## Returns INF if this body is a galaxy orbiter.
func get_hill_sphere() -> float:
	return _hill_sphere


## Returns a basis that rotates with the ground (i.e, with the body model).
## Supply [param time] only if you don't want the current value.
func get_orientation(time := NAN) -> Basis:
	if is_nan(time):
		if model_space and !_sleeping:
			return model_space.basis
		time = _times[0]
	var rotation_angle := wrapf(time * rotation_rate, 0.0, TAU)
	return orientation_at_epoch.rotated(rotation_axis, rotation_angle)


## Returns a valid current "postion" or projected position at specified time.
## Return is valid even if this instance is currently sleeping (unlike
## [member Node3D.position]). Supply [param time] only if you don't want the
## current value.
func get_position_vector(time := NAN) -> Vector3:
	if is_nan(time):
		if !_sleeping:
			return position
		time = _times[0]
	if _orbit:
		return _orbit.get_position(time)
	# TODO: galaxy-orbiters will have position and velocity eventually,
	# probably as fixed values relative to galaxy center.
	return Vector3.ZERO


## Returns current [position, velocity] or projected [position, velocity] at
## specified time as a Vector3 array. Return is valid even if this instance is
## currently sleeping. Supply [param time] only if you don't want the current
## value.
func get_state_vectors(time := NAN) -> Array[Vector3]:
	if is_nan(time):
		time = _times[0]
	if _orbit:
		return _orbit.get_state_vectors(time)
	# TODO: galaxy-orbiters will have position and velocity eventually,
	# probably as fixed values relative to galaxy center.
	return [Vector3.ZERO, Vector3.ZERO]


## Returns Vector2(latitude, longitude) of [param vector] with respect to this
## body's ground coordinates. Supply [param time] only if you don't want the
## value relative to the body's current orientation. 
func get_latitude_longitude(vector: Vector3, time := NAN) -> Vector2:
	const math := preload("uid://csb570a3u1x1k")
	var ground_basis := get_orientation(time)
	var spherical := math.get_rotated_spherical3(vector, ground_basis)
	return Vector2(spherical[1], wrapf(spherical[0], -PI, PI))


## Returns this body's axial tilt relative to its orbit normal. Supply [param time]
## only if you don't want the current value. 
func get_axial_tilt_to_orbit(time := NAN) -> float:
	if !_orbit:
		return NAN
	var orbit_normal: Vector3
	if is_nan(time):
		if !_sleeping:
			orbit_normal = _orbit.get_normal()
		else:
			time = _times[0]
			orbit_normal = _orbit.get_normal_at_time(time)
	else:
		orbit_normal = _orbit.get_normal_at_time(time)
	var positive_axis := get_positive_axis(time)
	return positive_axis.angle_to(orbit_normal)


## Returns this body's axial tilt relative to ecliptic north. Supply [param time]
## only if you don't want the current value. 
func get_axial_tilt_to_ecliptic(time := NAN) -> float:
	const ECLIPTIC_NORTH := Vector3(0, 0, 1)
	var positive_axis := get_positive_axis(time)
	return positive_axis.angle_to(ECLIPTIC_NORTH)


## Returns a basis that rotates with the body's orbit around its parent, with
## parent in the -x direction and orbit normal in the z direction. Returns
## identity basis if this IVBody has no IVOrbit. This is a different basis than
## IVOrbit.get_basis().
## Supply [param time] only if you don't want the current value.
func get_orbit_tracking_basis(time := NAN) -> Basis:
	const ECLIPTIC_BASIS := Basis.IDENTITY
	if !_orbit:
		return ECLIPTIC_BASIS
	var x_axis: Vector3
	var y_axis: Vector3
	var z_axis: Vector3
	if is_nan(time):
		if !_sleeping:
			x_axis = -position.normalized()
			z_axis = _orbit.get_normal(true, true)
			y_axis = z_axis.cross(x_axis)
			return Basis(x_axis, y_axis, z_axis)
		time = _times[0]
	x_axis = -_orbit.get_position(time).normalized()
	z_axis = _orbit.get_normal_at_time(time, true, true)
	y_axis = z_axis.cross(x_axis)
	return Basis(x_axis, y_axis, z_axis)


# *****************************************************************************
# core mechanics...


## Adds [param satellite] to this body's [member satellites]. Does [b]NOT[/b]
## add [param satellite] to the tree!
func add_satellite(satellite: IVBody) -> void:
	assert(!satellites.has(satellite.name))
	satellites[satellite.name] = satellite


## Removes [param satellite] from this body's [member satellites]. Does [b]NOT[/b]
## remove [param satellite] from the tree!
func remove_satellite(satellite: IVBody) -> void:
	satellites.erase(satellite.name)


## Adds a child Node3D to this body's [IVModelSpace]. Use for nodes that need to
## share the model's orientation and rotation in space, but not its scale. Used
## by [IVRings] (e.g., Saturn's Rings).
func add_child_to_model_space(node3d: Node3D) -> void:
	if !model_space:
		_add_model_space()
	model_space.add_child(node3d)


## Removes a child Node3D from this body's [IVModelSpace]. See [method add_child_to_model_space].
func remove_child_from_model_space(node3d: Node3D) -> void:
	model_space.remove_child(node3d)


## @deprecated
func remove_and_disable_model_space() -> void:
	# Removes model(s) but everything else remains (label & orbit HUDs, etc.).
	# Unsets BodyFlags.BODYFLAGS_EXISTS.
	flags |= BodyFlags.BODYFLAGS_DISABLE_MODEL_SPACE
	flags &= ~BodyFlags.BODYFLAGS_EXISTS
	if model_space:
		model_space.queue_free()
	model_space = null


## Returns true if this body has [member BodyFlags.BODYFLAGS_LAZY_MODEL] set
## and a model has not been inited yet. 
func is_lazy_model_uninited() -> bool:
	return _lazy_model_uninited


## Use to init a lazy model, if needed. Normally called by [IVLazyModelInitializer].
func lazy_model_init() -> void:
	_add_model_space()


## Current sleeping state. See [IVSleepManager].
func is_sleeping() -> bool:
	return _sleeping


## Set sleeping state. Only [IVSleepManager] should call this.
func set_sleeping(is_asleep: bool) -> void:
	const CAN_SLEEP := BodyFlags.BODYFLAGS_CAN_SLEEP
	if _sleeping == is_asleep or !(flags & CAN_SLEEP):
		return
	_sleeping = is_asleep
	if is_asleep:
		hide()
		set_process(false)
		_world_controller.remove_world_target(self)
	else:
		set_process(true)


## Used for mouse-over identification of this body's orbit visual.
func get_fragment_data(_fragment_type: int) -> Array:
	# Only FRAGMENT_BODY_ORBIT at this time.
	return [get_instance_id()]


## Used for mouse-over identification of this body's orbit visual.
func get_fragment_text(_data: Array) -> String:
	# Only FRAGMENT_BODY_ORBIT at this time.
	return tr(name) + " (" + tr("LABEL_ORBIT").to_lower() + ")"


# *****************************************************************************
# private


func _clear_procedural() -> void:
	if _orbit:
		_orbit.changed.disconnect(_on_orbit_changed)
	parent = null
	star = null
	star_orbiter = null
	satellites.clear()
	model_space = null
	bodies.clear()
	galaxy_orbiters.clear()


func _on_system_tree_built_or_loaded(is_new_game: bool) -> void:
	if !is_new_game:
		return
	# persisted data needed for new game only...
	_set_system_radius()
	_set_hill_sphere()


func _set_relative_bodies() -> void:
	# For multi-star system, a star could be a star orbiter.
	const STAR := BodyFlags.BODYFLAGS_STAR
	const STAR_ORBITER := BodyFlags.BODYFLAGS_STAR_ORBITER
	parent = get_parent_node_3d() as IVBody # null only for galaxy orbiter
	star = null
	star_orbiter = null
	var ascending_body := self
	while ascending_body:
		if !star_orbiter and ascending_body.flags & STAR_ORBITER:
			star_orbiter = ascending_body
		if ascending_body.flags & STAR:
			star = ascending_body
			break
		ascending_body = ascending_body.get_parent_node_3d() as IVBody
	if parent:
		parent.add_satellite(self)


func _clear_relative_bodies() -> void:
	if parent:
		parent.remove_satellite(self)
		parent = null
	star = null
	star_orbiter = null


func _set_resources() -> void:
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	texture_2d = asset_preloader.get_body_texture_2d(name)
	texture_slice_2d = asset_preloader.get_body_texture_slice_2d(name) # usually null


func _set_min_hud_dist() -> void:
	if !IVGlobal.settings[&"hide_hud_when_close"]:
		_min_hud_dist = 0.0
		return
	_min_hud_dist = mean_radius * min_hud_dist_radius_multiplier
	if flags & BodyFlags.BODYFLAGS_STAR:
		_min_hud_dist *= min_hud_dist_star_multiplier # star grows at distance


func _set_system_radius() -> void:
	var system_radius := mean_radius * system_mean_radius_multiplier
	if characteristics.get(&"system_radius", 0.0) > system_radius:
		system_radius = characteristics[&"system_radius"]
	for satellite_name in satellites:
		var a: float = satellites[satellite_name].get_orbit_semi_major_axis()
		if system_radius < a:
			system_radius = a
	_system_radius = system_radius


func _set_hill_sphere() -> void:
	if !parent:
		_hill_sphere = INF
		return
	var mass := get_mass()
	if !mass:
		_hill_sphere = 0.0
		return
	var parent_mass: float = parent.get_mass()
	if !parent_mass:
		_hill_sphere = 0.0
		return
	var a := _orbit.get_semi_major_axis()
	var e := _orbit.get_eccentricity()
	_hill_sphere = a * (1.0 - e) * pow(mass / (3.0 * parent_mass), 0.3333333333333333)


func _on_orbit_changed(is_intrinsic: bool, precession_only: bool) -> void:
	const TIDALLY_LOCKED := BodyFlags.BODYFLAGS_TIDALLY_LOCKED
	assert(is_inside_tree(), "A body's orbit should change only when processing in the tree!")
	orbit_changed.emit(_orbit, is_intrinsic, precession_only)
	if !precession_only:
		_set_hill_sphere()
	if flags & TIDALLY_LOCKED:
		_update_rotations(is_intrinsic)


func _update_rotations(is_intrinsic: bool) -> void:
	# A body can only be axis-locked if it is also tidally locked.
	const TIDALLY_LOCKED := BodyFlags.BODYFLAGS_TIDALLY_LOCKED
	const AXIS_LOCKED := BodyFlags.BODYFLAGS_AXIS_LOCKED
	assert(flags & TIDALLY_LOCKED)
	
	# rotation
	var new_rotation_rate := _orbit.get_mean_longitude_rate()
	var locked_rotation_at_epoch: float = characteristics[&"locked_rotation_at_epoch"]
	var new_rotation_at_epoch := fposmod(locked_rotation_at_epoch
			+ _orbit.get_mean_longitude_at_epoch() - PI, TAU)
	
	# axis
	var new_rotation_axis := rotation_axis
	if flags & AXIS_LOCKED:
		new_rotation_axis = _orbit.get_normal()
		# Possible polarity reversal. See comments under get_north_axis().
		# For any body that is axis-locked, "north" follows parent north,
		# whatever that is. Note that rotation_axis defines "north".
		if parent.rotation_axis.dot(new_rotation_axis) < 0.0: # e.g., Triton
			new_rotation_axis *= -1.0
			new_rotation_rate *= -1.0
			new_rotation_at_epoch = fposmod(-new_rotation_at_epoch, TAU)
	
	rotation_rate = new_rotation_rate
	rotation_axis = new_rotation_axis
	rotation_at_epoch = new_rotation_at_epoch
	var new_basis := IVAstronomy.get_basis_from_z_axis_and_vernal_equinox(rotation_axis)
	orientation_at_epoch = new_basis.rotated(rotation_axis, rotation_at_epoch)
	
	rotation_chaged.emit(is_intrinsic)


func _add_model_space() -> void:
	const DISABLE_MODEL_SPACE := BodyFlags.BODYFLAGS_DISABLE_MODEL_SPACE
	assert(!model_space)
	_lazy_model_uninited = false
	if flags & DISABLE_MODEL_SPACE:
		return
	var e_radius := get_equatorial_radius()
	if replacement_model_space_class:
		@warning_ignore("unsafe_method_access")
		model_space = replacement_model_space_class.new(name, mean_radius, e_radius)
	else:
		model_space = IVModelSpace.new(name, mean_radius, e_radius)
	@warning_ignore("unsafe_property_access")
	_max_model_dist = model_space.max_distance # FIXME: Use Node3D visual distance parameters
	add_child(model_space)


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"hide_hud_when_close":
		_set_min_hud_dist()
