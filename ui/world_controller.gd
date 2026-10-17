# world_controller.gd
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
class_name IVWorldController
extends Control

## Interface between the user mouse and the 3D world.
##
## Receives mouse events in the 3D world area, sets cursor shape and interprets
## mouse drags, clicks and wheel turn. A potential mouse target is reported each
## frame it can be hovered, through [method update_world_target] for the disc or
## point it draws and [method update_world_target_rect] for a HUD element that marks
## it; one not reported in a frame is not a target in that frame.[br][br]
##
## Of the targets under the cursor, the disc whose surface is nearest the camera is
## what the cursor is on, so a body in front of another can be hovered. A HUD element
## wins over that disc where it is drawn, which is wherever no other body's disc lies in
## front of its body (HUDs are depth-tested; a point of light hides nothing); among such
## HUD elements, which overlap as flat overlays, the one whose body is nearest the cursor
## on screen wins. A body's own disc does not hide its own HUD, so the body keeps the
## pixels at its centre. The frame's target is settled at process priority +200, after
## every reporter has run.

## Emitted when the Node3D under the mouse changes; [param target] is null
## when nothing is under the cursor.
signal mouse_target_changed(target: Object)
## Emitted on mouse click over an active target. [param button_mask] /
## [param key_modifier_mask] reflect the input state when clicked.
signal mouse_target_clicked(target: Object, button_mask: int, key_modifier_mask: int)
## Emitted while the mouse is being dragged in the 3D viewport.
## [param drag_vector] is the per-frame motion in logical pixels (see [IVGraphicsManager]).
signal mouse_dragged(drag_vector: Vector2, button_mask: int, key_modifier_mask: int)
## Emitted on mouse-wheel input, once per turn. [param is_up] is true for wheel-up,
## false for wheel-down. [param factor] is the turn amount, but its unit is a platform
## detail rather than a notch: desktop reports 1.0 per notch (macOS, 0.3-0.9), web reports
## a raw scroll delta (one notch is 3.0 in Chrome, 0.9 in Firefox), and a precise device
## such as a trackpad reports a small fraction of a turn many times per frame. A receiver
## that scales motion by it should bound one event's contribution.
signal mouse_wheel_turned(is_up: bool, factor: float)


# project settings
## Minimum hover radius of a disc target, in logical pixels. At 0.0 a target is
## exactly as easy to hit as it is large on screen.
var min_click_radius := 0.0

# read-only!
## The active 3D camera. Read-only.
var camera: Camera3D
## The Node3D currently under the mouse, or null. Read-only.
var current_target: Node3D
## Current mouse cursor shape. Read-only.
var cursor_shape := CURSOR_ARROW
## Most recent mouse position in viewport coordinates. Read-only.
var mouse_position := Vector2.ZERO
## True while the mouse is over the 3D world, false while it is over a GUI panel
## or outside the window. Read-only.
var is_mouse_in_world := false

@onready var veiwport_height := get_viewport().get_visible_rect().size.y

# private
const _DRAG_BUTTONS := MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT # left or right button drags
var _drag_start := Vector2.ZERO
# this frame's candidates under the cursor, settled in _process()
var _disc_hits: Array[Node3D] = []
var _disc_hit_depths := PackedFloat64Array() # camera distance of what the cursor is on
var _disc_hit_cover_depths := PackedFloat64Array() # ditto, but INF unless on the disc itself
var _hud_hits: Array[Node3D] = []
var _hud_hit_dists := PackedFloat64Array() # camera distance of each hit's body
var _hud_hit_screen_dists := PackedFloat64Array() # screen distance, cursor to body



func _init() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect(_restore_init_state)
	IVGlobal.current_camera_changed.connect(_set_camera)


func _ready() -> void:
	process_priority = 200 # after every target has reported; see class doc
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	IVGlobal.viewport_size_changed.connect(_on_viewport_size_changed)


func _process(_delta: float) -> void:
	var target: Node3D
	var target_depth := INF
	for i in _disc_hits.size():
		if _disc_hit_depths[i] < target_depth:
			target = _disc_hits[i]
			target_depth = _disc_hit_depths[i]
	var target_screen_dist := INF
	for i in _hud_hits.size():
		if _hud_hit_screen_dists[i] < target_screen_dist and !_is_hud_hit_hidden(i):
			target = _hud_hits[i]
			target_screen_dist = _hud_hit_screen_dists[i]
	if !is_mouse_in_world:
		target = null
	_clear_candidates()
	if current_target != target:
		current_target = target
		mouse_target_changed.emit(target)
	if _drag_start:
		cursor_shape = CURSOR_MOVE
	elif current_target:
		cursor_shape = CURSOR_POINTING_HAND
	else:
		cursor_shape = CURSOR_ARROW
	# TODO: When we can have interaction with asteroid point, that will
	# cause pointy finger too.
	set_default_cursor_shape(cursor_shape)


func _gui_input(input_event: InputEvent) -> void:
	# _gui_input events are consumed
	var event := input_event as InputEventMouse
	if !event:
		return # is this possible?
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion:
		mouse_position = mouse_motion.position
		var button_mask := mouse_motion.button_mask
		# Gate on the live button state; a drag then can't outlive the physical release,
		# even when that release is delivered to a popup instead of this Control.
		if button_mask & _DRAG_BUTTONS:
			mouse_dragged.emit(mouse_motion.relative, button_mask,
					_get_key_modifier_mask(mouse_motion))
		else:
			_drag_start = Vector2.ZERO # clear a press anchor stranded by a release we never saw
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button:
		var button_index: int = mouse_button.button_index
		# BUTTON_WHEEL_UP & _DOWN always fire twice (pressed then not pressed), carrying the
		# same factor both times; a receiver that accumulates would count the turn twice.
		if button_index == MOUSE_BUTTON_WHEEL_UP:
			if mouse_button.pressed:
				mouse_wheel_turned.emit(true, mouse_button.factor)
			return
		if button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mouse_button.pressed:
				mouse_wheel_turned.emit(false, mouse_button.factor)
			return
		# Left/right press records a click anchor; the release decides click vs. drag.
		if button_index == MOUSE_BUTTON_LEFT or button_index == MOUSE_BUTTON_RIGHT:
			if mouse_button.pressed:
				_drag_start = mouse_button.position
			else:
				# Press and release on the same pixel (no motion between) is a click.
				if _drag_start == mouse_button.position and current_target:
					mouse_target_clicked.emit(current_target, mouse_button.button_mask,
							_get_key_modifier_mask(mouse_button))
				_drag_start = Vector2.ZERO


