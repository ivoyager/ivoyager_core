# path_visual.gd
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
class_name IVPathVisual
extends MeshInstance3D

## Visual representation of an [IVBody]'s orbit, or its [IVTrajectory] (a
## patched-conic path) when present.
##
## [b]Orbit mode[/b] (no [IVTrajectory]): transforms a unit circle, parabola or
## rectangular-hyperbola mesh into the body's elliptic, parabolic or hyperbolic
## orbit. The three "unit" meshes are reused for all such orbits.[br][br]
##
## [b]Trajectory mode[/b] (the body has an [IVTrajectory]): for a transfer segment, builds a
## generated [code]LINE_STRIP[/code] mesh (one surface per segment) from the trajectory's
## precomputed [member IVTrajectory.path], expressed in the lowest-common-ancestor frame of
## the segment primaries; this node reparents itself to that ancestor
## ([method IVTrajectory.get_lca]) while the body reparents through the segment primaries.
## The mesh is built once and cached.[br][br]
##
## Any segment can instead be drawn as a parking/capture orbit (see
## [member IVTrajectory.visual_orbits], [member IVTrajectory.end_remove]); while the body
## is in such a segment this node renders in orbit mode in the body's own parent frame and
## omits that segment from the polyline.
## [method _on_orbit_changed] is the single switchboard that, on each segment change (via
## [signal IVBody.orbit_changed]), selects the mode, reparents, and sets the mesh.[br][br]
##
## [b]Rebased mode (issue #17)[/b]: a shared unit/LCA-frame mesh is built in float32 at heliocentric
## magnitude, so its rounding (~ magnitude × 1.2e-7) leaves the body visibly off its own line once that
## exceeds a sub-pixel fraction of the viewing distance. While the camera is focused on this body (or the
## flyby primary it is currently near — see [method _is_camera_focused]), [method _process] compares that
## rounding to the live viewing distance ([method _is_rebase_warranted], scale-free so it covers a close
## inner planet as well as an outer one) and flips between rebased and normal rendering. Rebased, the node
## reparents under the camera-body — inheriting that body's global transform, so its float32 imprecision is
## shared and cancels exactly as it does for IVCamera origin-shifting. Vertices are rebased to a near-body
## anchor (small, precise), and a local position tracks the body's motion each frame; it rebuilds on drift /
## zoom (the expensive orbit resampling on a worker thread when enabled). See [method _on_camera_tree_changed].[br][br]
##
## If [IVFragmentIdentifier] is present, a pure id-overlay (the [code]uniform_id[/code] shader,
## attached as [member GeometryInstance3D.material_overlay]) provides mouse-over identification
## of the line without constraining the base material's appearance.


const FRAGMENT_BODY_ORBIT := IVFragmentIdentifier.FRAGMENT_BODY_ORBIT

var _body: IVBody
var _trajectory: IVTrajectory # null in orbit mode
var _color: Color
var _is_orbit_group_visible: bool
var _body_huds_visible: bool # too close / too far
var _body_visible: bool # tracks _body.visible
var _dirty_orbit := true
var _trajectory_mesh: ArrayMesh # built once (non-rebased), reused across trajectory<->orbit toggles

