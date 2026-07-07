# body.gd
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
class_name IVBody
extends Node3D

## An object that orbits or is orbited, including stars, planets, moons,
## instantiated asteroids, and spacecrafts (TODO: and barycenters).
##         
## [member Node.name] is always the data table row name: "PLANET_VENUS",
## "MOON_EUROPA", "SPACECRAFT_JUNO", etc.[br][br]
##
## Using our Solar System as example, the structure of the scene tree is:
## [codeblock]
## Universe
##    |- IVBody (STAR_SUN)
##        |- IVBody (PLANET_MERCURY)
##        |- IVBody (PLANET_VENUS)
##        |- IVBody (PLANET_EARTH)
##            |- IVBody (SPACECRAFT_INTERNATIONAL_SPACE_STATION)
##            |- IVBody (SPACECRAFT_HUBBLE_SPACE_TELESCOPE)
##            |- IVBody (MOON_MOON)
##                |- IVBody (a spacecraft orbiting the Moon)
##        |- etc...
## [/codeblock][br]
##
## Note that current core mechanics [i]should[/i] handle multi-star systems
## or >1 primary star under Universe, but this has not been tested yet.[br][br]
##
## [IVBody] nodes are NEVER scaled or rotated. Hence, local distances and
## directions are always in the ecliptic basis at any level of the "body tree".[br][br]
##
## All [IVBody] instances that orbit another [IVBody] have an [IVOrbit]. This
## component provides state vectors (position and velocity) given time. Orbits
## can evolve over time (e.g., the base class supports orbit precessions) or
## change in other ways. See [IVOrbit] file docs for thrust implementation.[br][br]
##
## This node adds its own [IVBodyVisual] if needed, parented under an
## interposed [member farwarp_space] Node3D that carries only the farwarp
## position offset and uniform scale (see [IVFarwarpManager]). [IVBody]
## maintains the rotation of its [IVBodyVisual] if present. [IVBodyVisual]
## instantiates and scales the visual representation (i.e., model) of this body. Note that
## ivoyager_core does not implement collisions. ([IVBody] and [IVBodyVisual]
## subclasses would likely be needed to do that.) If [IVLazyModelInitializer] is
## present and this body has [enum BodyFlags].BODYFLAGS_LAZY_MODEL (from data
## table field [param lazy_model]),
## then [IVBodyVisual] won't be added until the camera visits this body or a
## closely associated "lazy" body. This is generally set for spacecraft (which
## are small but have large models) and for the 100s of small outer moons of
## the gas giants (but not for inner moons because these can be seen from
## nearby).[br][br]
##
## Some bodies (particularly moons and spacecrafts) have
## [member BodyFlags].BODYFLAGS_CAN_SLEEP set from data table field
## [param can_sleep]. If [IVSleepManager] is present, these bodies will
## only [code]_process()[/code] when the camera is at or under the same planet
## or other star-orbiter.
## Note that [IVBody] API methods such as [method get_position_vector] and
## [method get_state_vectors] will provide correct values even if the body is
## not currently processing, but [member Node3D.postion] will not. These methods also
## take an optional [param time] argument to allow projected results.[br][br]
##
## [IVBody] properties are core information required for all bodies. Specialized
## information is contained in dictionary [member characteristics]. For
## example all bodies have [member mean_radius], but oblate spheroid bodies
## (stars, planets, and large moons) also have [param equatorial_radius] and
## [param polar_radius] as keys in characteristics. API methods provide access
## to many of these characteristics with sensible fallbacks for missing keys.[br][br]
##
## Many body-associated "graphic" nodes are added by [IVBodyFinisher] including
## [IVRings], [IVDynamicLight], [IVPathVisual], and [IVBodyPositionVisual]. Dependency
## is inverted for these classes: they have reference to their [IVBody] but
## [IVBody] has no reference to them.[br][br]
## 
## See also [IVSmallBodiesGroup] for handling 1000s or 100000s of orbiting
## bodies without individual instantiation. This is implemented for asteroids at
## this time, but could support other small body types. E.g., it could easily
## handle all of Earth's artificial satellites.[br][br]
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
## 2. Axisymmetric wobbling (easy-ish). I1 == I2 != I3. This may be a reasonable
##    approximation for many elongated asteroids. (It's also applicable for north
##    precession in planets, but the time scale for that is too long to matter
##    for most applications.)[br]
## 3. Asymmetric tumbling (quasi-periodic, non-chaotic; hard). I1 != I2 != I3.
##    The math is difficult (need Jacobi elliptic functions) but the rotations
##    are fully deterministic.[br]
## 4. Chaotic tumbling (harder). Above with perturbations. (E.g., Hyperion.)[br]
## (Even #2 would be an asthetic improvement for bodies that are really #4.)[br][br]
## 
## TODO: API for changing orbit context or "identity". E.g., a spacecraft
## becomes BODYFLAGS_STAR_ORBITER, or an asteroid is captured to become a moon.[br][br]
##
## TODO: (Ongoing) Make this node editable and constructable in the Editor
## (while maintaining existing table and code-based generation).[br][br]
##
## TODO: Barycenters! They orbit and are orbited. This will make Pluto system
## (especially) more accurate, and allow things like twin planets.[br][br]
##
## TODO: Implement network sync! This will mainly involve synching IVOrbit
## anytime it changes in an extrinsic way (e.g., impulse from a rocket
## engine). Same for rotations: we only sync when an extrinsic force changes
## the current (deterministic) state properties.[br][br]
##
## TODO: We want to handle local stars out to some range. Each solitary star or
## system primary star will be a "top" body with relative position
## and velocity in Universe. Any larger scope will require procedural system
## building and scene loading, which is not in our plans but could be supported.

## Emitted when this body's orbit changes. [param is_intrinsic] distinguishes
## intrinsic changes (e.g. spacecraft thrust) from extrinsic changes (e.g.
## time-dependent precession). [param precession_only] indicates that only
## precession has updated.
signal orbit_changed(orbit: IVOrbit, is_intrinsic: bool, precession_only: bool)
## Emitted when this body is reparented at runtime to [param new_parent] — an
## [IVTrajectory] segment change in [method set_orbit_and_parent] that moves the body
## under a different parent. NOT emitted during initial system build. Fires on the main
## thread, after the reparent (this body's [member parent] already equals [param new_parent]).
signal parent_changed(new_parent: IVBody)
## Emitted when rotation parameters change. [param is_intrinsic] distinguishes
## an externally-imposed rotation change from time-driven rotation evolution.
signal rotation_chaged(is_intrinsic: bool)
## Emitted when this body's HUD visibility (label, orbit visual, etc.) toggles.
signal huds_visibility_changed(is_visible: bool)
## Emitted when this body's sleep state changes. This is managed by
## [IVSleepManager], if present.
signal sleep_changed(is_sleeping: bool)
## Emitted when [member within_lifespan] toggles as simulator time crosses this
## body's [member begin] or [member end]. Never emitted for a body with no
## [member begin] set (such a body is always within its lifespan).
signal within_lifespan_changed(is_within_lifespan: bool)


## Bits to 1 << 39 are reserved for ivoyager_core future use. Higher bits are
## safe to use for external projects. Max bit shift is 1 << 62 (sign bit 1 << 63
## isn't safe to use!).
enum BodyFlags {
	
