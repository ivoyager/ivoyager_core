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

## Visual representation of an [IVBody]'s orbit or [IVTrajectory] path.
##
## This node is a thin renderer: it never touches [IVOrbit] or [IVTrajectory] and knows nothing about
## conics, epochs, or segments. It asks its [IVBody] (see [method IVBody.get_display_state_paths],
## [method IVBody.get_orbit_display], [method IVBody.get_path_frame], [method IVBody.is_showing_orbit])
## for drawable geometry and renders it in one of three tiers:[br][br]
##
## [b]Tier 1 — coarse[/b]: when the camera is elsewhere or too far for float32 line error to matter, an
## orbit draws as a shared unit conic mesh + transform and a trajectory as a plain low-density polyline,
## both in the body's own frame ([method IVBody.get_path_frame]).[br][br]
##
## [b]Tier 2 — rebased (issue #17)[/b]: while the camera is focused on this body (or the flyby primary it
## is currently near — see [method IVBody.is_camera_focused]) and close enough that the float32 rounding of
## the AU-magnitude line would be visible ([method _is_rebase_warranted]), this node reparents under the
## camera-body so it shares that body's global-transform imprecision (which then cancels), and rebases the
## body's 64-bit state path to a near-body anchor (small, precise) with a local position tracking the
## body's motion each frame.[br][br]
##
## [b]Tier 3 — Hermite smoothing[/b]: the rebased base vertices are refined by cubic-Hermite interpolation
## (time-parameterized, with the state path's true velocities as tangents), so a modest, curvature-aware
## base density from the body smooths to a sub-pixel line at any zoom without re-solving Kepler
## ([method _hermite_tessellate]). Rebuilt on body drift / zoom; the epoch-correct base comes from the body.[br][br]
##
## [b]Render-frame pin[/b]: while rebased, the f64 residual between the body and its drawn curve at the
## current time (the Hermite bow between knots, or error in the path data itself) goes to the line shader
## each frame, which shifts a knot-interval-sized window of the line by it — the line passes exactly
## through the body at any zoom, and the base density only has to deliver smoothness, not absolute
## trueness (see [method _update_pin] and [code]_path_pin.gdshaderinc[/code]).
##
## If [IVFragmentIdentifier] is present, a pure id-overlay (the [code]path_id[/code] shader,
## attached as [member GeometryInstance3D.material_overlay]) provides mouse-over identification
## of the line without constraining the base material's appearance.


const FRAGMENT_BODY_ORBIT := IVFragmentIdentifier.FRAGMENT_BODY_ORBIT

# #17 rebased mode: reparent under the camera-body (sharing its global-transform imprecision, which then
# cancels), rebase the body's state path to a near-body anchor, and track the body's motion in position.
const REBASE_PRECISION_RATIO := 500.0 # rebase when (camera-body distance from frame) / (viewing distance) exceeds this. The float32 line rounding (~magnitude * 1.2e-7) is then ~0.3 px. Scale-free: close inner planets qualify, distant outer views don't
const REBAKE_DRIFT_FACTOR := 4.0 # re-anchor once the body drifts this multiple of the camera distance out of the fresh dense core (checked every frame, so a fast body re-centers each frame instead of outrunning the line)
const REBASE_MAX_VERTICES := 16384 # cap for the tessellated rebased line's total vertex count
const REBASE_ZOOM_FACTOR := 0.5 # re-tessellate once camera-to-body distance passes this factor (in or out)
const REBASE_CHORD_LENGTH_FACTOR := 0.25 # adaptive tessellation: max sub-chord length / viewing distance (LOD; smaller = denser near camera)
const REBASE_CHORD_TOLERANCE := 0.0015 # adaptive tessellation: max sub-chord deviation from the Hermite curve / viewing distance (~sub-pixel; keeps the body on the line)
const REBASE_BEND_RATIO := 0.001 # adaptive tessellation: max sub-chord deviation / sub-chord length. Caps the drawn corner angle (~8x this, ~0.5 deg) at any zoom; the two view-scaled terms alone allow ~3 deg corners where the curvature radius is a few times the viewing distance
const ADAPTIVE_MAX_DEPTH := 34 # bisection recursion cap per base segment