# #17 fix (rebased mode): when a large orbit/trajectory is viewed from far out at its own body or a
# flyby primary, its LCA-frame vertices lose float32 precision. We reparent this node under the
# camera-body (so it shares that body's global-transform imprecision, which then cancels), rebase the
# vertices to a near-body anchor, and track the body's motion in position each frame (_process).
static var use_threads := true ## Class-wide gate for threaded rebased-path builds (with [member IVCoreSettings.use_threads]).
const REBASE_PRECISION_RATIO := 500.0 # rebase when (camera-body distance from LCA) / (viewing distance) exceeds this. The float32 line rounding (~magnitude * 1.2e-7) is then ~0.3 px, well before it's noticeable. Scale-free: close inner planets qualify, distant outer views don't
const REBAKE_DRIFT_FACTOR := 4.0 # re-anchor once the body drifts this multiple of the camera distance (keeps the dense near-field on it)
const REBAKE_MIN_INTERVAL_MSEC := 250 # rate cap: never re-anchor more than ~4×/sec (position tracks between)
const REBASE_MAX_VERTICES := 16384 # cap for the adaptive rebased-orbit vertex count
const REBASE_TOLERANCE := 0.008 # target chord-deviation / camera-distance (~sub-pixel); smaller = denser
const REBASE_ZOOM_FACTOR := 0.5 # redensify the orbit once camera-to-body distance passes this factor (in or out)
const REBASE_CHORD_TOLERANCE := 0.0015 # rebased-trajectory adaptive sampling: max chord deviation / viewing distance (~sub-pixel)
const REBASE_CHORD_LENGTH_FACTOR := 0.25 # rebased-trajectory adaptive sampling: max chord length / viewing distance (LOD; smaller = denser near camera)
const REBASE_SWATH_FACTOR := 2.0 # widen the dense near-field to this multiple of the body's per-rebake drift, so it can't outrun the line at high game speed
var _rebake_drift: float # re-anchor threshold; = camera distance × REBAKE_DRIFT_FACTOR, set per rebake
var _lca: IVBody # frame the current path is expressed in (orbit parent, or trajectory LCA)
var _camera: Camera3D
var _camera_body: IVBody # body the camera is parented at (camera_tree_changed 'parent')
var _rebased := false
var _rebase_offset := PackedFloat64Array([0.0, 0.0, 0.0]) # camera-body anchor in the _lca frame
var _rebaking := false # guards against overlapping rebakes
var _rebake_cam_dist := 0.0 # camera-to-body distance at last rebake (for zoom-triggered redensify)
var _rebake_task_id := -1 # WorkerThreadPool task id for an in-flight orbit rebake, else -1
var _last_rebake_msec := 0 # Time.get_ticks_msec() at last rebake (rate cap; see REBAKE_MIN_INTERVAL_MSEC)
var _rebase_swath := 0.0 # body's drift since the last rebake (0 on activation); scaled by REBASE_SWATH_FACTOR into the sampler's swath

var _fragment_identifier: IVFragmentIdentifier = IVGlobal.program.get(&"FragmentIdentifier")
var _body_huds_state: IVBodyHUDsState = IVGlobal.program[&"BodyHUDsState"]
var _circle_mesh: ArrayMesh = IVGlobal.resources[&"circle_mesh"]
var _parabola_mesh: ArrayMesh = IVGlobal.resources[&"parabola_mesh"]
var _rectangular_hyperbola_mesh: ArrayMesh = IVGlobal.resources[&"rectangular_hyperbola_mesh"]


func _init(body: IVBody) -> void:
	_body = body
	name = "PathVisual_" + body.name


func _ready() -> void:
	#process_priority = 2
	_body.orbit_changed.connect(_on_orbit_changed)
	_body_huds_state.visibility_changed.connect(_on_global_huds_changed)
	_body_huds_state.color_changed.connect(_set_color)
	_body.huds_visibility_changed.connect(_on_body_huds_changed)
	_body.visibility_changed.connect(_on_body_visibility_changed)
	IVGlobal.camera_tree_changed.connect(_on_camera_tree_changed)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_rebased)
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	var standard_material := StandardMaterial3D.new()
	standard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_override = standard_material
	if _fragment_identifier: # add self-identifying id overlay pass
		var data := _body.get_fragment_data(FRAGMENT_BODY_ORBIT)
		var fragment_id := _fragment_identifier.get_new_id_as_vec3(data)
		var id_material := ShaderMaterial.new()
		id_material.shader = IVGlobal.resources[&"id_shader"]
		id_material.set_shader_parameter(&"fragment_id", fragment_id)
		id_material.render_priority = 1 # draw the id stamp above the base pass
		material_overlay = id_material
	_set_color()
	# Parenting and display mode (orbit vs trajectory) are resolved per segment in
	# _on_orbit_changed, the single switchboard; nothing to reparent eagerly here.
	set_process(false) # enabled while the camera is focused on this body (per-frame rebase check)
	_camera = get_viewport().get_camera_3d()
	if _camera:
		_camera_body = _find_body_ancestor(_camera)
	_body_huds_visible = _body.huds_visible
	_body_visible = _body.visible
	_on_global_huds_changed()


