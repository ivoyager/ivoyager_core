# trajectory.gd
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
class_name IVTrajectory
extends RefCounted

## An ordered set of [IVOrbit] segments forming a patched-conic trajectory.
##
## A trajectory is fully specified by [member orbits]: an ordered, time-contiguous
## array of conic segments, each about a (possibly different) gravitational primary
## named by [member IVOrbit.parent_name] and valid over [member IVOrbit.segment_begin]
## to [member IVOrbit.segment_end]. An [IVBody] that has a trajectory autonomously
## swaps its [member IVBody.orbit] and tree parent to the active segment as time
## changes; see [method IVBody.set_orbit_and_parent].[br][br]
##
## Everything except [member orbits] is derived and not persisted. [member path] is
## a single connected polyline of the whole trajectory expressed in the [member lca]
## (lowest-common-ancestor) frame, suitable for [IVPathVisual]. Derived data is
## (re)built by the static creators (new game) or on [signal IVStateManager.game_loaded]
## (loaded game), at which point all segment primaries exist in [member IVBody.bodies].[br][br]
##
## WARNING: derived data holds [IVBody] references ([member lca], the per-segment
## primaries), forming an [IVBody]↔[IVTrajectory] reference cycle. The cycle is
## broken by clearing those references on [signal IVStateManager.about_to_free_procedural_nodes].


const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"orbits",
	&"visual_orbits",
	&"end_remove",
]

# Gap-fixing tunables (see [method _fix_gaps]); applied as multiples of the IVUnits
# scale constants at runtime so they stay correct regardless of the sim's METER scale.
const GAP_SKIP_KM := 100.0 ## Cruise gap below this (× IVUnits.KM) is left as authored.
const GAP_WARN_AU := 0.1 ## Cruise gap above this (× IVUnits.AU) is still re-fitted, but logged.
const OPEN_TERMINAL_LOOKAHEAD_YEARS := 5.0 ## Far Lambert-point look-ahead for an open terminal cruise.


# persisted

## Ordered, time-contiguous conic segments. Segment [code]i[/code] is active for time in
## [code][segment_begin, segment_end)[/code]. The first segment's begin and the last
## segment's end may be finite (e.g. a launch time): for times outside that overall
## window the body parks at the nearest path endpoint instead of extrapolating (see
## [method get_clamped_time]); use -INF/INF for an open-ended window. To define
## a corresponding spacecraft beginning- and end-of-life, see [member IVBody.begin] and
## [member IVBody.end]
var orbits: Array[IVOrbit] = []
## Segment indexes drawn with the normal orbit visual (in the body's own parent frame)
## while the body is in them and omitted from the trajectory polyline, instead of being
## drawn as part of the trajectory. A negative index counts from the end, so
## [code][0, -1][/code] marks the first and last segments (a launch parking orbit and a
## capture orbit). Empty (the default) draws every segment as part of the trajectory.
## See [method is_orbit_segment].
var visual_orbits: Array[int] = []
## If true, on reaching the last segment the body switches to the normal orbit visual
## and then discards the trajectory, reverting to a plain orbiter.
var end_remove: bool

# derived

## Connected state path of the whole trajectory in the [member lca] frame (ecliptic basis), as
## flat orbit-precision stride-7 knots [x, y, z, vx, vy, vz, t]: position, velocity (the Hermite
## tangent used by [IVPathVisual]), and passage time (s). Derived from [member orbits];
## consumed by [IVPathVisual].
var path: PackedFloat64Array
## Lowest common ancestor (in the [IVBody] tree) of all segment primaries. This is
## the frame in which [member path] is expressed and the correct scene-tree parent
## for an [IVPathVisual] of this trajectory.
var lca: IVBody

var _segment_parents: Array[IVBody] = [] # primary IVBody per segment, parallel to orbits
var _boundaries: PackedFloat64Array # interior segment-begin times, ascending, for bsearch
var _cached_index := 0


# *****************************************************************************
# static creators

## Creates an [IVTrajectory] from an ordered, time-contiguous array of [IVOrbit]
## segments. Each segment's [member IVOrbit.parent_name] must name a body present
## in [member IVBody.bodies]. [param visual_orbits] and [param end_remove] set the
## same-named members (see [member visual_orbits] and [method is_orbit_segment]).
@warning_ignore("shadowed_variable")
static func create(orbits: Array[IVOrbit], visual_orbits: Array[int] = [],
		end_remove := true) -> IVTrajectory:
	assert(!orbits.is_empty(), "IVTrajectory requires at least one orbit segment")
	for i in range(1, orbits.size()):
		assert(orbits[i].segment_begin >= orbits[i - 1].segment_begin,
				"IVTrajectory segments must be ordered by segment_begin")
	var trajectory := IVTrajectory.new()
	trajectory.orbits = orbits
	trajectory.visual_orbits = visual_orbits
	trajectory.end_remove = end_remove
	trajectory._build_derived(true)
	return trajectory