# Render-frame pin: the tessellation bounds are view-relative, but the curve's deviation from the true
# body position is absolute — so it can dominate the view at close zoom no matter how dense the base is.
# The pin shifts the line's near-body window by the live body-minus-curve residual (see _update_pin).
# The window is sized to the LOCAL KNOT CHORD — the residual field's own correlation length — never to
# the view: the field varies over exactly that scale, so any tighter taper compresses its amplitude
# into a short stretch of line and paints a visible S-bend ("lump" that breathes with each knot pass)
# just ahead of and behind the body at close zoom. Spread over the chord, the taper bend can never
# exceed ~4 x residual / chord radians — sub-pixel at any zoom.
const PIN_INNER_CHORD_FRACTION := 0.25 # full-shift radius as a fraction of the bracketing knot chord
const PIN_SLOPE_FACTOR := 32.0 # min taper width per unit residual; backstop bend cap for tiny chords

var _body: IVBody
var _color: Color
var _is_orbit_group_visible: bool
var _body_huds_visible: bool # too close / too far
var _body_visible: bool # tracks _body.visible
var _dirty_orbit := true

var _frame: IVBody # frame the coarse (non-rebased) line is expressed in (IVBody.get_path_frame)
var _camera: Camera3D
var _camera_body: IVBody # body the camera is parented at (camera_tree_changed 'parent')
var _rebased := false
var _rebase_offset := PackedFloat64Array([0.0, 0.0, 0.0]) # camera-body anchor in the _frame frame
var _rebake_drift: float # re-anchor threshold; = camera distance x REBAKE_DRIFT_FACTOR, set per rebake
var _rebake_cam_dist := 0.0 # camera-to-body distance at last rebake (for zoom-triggered re-tessellate)

var _line_material: ShaderMaterial # base pass; owns the color and pin shader parameters
var _id_material: ShaderMaterial # id overlay pass, or null; pin parameters mirror the base pass
var _pin_paths: Array[PackedFloat64Array] = [] # sub-paths of the last rebake, so the pin evaluates the exact curve that was drawn
var _pin_active := false

var _fragment_identifier: IVFragmentIdentifier = IVGlobal.program.get(&"FragmentIdentifier")
var _body_huds_state: IVBodyHUDsState = IVGlobal.program[&"BodyHUDsState"]


func _init(body: IVBody) -> void:
	_body = body
	name = "PathVisual_" + body.name


func _ready() -> void:
	_body.orbit_changed.connect(_on_orbit_changed)
	_body_huds_state.visibility_changed.connect(_on_global_huds_changed)
	_body_huds_state.color_changed.connect(_set_color)
	_body.huds_visibility_changed.connect(_on_body_huds_changed)
	_body.visibility_changed.connect(_on_body_visibility_changed)
	IVGlobal.camera_tree_changed.connect(_on_camera_tree_changed)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_rebased)
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	_line_material = ShaderMaterial.new()
	_line_material.shader = IVGlobal.resources[&"path_shader"]
	material_override = _line_material
	if IVCoreSettings.apply_farwarp:
		# Frustum culling tests the true-scale AABB against the far plane, but
		# farwarp-remapped vertices are on-screen even when that test fails;
		# make the test always pass wherever the camera can be.
		var extent := IVCoreSettings.max_camera_distance
		custom_aabb = AABB(-Vector3.ONE * extent, 2.0 * Vector3.ONE * extent)
	if _fragment_identifier: # add self-identifying id overlay pass
		var data := _body.get_fragment_data(FRAGMENT_BODY_ORBIT)
		var fragment_id := _fragment_identifier.get_new_id_as_vec3(data)
		_id_material = ShaderMaterial.new()
		_id_material.shader = IVGlobal.resources[&"path_id_shader"]
		_id_material.set_shader_parameter(&"fragment_id", fragment_id)
		_id_material.render_priority = 1 # draw the id stamp above the base pass
		material_overlay = _id_material
	_set_color()
	set_process(false) # enabled while the camera is focused on this body (per-frame rebase check)
	_camera = get_viewport().get_camera_3d()
	if _camera:
		_camera_body = _find_body_ancestor(_camera)
	_body_huds_visible = _body.huds_visible
	_body_visible = _body.visible
	_on_global_huds_changed()