	# orbit context & identity
	BODYFLAGS_TOP = 1, ## Directly under Universe.
	BODYFLAGS_STAR_ORBITER = 1 << 1, ## Planet, dwarf planet, asteroid, comet, etc.
	BODYFLAGS_BARYCENTER = 1 << 2, ## NOT IMPLEMENTED YET.
	BODYFLAGS_PLANETARY_MASS_OBJECT = 1 << 3, ## Includes dwarf planet and larger spheroid moon.
	BODYFLAGS_STAR = 1 << 4, ## May or may not be BODYFLAGS_TOP.
	BODYFLAGS_PLANET_OR_DWARF_PLANET = 1 << 5,
	BODYFLAGS_PLANET = 1 << 6, ## Does not include dwarf planet.
	BODYFLAGS_DWARF_PLANET = 1 << 7,
	BODYFLAGS_MOON = 1 << 8,
	BODYFLAGS_PLANETARY_MASS_MOON = 1 << 9,
	BODYFLAGS_NON_PLANETARY_MASS_MOON = 1 << 10,
	BODYFLAGS_ASTEROID = 1 << 11,
	BODYFLAGS_COMET = 1 << 12, ## NOT IMPLEMENTED YET.
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
	BODYFLAGS_DISABLE_MODEL_SPACE = 1 << 25,
	
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
	&"_trajectory",
	&"_system_radius",
	&"_hill_sphere",
]


## Set this script to generate a subclass in place of IVBody in create methods.
## A subclass can do this in their _static_init() for project-wide replacement.
static var replacement_subclass: Script
## Set this script to replace the [IVBodyVisual] class.
static var replacement_body_visual_class: Script
## Static class setting.
static var system_mean_radius_multiplier := 15.0
## Static class setting.
static var min_visual_separation_multiplier := 100.0
## Static class setting.
static var min_hud_dist_radius_multiplier := 500.0
## Static class setting.
static var min_hud_dist_star_multiplier := 20.0
## A static class dictionary that contains all added IVBody instances.
## WARNING: Access on main thread only!
static var bodies: Dictionary[StringName, IVBody] = {}
## A static class dictionary that contains IVBody instances that are at the top
## of a system, i.e., the primary star for every star system (these have no
## [IVOrbit]). WARNING: Access on main thread only!
static var top_bodies: Dictionary[StringName, IVBody] = {}

static var _selection_ordered_bodies: Array[IVBody] = [] # build/rebuild only when needed
static var _selection_order_dirty := true


# persisted
## See [enum BodyFlags].
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
## Rotation phase (radians) at the simulator epoch.
var rotation_at_epoch := 0.0
## Beginning of life. NAN or -INF mean no begining, but the latter is required
## for [member end] to be effective. This is mainly for spacecraft that begin
## life via table value (not added by code).
var begin := NAN
## End of life. Only works if [member begin] is not NAN. NAN or INF mean no end.
## This is mainly for spacecraft that end life via table value (not removed by
## code).
var end := NAN
## Persisted dictionary of non-object characteristics (mass, surface gravity,
## albedo, atmosphere data, etc.) loaded from data tables.
var characteristics: Dictionary[StringName, Variant] = {} # non-object values
## Persisted dictionary of object-valued components (e.g. an [IVComposition]).
var components: Dictionary[StringName, RefCounted] = {} # objects (persisted only)

# redirect (authoritative value in private variable)
## This body's [IVOrbit]; null if "top" body.
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
## Orbiting bodies sorted by semi-parameter. Order isn't maintained during
## game session and can be lost due to orbit changes (e.g., spacecraft changing
## semi-parameter). It will be restored after every game load.
var ordered_satellites: Array[IVBody]
## If present, the Node3D that has this body's visual
## representation (model). If data table value [param lazy_model] == TRUE, then
## this value will be null until needed. Read-only!
var body_visual: Node3D
## If present, the Node3D interposed between this body and [member body_visual]
## that carries the farwarp position and uniform scale (rotation is never
## applied here). It is [member Node3D.top_level] when farwarp is enabled:
## positioned per-frame in world space from camera-relative math, because
## summing true-scale translations through the ancestor chain loses the
## compressed position to float32 rounding (one ulp of the true distance can
## exceed the whole compressed distance). See [IVFarwarpManager]. Read-only!
var farwarp_space: Node3D
## Current farwarp-compressed global position of this body's visuals; equals
## the true global position inside the farwarp start distance. Consumed
## per-frame by [IVBodyPositionVisual] (also top_level). Not maintained when
## farwarp is disabled. Read-only!
var farwarp_position := Vector3.ZERO
## Current visibility state for associated HUD elements, including
## IVBodyPositionVisual and IVPathVisual. Read-only!
var huds_visible := false
## True while simulator time is within [member begin]/[member end], or always true
## if no [member begin] is set. Maintained in [method _process]; see
## [signal within_lifespan_changed]. Read-only!
var within_lifespan := true
## GUI graphic representation of this body. Read-only!
var texture_2d: Texture2D
## GUI graphic representation of this body as a "slice" for a system star. Read-only!
var texture_slice_2d: Texture2D


# private persisted
var _orbit: IVOrbit
var _trajectory: IVTrajectory # usually null; if set, _process swaps _orbit per segment
var _system_radius: float
var _hill_sphere: float

# private non-persisted
var _lazy_model_uninited := false
var _sleeping := false
var _min_hud_dist: float
var _farwarp_no_cutoff := false # stars bypass the farwarp angular-size gate
var _times: Array[float] = IVGlobal.times
var _world_controller: IVWorldController = IVGlobal.program[&"WorldController"]
var _process_callable: Callable # bespoke model attitude named by spacecrafts.tsv 'process'

var _stroboscope_frame_rate := IVCoreSettings.stroboscope_frames_per_second / IVUnits.SECOND
var _stroboscope_minimum_blur := IVCoreSettings.stroboscope_minimum_blur
var _stroboscope_motion_blur := IVCoreSettings.stroboscope_motion_blur


var _stroboscope_rotation := 0.0

@onready var _tree := get_tree()



# *****************************************************************************
# create methods

## Creates a new [IVBody] instance (or specified [member replacement_subclass])
## using specified parameters. See also [method create_from_astronomy_specs].
@warning_ignore("shadowed_variable", "shadowed_variable_base_class")
static func create(
		name: StringName,
		flags: int,
		mean_radius: float,
		gravitational_parameter: float,
		orientation_at_epoch: Basis,
		rotation_axis: Vector3,
		rotation_at_epoch: float,
		rotation_rate: float,
		orbit: IVOrbit,
		characteristics: Dictionary,
		components: Dictionary,
		exisiting_body: IVBody = null
	) -> IVBody:
	
	assert(name)
	assert(mean_radius > 0.0, "IVBody requires mean_radius > 0.0")
	assert(!is_nan(gravitational_parameter), "Use 0.0 if missing or unknown")
	assert(orientation_at_epoch.is_conformal())
	assert(orientation_at_epoch.x.is_normalized())
	assert(rotation_axis.is_normalized())
	assert(!is_nan(rotation_at_epoch), "IVBody requires 'rotation_at_epoch'")
	assert(flags > 0, "IVBody requires non-zero flags")
	
	rotation_at_epoch = fposmod(rotation_at_epoch, TAU)
	
	assert(bool(flags & BodyFlags.BODYFLAGS_TOP) == (orbit == null))
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