## Returns 0.0 if there is no camera, (+) camera distance if [param node3d] is
## in front of camera, or (-) camera distance if behind.
func get_camera_distance_signed(node3d: Node3D) -> float:
	if !camera:
		return 0.0
	var node3d_global_position := node3d.global_position
	var camera_dist := node3d_global_position.distance_to(camera.global_position)
	return -camera_dist if camera.is_position_behind(node3d_global_position) else camera_dist


## Reports [param node3d] as hoverable this frame by the disc it draws: [param radius]
## in world units at [param camera_dist], or [param min_screen_radius] logical pixels
## if that is larger (a point of light outdrawing its disc).
func update_world_target(node3d: Node3D, camera_dist: float, radius: float,
		min_screen_radius := 0.0) -> void:
	if !camera:
		return
	var disc_radius := 0.0
	var divisor := camera.fov * camera_dist
	if divisor > 0.0:
		disc_radius = 55.0 * radius * veiwport_height / divisor
	var click_radius := maxf(disc_radius, maxf(min_click_radius, min_screen_radius))
	var mouse_dist := camera.unproject_position(node3d.global_position).distance_to(mouse_position)
	if mouse_dist >= click_radius:
		return
	# The sphere's near surface under the cursor; a hit only by point or minimum radius
	# is taken at the body's centre, and hides nothing.
	var depth := camera_dist
	var cover_depth := INF
	if mouse_dist < disc_radius:
		var fraction := mouse_dist / disc_radius
		depth -= radius * sqrt(1.0 - fraction * fraction)
		cover_depth = depth
	_disc_hits.append(node3d)
	_disc_hit_depths.append(depth)
	_disc_hit_cover_depths.append(cover_depth)


## Reports [param node3d] as hoverable this frame by a HUD element that marks it:
## [param rect] in logical pixels, relative to [param node3d]'s screen position, drawn at
## [param camera_dist]. The caller must not report a [param node3d] behind the camera.
func update_world_target_rect(node3d: Node3D, camera_dist: float, rect: Rect2) -> void:
	if !camera:
		return
	var offset := mouse_position - camera.unproject_position(node3d.global_position)
	if !rect.has_point(offset):
		return
	_hud_hits.append(node3d)
	_hud_hit_dists.append(camera_dist)
	_hud_hit_screen_dists.append(offset.length())


## Drops [param node3d] as a target at once, rather than at the end of the frame.
func remove_world_target(node3d: Node3D) -> void:
	var disc_index := _disc_hits.find(node3d)
	while disc_index != -1:
		_disc_hits.remove_at(disc_index)
		_disc_hit_depths.remove_at(disc_index)
		_disc_hit_cover_depths.remove_at(disc_index)
		disc_index = _disc_hits.find(node3d)
	var index := _hud_hits.find(node3d)
	while index != -1:
		_hud_hits.remove_at(index)
		_hud_hit_dists.remove_at(index)
		_hud_hit_screen_dists.remove_at(index)
		index = _hud_hits.find(node3d)
	if node3d == current_target:
		current_target = null
		mouse_target_changed.emit(null)


func _restore_init_state() -> void:
	camera = null
	current_target = null
	_clear_candidates()
	_drag_start = Vector2.ZERO
	is_mouse_in_world = false


func _on_mouse_entered() -> void:
	is_mouse_in_world = true


func _on_mouse_exited() -> void:
	# Moving onto a GUI panel (a sibling Control drawn on top) or off the window
	# stops _gui_input here, freezing mouse_position over the last world target.
	# Drop the target so the mouse-target label and fragment tooltip don't stick.
	is_mouse_in_world = false
	if current_target:
		current_target = null
		mouse_target_changed.emit(null)


func _is_hud_hit_hidden(hud_index: int) -> bool:
	var hud_body := _hud_hits[hud_index]
	var hud_dist := _hud_hit_dists[hud_index]
	for i in _disc_hits.size():
		if _disc_hit_cover_depths[i] < hud_dist and _disc_hits[i] != hud_body:
			return true
	return false


func _clear_candidates() -> void:
	_disc_hits.clear()
	_disc_hit_depths.clear()
	_disc_hit_cover_depths.clear()
	_hud_hits.clear()
	_hud_hit_dists.clear()
	_hud_hit_screen_dists.clear()


func _set_camera(camera_: Camera3D) -> void:
	camera = camera_


func _get_key_modifier_mask(event: InputEventMouse) -> int:
	var mask := 0
	if event.alt_pressed:
		mask |= KEY_MASK_ALT
	if event.shift_pressed:
		mask |= KEY_MASK_SHIFT
	if event.ctrl_pressed:
		mask |= KEY_MASK_CTRL
	if event.meta_pressed:
		mask |= KEY_MASK_META
	# FIXME: Mac Command
#	if event.command:
#		mask |= KEY_MASK_CMD
	return mask


func _on_viewport_size_changed(viewport_size: Vector2) -> void:
	veiwport_height = viewport_size.y