func _on_orbit_changed(orbit: IVOrbit, _is_intrinsic := false, _precession_only := false) -> void:
	if !visible:
		_dirty_orbit = true
		return
	_dirty_orbit = false
	_trajectory = _body.get_trajectory() # may have become null via end_remove
	# A parking/capture segment (or a body with no trajectory) draws as a normal orbit in
	# the body's parent frame; a transfer segment draws as the polyline in the LCA frame.
	var as_orbit := _trajectory == null \
			or _trajectory.is_orbit_segment(_trajectory.orbits.find(orbit))
	_lca = _body.parent if as_orbit else _trajectory.get_lca()
	# When the camera is focused on this body (or the flyby primary it is currently near), _process runs
	# and flips between rebased and normal by the live viewing distance (self-correcting as the camera
	# settles / zooms). Focus changes only on camera or segment change, so it is resolved here; the
	# distance test changes continuously, so _process owns it.
	if _is_camera_focused(as_orbit):
		set_process(true)
		if _is_rebase_warranted():
			_rebase_swath = 0.0 # fresh (re)activation: no prior drift, so the near-field is the camera distance
			_rebake(orbit, as_orbit) # the orbit/segment changed, so build fresh
			return
	else:
		set_process(false)
	_render_normal(orbit, as_orbit)


# Non-rebased rendering in the LCA frame: the shared unit conic mesh (orbit) or the once-built,
# fixed-density trajectory polyline. Used when the camera is elsewhere or too far for the float32 line
# error to matter (see [method _is_rebase_warranted)].
func _render_normal(orbit: IVOrbit, as_orbit: bool) -> void:
	_reparent(_lca)
	_rebased = false
	if as_orbit:
		_set_orbit_mesh(orbit)
		return
	if not _trajectory_mesh:
		_trajectory_mesh = _assemble_line_mesh(
				_build_trajectory_surfaces(_trajectory, PackedFloat64Array([0.0, 0.0, 0.0])))
	mesh = _trajectory_mesh
	transform = Transform3D.IDENTITY


# Sets the unit conic mesh and transform for orbit-mode display (no trajectory, or a
# parking/capture segment). The three unit meshes are shared across all such orbits.
func _set_orbit_mesh(orbit: IVOrbit) -> void:
	var e := orbit.get_eccentricity()
	if e < 1.0:
		mesh = _circle_mesh
		transform = orbit.get_unit_circle_transform()
	elif e > 1.0:
		mesh = _rectangular_hyperbola_mesh
		transform = orbit.get_unit_rectangular_hyperbola_transform()
	else:
		mesh = _parabola_mesh
		transform = orbit.get_unit_parabola_transform()


# *****************************************************************************
# #17 rebased mode (see class-member notes and [method _on_camera_tree_changed])

# The camera is at this body (orbit) or at the primary the body is CURRENTLY near (trajectory flyby).
# Uses the current segment's primary, not any historical one, so being at Neptune decades after V2's
# flyby doesn't rebase V2's whole path. Focus gates whether _process runs at all.
func _is_camera_focused(as_orbit: bool) -> bool:
	if not _camera or not _camera_body or not _lca:
		return false
	if _camera_body == _body:
		return true
	if as_orbit:
		return false
	var time: float = IVGlobal.times[0]
	return _camera_body == _trajectory.get_parent(time)