# Single switchboard, run on each segment/element change (IVBody.orbit_changed) and camera change: resolve
# the display frame and pick the tier. Focus changes only on those events, so it is resolved here; the
# distance test changes continuously, so _process owns the coarse<->rebased flip while focused.
func _on_orbit_changed(_orbit: Object = null, _is_intrinsic := false, _precession_only := false) -> void:
	if !visible:
		_dirty_orbit = true
		return
	_dirty_orbit = false
	_frame = _body.get_path_frame()
	if _is_camera_focused():
		set_process(true)
		if _is_rebase_warranted():
			_rebake()
			return
	else:
		set_process(false)
	_render_normal()


# Tier 1: coarse rendering in the body's own frame. An orbit uses the shared unit conic mesh + transform
# (the body picks the conic); a trajectory uses its low-density polyline. Used when the camera is elsewhere
# or too far for the float32 line error to matter (see [method _is_rebase_warranted]).
func _render_normal() -> void:
	_reparent(_frame)
	_rebased = false
	_disable_pin()
	if _body.is_showing_orbit():
		var display := _body.get_orbit_display()
		var display_mesh: Mesh = display[0]
		var display_transform: Transform3D = display[1]
		mesh = display_mesh
		transform = display_transform
		return
	mesh = _build_coarse_mesh(_body.get_display_state_paths())
	transform = Transform3D.IDENTITY


# *****************************************************************************
# #17 rebased mode (Tier 2) + Hermite smoothing (Tier 3)

# The camera is at this body (orbit) or at the primary the body is CURRENTLY near (trajectory flyby); the
# body owns that decision. Gates whether _process runs at all.
func _is_camera_focused() -> bool:
	if not _camera or not _camera_body or not _frame:
		return false
	return _body.is_camera_focused(_camera_body)


# True when the non-rebased line's float32 rounding would be visible. That line is built at heliocentric
# magnitude (~ the camera-body's distance from the frame), so its absolute error ~ magnitude * 1.2e-7;
# rebase once that exceeds a sub-pixel fraction of the viewing distance. Scale-free — a close inner planet
# qualifies, a distant outer one does not. Hysteresis (half the ratio while rebased) prevents flicker.
func _is_rebase_warranted() -> bool:
	var magnitude := _camera_body.global_position.distance_to(_frame.global_position)
	var cam_dist := _camera.global_position.distance_to(_camera_body.global_position)
	if cam_dist <= 0.0:
		return magnitude > 0.0
	var threshold := REBASE_PRECISION_RATIO * 0.5 if _rebased else REBASE_PRECISION_RATIO
	return magnitude / cam_dist > threshold


# Tier 2 + 3: reparent under the camera-body, fetch the body's epoch-correct state path, rebase it to the
# near-body anchor, and build the Hermite-smoothed line. The Kepler cost is inside the body (dirty-gated,
# so a fixed orbit builds once); a drift/zoom rebake here is just the f64 subtract + Hermite (sub-ms).
func _rebake() -> void:
	var time: float = IVGlobal.times[0]
	_rebased = true
	_reparent(_camera_body)
	_rebase_offset = _camera_body.get_translation_to_ancestor(_frame, time)
	_rebake_cam_dist = _camera.global_position.distance_to(_camera_body.global_position)
	_rebake_drift = _rebake_cam_dist * REBAKE_DRIFT_FACTOR
	_pin_paths = _body.get_display_state_paths(time)
	mesh = _build_hermite_mesh(_pin_paths, _rebase_offset, _rebake_cam_dist)
	transform = Transform3D.IDENTITY # clear any leftover unit-mesh basis/scale before position tracking
	position = Vector3.ZERO # anchor == current body position at rebake; _process tracks drift from here
	_update_pin(time)


# Sets local position (relative to the camera-body parent) so the static rebased line stays coincident with
# the moving body: position = anchor - body's current frame position. Done in f64 (both ~AU) to keep the
# small drift exact — setting global_position would re-do the large-magnitude float32 cancellation this
# mode exists to avoid.
func _set_rebase_position(current_frame_position: PackedFloat64Array) -> void:
	position = Vector3(
		_rebase_offset[0] - current_frame_position[0],
		_rebase_offset[1] - current_frame_position[1],
		_rebase_offset[2] - current_frame_position[2]
	)