## Creates an [IVTrajectory] from row [param trajectory_name] of trajectories.tsv,
## building each segment from its referenced orbits.tsv row. Named segment parents
## must already exist in [member IVBody.bodies] (so call after the system tree is built).
static func create_from_table(trajectory_name: StringName) -> IVTrajectory:
	var trajectory_row := IVTableData.get_row(trajectory_name)
	assert(trajectory_row != -1, "No trajectories.tsv row named '%s'" % trajectory_name)
	var orbit_rows: Array[int] = IVTableData.get_db_array(&"trajectories", &"orbits", trajectory_row)
	var table_orbit_builder: IVTableOrbitBuilder = IVGlobal.program[&"TableOrbitBuilder"]
	var segment_orbits: Array[IVOrbit] = []
	for orbit_row in orbit_rows:
		var parent_name := IVTableData.get_db_string_name(&"orbits", &"parent", orbit_row)
		assert(IVBody.bodies.has(parent_name),
				"Trajectory segment parent '%s' not found in IVBody.bodies" % parent_name)
		var parent: IVBody = IVBody.bodies[parent_name]
		segment_orbits.append(table_orbit_builder.make_orbit_from_orbit_row(orbit_row, parent))
	var visual_orbit_indexes: Array[int] = IVTableData.get_db_array(&"trajectories", &"visual_orbits",
			trajectory_row)
	return create(segment_orbits, visual_orbit_indexes,
			IVTableData.get_db_bool(&"trajectories", &"end_remove", trajectory_row))


# *****************************************************************************
# Virtual

func _init() -> void:
	# Rebuild derived data after a load (orbits are restored by then). Clear IVBody
	# references before teardown to break the IVBody<->IVTrajectory cycle.
	IVStateManager.game_loaded.connect(_build_derived.bind(false))
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)


# *****************************************************************************
# API

## Returns the active orbit segment for [param time]. Never null: out-of-range times
## clamp to the first or last segment (the segment index is always in bounds). This
## selects the segment only; callers clamp the evaluation time (see
## [method get_clamped_time]) to park a body at the endpoints instead of extrapolating.
func get_orbit(time: float) -> IVOrbit:
	return orbits[_get_index(time)]


## Returns the gravitational primary [IVBody] of the active segment for [param time].
func get_parent(time: float) -> IVBody:
	return _segment_parents[_get_index(time)]


## Returns the lowest-common-ancestor [IVBody] whose frame [member path] is expressed
## in. This is the correct scene-tree parent for an [IVPathVisual] of this trajectory.
func get_lca() -> IVBody:
	return lca


## Returns true if segment [param index] should be drawn as a standalone orbit (a
## parking/capture orbit shown with the normal orbit visual in the body's own parent
## frame) rather than as part of the trajectory polyline. Driven by [member visual_orbits]
## (any segment) and [member end_remove] (which forces the last segment). [IVPathVisual]
## uses this both to choose its display mode and to omit these segments from the polyline.
func is_orbit_segment(index: int) -> bool:
	if end_remove and index == orbits.size() - 1:
		return true
	# visual_orbits may use negative indexes counting from the end (e.g. -1 == last segment)
	return visual_orbits.has(index) or visual_orbits.has(index - orbits.size())


## Clamps [param time] to this trajectory's validity window: the first segment's
## [member IVOrbit.segment_begin] to the last segment's [member IVOrbit.segment_end].
## A body uses this so that, outside the window, it parks at the path's endpoint
## instead of extrapolating the first/last conic far off the drawn path. Outer
## bounds of -INF/INF (the defaults) impose no clamp.
func get_clamped_time(time: float) -> float:
	return clampf(time, orbits[0].segment_begin, orbits[-1].segment_end)


## Returns flat orbit-precision stride-7 state-path knots [x, y, z, vx, vy, vz, t] (size
## 7 * [param times].size()) for segment [param index] evaluated at the ascending [param times],
## expressed in the [member lca] frame. Used by [method _build_path] to fill [member path] one
## segment at a time.
func sample_segment_states_lca(index: int, times: PackedFloat64Array) -> PackedFloat64Array:
	var n_knots := times.size()
	var states := PackedFloat64Array()
	states.resize(7 * n_knots)
	for j in n_knots:
		var time := times[j]
		var position := _segment_position_lca(index, time)
		var velocity := _segment_velocity_lca(index, time)
		var base := 7 * j
		states[base] = position[0]
		states[base + 1] = position[1]
		states[base + 2] = position[2]
		states[base + 3] = velocity[0]
		states[base + 4] = velocity[1]
		states[base + 5] = velocity[2]
		states[base + 6] = time
	return states