# True when the non-rebased line's float32 rounding would be visible. That line is built at heliocentric
# magnitude (~ the camera-body's distance from the LCA), so its absolute error ~ magnitude * 1.2e-7;
# rebase once that exceeds a sub-pixel fraction of the viewing distance. Scale-free — a close inner planet
# qualifies, a distant outer one does not (which also avoids rebasing when the error is already sub-pixel).
# Hysteresis (half the ratio to stay rebased) keeps a camera hovering at the threshold from flickering.
func _is_rebase_warranted() -> bool:
	var magnitude := _camera_body.global_position.distance_to(_lca.global_position)
	var cam_dist := _camera.global_position.distance_to(_camera_body.global_position)
	if cam_dist <= 0.0:
		return magnitude > 0.0
	var threshold := REBASE_PRECISION_RATIO * 0.5 if _rebased else REBASE_PRECISION_RATIO
	return magnitude / cam_dist > threshold


# (Re)builds the rebased polyline: computes the camera-body anchor in the [member _lca] frame,
# then builds the local vertices with that anchor removed — on a worker thread when enabled.
# Called on entering rebased mode and from [method _process] on camera-body drift.
func _rebake(orbit: IVOrbit, as_orbit: bool) -> void:

	#prints("_rebake ", _rebaking, _body.name, Time.get_ticks_usec())

	if _rebaking:
		return
	_rebased = true
	_rebaking = true
	_last_rebake_msec = Time.get_ticks_msec()
	var trajectory := _trajectory # snapshot for the worker (may be nulled on the main thread)
	var time: float = IVGlobal.times[0]
	var offset := _camera_body.get_translation_to_ancestor(_lca, time)
	# Adaptive orbit density: more vertices when the camera is zoomed in close (see
	# _rebase_vertex_count). orbit_radius is the camera-body's distance from the LCA frame.
	var orbit_radius := sqrt(offset[0] * offset[0] + offset[1] * offset[1] + offset[2] * offset[2])
	_rebake_cam_dist = _camera.global_position.distance_to(_camera_body.global_position)
	# Re-anchor threshold scales with the viewing distance: keeps the near-view float32 error ~sub-pixel
	# without re-anchoring constantly when zoomed out (the per-frame position track keeps it coincident).
	_rebake_drift = _rebake_cam_dist * REBAKE_DRIFT_FACTOR
	var n_vertices := _rebase_vertex_count(_rebake_cam_dist, orbit_radius)
	# Only orbit sampling (expensive; N up to REBASE_MAX_VERTICES) is threaded, and it touches only
	# the bind-held [param orbit] (kept alive for the task) plus [param offset]. Trajectory rebakes
	# run on the main thread: they only re-offset the precomputed [member IVTrajectory.path], which
	# IVTrajectory clears on teardown — a worker reading it would race that clear (SIGSEGV on quit).
	if as_orbit and use_threads and IVCoreSettings.use_threads:
		_rebake_task_id = WorkerThreadPool.add_task(_rebake_task.bind(orbit, as_orbit, trajectory,
				offset, n_vertices))
	else:
		_rebake_task(orbit, as_orbit, trajectory, offset, n_vertices)


# Worker-thread body of [method _rebake]: pure vertex computation only (reads frozen
# IVTrajectory.path and threadsafe IVOrbit getters). ArrayMesh assembly and node mutation are
# deferred to the main thread ([method _apply_rebaked_surfaces]).
func _rebake_task(orbit: IVOrbit, as_orbit: bool, trajectory: IVTrajectory,
		offset: PackedFloat64Array, n_vertices: int) -> void:
	var surfaces: Array[PackedVector3Array]
	if as_orbit:
		surfaces = _build_orbit_surfaces(orbit, offset, n_vertices)
	else:
		surfaces = _build_trajectory_surfaces_rebased(trajectory, offset)
	_apply_rebaked_surfaces.call_deferred(surfaces, offset)