func _process(_delta: float) -> void:
	# Runs while the camera is focused on this body (set in _on_orbit_changed). Owns the rebased-vs-coarse
	# decision by the live viewing distance and, while rebased, the per-frame position track + rebake policy.
	if not _camera or not _camera_body or not _frame:
		return
	if not _is_rebase_warranted():
		if _rebased:
			_render_normal() # zoomed out until the float32 line error is sub-pixel again
		return
	if not _rebased or get_parent() != _camera_body:
		_rebake() # activate (camera settled close enough) or reparent pending
		return
	# Rebased and reparented under the camera-body: keep the static line on the moving body, then re-anchor
	# on drift / zoom. The re-anchor is checked (and taken) every frame with no rate cap: a rebake is cheap
	# (f64 subtract + Hermite), so a fast body re-centers its dense core each frame rather than sliding off
	# the last bake's core between anchors (which read as the body "outrunning" its line at high game speed).
	var time: float = IVGlobal.times[0]
	var current_offset := _camera_body.get_translation_to_ancestor(_frame, time)
	_set_rebase_position(current_offset)
	var need_rebake := IVMath64.distance(current_offset, _rebase_offset) > _rebake_drift
	if not need_rebake:
		# Re-tessellate as the camera zooms in / out (the Hermite step count scales with the viewing
		# distance, which is only re-read on rebake).
		var cam_dist := _camera.global_position.distance_to(_camera_body.global_position)
		need_rebake = cam_dist < _rebake_cam_dist * REBASE_ZOOM_FACTOR \
				or cam_dist > _rebake_cam_dist / REBASE_ZOOM_FACTOR
	if need_rebake:
		_rebake() # ends with its own pin update against the fresh anchor
		return
	_update_pin(time)


# Teardown: stop rebased processing before procedural bodies (this node's parent _camera_body, and _frame)
# are freed. Fires on IVStateManager.about_to_free_procedural_nodes.
func _clear_rebased() -> void:
	set_process(false)
	_rebased = false
	_disable_pin()
	_pin_paths = []


# Render-frame pin: sends the f64 body-minus-curve residual at [param time] to the line shader, which
# shifts the line's near-body window by it (see _path_pin.gdshaderinc). The tessellation bounds are
# view-relative, but this residual is absolute — Hermite bow between knots, or error in the path data
# itself — so alone it would dominate the view at close zoom no matter how dense the base path is. Runs
# every rebased frame (the body slides along the curve, so the residual is live). The taper window
# spans the bracketing knot chord (see the PIN_ constants for why never tighter).
func _update_pin(time: float) -> void:
	var curve_state := _pin_curve_position(time) # [x, y, z, chord]
	if curve_state.is_empty(): # time is off the drawn path (an open path beyond its data)
		_disable_pin()
		return
	var body_translation := _body.get_translation_to_ancestor(_frame, time)
	var residual := Vector3(
		body_translation[0] - curve_state[0],
		body_translation[1] - curve_state[1],
		body_translation[2] - curve_state[2]
	)
	var pin_center := Vector3(
		body_translation[0] - _rebase_offset[0],
		body_translation[1] - _rebase_offset[1],
		body_translation[2] - _rebase_offset[2]
	)
	var chord := curve_state[3]
	var cam_dist := _camera.global_position.distance_to(_body.global_position)
	var pin_inner := maxf(PIN_INNER_CHORD_FRACTION * chord, cam_dist)
	var pin_outer := maxf(chord, pin_inner + PIN_SLOPE_FACTOR * residual.length())
	if pin_outer <= 0.0:
		_disable_pin()
		return
	_pin_active = true
	_line_material.set_shader_parameter(&"pin_offset", residual)
	_line_material.set_shader_parameter(&"pin_center", pin_center)
	_line_material.set_shader_parameter(&"pin_inner", pin_inner)
	_line_material.set_shader_parameter(&"pin_outer", pin_outer)
	if _id_material:
		_id_material.set_shader_parameter(&"pin_offset", residual)
		_id_material.set_shader_parameter(&"pin_center", pin_center)
		_id_material.set_shader_parameter(&"pin_inner", pin_inner)
		_id_material.set_shader_parameter(&"pin_outer", pin_outer)