## Creates a new [IVBody] instance (or specified [member replacement_subclass])
## using specified parameters. [param right_ascension] and [param declination]
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
	
	assert(bool(flags & BodyFlags.BODYFLAGS_TOP) == (orbit == null))
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


static func _is_ordered_satellites(a: IVBody, b: IVBody) -> bool:
	# Semi-parameter is always defined, unlike semi-major axis. These are
	# nearly the same for nearly circular orbits.
	return a.get_orbit_semi_parameter() < b.get_orbit_semi_parameter()


static func _rebuild_selection_order() -> void:
	# Prints msec in case you're worried. Scales linearly, so should be ok
	# with many 1000s of spacecrafts.
	var usec := Time.get_ticks_usec()
	_selection_ordered_bodies.clear()
	for body_name in top_bodies:
		_add_selection_recursive(top_bodies[body_name])
	_selection_order_dirty = false
	var rebuild_msec := (Time.get_ticks_usec() - usec) / 1000.0
	print("Rebuilt IVBody selection order in %s msec" % rebuild_msec)


static func _add_selection_recursive(body: IVBody) -> void:
	_selection_ordered_bodies.append(body)
	for satellite in body.ordered_satellites:
		_add_selection_recursive(satellite)


# *****************************************************************************
# virtual


func _enter_tree() -> void:
	# Happens:
	# 1) During system build from data tables.
	# 2) During system build from game save.
	# 3) When a body changes parent, e.g., in a spacecraft trajectory. 
	const LAZY_MODEL := BodyFlags.BODYFLAGS_LAZY_MODEL
	_index()
	if is_node_ready(): # existing ready body has changed parent
		return
	if _orbit:
		_orbit.changed.connect(_on_orbit_changed)
	if flags & LAZY_MODEL and IVGlobal.program.has(&"LazyModelInitializer"):
		_lazy_model_uninited = true
	else:
		_add_body_visual()


func _exit_tree() -> void:
	_clear_indexing()


func _ready() -> void:
	# Happens once only, but could be during or after whole system build.
	IVStateManager.system_tree_built.connect(_on_system_tree_built, CONNECT_ONE_SHOT)
	IVStateManager.simulator_started.connect(_on_simulator_started, CONNECT_ONE_SHOT)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural, CONNECT_ONE_SHOT)
	IVSettingsManager.changed.connect(_settings_listener)
	_set_resources()
	_set_min_hud_dist()
	_farwarp_no_cutoff = get_inf_visibility()
	_stroboscope_rotation = randf() * TAU if _stroboscope_frame_rate else 0.0

	var process_method: StringName = characteristics.get(&"process", &"")
	var process_args: Array = characteristics.get(&"process_args", [])
	_resolve_process(process_method, process_args)

	# Below for body added after system tree is already built
	if not IVStateManager.built_system: # currently building from tables or savefile
		return
	_set_system_radius()
	_set_hill_sphere()


func _process(delta: float) -> void:
	# _process() is disabled while in sleep mode (_sleeping == true). When in
	# sleep mode, API assumes that any properties updated here are stale and
	# must be calculated.
	
	var time := _times[0]
	
	if not is_nan(begin):
		# Only here if begin was set. This is mainly for spacecraft beginning
		# and end of life (if you don't add or remove by code). Handle visual
		# orbit using orbit segment_begin and segment_end.
		# NAN-safe: 'time > NAN' is always false, so a NAN end means "no end bound".
		var is_within := not (time < begin or time > end)
		if is_within != within_lifespan:
			within_lifespan = is_within
			visible = is_within
			within_lifespan_changed.emit(is_within)
			if not is_within:
				IVGlobal.selection_invalidated.emit(name)
		if not is_within:
			return

	if _trajectory:
		time = _clamp_trajectory_time(time)
		var trajectory_orbit := _trajectory.get_orbit(time)
		if trajectory_orbit != _orbit:
			var new_parent := _trajectory.get_parent(time)
			# end_remove: discard the trajectory on reaching the final segment (one-way
			# trips in games without time reversal). Null it before the swap so the visual's
			# orbit_changed handler sees a plain orbiter and releases its trajectory ref.
			if _trajectory.end_remove and trajectory_orbit == _trajectory.orbits[-1]:
				_trajectory = null
			set_orbit_and_parent(trajectory_orbit, new_parent)
	
	if _orbit:
		position = _orbit.update(time)
	
	# Mouse-over target
	var camera_dist_signed := _world_controller.get_camera_distance_signed(self)
	var camera_dist := absf(camera_dist_signed)
	var visually_separate := true
	if !_trajectory or _trajectory.get_lca() == parent:
		visually_separate = camera_dist < position.length() * min_visual_separation_multiplier
	if visually_separate and camera_dist_signed > 0.0:
		_world_controller.update_world_target(self, camera_dist, mean_radius)
	else:
		_world_controller.remove_world_target(self)
	
	# set HUDs visibility
	var show_huds := visually_separate and camera_dist > _min_hud_dist
	if huds_visible != show_huds:
		huds_visible = show_huds
		huds_visibility_changed.emit(show_huds)

	# update model if needed
	if not body_visual:
		return

	if _process_callable.is_valid():
		# A spacecrafts.tsv 'process' method owns this body's model attitude.
		_process_callable.call(delta)
		return

	var rotation_angle: float
	if !_stroboscope_frame_rate or _tree.paused:
		rotation_angle = fposmod(time * rotation_rate, TAU)
		body_visual.basis = orientation_at_epoch.rotated(rotation_axis, rotation_angle)
		return
	
	# Stroboscope effect uses a simulated frame rate. (True frame rate doesn't matter.)
	var rotation_per_frame := rotation_rate * _times[1] / _stroboscope_frame_rate
	if absf(rotation_per_frame) < PI: # no stroboscopic effect; show true rotation
		rotation_angle = fposmod(time * rotation_rate, TAU)
		body_visual.basis = orientation_at_epoch.rotated(rotation_axis, rotation_angle)
		return
	
	var visual_rotation_per_frame := angle_difference(0.0, rotation_per_frame)
	var visual_rotation_per_second := visual_rotation_per_frame * _stroboscope_frame_rate
	delta /= Engine.time_scale # actual seconds
	_stroboscope_rotation = fposmod(_stroboscope_rotation + visual_rotation_per_second * delta, TAU)
	rotation_angle = _stroboscope_rotation
	if Engine.get_process_frames() % 2:
		# We experimented with noise and other kinds of jitter here, but a small
		# shift every other frame is the most pleasing at ~60 Hz actual frame rate.
		rotation_angle += _stroboscope_minimum_blur
		rotation_angle += _stroboscope_motion_blur * absf(visual_rotation_per_frame)
	body_visual.basis = orientation_at_epoch.rotated(rotation_axis, rotation_angle)


# *****************************************************************************
# remove