## Returns the drawn transfer segments as a list of state-path sub-paths, each a flat
## orbit-precision [PackedFloat64Array] of stride-7 knots [x, y, z, vx, vy, vz, t] in the
## [member lca] frame, sliced from [member path]. Parking/capture segments
## ([method is_orbit_segment]) are omitted — they render as standalone orbits while the body
## is in them. Each sub-path is smoothed independently ([IVPathVisual]): velocity is
## discontinuous at patch points, so a single Hermite must not span two segments.
func get_display_state_paths() -> Array[PackedFloat64Array]:
	var sub_paths: Array[PackedFloat64Array] = []
	var n_segments := orbits.size()
	if n_segments == 0 or path.is_empty():
		return sub_paths
	@warning_ignore("integer_division") # path is exactly n_segments * vertecies_per_trajectory_segment knots
	var chunk := path.size() / n_segments # floats per segment (7 * knots)
	for i in n_segments:
		if is_orbit_segment(i):
			continue
		sub_paths.append(path.slice(i * chunk, (i + 1) * chunk))
	return sub_paths


func _get_index(time: float) -> int:
	var i := _cached_index
	if time >= orbits[i].segment_begin and time < orbits[i].segment_end:
		return i
	# bsearch(..., false) is upper_bound: count of interior boundaries <= time == segment index.
	i = _boundaries.bsearch(time, false)
	_cached_index = i
	return i


# *****************************************************************************
# derived data

# Rebuilds all derived data from orbits. Called by the creators ([param new_game] true)
# and on game_loaded ([param new_game] false). When new_game, fix_gaps cruise segments
# are re-fitted to close patched-conic gaps (see _fix_gaps); on a load the already-fixed
# orbits are restored, so the fix is neither needed nor re-run.
func _build_derived(new_game: bool) -> void:
	var n_segments := orbits.size()
	_segment_parents.clear()
	_segment_parents.resize(n_segments)
	for i in n_segments:
		var parent_name := orbits[i].parent_name
		assert(IVBody.bodies.has(parent_name),
				"Trajectory segment parent '%s' not found in IVBody.bodies" % parent_name)
		_segment_parents[i] = IVBody.bodies[parent_name]
	_boundaries = PackedFloat64Array()
	for i in range(1, n_segments):
		_boundaries.append(orbits[i].segment_begin)
	_cached_index = 0
	lca = _compute_lca()
	if new_game:
		_fix_gaps()
	_build_path()


# Re-fits each fix_gaps cruise segment as the conic (Lambert) through its neighbor
# segments' boundary positions, using the primaries' actual positions, so the
# patched-conic joins meet. New-game only; runs before _build_path so the polyline
# uses the fixed orbits. Each cruise orbit is recycled in place (segment count and
# per-segment vertex count unchanged). A boundary that abuts another segment pins to
# that segment's drawn endpoint; an open trajectory end keeps the cruise's own
# position. Skips a near-continuous cruise; logs (but still fits) a large gap.
func _fix_gaps() -> void:
	var skip_threshold := GAP_SKIP_KM * IVUnits.KM
	var warn_threshold := GAP_WARN_AU * IVUnits.AU
	var lookahead := OPEN_TERMINAL_LOOKAHEAD_YEARS * IVUnits.YEAR
	var n_segments := orbits.size()
	for i in n_segments:
		var cruise := orbits[i]
		if !cruise.fix_gaps:
			continue
		var primary := _segment_parents[i]
		var gm := cruise.gravitational_parameter
		var t_begin := cruise.segment_begin
		var t_end := cruise.segment_end
		# Targets expressed in the cruise's own primary frame (subtract the primary's
		# offset to the lca frame, where neighbor endpoints are computed).
		var begin_target: PackedFloat64Array
		var begin_anchor: StringName # neighbor primary we snap the begin to (cruise's own if open)
		if i > 0:
			begin_target = IVMath64.subtract(_segment_position_lca(i - 1, t_begin),
					_offset_to_lca(primary, t_begin))
			begin_anchor = orbits[i - 1].parent_name
		else:
			begin_target = cruise.get_translation(t_begin)
			begin_anchor = cruise.parent_name
		var end_target: PackedFloat64Array
		var end_anchor: StringName # neighbor primary we snap the end to (cruise's own if open)
		if i < n_segments - 1:
			end_target = IVMath64.subtract(_segment_position_lca(i + 1, t_end),
					_offset_to_lca(primary, t_end))
			end_anchor = orbits[i + 1].parent_name
		else:
			t_end = t_begin + lookahead # open terminal: keep the conic's far field, re-pin the start
			end_target = cruise.get_translation(t_end)
			end_anchor = cruise.parent_name
		var begin_gap := IVMath64.distance(begin_target, cruise.get_translation(t_begin))
		var end_gap := IVMath64.distance(end_target, cruise.get_translation(t_end))
		var gap := maxf(begin_gap, end_gap)
		if gap < skip_threshold:
			continue
		if gap > warn_threshold:
			# Report the neighbor anchor on the larger-gap side; the cruise's own parent is
			# always the system primary (e.g. Sun) and so uninformative. A large gap here is
			# expected when fitting IVOrbit (rather than real-ephemeris) primaries at a distant
			# flyby, so log it rather than warn.
			var anchor := begin_anchor if begin_gap >= end_gap else end_anchor
			print("IVTrajectory: large gap (%.3f au) at segment %d,anchor %s; fitting anyway."
					% [gap / IVUnits.AU, i, anchor]
					+ "Expected for Uranus+ flybys if use_real_planet_orbits = false.")
		var velocities := IVOrbit.solve_lambert(begin_target, end_target, t_end - t_begin, gm)
		if velocities.is_empty():
			push_warning("IVTrajectory: Lambert did not converge for segment %d ('%s'); left as authored"
					% [i, cruise.parent_name])
			continue
		orbits[i] = IVOrbit.create_from_state_and_precessions(begin_target[0], begin_target[1],
				begin_target[2], velocities[0], velocities[1], velocities[2],
				gm, t_begin, cruise.reference_plane_type, cruise.reference_basis,
				cruise.longitude_ascending_node_rate, cruise.argument_periapsis_rate, cruise)