# Clears the shader pin (pin_outer <= 0.0 disables it) so non-rebased tiers render unshifted.
func _disable_pin() -> void:
	if not _pin_active:
		return
	_pin_active = false
	_line_material.set_shader_parameter(&"pin_outer", 0.0)
	if _id_material:
		_id_material.set_shader_parameter(&"pin_outer", 0.0)


# Evaluates the drawn curve — the same per-interval cubic Hermite that _build_hermite_mesh tessellates,
# from the same sub-paths cached at the last rebake — at [param time], in the _frame frame. Returns
# [code][x, y, z, chord][/code]: the curve position plus the bracketing knot interval's chord length,
# which sizes the pin's taper window (the residual field's correlation scale). A closed loop wraps time
# by its span, so a fixed orbit's one-period window never goes stale as time advances. Returns empty
# when [param time] is outside every open sub-path (pin disabled).
func _pin_curve_position(time: float) -> PackedFloat64Array:
	for states in _pin_paths:
		@warning_ignore("integer_division") # states is stride-7 knots [x, y, z, vx, vy, vz, t]
		var n_knots := states.size() / 7
		if n_knots < 2:
			continue
		var span_begin := states[6]
		var span_end := states[7 * (n_knots - 1) + 6]
		var curve_time := time
		if curve_time < span_begin or curve_time > span_end:
			if not _is_closed_loop(states):
				continue
			curve_time = span_begin + fposmod(curve_time - span_begin, span_end - span_begin)
		# Bisect the knot times (ascending, at stride offset 6) for the bracketing interval.
		var low := 0
		var high := n_knots - 1
		while high - low > 1:
			@warning_ignore("integer_division")
			var mid := (low + high) / 2
			if states[7 * mid + 6] <= curve_time:
				low = mid
			else:
				high = mid
		var i0 := 7 * low
		var i1 := i0 + 7
		var dt := states[i1 + 6] - states[i0 + 6]
		var u := (curve_time - states[i0 + 6]) / dt
		var p0 := states.slice(i0, i0 + 3)
		var p1 := states.slice(i1, i1 + 3)
		var m0 := PackedFloat64Array([states[i0 + 3] * dt, states[i0 + 4] * dt,
				states[i0 + 5] * dt])
		var m1 := PackedFloat64Array([states[i1 + 3] * dt, states[i1 + 4] * dt,
				states[i1 + 5] * dt])
		var chord_x := p1[0] - p0[0]
		var chord_y := p1[1] - p0[1]
		var chord_z := p1[2] - p0[2]
		var curve_state := _hermite_point(p0, m0, p1, m1, u)
		curve_state.append(sqrt(chord_x * chord_x + chord_y * chord_y + chord_z * chord_z))
		return curve_state
	return PackedFloat64Array()


# True when the sub-path's endpoints coincide relative to its scale: a closed orbit loop, never an open
# arc or transfer segment (patch points are parsecs from coinciding at this tolerance). Geometric test
# so this node stays conic-agnostic; loop closure lands ~1e-16 relative, real gaps are >=1e-2.
func _is_closed_loop(states: PackedFloat64Array) -> bool:
	var n := states.size()
	var dx := states[n - 7] - states[0]
	var dy := states[n - 6] - states[1]
	var dz := states[n - 5] - states[2]
	var scale_sq := states[0] * states[0] + states[1] * states[1] + states[2] * states[2]
	return dx * dx + dy * dy + dz * dz < 1e-18 * scale_sq


func _on_camera_tree_changed(camera: Camera3D, parent: Node3D, _star_orbiter: Node3D,
		_star: Node3D) -> void:
	_camera = camera
	var camera_body: IVBody = parent # camera_tree_changed 'parent' is always an IVBody
	_camera_body = camera_body
	# The camera moved to a new body; re-evaluate tier for the current path.
	if visible:
		_on_orbit_changed()
	else:
		_dirty_orbit = true


# *****************************************************************************
# Mesh building