## Removes this body and all of its satellites recursively, freeing them via
## [method Node.queue_free].
func remove() -> void:
	# Pre-clear satellite containers so child exits do less work.
	var temp_satellites: Array[IVBody] = satellites.values()
	satellites.clear()
	ordered_satellites.clear()
	for satellite in temp_satellites:
		satellite.remove()
	# Deepest children exit first, each calling _clear_indexing().
	get_parent().remove_child(self)
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


## Sets or removes (when [param value] is null) a component in
## [member components]. The value must be a [code]PERSIST_PROCEDURAL[/code]
## RefCounted.
func set_component(key: StringName, value: RefCounted) -> void:
	if value == null:
		components.erase(key)
		return
	assert(&"PERSIST_MODE" in value)
	assert(value[&"PERSIST_MODE"] == IVGlobal.PERSIST_PROCEDURAL)
	components[key] = value


## Returns the component for [param key] from [member components], or null if
## absent.
func get_component(key: StringName) -> RefCounted:
	return components.get(key)


## Returns true if this body has an associated [IVOrbit] (i.e., it is not a
## top-level star).
func has_orbit() -> bool:
	return _orbit != null


## Returns the [IVOrbit] for this body, or null for a top-level star.
func get_orbit() -> IVOrbit:
	return _orbit


## Replaces this body's [IVOrbit]. Disconnects from the previous orbit's
## [signal IVOrbit.changed] and connects to the new one.
func set_orbit(new_orbit: IVOrbit) -> void:
	if _orbit:
		_orbit.changed.disconnect(_on_orbit_changed)
	_orbit = new_orbit
	if is_inside_tree(): # otherwise, connected on _enter_tree()
		new_orbit.changed.connect(_on_orbit_changed)


## Returns this body's [IVTrajectory], or null if it follows a single [member orbit].
func get_trajectory() -> IVTrajectory:
	return _trajectory


## Returns true if this body has an [IVTrajectory] (a patched-conic path of orbit
## segments) rather than a single fixed [member orbit].
func has_trajectory() -> bool:
	return _trajectory != null


## Atomically swaps this body's [IVOrbit] and reparents it under [param new_parent].
## This is the coordinated event for an [IVTrajectory] segment change; [param new_orbit]'s
## [member IVOrbit.parent_name] should name [param new_parent]. Position is recomputed
## from the new orbit later in the same [method _process] frame, so there is no visible jump.
## Emits [signal orbit_changed] so an [IVPathVisual] can switch display mode and reparent.
## When the parent actually changes, also emits [signal parent_changed] after the reparent.
func set_orbit_and_parent(new_orbit: IVOrbit, new_parent: IVBody) -> void:
	var is_reparent := new_parent != parent
	if _orbit:
		_orbit.changed.disconnect(_on_orbit_changed)
	_orbit = new_orbit # set before reparent so satellite re-indexing sorts by the new orbit
	if is_reparent:
		get_parent().remove_child(self)
		new_parent.add_child(self) # _exit_tree -> _clear_indexing; _enter_tree -> _index
	# _enter_tree's is_node_ready() guard skips the orbit reconnect on reparent, so do it here
	new_orbit.changed.connect(_on_orbit_changed)
	orbit_changed.emit(new_orbit, false, false)
	if is_reparent:
		parent_changed.emit(new_parent)


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
		&"body_class":
			return get_body_class()
		&"perspective_radius":
			return get_perspective_radius()
		&"spheroid_type":
			return get_spheroid_type()
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


func get_spheroid_type() -> int: # spheroids.tsv (intent; -1 = unspecified)
	return characteristics.get(&"spheroid_type", -1)


## Returns whether this body's model is exempt from distance culling (stars). Set
## per body via the [code]inf_visibility[/code] column (currently only in stars.tsv).
func get_inf_visibility() -> bool:
	return characteristics.get(&"inf_visibility", false)


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


# Clamps [param time] to the trajectory's validity window when this body has a
# trajectory (so it parks at the path's endpoints instead of extrapolating the
# first/last conic far off the drawn path); returns [param time] unchanged otherwise.
func _clamp_trajectory_time(time: float) -> float:
	return _trajectory.get_clamped_time(time) if _trajectory else time


# Returns the orbit governing a projected/sleeping query at [param time]: the
# trajectory's active segment for that time if this body has a trajectory, else
# the single _orbit. Callers must have already guarded against null _orbit.
func _get_orbit_at_time(time: float) -> IVOrbit:
	if _trajectory:
		return _trajectory.get_orbit(_clamp_trajectory_time(time))
	return _orbit