# Drawn position of segment [param index] at [param time] in the [member lca] frame (size-3).
func _segment_position_lca(index: int, time: float) -> PackedFloat64Array:
	var pos := orbits[index].get_translation(time)
	var offset := _offset_to_lca(_segment_parents[index], time)
	return PackedFloat64Array([pos[0] + offset[0], pos[1] + offset[1], pos[2] + offset[2]])


# Velocity of segment [param index] at [param time] in the [member lca] frame (size-3): the segment's
# orbital velocity about its primary plus the primary's own velocity relative to the LCA. The primary's
# velocity is a central difference of its composed position, NOT its osculating two-body velocity, which
# omits the element-rate drift of evolving
# (real-planet) orbits — a ~m/s bias, common to an interval's two knots, that the cubic Hermite turns
# into a knot-period line "sweep" of ~0.1 x bias x knot interval (measured km-scale on Saturn/Uranus
# flyby legs), with zero error at the knots and interval midpoint.
func _segment_velocity_lca(index: int, time: float) -> PackedFloat64Array:
	var state := orbits[index].get_state(time)
	var primary := _segment_parents[index]
	if primary == lca:
		return PackedFloat64Array([state[3], state[4], state[5]])
	var half_step := 60.0 * IVUnits.SECOND
	var plus := _offset_to_lca(primary, time + half_step)
	var minus := _offset_to_lca(primary, time - half_step)
	var inv_step := 0.5 / half_step
	return PackedFloat64Array([
		state[3] + (plus[0] - minus[0]) * inv_step,
		state[4] + (plus[1] - minus[1]) * inv_step,
		state[5] + (plus[2] - minus[2]) * inv_step,
	])


func _compute_lca() -> IVBody:
	var common := _segment_parents[0]
	for i in range(1, _segment_parents.size()):
		common = _lowest_common_ancestor(common, _segment_parents[i])
	return common


func _lowest_common_ancestor(body_a: IVBody, body_b: IVBody) -> IVBody:
	var a_ancestors := {} # IVBody set (a and all its ancestors)
	var node := body_a
	while node:
		a_ancestors[node] = true
		node = node.parent
	node = body_b
	while node:
		if a_ancestors.has(node):
			return node
		node = node.parent
	return null # no shared ancestor (e.g., separate star systems)


func _build_path() -> void:
	var n_vertices := IVCoreSettings.vertecies_per_trajectory_segment
	var max_radius := IVCoreSettings.open_conic_max_radius
	path = PackedFloat64Array()
	for i in orbits.size():
		var orbit := orbits[i]
		var arc := orbit.sample_arc(orbit.segment_begin, orbit.segment_end, n_vertices, max_radius)
		var times: PackedFloat64Array = arc[1]
		path.append_array(sample_segment_states_lca(i, times))


# Returns the position of [param primary] relative to [member lca] at [param time] (size-3).
func _offset_to_lca(primary: IVBody, time: float) -> PackedFloat64Array:
	return primary.get_translation_to_ancestor(lca, time)


# Breaks the IVBody<->IVTrajectory reference cycle just before this object is freed.
func _clear_procedural() -> void:
	lca = null
	_segment_parents.clear()
	orbits.clear()
	path = PackedFloat64Array()
	_boundaries = PackedFloat64Array()
