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
	&"begin_orbit",
	&"end_orbit",
	&"end_remove",
]


## Ordered, time-contiguous conic segments. The only persisted member; all other
## members are derived from this. Segment [code]i[/code] is active for time in
## [code][segment_begin, segment_end)[/code]. The first segment's begin and the last
## segment's end may be finite (e.g. a launch time): for times outside that overall
## window the body parks at the nearest path endpoint instead of extrapolating (see
## [method get_clamped_time]); use -INF/INF for an open-ended window.
var orbits: Array[IVOrbit] = []

## If true, the first segment is a closed/parking orbit: it is drawn with the normal
## orbit visual (in the body's own parent frame) while the body is in it, and is omitted
## from the trajectory polyline. See [method is_orbit_segment].
var begin_orbit: bool
## If true, the last segment is a closed/capture orbit, drawn as a normal orbit like
## [member begin_orbit]. See [method is_orbit_segment].
var end_orbit: bool
## If true, on reaching the last segment the body switches to the normal orbit visual
## (as [member end_orbit]) and then discards the trajectory, reverting to a plain orbiter.
## Intended for games without time reversal; keep false for Planetarium content so
## spacecraft trajectories persist. The [method create] argument defaults to true.
var end_remove: bool

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


func _init() -> void:
	# Rebuild derived data after a load (orbits are restored by then). Clear IVBody
	# references before teardown to break the IVBody<->IVTrajectory cycle.
	IVStateManager.game_loaded.connect(_build_derived)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)


# *****************************************************************************
# static creators


## Creates an [IVTrajectory] from an ordered, time-contiguous array of [IVOrbit]
## segments. Each segment's [member IVOrbit.parent_name] must name a body present
## in [member IVBody.bodies]. [param begin_orbit], [param end_orbit] and
## [param end_remove] set the same-named members (see [method is_orbit_segment]).
@warning_ignore("shadowed_variable")
static func create(orbits: Array[IVOrbit], begin_orbit: bool, end_orbit: bool,
		end_remove := true) -> IVTrajectory:
	assert(!orbits.is_empty(), "IVTrajectory requires at least one orbit segment")
	for i in range(1, orbits.size()):
		assert(orbits[i].segment_begin >= orbits[i - 1].segment_begin,
				"IVTrajectory segments must be ordered by segment_begin")
	var trajectory := IVTrajectory.new()
	trajectory.orbits = orbits
	trajectory.begin_orbit = begin_orbit
	trajectory.end_orbit = end_orbit
	trajectory.end_remove = end_remove
	trajectory._build_derived()
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
	return create(segment_orbits,
			IVTableData.get_db_bool(&"trajectories", &"begin_orbit", trajectory_row),
			IVTableData.get_db_bool(&"trajectories", &"end_orbit", trajectory_row),
			IVTableData.get_db_bool(&"trajectories", &"end_remove", trajectory_row))


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
## frame) rather than as part of the trajectory polyline. Driven by [member begin_orbit]
## (first segment) and [member end_orbit]/[member end_remove] (last segment). [IVPathVisual]
## uses this both to choose its display mode and to omit these segments from the polyline.
func is_orbit_segment(index: int) -> bool:
	if begin_orbit and index == 0:
		return true
	if (end_orbit or end_remove) and index == orbits.size() - 1:
		return true
	return false


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


# Rebuilds all derived data from orbits. Called by the creators (new game) and on
# game_loaded (after the procedural tree, including all segment primaries, is rebuilt).
func _build_derived() -> void:
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
	_build_path()


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
