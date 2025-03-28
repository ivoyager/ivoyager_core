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

## Receives mouse events in the 3D world area, sets cursor shape and interprets
## mouse drags, clicks and wheel turn.

# TODO: Below should really be a dictionary...
# Inits IVGlobal.world_targeting, which has elements:
#  [0] mouse_position: Vector2 (this object sets)
#  [1] veiwport_height: float (this object sets)
#  [2] camera: Camera (camera sets)
#  [3] camera_fov: float (camera sets)
#  [4] current_mouse_target: Object (targets set/unset themselves; e.g., see IVBody)
#  [5] current_mouse_target_dist: float (as above)
#  [6] current_fragment_id: int (a shader target; IVFragmentIdentifier sets)
#  [7] current_cursor_type: int (this object sets)
#
#  The single instance of this node is added by IVCoreInitializer.


signal mouse_target_changed(target: Object)
signal mouse_target_clicked(target: Object, button_mask: int, key_modifier_mask: int)
signal mouse_dragged(drag_vector: Vector2, button_mask: int, key_modifier_mask: int)
signal mouse_wheel_turned(is_up: bool)


# read-only!
var current_target: Object = null

# private
var _world_targeting: Array = IVGlobal.world_targeting
var _pause_only_stops_time: bool = IVCoreSettings.pause_only_stops_time
var _drag_start := Vector2.ZERO
var _drag_segment_start := Vector2.ZERO
var _has_mouse := true
var _suppress_mouse_control := true # blocks signals EXCEPT 'mouse_target_changed'


func _init() -> void:
	IVGlobal.about_to_free_procedural_nodes.connect(_clear)
	# see 'IVGlobal.world_targeting' comments above
	_world_targeting.resize(8)
	_world_targeting[0] = Vector2.ZERO
	_world_targeting[1] = 0.0
	_world_targeting[2] = null
	_world_targeting[3] = 50.0
	_world_targeting[4] = null
	_world_targeting[5] = INF
	_world_targeting[6] = -1
	_world_targeting[7] = CURSOR_ARROW # current mouse cursor


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS # but some functionaly stops if !pause_only_stops_time
	mouse_filter = MOUSE_FILTER_STOP
	IVGlobal.pause_changed.connect(_on_pause_changed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var viewport := get_viewport()
	viewport.size_changed.connect(_on_viewport_size_changed)
	_world_targeting[1] = viewport.get_visible_rect().size.y


func _process(_delta: float) -> void:
	var cursor_type := CURSOR_ARROW
	if _drag_start:
		cursor_type = CURSOR_MOVE
	elif _world_targeting[4]: # there is a target object under the mouse!
		cursor_type = CURSOR_POINTING_HAND
	# TODO: When we can have interaction with asteroid point, that will
	# cause pointy finger too.
	_world_targeting[7] = cursor_type
	set_default_cursor_shape(cursor_type)
	if current_target != _world_targeting[4]:
		current_target = _world_targeting[4]
		mouse_target_changed.emit(current_target)


func _gui_input(input_event: InputEvent) -> void:
	# _gui_input events are consumed
	var event := input_event as InputEventMouse
	if !event:
		return # is this possible?
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion:
		var mouse_pos: Vector2 = mouse_motion.position
		_world_targeting[0] = mouse_pos
		if _suppress_mouse_control:
			return
		if _drag_segment_start: # accumulated mouse drag motion
			var drag_vector := mouse_pos - _drag_segment_start
			_drag_segment_start = mouse_pos
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
					if _world_targeting[4]: # mouse_target
						mouse_target_clicked.emit(_world_targeting[4], mouse_button.button_mask,
								_get_key_modifier_mask(mouse_button))
				_drag_start = Vector2.ZERO
				_drag_segment_start = Vector2.ZERO


func _clear() -> void:
	_world_targeting[2] = null
	_world_targeting[4] = null
	_world_targeting[5] = INF
	_drag_start = Vector2.ZERO
	_drag_segment_start = Vector2.ZERO


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
	# FIXME34: Mac Command
#	if event.command:
#		mask |= KEY_MASK_CMD
	return mask


func _on_pause_changed(is_paused: bool) -> void:
	if is_paused:
		if !_pause_only_stops_time:
			_suppress_mouse_control = true
			_drag_start = Vector2.ZERO
			_drag_segment_start = Vector2.ZERO
	else:
		_suppress_mouse_control = false


func _on_viewport_size_changed() -> void:
	_world_targeting[1] = get_viewport().get_visible_rect().size.y


func _on_mouse_entered() -> void:
	_has_mouse = true


func _on_mouse_exited() -> void:
	_has_mouse = false