# Main-thread completion of a rebake: reparents under the camera-body, installs the mesh, and sets
# the tracking position — atomically, so the previous rendering shows until the rebased one is ready.
func _apply_rebaked_surfaces(surfaces: Array[PackedVector3Array], offset: PackedFloat64Array) -> void:
	_rebaking = false
	if _rebake_task_id != -1:
		# The worker deferred us as its last act, so its task is complete: collect it (returns at once)
		# to release the pooled task Callable and its bound orbit ref. WorkerThreadPool otherwise retains
		# an uncollected task until engine finalization, destructing that ref too late (SIGSEGV on quit).
		WorkerThreadPool.wait_for_task_completion(_rebake_task_id)
		_rebake_task_id = -1
	if not _rebased:
		return # exited rebased mode while this build was in flight; discard the stale result
	_reparent(_camera_body)
	mesh = _assemble_line_mesh(surfaces)
	transform = Transform3D.IDENTITY # clear any leftover unit-mesh basis/scale before position tracking
	_rebase_offset = offset
	_set_rebase_position(_camera_body.get_translation_to_ancestor(_lca, IVGlobal.times[0]))


# Sets local position (relative to the camera-body parent) so the static LCA-frame line stays
# coincident with the moving body: position = anchor - body's current LCA-frame position. Done in
# f64 (both ~AU) to keep the small drift exact — setting global_position would instead re-do the
# large-magnitude float32 cancellation this mode exists to avoid.
func _set_rebase_position(current_lca_position: PackedFloat64Array) -> void:
	position = Vector3(
		_rebase_offset[0] - current_lca_position[0],
		_rebase_offset[1] - current_lca_position[1],
		_rebase_offset[2] - current_lca_position[2]
	)


# PREDELETE backstop: for the atypical case of this node being freed outside procedural teardown
# (which joins the worker earlier, in _clear_rebased), block until any in-flight orbit rebake
# finishes so the worker never calls into a freed instance.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rebake_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_rebake_task_id)
		_rebake_task_id = -1


# Teardown: stop rebased processing and join any in-flight orbit rebake worker before procedural
# bodies (this node's parent _camera_body, and _lca) are freed. Joining here — while everything is
# still alive — rather than at PREDELETE avoids the worker calling call_deferred into a self that is
# already mid-destruction (SIGSEGV on quit). _rebased = false makes the joined worker's queued
# _apply a no-op. Fires on IVStateManager.about_to_free_procedural_nodes.
func _clear_rebased() -> void:
	set_process(false)
	_rebased = false
	if _rebake_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_rebake_task_id)
		_rebake_task_id = -1


func _process(_delta: float) -> void:
	# Runs while the camera is focused on this body (set in _on_orbit_changed). Owns the rebased-vs-normal
	# decision by the live viewing distance and, while rebased, the per-frame position track.
	if not _camera or not _camera_body or not _lca:
		return
	var orbit := _body.orbit
	var as_orbit := _trajectory == null or _trajectory.is_orbit_segment(
			_trajectory.orbits.find(orbit))
	if not _is_rebase_warranted():
		if _rebased:
			_render_normal(orbit, as_orbit) # zoomed out until the float32 line error is sub-pixel again
		return
	if not _rebased or get_parent() != _camera_body:
		if not _rebaking:
			_rebase_swath = 0.0
			_rebake(orbit, as_orbit) # activate (camera has settled close enough) or reparent pending
		return
	# Rebased and reparented under the camera-body: keep the static line on the moving body, then
	# re-anchor on drift / zoom.
	var time: float = IVGlobal.times[0]
	var current_offset := _camera_body.get_translation_to_ancestor(_lca, time)
	_set_rebase_position(current_offset)
	if _rebaking:
		return # a rebake is in flight; position still tracks (above), but don't trigger another
	var drift := IVMath64.distance(current_offset, _rebase_offset)
	var need_rebake := drift > _rebake_drift
	if not need_rebake:
		# Redensify as the camera zooms in / out (orbit vertex count and trajectory LOD both scale
		# with the viewing distance, which is only re-read on rebake).
		var cam_dist := _camera.global_position.distance_to(_camera_body.global_position)
		need_rebake = cam_dist < _rebake_cam_dist * REBASE_ZOOM_FACTOR \
				or cam_dist > _rebake_cam_dist / REBASE_ZOOM_FACTOR
	if need_rebake and Time.get_ticks_msec() - _last_rebake_msec >= REBAKE_MIN_INTERVAL_MSEC:
		_rebase_swath = drift # how far the body moved this interval → the near-field width for the next
		_rebake(orbit, as_orbit)