# Tier 1 trajectory line: a plain low-density polyline per drawable sub-path, in the frame (no rebase).
# Absolute AU-magnitude vertices are float32-imprecise, but at this zoom the coarse line's own chords are
# larger than that error (the rebased tier takes over once the body is viewed up close).
func _build_coarse_mesh(sub_paths: Array[PackedFloat64Array]) -> ArrayMesh:
	var array_mesh := ArrayMesh.new()
	for states in sub_paths:
		@warning_ignore("integer_division") # states is stride-7 knots [x, y, z, vx, vy, vz, t]
		var n_knots := states.size() / 7
		if n_knots < 2:
			continue
		var vertices := PackedVector3Array()
		vertices.resize(n_knots)
		for k in n_knots:
			var base := 7 * k
			vertices[k] = Vector3(states[base], states[base + 1], states[base + 2])
		_add_line_strip(array_mesh, vertices)
	return array_mesh


# Tier 2 + 3: one Hermite-smoothed, rebased LINE_STRIP surface per sub-path. Sub-paths are smoothed
# independently — a trajectory's velocity is discontinuous at patch points, so a single Hermite must not
# span two segments (see [method IVTrajectory.get_display_state_paths]).
func _build_hermite_mesh(sub_paths: Array[PackedFloat64Array], offset: PackedFloat64Array,
		camera_distance: float) -> ArrayMesh:
	var array_mesh := ArrayMesh.new()
	for states in sub_paths:
		var vertices := _hermite_tessellate(states, offset, camera_distance)
		if vertices.size() >= 2:
			_add_line_strip(array_mesh, vertices)
	return array_mesh