## Returns this body's orbital mean longitude (L). Supply [param time] only if
## you don't want the current value. 
func get_orbit_mean_longitude(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_mean_longitude_at_update()
		time = _times[0]
	time = _clamp_trajectory_time(time)
	return _get_orbit_at_time(time).get_mean_longitude(time)


## Returns this body's orbital true longitude (l). Supply [param time] only if
## you don't want the current value. 
func get_orbit_true_longitude(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_true_longitude_at_update()
		time = _times[0]
	time = _clamp_trajectory_time(time)
	return _get_orbit_at_time(time).get_true_longitude(time)


## Returns true if this body's orbit is retrograde. Supply [param time] only if
## you don't want the current value. 
func is_orbit_retrograde(time := NAN) -> bool:
	if !_orbit:
		return false
	if is_nan(time):
		if !_sleeping:
			return _orbit.is_retrograde()
		time = _times[0]
	time = _clamp_trajectory_time(time)
	return _get_orbit_at_time(time).is_retrograde_at_time(time)


## Returns this body's orbital semi-parameter (p). Supply [param time] only if
## you don't want the current value. 
func get_orbit_semi_parameter(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_semi_parameter()
		time = _times[0]
	time = _clamp_trajectory_time(time)
	return _get_orbit_at_time(time).get_semi_parameter_at_time(time)


## Returns this body's orbital semi-major axis (a). Supply [param time] only if
## you don't want the current value. 
func get_orbit_semi_major_axis(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_semi_major_axis()
		time = _times[0]
	time = _clamp_trajectory_time(time)
	return _get_orbit_at_time(time).get_semi_major_axis_at_time(time)


## Returns this body's orbital eccentricity. Supply [param time] only if you
## don't want the current value. 
func get_orbit_eccentricity(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_eccentricity()
		time = _times[0]
	time = _clamp_trajectory_time(time)
	return _get_orbit_at_time(time).get_eccentricity_at_time(time)


## Returns this body's orbital inclination. Supply [param time] only if you
## don't want the current value. 
func get_orbit_inclination(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_inclination()
		time = _times[0]
	time = _clamp_trajectory_time(time)
	return _get_orbit_at_time(time).get_inclination_at_time(time)


## Returns this body's orbital mean motion. Supply [param time] only if you
## don't want the current value. 
func get_orbit_mean_motion(time := NAN) -> float:
	if !_orbit:
		return 0.0
	if is_nan(time):
		if !_sleeping:
			return _orbit.get_mean_motion()
		time = _times[0]
	time = _clamp_trajectory_time(time)
	return _get_orbit_at_time(time).get_mean_motion_at_time(time)


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
	time = _clamp_trajectory_time(time)
	return _get_orbit_at_time(time).get_normal_at_time(time, flip_retrograde)


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
## a) maximum semi-parameter of satellites (if any),
## b) [member mean_radius] times a multiplier, or
## c) a value set in data table using field name [param system_radius].
func get_system_radius() -> float:
	return _system_radius


## See [url]https://en.wikipedia.org/wiki/Hill_sphere[/url].
## Returns INF if this body is a "top" body.
func get_hill_sphere() -> float:
	return _hill_sphere


## Returns a basis that rotates with the ground (i.e, with the body model).
## Supply [param time] only if you don't want the current value.
func get_orientation(time := NAN) -> Basis:
	if is_nan(time):
		if body_visual and !_sleeping:
			return body_visual.basis
		time = _times[0]
	var rotation_angle := wrapf(time * rotation_rate, 0.0, TAU)
	return orientation_at_epoch.rotated(rotation_axis, rotation_angle)


## Returns a valid current or projected position at [param time] as a 32-bit [Vector3]
## (graphics idiom; see [method get_translation] for orbit precision). Valid even while
## sleeping (unlike [member Node3D.position]). Supply [param time] only if you don't want
## the current value.
func get_position_vector(time := NAN) -> Vector3:
	if is_nan(time):
		if !_sleeping:
			return position
		time = _times[0]
	if _orbit:
		var orbit_time := _clamp_trajectory_time(time)
		return _get_orbit_at_time(orbit_time).get_position_vector(orbit_time)
	# TODO: "top" bodies may have position and velocity eventually,
	# probably as fixed values relative to galaxy center.
	return Vector3.ZERO


## Returns a valid current or projected orbit-precision translation [x, y, z] (64-bit
## [PackedFloat64Array]) at [param time], relative to the parent. Valid even while sleeping.
## Supply [param time] only if you don't want the current value. See also
## [method get_position_vector] (32-bit).
func get_translation(time := NAN) -> PackedFloat64Array:
	if is_nan(time):
		time = _times[0]
	if _orbit:
		var orbit_time := _clamp_trajectory_time(time)
		return _get_orbit_at_time(orbit_time).get_translation(orbit_time)
	# TODO: "top" bodies may have position and velocity eventually,
	# probably as fixed values relative to galaxy center.
	return PackedFloat64Array([0.0, 0.0, 0.0])


## Returns this body's orbit-precision translation [x, y, z] (size-3 [PackedFloat64Array])
## in [param ancestor]'s frame at [param time], summed up the parent chain. IVBody nodes are
## never rotated/scaled, so frame conversion is pure vector addition. If [param ancestor] is
## not on the parent chain, sums to the top body (best effort).
func get_translation_to_ancestor(ancestor: IVBody, time := NAN) -> PackedFloat64Array:
	var offset := PackedFloat64Array([0.0, 0.0, 0.0])
	var node := self
	while node and node != ancestor:
		var translation := node.get_translation(time)
		offset[0] += translation[0]
		offset[1] += translation[1]
		offset[2] += translation[2]
		node = node.parent
	return offset


## Returns current or projected [code][position, velocity][/code] at [param time] as a
## 32-bit [PackedVector3Array] (graphics idiom; see [method get_state] for orbit precision).
## Valid even while sleeping. Supply [param time] only if you don't want the current value.
func get_state_vectors(time := NAN) -> PackedVector3Array:
	if is_nan(time):
		time = _times[0]
	if _orbit:
		var orbit_time := _clamp_trajectory_time(time)
		return _get_orbit_at_time(orbit_time).get_state_vectors(orbit_time)
	# TODO: "top" bodies may have position and velocity eventually,
	# probably as fixed values relative to galaxy center.
	return PackedVector3Array([Vector3.ZERO, Vector3.ZERO])


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
	# Orbit normal parks at the window endpoints (get_orbit_normal clamps the time);
	# the spin axis keeps its raw-time value since rotation is independent of the trajectory.
	var orbit_normal := get_orbit_normal(time)
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
	time = _clamp_trajectory_time(time)
	var active_orbit := _get_orbit_at_time(time)
	x_axis = -active_orbit.get_position_vector(time).normalized()
	z_axis = active_orbit.get_normal_at_time(time, true, true)
	y_axis = z_axis.cross(x_axis)
	return Basis(x_axis, y_axis, z_axis)


# *****************************************************************************
# IVCamera duck-type methods...

func get_camera_radius() -> float:
	return mean_radius


func get_camera_ground_basis() -> Basis:
	return get_orientation()


# FIXME: Do we need get_orbit_tracking_basis()? This is very camera-specific.
func get_camera_orbit_basis() -> Basis:
	var orbit_basis := get_orbit_tracking_basis()
	if flags & BodyFlags.BODYFLAGS_STAR_ORBITER:
		return orbit_basis.rotated(orbit_basis.z, PI)
	return orbit_basis


func get_camera_lat_lon_type() -> IVQFormat.LatitudeLongitudeType:
	const N_S_E_W := IVQFormat.LatitudeLongitudeType.N_S_E_W
	const LAT_LON := IVQFormat.LatitudeLongitudeType.LAT_LON
	const PITCH_YAW := IVQFormat.LatitudeLongitudeType.PITCH_YAW
	if flags & BodyFlags.BODYFLAGS_USE_CARDINAL_DIRECTIONS:
		return N_S_E_W
	if flags & BodyFlags.BODYFLAGS_USE_PITCH_YAW:
		return PITCH_YAW
	return LAT_LON


# *****************************************************************************
# IVSelectionManager duck-type methods...

## Returns parent, or null if this is a "top" body in the tree.
func get_selection_up() -> IVBody:
	return parent


## Returns first satellite (child IVBody) ordered by semi-parameter, or null if
## none exist.
func get_selection_down() -> IVBody:
	if ordered_satellites:
		return ordered_satellites[0]
	return null


## Returns next IVBody in tree. Satellites (child IVBodies) always follow after
## parent, ordered by semi-parameter.
func get_selection_next() -> IVBody:
	if _selection_order_dirty:
		_rebuild_selection_order()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos + 1
	if pos < _selection_ordered_bodies.size():
		return _selection_ordered_bodies[pos]
	pos = 0
	if pos < self_pos:
		return _selection_ordered_bodies[pos]
	return null


## Reverse of [method get_selection_next].
func get_selection_last() -> IVBody:
	if _selection_order_dirty:
		_rebuild_selection_order()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos - 1
	if pos >= 0:
		return _selection_ordered_bodies[pos]
	pos = _selection_ordered_bodies.size() - 1
	if pos > self_pos:
		return _selection_ordered_bodies[pos]
	return null


## Returns the next star in the tree.
func get_selection_next_star() -> IVBody:
	const STAR := BodyFlags.BODYFLAGS_STAR
	if _selection_order_dirty:
		_rebuild_selection_order()
	var size := _selection_ordered_bodies.size()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos + 1
	while pos < size:
		if _selection_ordered_bodies[pos].flags & STAR:
			return _selection_ordered_bodies[pos]
		pos += 1
	pos = 0
	while pos < self_pos:
		if _selection_ordered_bodies[pos].flags & STAR:
			return _selection_ordered_bodies[pos]
		pos += 1
	return null


## Reverse of [method get_selection_next_star].
func get_selection_last_star() -> IVBody:
	const STAR := BodyFlags.BODYFLAGS_STAR
	if _selection_order_dirty:
		_rebuild_selection_order()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos - 1
	while pos >= 0:
		if _selection_ordered_bodies[pos].flags & STAR:
			return _selection_ordered_bodies[pos]
		pos -= 1
	pos = _selection_ordered_bodies.size() - 1
	while pos > self_pos:
		if _selection_ordered_bodies[pos].flags & STAR:
			return _selection_ordered_bodies[pos]
		pos -= 1
	return null


## Returns the next planet or dwarf planet in the tree.
func get_selection_next_planet() -> IVBody:
	const PLANET_OR_DWARF_PLANET := BodyFlags.BODYFLAGS_PLANET_OR_DWARF_PLANET
	if _selection_order_dirty:
		_rebuild_selection_order()
	var size := _selection_ordered_bodies.size()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos + 1
	while pos < size:
		if _selection_ordered_bodies[pos].flags & PLANET_OR_DWARF_PLANET:
			return _selection_ordered_bodies[pos]
		pos += 1
	pos = 0
	while pos < self_pos:
		if _selection_ordered_bodies[pos].flags & PLANET_OR_DWARF_PLANET:
			return _selection_ordered_bodies[pos]
		pos += 1
	return null


## Reverse of [method get_selection_next_planet].
func get_selection_last_planet() -> IVBody:
	const PLANET_OR_DWARF_PLANET := BodyFlags.BODYFLAGS_PLANET_OR_DWARF_PLANET
	if _selection_order_dirty:
		_rebuild_selection_order()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos - 1
	while pos >= 0:
		if _selection_ordered_bodies[pos].flags & PLANET_OR_DWARF_PLANET:
			return _selection_ordered_bodies[pos]
		pos -= 1
	pos = _selection_ordered_bodies.size() - 1
	while pos > self_pos:
		if _selection_ordered_bodies[pos].flags & PLANET_OR_DWARF_PLANET:
			return _selection_ordered_bodies[pos]
		pos -= 1
	return null


## Returns the next "major" moon in the tree. Major in this contexts means it
## is a moon with BODYFLAGS_SHOW_IN_NAVIGATION_PANEL.
func get_selection_next_major_moon() -> IVBody:
	const NAV_MOON := BodyFlags.BODYFLAGS_SHOW_IN_NAVIGATION_PANEL | BodyFlags.BODYFLAGS_MOON
	if _selection_order_dirty:
		_rebuild_selection_order()
	var size := _selection_ordered_bodies.size()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos + 1
	while pos < size:
		if _selection_ordered_bodies[pos].flags & NAV_MOON == NAV_MOON:
			return _selection_ordered_bodies[pos]
		pos += 1
	pos = 0
	while pos < self_pos:
		if _selection_ordered_bodies[pos].flags & NAV_MOON == NAV_MOON:
			return _selection_ordered_bodies[pos]
		pos += 1
	return null


## Reverse of [method get_selection_next_major_moon].
func get_selection_last_major_moon() -> IVBody:
	const NAV_MOON := BodyFlags.BODYFLAGS_SHOW_IN_NAVIGATION_PANEL | BodyFlags.BODYFLAGS_MOON
	if _selection_order_dirty:
		_rebuild_selection_order()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos - 1
	while pos >= 0:
		if _selection_ordered_bodies[pos].flags & NAV_MOON == NAV_MOON:
			return _selection_ordered_bodies[pos]
		pos -= 1
	pos = _selection_ordered_bodies.size() - 1
	while pos > self_pos:
		if _selection_ordered_bodies[pos].flags & NAV_MOON == NAV_MOON:
			return _selection_ordered_bodies[pos]
		pos -= 1
	return null


## Returns the next moon in the tree.
func get_selection_next_moon() -> IVBody:
	const MOON := BodyFlags.BODYFLAGS_MOON
	if _selection_order_dirty:
		_rebuild_selection_order()
	var size := _selection_ordered_bodies.size()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos + 1
	while pos < size:
		if _selection_ordered_bodies[pos].flags & MOON:
			return _selection_ordered_bodies[pos]
		pos += 1
	pos = 0
	while pos < self_pos:
		if _selection_ordered_bodies[pos].flags & MOON:
			return _selection_ordered_bodies[pos]
		pos += 1
	return null


## Reverse of [method get_selection_next_moon].
func get_selection_last_moon() -> IVBody:
	const MOON := BodyFlags.BODYFLAGS_MOON
	if _selection_order_dirty:
		_rebuild_selection_order()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos - 1
	while pos >= 0:
		if _selection_ordered_bodies[pos].flags & MOON:
			return _selection_ordered_bodies[pos]
		pos -= 1
	pos = _selection_ordered_bodies.size() - 1
	while pos > self_pos:
		if _selection_ordered_bodies[pos].flags & MOON:
			return _selection_ordered_bodies[pos]
		pos -= 1
	return null


## Returns the next spacecraft in the tree.
func get_selection_next_spacecraft() -> IVBody:
	const SPACECRAFT := BodyFlags.BODYFLAGS_SPACECRAFT
	if _selection_order_dirty:
		_rebuild_selection_order()
	var size := _selection_ordered_bodies.size()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos + 1
	while pos < size:
		if _selection_ordered_bodies[pos].flags & SPACECRAFT:
			return _selection_ordered_bodies[pos]
		pos += 1
	pos = 0
	while pos < self_pos:
		if _selection_ordered_bodies[pos].flags & SPACECRAFT:
			return _selection_ordered_bodies[pos]
		pos += 1
	return null


## Reverse of [method get_selection_next_spacecraft].
func get_selection_last_spacecraft() -> IVBody:
	const SPACECRAFT := BodyFlags.BODYFLAGS_SPACECRAFT
	if _selection_order_dirty:
		_rebuild_selection_order()
	var self_pos := _selection_ordered_bodies.find(self)
	assert(self_pos >= 0)
	var pos := self_pos - 1
	while pos >= 0:
		if _selection_ordered_bodies[pos].flags & SPACECRAFT:
			return _selection_ordered_bodies[pos]
		pos -= 1
	pos = _selection_ordered_bodies.size() - 1
	while pos > self_pos:
		if _selection_ordered_bodies[pos].flags & SPACECRAFT:
			return _selection_ordered_bodies[pos]
		pos -= 1
	return null


# *****************************************************************************
# For GUI...


func get_periapsis_label() -> StringName:
	if parent:
		if parent.name == &"STAR_SUN":
			return &"LABEL_PERIHELION"
		if parent.name == &"PLANET_EARTH":
			return &"LABEL_PERIGEE"
	return &"LABEL_PERIAPSIS"


func get_apoapsis_label() -> StringName:
	if parent:
		if parent.name == &"STAR_SUN":
			return &"LABEL_APHELION"
		if parent.name == &"PLANET_EARTH":
			return &"LABEL_APOGEE"
	return &"LABEL_APOAPSIS"


# *****************************************************************************
# core mechanics...


## Adds [param satellite] to this body's [member satellites] and [member
## ordered_satellites].
func index_satellite(satellite: IVBody) -> void:
	assert(!satellites.has(satellite.name))
	satellites[satellite.name] = satellite
	# Note: Most adds are in order due to data table construction, and more so
	# for game loads due to _resort_child_bodies(). So we usually avoid
	# the expensive binary search and non-end array insert here.
	var ordered_index := 0
	if ordered_satellites:
		if _is_ordered_satellites(ordered_satellites[-1], satellite):
			ordered_index = ordered_satellites.size()
		else:
			ordered_index = ordered_satellites.bsearch_custom(satellite, _is_ordered_satellites)
	ordered_satellites.insert(ordered_index, satellite)


## Removes [param satellite] from this body's [member satellites] and [member
## ordered_satellites].
func unindex_satellite(satellite: IVBody) -> void:
	satellites.erase(satellite.name)
	ordered_satellites.erase(satellite)


## Adds a child Node3D to this body's [IVBodyVisual]. Use for nodes that need to
## share the model's orientation and rotation in space, but not its scale. Used
## by [IVRings] (e.g., Saturn's Rings).
func add_child_to_body_visual(node3d: Node3D) -> void:
	if !body_visual:
		_add_body_visual()
	body_visual.add_child(node3d)


## Removes a child Node3D from this body's [IVBodyVisual]. See [method add_child_to_body_visual].
func remove_child_from_body_visual(node3d: Node3D) -> void:
	body_visual.remove_child(node3d)


## Removes model(s) but everything else remains (label & orbit HUDs, etc.).
func remove_and_disable_body_visual() -> void:
	flags |= BodyFlags.BODYFLAGS_DISABLE_MODEL_SPACE
	if farwarp_space:
		farwarp_space.queue_free() # frees body_visual with it
	farwarp_space = null
	body_visual = null


## Returns true if this body has [member BodyFlags.BODYFLAGS_LAZY_MODEL] set
## and a model has not been inited yet. 
func is_lazy_model_uninited() -> bool:
	return _lazy_model_uninited


## Use to init a lazy model, if needed. Normally called by [IVLazyModelInitializer].
func lazy_model_init() -> void:
	_add_body_visual()


## Called by [IVFarwarpManager] once per frame AFTER the camera has moved and
## origin-shifted the Universe, so the world-space (top_level) placements of
## [member farwarp_space] and [member farwarp_position] land in the frame's
## final coordinates. A placement computed before the origin shift is one frame
## of camera world-motion behind, which reads as violent shake on fast nearby
## orbiters and off-center models during fast camera rotation. With
## [param farwarp_start] <= 0.0 (no camera), places visuals at true positions.
func update_farwarp(camera_global_position: Vector3, farwarp_start: float) -> void:
	var camera_vector := global_position - camera_global_position
	var farwarp_dist := camera_vector.length()
	var factor := IVFarwarpManager.get_farwarp_factor(farwarp_dist, farwarp_start)
	# Assembled camera-relative: scaling the true-scale vector keeps float32
	# rounding proportional to the compressed distance (origin shifting keeps
	# camera_global_position small). Never derive this by offsetting true-scale
	# positions - the rounding of the large terms swamps the small result.
	farwarp_position = camera_global_position + camera_vector * factor
	if !farwarp_space:
		return
	if factor != 1.0 and (_farwarp_no_cutoff
			or mean_radius > farwarp_dist * IVFarwarpManager.angular_cutoff):
		farwarp_space.position = farwarp_position
		farwarp_space.basis = Basis.from_scale(factor * Vector3.ONE)
	else:
		# Not remapped: track the true global position (top_level node doesn't
		# follow this body). Sub-cutoff models beyond the far plane are
		# distance-culled; the always-remapped HUD symbol represents the body.
		farwarp_space.position = global_position
		farwarp_space.basis = Basis.IDENTITY


## Current sleeping state. See [IVSleepManager].
func is_sleeping() -> bool:
	return _sleeping


## Set sleep state. Only [IVSleepManager] or appropriate replacement class or
## code should call this.
func set_sleeping(sleep: bool, show_hide := true) -> void:
	const CAN_SLEEP := BodyFlags.BODYFLAGS_CAN_SLEEP
	if _sleeping == sleep or !(flags & CAN_SLEEP):
		return
	_sleeping = sleep
	set_process(not sleep)
	if show_hide:
		visible = not sleep
	if sleep:
		_world_controller.remove_world_target(self)
		if huds_visible:
			huds_visible = false
			huds_visibility_changed.emit(false)
	sleep_changed.emit(sleep)


## Used for mouse-over identification of this body's orbit visual.
func get_fragment_data(_fragment_type: int) -> Array:
	# Only FRAGMENT_BODY_ORBIT at this time.
	return [get_instance_id()]


## Used for mouse-over identification of this body's orbit visual.
func get_fragment_text(_data: Array) -> String:
	# Only FRAGMENT_BODY_ORBIT at this time.
	return tr(name) + " (" + tr("LABEL_ORBIT").to_lower() + ")"


## Reorder this body's satellites after a satellite major orbit change
## (specifically in semi-parameter). This isn't strictly needed; the main effect
## is to fix GUI selection order for "next", "next_spacecraft", etc.
func resort_satellites() -> void:
	ordered_satellites.sort_custom(_is_ordered_satellites)
	_resort_child_bodies()
	_selection_order_dirty = true


# *****************************************************************************
# private

func _clear_procedural() -> void:
	if _orbit:
		_orbit.changed.disconnect(_on_orbit_changed)
	_trajectory = null # stop _process touching it; IVTrajectory clears itself on the same signal
	parent = null
	star = null
	star_orbiter = null
	body_visual = null
	farwarp_space = null
	satellites.clear()
	ordered_satellites.clear()
	# static re-clearing is redundant but not expensive
	bodies.clear()
	top_bodies.clear()
	_selection_ordered_bodies.clear()
	_selection_order_dirty = true


func _on_system_tree_built(is_new_game: bool) -> void:
	const TIDALLY_LOCKED := BodyFlags.BODYFLAGS_TIDALLY_LOCKED
	_resort_child_bodies()
	if !is_new_game:
		return
	# persisted data needed for new game only...
	if characteristics.has(&"trajectory"):
		var trajectory_name: StringName = characteristics[&"trajectory"]
		_trajectory = IVTrajectory.create_from_table(trajectory_name)
	_set_system_radius()
	_set_hill_sphere()
	if flags & TIDALLY_LOCKED:
		_update_rotations(true)


func _on_simulator_started() -> void:
	# Paused game load hack. Top IVBody and decendents (including IVCamera)
	# need to process 1 frame to get positions and visuals right.
	if not (flags & BodyFlags.BODYFLAGS_TOP):
		return # only TOP needed assuming others inherit
	if not _tree.paused:
		return
	if process_mode != PROCESS_MODE_INHERIT:
		return # hackery not needed or won't work
	if get_parent_node_3d().process_mode == PROCESS_MODE_ALWAYS:
		return # hackery not needed
	process_mode = PROCESS_MODE_ALWAYS
	await _tree.process_frame # 1 frame is enough!
	process_mode = PROCESS_MODE_INHERIT


func _index() -> void:
	# For multi-star system, a star could be a star orbiter.
	const TOP := BodyFlags.BODYFLAGS_TOP
	const STAR := BodyFlags.BODYFLAGS_STAR
	const STAR_ORBITER := BodyFlags.BODYFLAGS_STAR_ORBITER
	assert(not bodies.has(name))
	bodies[name] = self
	if flags & TOP:
		top_bodies[name] = self
	parent = get_parent_node_3d() as IVBody # null only for top bodies
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
		parent.index_satellite(self)
	_selection_ordered_bodies.clear()
	_selection_order_dirty = true


func _clear_indexing() -> void:
	const TOP := BodyFlags.BODYFLAGS_TOP
	assert(not satellites)
	assert(not ordered_satellites)
	bodies.erase(name)
	if flags & TOP:
		top_bodies.erase(name)
	if parent:
		parent.unindex_satellite(self)
		parent = null
	star = null
	star_orbiter = null
	_selection_ordered_bodies.clear()
	_selection_order_dirty = true


func _resort_child_bodies() -> void:
	# Not necessary, but neatens the tree in editor run. It also
	# makes index_satellite() marginally faster on subsequent game load after 
	# save. It's not expected to affect anything else. Children will go out of
	# order during session if orbits change dramatically or bodies change
	# parantage -- e.g., spacecrafts moving around.
	for i in ordered_satellites.size():
		var satellite := ordered_satellites[i]
		move_child(satellite, i)


func _set_resources() -> void:
	var asset_preloader: IVAssetPreloader = IVGlobal.program[&"AssetPreloader"]
	texture_2d = asset_preloader.get_body_texture_2d(name)
	texture_slice_2d = asset_preloader.get_body_texture_slice_2d(name) # usually null


func _set_min_hud_dist() -> void:
	if !IVSettingsManager.get_setting(&"hide_hud_when_close"):
		_min_hud_dist = 0.0
		return
	_min_hud_dist = mean_radius * min_hud_dist_radius_multiplier
	if flags & BodyFlags.BODYFLAGS_STAR:
		_min_hud_dist *= min_hud_dist_star_multiplier # star grows at distance


func _set_system_radius() -> void:
	var system_radius := mean_radius * system_mean_radius_multiplier
	if characteristics.get(&"system_radius", 0.0) > system_radius:
		system_radius = characteristics[&"system_radius"]
	if ordered_satellites:
		_system_radius = maxf(_system_radius, ordered_satellites[-1].get_orbit_semi_parameter())


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


func _add_body_visual() -> void:
	const DISABLE_MODEL_SPACE := BodyFlags.BODYFLAGS_DISABLE_MODEL_SPACE
	assert(!body_visual)
	_lazy_model_uninited = false
	if flags & DISABLE_MODEL_SPACE:
		return
	var e_radius := get_equatorial_radius()
	if replacement_body_visual_class:
		@warning_ignore("unsafe_method_access")
		body_visual = replacement_body_visual_class.new(name, mean_radius, e_radius, get_spheroid_type())
	else:
		body_visual = IVBodyVisual.new(name, mean_radius, e_radius, get_spheroid_type())
	farwarp_space = Node3D.new()
	farwarp_space.name = &"FarwarpSpace"
	# World-space placement (see farwarp_space doc); an inert identity child
	# when farwarp is disabled.
	farwarp_space.top_level = IVCoreSettings.apply_farwarp
	farwarp_space.add_child(body_visual)
	add_child(farwarp_space)


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"hide_hud_when_close":
		_set_min_hud_dist()


# *****************************************************************************
# model attitude 'process' methods

# The spacecrafts.tsv 'process' field names one of the methods below, called every
# frame as method(delta, ...process_args) via _process_callable to drive a bespoke
# model attitude in place of the default axial rotation in _process(). Mirrors the
# IVSpheroidModel 'process' mechanism. Per the table-method convention these methods
# may reference bodies by name (&"PLANET_EARTH", &"STAR_SUN") and must convert any
# unit-tagged argument in-method, since the table cannot specify a unit for a VARIANT.
# All operate on body_visual.basis, which is a world-oriented frame because IVBody
# nodes are never rotated; the model-frame axis arguments are tunable per body.

func _resolve_process(method: StringName, process_args: Array) -> void:
	if not method:
		return
	if not has_method(method):
		push_warning("Body %s: 'process' names unknown method '%s'" % [name, method])
		return
	_process_callable = Callable(self, method).bindv(process_args)


## Named by a 'process' field (spacecrafts.tsv). Aims the model's [param boresight_axis]
## (model frame) at Earth, rolling so [param up_axis] (model frame) stays near ecliptic
## north — a deep-space craft holding its high-gain antenna on Earth (Pioneer, Voyager,
## New Horizons).
func _earth_pointing(_delta: float, boresight_axis: Vector3, up_axis: Vector3) -> void:
	const ECLIPTIC_NORTH := Vector3(0, 0, 1)
	var earth: IVBody = bodies.get(&"PLANET_EARTH")
	if not earth:
		return
	var to_earth := earth.global_position - global_position
	if to_earth.is_zero_approx():
		return
	body_visual.basis = IVMath.get_alignment_basis(boresight_axis, up_axis, to_earth, ECLIPTIC_NORTH)


## Named by a 'process' field (spacecrafts.tsv). Aims the model's [param spin_axis]
## (model frame) at the Sun and spins the model about it once per [param spin_period_days]
## — a spin-stabilized, solar-powered craft (Juno).
func _sun_pointing(_delta: float, spin_axis: Vector3, spin_period_days: float) -> void:
	const ECLIPTIC_NORTH := Vector3(0, 0, 1)
	var sun: IVBody = bodies.get(&"STAR_SUN")
	if not sun:
		return
	var to_sun := sun.global_position - global_position
	if to_sun.is_zero_approx():
		return
	to_sun = to_sun.normalized()
	var base := IVMath.get_alignment_basis(spin_axis, Vector3(1, 0, 0), to_sun, ECLIPTIC_NORTH)
	var spin_rate := TAU / (spin_period_days * IVUnits.DAY) # turns/day -> internal rad/s
	body_visual.basis = base.rotated(to_sun, fposmod(_times[0] * spin_rate, TAU))


## Named by a 'process' field (spacecrafts.tsv). Holds a nadir-locked LVLH attitude:
## [param nadir_axis] (model frame) points at Earth's center and [param forward_axis]
## (model frame) tracks the orbital velocity, so the station keeps the same face toward
## Earth (ISS).
func _process_iss(_delta: float, forward_axis: Vector3, nadir_axis: Vector3) -> void:
	var lvlh := get_orbit_tracking_basis() # world: x = nadir, y = along-track, z = orbit normal
	body_visual.basis = IVMath.get_alignment_basis(nadir_axis, forward_axis, lvlh.x, lvlh.y)


## Named by a 'process' field (spacecrafts.tsv). Holds an inertial attitude that slews
## slowly about [param slew_axis] (world frame) at [param slew_deg_per_day] — a space
## telescope holding and re-pointing a celestial aim rather than tracking Earth (Hubble).
func _process_hubble(_delta: float, slew_axis: Vector3, slew_deg_per_day: float) -> void:
	const CONVERSION := IVUnits.DEG / IVUnits.DAY # deg/day -> internal rad/s
	var slew_rate := slew_deg_per_day * CONVERSION
	body_visual.basis = Basis(slew_axis.normalized(), fposmod(_times[0] * slew_rate, TAU))