func _on_camera_tree_changed(camera: Camera3D, parent: Node3D, _star_orbiter: Node3D,
		_star: Node3D) -> void:
	_camera = camera
	var camera_body: IVBody = parent # camera_tree_changed 'parent' is always an IVBody
	_camera_body = camera_body
	# The camera moved to a new body; re-evaluate rebase mode for the current orbit.
	if visible:
		_on_orbit_changed(_body.orbit)
	else:
		_dirty_orbit = true


# Moves this node under [param new_parent] (the LCA of the current display mode), matching
# IVBody.set_orbit_and_parent's idiom.
func _reparent(new_parent: Node) -> void:
	if not new_parent or get_parent() == new_parent:
		return
	get_parent().remove_child(self)
	new_parent.add_child(self)


# Walks up from [param node] to the nearest enclosing [IVBody] (the body the camera is at).
func _find_body_ancestor(node: Node) -> IVBody:
	while node:
		if node is IVBody:
			var body: IVBody = node
			return body
		node = node.get_parent()
	return null


# Vertex count for a rebased orbit polyline, sized so the chord deviation of the straight segments
# from the true curve at the viewed arc stays ~sub-pixel. A segment's sagitta ~ r * dθ²/8, so for a
# screen tolerance the step dθ ~ sqrt(tol * camera_distance / r); N = TAU / dθ scales with
# sqrt(orbit_radius / camera_distance): denser when zoomed in close, sparser when far (the shared
# non-rebased mesh is fine there). Clamped to [vertecies_per_orbit, REBASE_MAX_VERTICES].
func _rebase_vertex_count(camera_distance: float, orbit_radius: float) -> int:
	if camera_distance <= 0.0:
		return REBASE_MAX_VERTICES
	var n := int(TAU * sqrt(orbit_radius / (REBASE_TOLERANCE * camera_distance)))
	return clampi(n, IVCoreSettings.vertecies_per_orbit, REBASE_MAX_VERTICES)


# Builds one LINE_STRIP surface per transfer segment from [param trajectory]'s flat f64 path,
# subtracting the size-3 [param offset] (the rebase anchor; zero for plain LCA-frame display)
# in double precision before the float32 cast. Parking/capture segments are omitted.
func _build_trajectory_surfaces(trajectory: IVTrajectory,
		offset: PackedFloat64Array) -> Array[PackedVector3Array]:
	var surfaces: Array[PackedVector3Array] = []
	var path := trajectory.path
	var n_segments := trajectory.orbits.size()
	if path.is_empty() or n_segments == 0:
		return surfaces
	@warning_ignore("integer_division") # path.size() is exactly 3 * n_segments * vertices/segment
	var chunk := path.size() / (3 * n_segments) # vertices per segment
	for i in n_segments:
		if trajectory.is_orbit_segment(i):
			continue
		surfaces.append(_rebased_vertices(path, i * chunk, (i + 1) * chunk, offset))
	return surfaces