# Cubic-Hermite tessellation of one base sub-path (stride-7 knots [x, y, z, vx, vy, vz, t]) into a
# smooth, rebased LINE_STRIP. Rebased to [param offset] (subtracted in f64 before the float32 cast, per
# issue #17). Each base interval [k, k+1] is a time-parameterized cubic (true velocities as tangents,
# m = velocity * dt) that is ADAPTIVELY subdivided so sub-chords stay ~sub-pixel: dense where the curve
# is close to the camera or sharply curved (a flyby periapsis), sparse where far and straight. Everything
# runs in double precision in the LCA frame; the viewing distance is each point's distance from the
# anchor (camera-body), floored at [param camera_distance].
func _hermite_tessellate(states: PackedFloat64Array, offset: PackedFloat64Array,
		camera_distance: float) -> PackedVector3Array:
	@warning_ignore("integer_division") # states is stride-7 knots
	var n_knots := states.size() / 7
	var vertices := PackedVector3Array()
	if n_knots < 2:
		return vertices
	var min_view := maxf(camera_distance, 0.0)
	# The tessellation runs in double precision on the LCA-frame positions; the [param offset] (near-body
	# anchor) is subtracted only on the final float32 output vertex, per issue #17. Rebasing to float32
	# BEFORE the Hermite loses precision on the body's own segment, whose base vertices can span ~100 AU
	# (a long cruise), so their large-magnitude cancellation near the anchor jitters into a sawtooth.
	vertices.append(Vector3(states[0] - offset[0], states[1] - offset[1], states[2] - offset[2]))
	var off_x := offset[0]
	var off_y := offset[1]
	var off_z := offset[2]
	for k in n_knots - 1:
		var i0 := 7 * k
		var i1 := i0 + 7
		var dt := states[i1 + 6] - states[i0 + 6]
		var p0x := states[i0]
		var p0y := states[i0 + 1]
		var p0z := states[i0 + 2]
		var p1x := states[i1]
		var p1y := states[i1 + 1]
		var p1z := states[i1 + 2]
		# Fast path: almost every base interval already satisfies the three bounds (the base is denser
		# than any of them except near the anchor), and the recursive refiner costs ~10 heap allocations
		# per call — at tens of thousands of base intervals per rebake that read as ~50 ms frames at
		# close zoom. Run the refiner's own top-level termination test with allocation-free scalar math
		# and only pay for recursion where subdivision is actually needed.
		var mid_x := 0.5 * (p0x + p1x) + 0.125 * dt * (states[i0 + 3] - states[i1 + 3])
		var mid_y := 0.5 * (p0y + p1y) + 0.125 * dt * (states[i0 + 4] - states[i1 + 4])
		var mid_z := 0.5 * (p0z + p1z) + 0.125 * dt * (states[i0 + 5] - states[i1 + 5])
		var chord_x := p1x - p0x
		var chord_y := p1y - p0y
		var chord_z := p1z - p0z
		var chord := sqrt(chord_x * chord_x + chord_y * chord_y + chord_z * chord_z)
		var deviation := 0.0
		if chord > 0.0:
			var mid_dx := mid_x - p0x
			var mid_dy := mid_y - p0y
			var mid_dz := mid_z - p0z
			var cross_x := chord_y * mid_dz - chord_z * mid_dy
			var cross_y := chord_z * mid_dx - chord_x * mid_dz
			var cross_z := chord_x * mid_dy - chord_y * mid_dx
			deviation = sqrt(cross_x * cross_x + cross_y * cross_y + cross_z * cross_z) / chord
		var d0x := p0x - off_x
		var d0y := p0y - off_y
		var d0z := p0z - off_z
		var view := sqrt(d0x * d0x + d0y * d0y + d0z * d0z)
		var dmx := mid_x - off_x
		var dmy := mid_y - off_y
		var dmz := mid_z - off_z
		var dist_mid := sqrt(dmx * dmx + dmy * dmy + dmz * dmz)
		if dist_mid < view:
			view = dist_mid
		var d1x := p1x - off_x
		var d1y := p1y - off_y
		var d1z := p1z - off_z
		var dist1 := sqrt(d1x * d1x + d1y * d1y + d1z * d1z)
		if dist1 < view:
			view = dist1
		if view < min_view:
			view = min_view
		if chord <= REBASE_CHORD_LENGTH_FACTOR * view and deviation <= REBASE_CHORD_TOLERANCE * view \
				and deviation <= REBASE_BEND_RATIO * chord:
			vertices.append(Vector3(p1x - off_x, p1y - off_y, p1z - off_z))
			continue
		var p0 := PackedFloat64Array([p0x, p0y, p0z])
		var p1 := PackedFloat64Array([p1x, p1y, p1z])
		var m0 := PackedFloat64Array([states[i0 + 3] * dt, states[i0 + 4] * dt,
				states[i0 + 5] * dt])
		var m1 := PackedFloat64Array([states[i1 + 3] * dt, states[i1 + 4] * dt,
				states[i1 + 5] * dt])
		_refine_hermite(p0, m0, p1, m1, 0.0, 1.0, p0, p1, offset, min_view, 0, vertices)
		vertices.append(Vector3(p1x - off_x, p1y - off_y, p1z - off_z))
	return vertices


