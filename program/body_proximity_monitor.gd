# body_proximity_monitor.gd
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
class_name IVBodyProximityMonitor
extends Node

## Decides each frame what the camera can see of every [IVBody]: sleeps and wakes
## bodies, sets their HUD visibility, and reports them as mouse targets.
##
## Three things are kept apart per body: whether it is physically visible (draws a disc
## or a point of light), whether it is visually separable from its parent, and whether
## its HUDs show. A body with [enum IVBody.BodyFlags] BODYFLAGS_CAN_SLEEP (table column
## [code]sleep[/code]) sleeps while it is neither visible nor showing a HUD; its disc or
## point is a mouse target while it is visible and separable, and its name and symbol
## report themselves ([IVBodyPositionVisual]). See [i]Culling, visibility and
## lifecycle[/i] in VISUAL_MODEL.md.[br][br]
##
## Some bodies stay awake at any distance: the body the camera hangs from, an
## [IVCamera]'s [member IVCamera.target], and any passed to [method pin_awake], which is
## how a project driving its own camera holds its target. No body sleeps while a
## descendant is awake.[br][br]
##
## Processes at priority +99, after the camera has moved and before the +100 managers
## that read the bodies it wakes. Required: without it no HUD shows and nothing can be
## hovered. Only this node should call [method IVBody.set_sleeping] and
## [method IVBody.set_huds_visible].


const CAN_SLEEP := IVBody.BodyFlags.BODYFLAGS_CAN_SLEEP
const STAR := IVBody.BodyFlags.BODYFLAGS_STAR

## Ratio of the distance at which an awake body sleeps to the distance at which it
## wakes. Above 1.0, so a camera at the boundary cannot toggle a body every frame.
var sleep_distance_ratio := 1.5

var _world_controller: IVWorldController
var _body_huds_state: IVBodyHUDsState
var _hides_huds_when_close := false
var _is_dirty := true
var _body_count := 0
# Every body, parents before their satellites.
var _bodies: Array[IVBody] = []
var _min_hud_distances := PackedFloat64Array() # by _bodies index
var _draws_points := PackedByteArray() # by _bodies index
# Sleepable bodies grouped by parent, every group after its parent's own group.
var _sleepers: Array[IVBody] = []
var _wake_distances := PackedFloat64Array() # by _sleepers index; from the parent
var _group_parents: Array[IVBody] = []
var _group_ends := PackedInt32Array() # _sleepers index past each group's last
# No unheld member of a group changes state while its parent's distance stays in
# [lower, upper); a NAN lower forces the group to be looked at.
var _group_lower_distances := PackedFloat64Array()
var _group_upper_distances := PackedFloat64Array()
var _group_indices: Dictionary[IVBody, int] = {}
var _held: Dictionary[IVBody, bool] = {}
var _previously_held: Dictionary[IVBody, bool] = {}
var _pinned: Dictionary[StringName, bool] = {}



func _ready() -> void:
	set_process_priority(99) # after IVCamera, before the +100 consumers; see class doc
	set_process(false)
	_world_controller = IVGlobal.program[&"WorldController"]
	_body_huds_state = IVGlobal.program[&"BodyHUDsState"]
	_hides_huds_when_close = IVSettingsManager.get_setting(&"hide_hud_when_close")
	_body_huds_state.visibility_changed.connect(_mark_dirty)
	_body_huds_state.symbol_changed.connect(_mark_dirty)
	IVSettingsManager.changed.connect(_settings_listener)
	IVStateManager.system_tree_ready.connect(_on_system_tree_ready)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if !camera:
		return
	if _is_dirty or IVBody.bodies.size() != _body_count:
		_rebuild()
	var camera_position := camera.global_position
	_update_held(camera)
	_update_sleep(camera_position)
	_update_awake(camera, camera_position)


## Keeps [param body] and its ancestors awake at any distance until
## [method unpin_awake]. For a project whose own camera has a target.
func pin_awake(body: IVBody) -> void:
	_pinned[body.name] = true


