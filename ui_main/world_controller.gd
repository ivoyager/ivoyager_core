# world_controller.gd
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
class_name IVWorldController
extends Control

## Interface between the user mouse and the 3D world.
##
## Receives mouse events in the 3D world area, sets cursor shape and interprets
## mouse drags, clicks and wheel turn. Potential mouse target Node3Ds must
## call [method update_world_target] each frame to be available for mouse-over
## identification and selection.

signal mouse_target_changed(target: Object)
signal mouse_target_clicked(target: Object, button_mask: int, key_modifier_mask: int)
signal mouse_dragged(drag_vector: Vector2, button_mask: int, key_modifier_mask: int)
signal mouse_wheel_turned(is_up: bool)


# project settings
var min_click_radius := 20.0

# read-only!
var camera: Camera3D
var current_target: Node3D
var cursor_shape := CURSOR_ARROW
var mouse_position := Vector2.ZERO

@onready var veiwport_height := get_viewport().get_visible_rect().size.y

# private
var _pause_only_stops_time: bool = IVCoreSettings.pause_only_stops_time
var _drag_start := Vector2.ZERO
var _drag_segment_start := Vector2.ZERO
var _suppress_mouse_control := true # blocks signals EXCEPT 'mouse_target_changed'
var _current_target_dist := INF



func _init() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect(_restore_init_state)
	IVStateManager.paused_changed.connect(_on_paused_changed)
	IVGlobal.camera_ready.connect(_set_camera)


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS # but some functionaly stops if !pause_only_stops_time
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	IVGlobal.viewport_size_changed.connect(_on_viewport_size_changed)


func _process(_delta: float) -> void:
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
		if _suppress_mouse_control:
			return
		if _drag_segment_start: # accumulated mouse drag motion
			var drag_vector := mouse_position - _drag_segment_start
			_drag_segment_start = mouse_position
			mouse_dragged.emit(drag_vector, mouse_motion.button_mask,
					_get_key_modifier_mask(mouse_motion))
		return
	if _suppress_mouse_control:
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button:
		var button_index: int = mouse_button.button_index
		# BUTTON_WHEEL_UP & _DOWN always fires twice (pressed then not pressed)
		if button_index == MOUSE_BUTTON_WHEEL_UP:
			mouse_wheel_turned.emit(true)
			return
		if button_index == MOUSE_BUTTON_WHEEL_DOWN:
			mouse_wheel_turned.emit(false)
			return
		# start/stop mouse drag or process a mouse click
		if button_index == MOUSE_BUTTON_LEFT or button_index == MOUSE_BUTTON_RIGHT:
			if mouse_button.pressed: # start of drag or button-down for click selection
				_drag_start = mouse_button.position
				_drag_segment_start = _drag_start
			else: # end of drag or button-up after click selection
				if _drag_start == mouse_button.position: # was a mouse click!
					if current_target: # mouse_target
						mouse_target_clicked.emit(current_target, mouse_button.button_mask,
								_get_key_modifier_mask(mouse_button))
				_drag_start = Vector2.ZERO
				_drag_segment_start = Vector2.ZERO



## Potential mouse targets must call this every frame to be available for
## mouse-over identification and selection. Return value is distance from
## target to the camera.
func update_world_target(node3d: Node3D, radius: float) -> float:
	if !camera:
		return 0.0
	var node3d_global_position := node3d.global_position
	var camera_dist := node3d_global_position.distance_to(camera.global_position)
	var is_in_mouse_click_radius := false
	if !camera.is_position_behind(node3d_global_position):
		var pos2d := camera.unproject_position(node3d_global_position)
		var mouse_dist := pos2d.distance_to(mouse_position)
		var click_radius := min_click_radius
		var divisor := camera.fov * camera_dist
		if divisor > 0.0:
			var screen_radius := 55.0 * radius * veiwport_height / divisor
			if click_radius < screen_radius:
				click_radius = screen_radius
		if mouse_dist < click_radius:
			is_in_mouse_click_radius = true
	
	# set/unset this node3d as mouse target
	if is_in_mouse_click_radius:
		if node3d != current_target:
			if camera_dist < _current_target_dist: # make node3d the mouse target
				current_target = node3d
				_current_target_dist = camera_dist
				mouse_target_changed.emit(node3d)
		else:
			_current_target_dist = camera_dist
	elif node3d == current_target: # remove node3d as mouse target
		current_target = null
		_current_target_dist = INF
		mouse_target_changed.emit(null)
	
	return camera_dist


func remove_world_target(node3d: Node3D) -> void:
	if node3d == current_target:
		current_target = null
		_current_target_dist = INF



func _restore_init_state() -> void:
	camera = null
	current_target = null
	_current_target_dist = INF
	_drag_start = Vector2.ZERO
	_drag_segment_start = Vector2.ZERO


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


func _on_paused_changed(paused_tree: bool, _paused_by_user: bool) -> void:
	if paused_tree:
		if !_pause_only_stops_time:
			_suppress_mouse_control = true
			_drag_start = Vector2.ZERO
			_drag_segment_start = Vector2.ZERO
	else:
		_suppress_mouse_control = false


func _on_viewport_size_changed(viewport_size: Vector2) -> void:
	veiwport_height = viewport_size.y