# Recursively bisects the Hermite segment parameter interval ([param u_a], [param u_b]) for
# [method _hermite_tessellate], appending interior points (ascending) while the bracket's chord is too long
# for the viewing distance ([constant REBASE_CHORD_LENGTH_FACTOR], LOD), OR the curve's deviation from the
# chord exceeds [constant REBASE_CHORD_TOLERANCE] of it (curvature — this is what keeps the body ON the
# line), OR the deviation exceeds [constant REBASE_BEND_RATIO] of the chord itself (bend — caps the corner
# angle between adjacent sub-chords, which the view-scaled terms leave unbounded). Viewing distance is the
# nearest of the three known points to the camera (the rebased origin), floored at [param min_view].
# Bounded by [constant ADAPTIVE_MAX_DEPTH] and [constant REBASE_MAX_VERTICES].
func _refine_hermite(p0: PackedFloat64Array, m0: PackedFloat64Array, p1: PackedFloat64Array,
		m1: PackedFloat64Array, u_a: float, u_b: float, point_a: PackedFloat64Array,
		point_b: PackedFloat64Array, offset: PackedFloat64Array, min_view: float,
		depth: int, vertices: PackedVector3Array) -> void:
	if depth >= ADAPTIVE_MAX_DEPTH or vertices.size() >= REBASE_MAX_VERTICES:
		return
	var u_mid := 0.5 * (u_a + u_b)
	var point_mid := _hermite_point(p0, m0, p1, m1, u_mid)
	# chord and deviation are differences (the anchor cancels), so they stay exact in the LCA frame; the
	# viewing distance is each point's distance from the rebased origin (the camera-body, at the anchor).
	var chord_x := point_b[0] - point_a[0]
	var chord_y := point_b[1] - point_a[1]
	var chord_z := point_b[2] - point_a[2]
	var chord := sqrt(chord_x * chord_x + chord_y * chord_y + chord_z * chord_z)
	var deviation := 0.0
	if chord > 0.0:
		var mid_x := point_mid[0] - point_a[0]
		var mid_y := point_mid[1] - point_a[1]
		var mid_z := point_mid[2] - point_a[2]
		var cross_x := chord_y * mid_z - chord_z * mid_y
		var cross_y := chord_z * mid_x - chord_x * mid_z
		var cross_z := chord_x * mid_y - chord_y * mid_x
		deviation = sqrt(cross_x * cross_x + cross_y * cross_y + cross_z * cross_z) / chord
	# The first two terms scale with the viewing distance (nearest of the three points to the anchor,
	# floored at min_view): distant arc relaxes to coarse chords while the near field around the body —
	# which the rebake re-centers every frame — stays sub-pixel and keeps the body ON its line. The bend
	# term is scale-free: without it, corner angles reach ~3 deg wherever the curvature radius is a few
	# times the viewing distance (a mid-field orbit arc), visibly faceting the line at any zoom.
	var bracket := minf(_view_distance(point_a, offset),
			minf(_view_distance(point_mid, offset), _view_distance(point_b, offset)))
	var view := maxf(bracket, min_view)
	if chord <= REBASE_CHORD_LENGTH_FACTOR * view and deviation <= REBASE_CHORD_TOLERANCE * view \
			and deviation <= REBASE_BEND_RATIO * chord:
		return
	_refine_hermite(p0, m0, p1, m1, u_a, u_mid, point_a, point_mid, offset, min_view, depth + 1, vertices)
	vertices.append(Vector3(point_mid[0] - offset[0], point_mid[1] - offset[1], point_mid[2] - offset[2]))
	_refine_hermite(p0, m0, p1, m1, u_mid, u_b, point_mid, point_b, offset, min_view, depth + 1, vertices)


# Cubic Hermite basis at [param u] for endpoints/tangents (all size-3 double-precision), returned in the
# same LCA frame (not yet rebased).
func _hermite_point(p0: PackedFloat64Array, m0: PackedFloat64Array, p1: PackedFloat64Array,
		m1: PackedFloat64Array, u: float) -> PackedFloat64Array:
	var u2 := u * u
	var u3 := u2 * u
	var h00 := 2.0 * u3 - 3.0 * u2 + 1.0
	var h10 := u3 - 2.0 * u2 + u
	var h01 := -2.0 * u3 + 3.0 * u2
	var h11 := u3 - u2
	return PackedFloat64Array([
		h00 * p0[0] + h10 * m0[0] + h01 * p1[0] + h11 * m1[0],
		h00 * p0[1] + h10 * m0[1] + h01 * p1[1] + h11 * m1[1],
		h00 * p0[2] + h10 * m0[2] + h01 * p1[2] + h11 * m1[2],
	])


# Distance from a size-3 LCA-frame [param point] to the [param anchor] (the rebased origin / camera-body).
func _view_distance(point: PackedFloat64Array, anchor: PackedFloat64Array) -> float:
	var dx := point[0] - anchor[0]
	var dy := point[1] - anchor[1]
	var dz := point[2] - anchor[2]
	return sqrt(dx * dx + dy * dy + dz * dz)


# Adds a single LINE_STRIP surface to [param array_mesh]. Main-thread only (touches the RenderingServer).
func _add_line_strip(array_mesh: ArrayMesh, vertices: PackedVector3Array) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)


# Moves this node under [param new_parent] (the display frame, or the camera-body when rebased),
# matching IVBody.set_orbit_and_parent's idiom.
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


# *****************************************************************************
# Visibility and color

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
		_on_orbit_changed()


func _set_color() -> void:
	var color := _body_huds_state.get_color(_body.flags)
	if _color == color:
		return
	_color = color
	_line_material.set_shader_parameter(&"color", color)