## Releases a body held by [method pin_awake].
func unpin_awake(body: IVBody) -> void:
	_pinned.erase(body.name)


func _clear_procedural() -> void:
	set_process(false)
	_is_dirty = true
	_body_count = 0
	_clear_tables()
	_pinned.clear()


func _clear_tables() -> void:
	_bodies.clear()
	_min_hud_distances.clear()
	_draws_points.clear()
	_sleepers.clear()
	_wake_distances.clear()
	_group_parents.clear()
	_group_ends.clear()
	_group_lower_distances.clear()
	_group_upper_distances.clear()
	_group_indices.clear()
	_held.clear()
	_previously_held.clear()


func _on_system_tree_ready(_is_new_game: bool) -> void:
	_is_dirty = true
	set_process(true)


func _mark_dirty() -> void:
	_is_dirty = true


func _settings_listener(setting: StringName, value: Variant) -> void:
	if setting != &"hide_hud_when_close":
		return
	_hides_huds_when_close = value
	_is_dirty = true


func _on_orbit_changed(_orbit: IVOrbit, _is_intrinsic: bool, precession_only: bool) -> void:
	if !precession_only:
		_is_dirty = true


func _on_parent_changed(_new_parent: IVBody) -> void:
	_is_dirty = true


func _rebuild() -> void:
	_is_dirty = false
	_body_count = IVBody.bodies.size()
	_clear_tables()
	var queue: Array[IVBody] = IVBody.top_bodies.values()
	var queue_index := 0
	while queue_index < queue.size():
		var parent := queue[queue_index]
		queue_index += 1
		_bodies.append(parent)
		_min_hud_distances.append(_get_min_hud_distance(parent))
		_draws_points.append(1 if IVBodyPSF.is_applicable(parent) else 0)
		var group_start := _sleepers.size()
		for satellite in parent.ordered_satellites:
			queue.append(satellite)
			if !satellite.orbit_changed.is_connected(_on_orbit_changed):
				satellite.orbit_changed.connect(_on_orbit_changed)
				satellite.parent_changed.connect(_on_parent_changed)
			if !(satellite.flags & CAN_SLEEP):
				continue
			var wake_distance := _get_wake_distance(satellite)
			if is_inf(wake_distance):
				satellite.set_sleeping(false) # never sleeps, so never needs looking at
				continue
			_group_indices[satellite] = _group_parents.size()
			_sleepers.append(satellite)
			_wake_distances.append(wake_distance)
		if _sleepers.size() == group_start:
			continue
		_group_parents.append(parent)
		_group_ends.append(_sleepers.size())
		_group_lower_distances.append(NAN)
		_group_upper_distances.append(INF)


func _get_min_hud_distance(body: IVBody) -> float:
	if !_hides_huds_when_close:
		return 0.0
	var distance := body.mean_radius * IVBody.min_hud_dist_radius_multiplier
	if body.flags & STAR:
		distance *= IVBody.min_hud_dist_star_multiplier # a star grows at distance
	return distance


# INF for a body that must never sleep, and for any body above one: a sleeping body's
# stale position would misplace an awake descendant.
func _get_wake_distance(body: IVBody) -> float:
	if !(body.flags & CAN_SLEEP) or IVBodyPSF.is_applicable(body):
		return INF # a point of light can show from any distance
	var orbit := body.get_orbit()
	if !orbit:
		return INF
	var apoapsis := orbit.get_apoapsis()
	var hud_reach := 0.0
	if _shows_any_hud(body.flags):
		hud_reach = apoapsis * IVBody.min_visual_separation_multiplier
	var shell_reach := body.mean_radius * IVCoreSettings.radius_multiplier_visibility_range_end
	var reach := maxf(hud_reach, shell_reach)
	for satellite_name in body.satellites:
		reach = maxf(reach, _get_wake_distance(body.satellites[satellite_name]))
	return reach + apoapsis # the body may be that much nearer the camera than its parent