# As [method _build_trajectory_surfaces], but adaptively resamples every drawn segment for the rebased
# line: IVTrajectory subdivides each by screen-space chord error relative to the camera anchor (this
# node's [param offset] in the LCA frame), so vertices densify where a segment is close to the camera
# and/or sharply curved (a flyby periapsis) and thin out where it is far and straight. This keeps a
# close spacecraft's line — and a sharp flyby ahead of it during approach — smooth, which the fixed-
# density precomputed path cannot. Main-thread only (trajectory rebakes never thread), so the per-vertex
# IVOrbit.get_translation inside IVTrajectory is safe.
func _build_trajectory_surfaces_rebased(trajectory: IVTrajectory,
		offset: PackedFloat64Array) -> Array[PackedVector3Array]:
	var surfaces: Array[PackedVector3Array] = []
	var n_segments := trajectory.orbits.size()
	for i in n_segments:
		if trajectory.is_orbit_segment(i):
			continue
		var positions := trajectory.sample_segment_adaptive_lca(i, offset, _rebake_cam_dist,
				REBASE_SWATH_FACTOR * _rebase_swath, REBASE_CHORD_LENGTH_FACTOR, REBASE_CHORD_TOLERANCE,
				REBASE_MAX_VERTICES)
		@warning_ignore("integer_division") # sample_segment_adaptive_lca returns exactly 3 floats per vertex
		var n_vertices := positions.size() / 3
		if n_vertices >= 2:
			surfaces.append(_rebased_vertices(positions, 0, n_vertices, offset))
	return surfaces


# Builds a single LINE_STRIP surface sampling the full [param orbit] (one period, or to
# open_conic_max_radius) at [param n_vertices], with [param offset] removed in double precision
# before the float32 cast.
func _build_orbit_surfaces(orbit: IVOrbit, offset: PackedFloat64Array,
		n_vertices: int) -> Array[PackedVector3Array]:
	var surfaces: Array[PackedVector3Array] = []
	var arc := orbit.sample_arc(-INF, INF, n_vertices, IVCoreSettings.open_conic_max_radius)
	var positions: PackedFloat64Array = arc[0]
	if positions.is_empty():
		return surfaces
	surfaces.append(_rebased_vertices(positions, 0, n_vertices, offset))
	return surfaces


# Converts flat f64 [param path] vertices [begin_vertex, end_vertex) to a float32
# [PackedVector3Array], subtracting size-3 [param offset]. The subtraction is the precision-
# preserving step: it runs in double precision before the float32 cast.
func _rebased_vertices(path: PackedFloat64Array, begin_vertex: int, end_vertex: int,
		offset: PackedFloat64Array) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	vertices.resize(end_vertex - begin_vertex)
	var offset_x := offset[0]
	var offset_y := offset[1]
	var offset_z := offset[2]
	var vertex_index := 0
	for k in range(begin_vertex, end_vertex):
		vertices[vertex_index] = Vector3(path[3 * k] - offset_x, path[3 * k + 1] - offset_y,
				path[3 * k + 2] - offset_z)
		vertex_index += 1
	return vertices


# Assembles a LINE_STRIP [ArrayMesh] from per-surface vertex arrays (one surface per transfer
# segment, or one for an orbit). Main-thread only (touches the RenderingServer).
func _assemble_line_mesh(surfaces: Array[PackedVector3Array]) -> ArrayMesh:
	var array_mesh := ArrayMesh.new()
	for surface_vertices in surfaces:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface_vertices
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	return array_mesh


func _on_global_huds_changed() -> void:
	_is_orbit_group_visible = _body_huds_state.is_orbit_visible(_body.flags)
	_set_visibility_state()


func _on_body_huds_changed(is_visible_: bool) -> void:
	_body_huds_visible = is_visible_
	_set_visibility_state()


func _on_body_visibility_changed() -> void:
	_body_visible = _body.visible
	_set_visibility_state()


func _set_visibility_state() -> void:
	visible = _is_orbit_group_visible and _body_huds_visible and _body_visible
	if visible and _dirty_orbit:
		_on_orbit_changed(_body.orbit)


func _set_color() -> void:
	var color := _body_huds_state.get_color(_body.flags)
	if _color == color:
		return
	_color = color
	var standard_material: StandardMaterial3D = material_override
	standard_material.albedo_color = color
