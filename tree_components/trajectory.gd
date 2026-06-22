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

## Connected polyline of the whole trajectory in the [member lca] frame (ecliptic
## basis). Derived from [member orbits]; consumed by [IVPathVisual].
var path: PackedVector3Array
## Passage time (s) of each vertex in [member path] (same size as [member path]).
var path_times: PackedFloat64Array
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
		var begin_target: Vector3
		var begin_anchor: StringName # neighbor primary we snap the begin to (cruise's own if open)
		if i > 0:
			begin_target = _segment_position_lca(i - 1, t_begin) - _offset_to_lca(primary, t_begin)
			begin_anchor = orbits[i - 1].parent_name
		else:
			begin_target = cruise.get_position(t_begin)
			begin_anchor = cruise.parent_name
		var end_target: Vector3
		var end_anchor: StringName # neighbor primary we snap the end to (cruise's own if open)
		if i < n_segments - 1:
			end_target = _segment_position_lca(i + 1, t_end) - _offset_to_lca(primary, t_end)
			end_anchor = orbits[i + 1].parent_name
		else:
			t_end = t_begin + lookahead # open terminal: keep the conic's far field, re-pin the start
			end_target = cruise.get_position(t_end)
			end_anchor = cruise.parent_name
		var begin_gap := (begin_target - cruise.get_position(t_begin)).length()
		var end_gap := (end_target - cruise.get_position(t_end)).length()
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
		orbits[i] = IVOrbit.create_from_state_and_precessions(begin_target.x, begin_target.y,
				begin_target.z, velocities[0], velocities[1], velocities[2],
				gm, t_begin, cruise.reference_plane_type, cruise.reference_basis,
				cruise.longitude_ascending_node_rate, cruise.argument_periapsis_rate, cruise)


# Drawn position of segment [param index] at [param time] in the [member lca] frame.
func _segment_position_lca(index: int, time: float) -> Vector3:
	return orbits[index].get_position(time) + _offset_to_lca(_segment_parents[index], time)


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
	var n_vertices := IVCoreSettings.vertecies_per_orbit
	var max_radius := IVCoreSettings.open_conic_max_radius
	path = PackedVector3Array()
	path_times = PackedFloat64Array()
	for i in orbits.size():
		var orbit := orbits[i]
		var primary := _segment_parents[i]
		var arc := orbit.sample_arc(orbit.segment_begin, orbit.segment_end, n_vertices, max_radius)
		var positions: PackedVector3Array = arc[0]
		var times: PackedFloat64Array = arc[1]
		for j in positions.size():
			var time := times[j]
			path.append(positions[j] + _offset_to_lca(primary, time))
			path_times.append(time)


# Returns the position of [param primary] relative to [member lca] at [param time]
# by summing positions up the parent chain. IVBody nodes are never rotated/scaled,
# so frame conversion is pure vector addition.
func _offset_to_lca(primary: IVBody, time: float) -> Vector3:
	var offset := Vector3.ZERO
	var node := primary
	while node and node != lca:
		offset += node.get_position_vector(time)
		node = node.parent
	return offset


# Breaks the IVBody<->IVTrajectory reference cycle just before this object is freed.
func _clear_procedural() -> void:
	lca = null
	_segment_parents.clear()
	orbits.clear()
	path = PackedVector3Array()
	path_times = PackedFloat64Array()
	_boundaries = PackedFloat64Array()