func _shows_any_hud(body_flags: int) -> bool:
	if _body_huds_state.huds_hidden:
		return false
	return (_body_huds_state.is_name_visible(body_flags)
			or _body_huds_state.is_orbit_visible(body_flags)
			or (_body_huds_state.is_symbol_visible(body_flags)
			and _body_huds_state.get_symbol_type(body_flags) >= 0))


func _update_held(camera: Camera3D) -> void:
	var recycled := _previously_held
	_previously_held = _held
	_held = recycled
	_held.clear()
	# v0.2's camera transform composes through the body it hangs from.
	_hold(_get_body_at_or_above(camera.get_parent()))
	# IVCamera flies toward its target's live position, which a sleeping target lacks.
	var ivcamera := camera as IVCamera
	if ivcamera:
		_hold(_get_body_at_or_above(ivcamera.target))
	for body_name in _pinned:
		if IVBody.bodies.has(body_name):
			_hold(IVBody.bodies[body_name])
	for body in _previously_held:
		if !_held.has(body) and _group_indices.has(body):
			_group_lower_distances[_group_indices[body]] = NAN


func _hold(body: IVBody) -> void:
	while body and !_held.has(body):
		_held[body] = true
		if _group_indices.has(body):
			body.set_sleeping(false)
		body = body.parent


func _get_body_at_or_above(node: Node) -> IVBody:
	while node:
		var body := node as IVBody
		if body:
			return body
		node = node.get_parent()
	return null


func _update_sleep(camera_position: Vector3) -> void:
	var start := 0
	for group in _group_parents.size():
		var end := _group_ends[group]
		var parent := _group_parents[group]
		var distance := (INF if parent.is_sleeping()
				else camera_position.distance_to(parent.global_position))
		var upper := _group_upper_distances[group]
		if distance >= _group_lower_distances[group] and (distance < upper or is_inf(upper)):
			start = end
			continue
		var lower := 0.0
		upper = INF
		for i in range(start, end):
			var sleeper := _sleepers[i]
			if _held.has(sleeper):
				continue # awake while held; its group is looked at again on release
			var wake_distance := _wake_distances[i]
			var sleep_distance := wake_distance * sleep_distance_ratio
			var is_sleeping := sleeper.is_sleeping()
			var is_awake := distance < (wake_distance if is_sleeping else sleep_distance)
			if is_awake == is_sleeping:
				sleeper.set_sleeping(!is_awake)
			if is_awake:
				upper = minf(upper, sleep_distance)
			else:
				lower = maxf(lower, wake_distance)
		_group_lower_distances[group] = lower
		_group_upper_distances[group] = upper
		start = end


func _update_awake(camera: Camera3D, camera_position: Vector3) -> void:
	var separation_multiplier := IVBody.min_visual_separation_multiplier
	var range_end_multiplier := IVCoreSettings.radius_multiplier_visibility_range_end
	# IVBody.psf_handoff is in render pixels; mouse targets are in logical pixels.
	var point_scale := 1.0 / (IVGlobal.get_window().content_scale_factor
			* get_viewport().scaling_3d_scale)
	for i in _bodies.size():
		var body := _bodies[i]
		if body.is_sleeping() or !body.within_lifespan:
			continue # set_sleeping() dropped its HUDs; a lifespan-hidden body keeps its own
		var body_position := body.global_position
		var camera_dist := camera_position.distance_to(body_position)
		var trajectory := body.get_trajectory()
		var is_separable := ((trajectory and trajectory.get_lca() != body.parent)
				or camera_dist < body.position.length() * separation_multiplier)
		body.set_huds_visible(is_separable and camera_dist > _min_hud_distances[i])
		if !is_separable or camera.is_position_behind(body_position):
			continue
		var point_radius := body.psf_handoff.y * point_scale if _draws_points[i] else 0.0
		if (!point_radius and (!body.body_visual
				or camera_dist >= body.mean_radius * range_end_multiplier)):
			continue # nothing of it is drawn
		_world_controller.update_world_target(body, camera_dist, body.mean_radius, point_radius)
