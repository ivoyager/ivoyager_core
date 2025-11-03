# control_mod_draggable.gd
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
class_name IVControlModDraggable
extends Node

## Makes parent Control draggable
##
## This node is designed mainly for PanelContainer instances, but could be added
## to any Control that is not child of a Container. The Control will always
## reposition to be fully on screen even if the user drags it off screen.[br][br]
##
## Note: Mouse input has to reach the parent Control for it to be draggable.
## Be sure to set mouse filters of child controls so that user has control
## regions where drag is possible.

enum {UP, DOWN, LEFT, RIGHT}


## Snap distance for the screen edge.
@export var screen_edge_snap := 30.0
## Snap distance for PanelContainers.
@export var panel_edge_snap := 15.0
## If true, Control will attempt to move to not overlap with other
## PanelContainers. This is not always successful if the screen region is very
## crowded with PanelContainers, but a good effort is made.
@export var prevent_panel_overlap := true
## Disable user drag. This may be useful if project moves Control by code only
## but needs subsequent position fix using [method finish_move]. Must be set
## before _ready().
@export var disable_drag := false


var _drag_point := Vector2.ZERO


@onready var _control := get_parent() as Control
@onready var _viewport := get_viewport()



func _ready() -> void:
	assert(_control, "IVControlModDraggable requires a Control as parent")
	assert(not _control.get_parent() is Container,
			"IVControlModDraggable used for Control that is child of a Container")
	set_process_input(false) # only during drag
	if !disable_drag:
		_control.gui_input.connect(_on_control_input)


func _input(event: InputEvent) -> void:
	# We process input only during drag to ensure that we capture the mouse
	# button release. This is necessary because the parent control doesn't
	# always get the button release event. This was observed in HTML5 builds as
	# of early Godot 4.x versions.
	if event is InputEventMouseButton:
		var mouse_button_event: InputEventMouseButton = event
		if !mouse_button_event.pressed and mouse_button_event.button_index == MOUSE_BUTTON_LEFT:
			finish_move()
			_control.set_default_cursor_shape(Control.CURSOR_ARROW)


func _on_control_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button_event: InputEventMouseButton = event
		if mouse_button_event.pressed and mouse_button_event.button_index == MOUSE_BUTTON_LEFT:
			_drag_point = _control.get_global_mouse_position() - _control.position
			set_process_input(true)
			_control.set_default_cursor_shape(Control.CURSOR_MOVE)
	elif event is InputEventMouseMotion and _drag_point:
		_control.position = _control.get_global_mouse_position() - _drag_point


## "Fixes" Control position after movement to be on screen and adjusted for
## class properties. This method is exposed in case project moves Control by
## code and needs a subsequent position fix.
func finish_move() -> void:
	_drag_point = Vector2.ZERO
	set_process_input(false)
	_snap_horizontal()
	_snap_vertical()
	_fix_offscreen()
	if prevent_panel_overlap:
		_fix_panel_overlap()
	_set_anchors_to_position()


func _set_anchors_to_position() -> void:
	var position := _control.position
	var size := _control.size
	var viewport_size := _viewport.get_visible_rect().size
	var extra_x := viewport_size.x - size.x
	var horizontal_anchor := 1.0
	if extra_x > 0.0:
		horizontal_anchor = clampf(position.x / extra_x, 0.0, 1.0)
	var extra_y := viewport_size.y - size.y
	var vertical_anchor := 1.0
	if extra_y > 0.0:
		vertical_anchor = clampf(position.y / extra_y, 0.0, 1.0)
	_control.anchor_left = horizontal_anchor
	_control.anchor_right = horizontal_anchor
	_control.anchor_top = vertical_anchor
	_control.anchor_bottom = vertical_anchor
	_control.position = position # setting anchors screws up position (Godot bug?)


func _snap_horizontal() -> void:
	var left := _control.position.x
	if left < screen_edge_snap:
		_control.position.x = 0.0
		return
	var right := left + _control.size.x
	var screen_right := _viewport.get_visible_rect().size.x
	if right > screen_right - screen_edge_snap:
		_control.position.x = screen_right - right + left
		return
	var top := _control.position.y
	var bottom := top + _control.size.y
	for child in _control.get_parent().get_children():
		var test_panel := child as PanelContainer
		if !test_panel or test_panel == _control:
			continue
		var panel_top := test_panel.position.y
		if bottom < panel_top:
			continue
		var panel_bottom := panel_top + test_panel.size.y
		if top > panel_bottom:
			continue
		var panel_left := test_panel.position.x
		if abs(right - panel_left) < panel_edge_snap:
			_control.position.x = panel_left - right + left
			return
		var panel_right := panel_left + test_panel.size.x
		if abs(left - panel_right) < panel_edge_snap:
			_control.position.x = panel_right
			return


func _snap_vertical() -> void:
	var top := _control.position.y
	if top < screen_edge_snap:
		_control.position.y = 0.0
		return
	var bottom := top + _control.size.y
	var screen_bottom := _viewport.get_visible_rect().size.y
	if bottom > screen_bottom - screen_edge_snap:
		_control.position.y = screen_bottom - bottom + top
		return
	var left := _control.position.x
	var right := left + _control.size.x
	for child in _control.get_parent().get_children():
		var test_panel := child as PanelContainer
		if !test_panel or test_panel == _control:
			continue
		var panel_left := test_panel.position.x
		if right < panel_left:
			continue
		var panel_top := test_panel.position.y
		if abs(bottom - panel_top) < panel_edge_snap:
			_control.position.y = panel_top - bottom + top
			return
		var panel_bottom := panel_top + test_panel.size.y
		if abs(top - panel_bottom) < panel_edge_snap:
			_control.position.y = panel_bottom
			return


func _fix_offscreen() -> void:
	var rect := _control.get_rect()
	var screen_rect := _control.get_viewport_rect()
	if screen_rect.encloses(rect):
		return
	if rect.position.x < 0.0:
		_control.position.x = 0.0
	elif rect.end.x > screen_rect.end.x:
		_control.position.x = screen_rect.end.x - rect.size.x
	if rect.position.y < 0.0:
		_control.position.y = 0.0
	elif rect.end.y > screen_rect.end.y:
		_control.position.y = screen_rect.end.y - rect.size.y


func _fix_panel_overlap() -> void:
	# Tries 8 directions and then gives up
	var rect := _control.get_rect()
	var overlap := _get_overlap(rect)
	if !overlap:
		return
	if _try_directions(rect, overlap.duplicate(), false):
		return
	_try_directions(rect, overlap, true)


func _try_directions(rect: Rect2, overlap: Array, diagonals: bool) -> bool:
	# smallest overlap is our prefered correction
	var overlap2: Array
	if diagonals:
		overlap2 = overlap.duplicate()
	while true:
		var smallest_offset := INF
		var smallest_direction := -1
		var direction := 0
		while direction < 4:
			if abs(overlap[direction]) < abs(smallest_offset):
				smallest_offset = overlap[direction]
				smallest_direction = direction
			direction += 1
		if smallest_direction == -1:
			return false # failed
		if !diagonals:
			if _try_cardinal_offset(rect, smallest_direction, smallest_offset):
				return true # success
		else:
			var orthogonal := []
			match smallest_direction:
				UP, DOWN:
					orthogonal.append(overlap2[LEFT])
					orthogonal.append(overlap2[RIGHT])
					if abs(overlap2[LEFT]) > abs(overlap2[RIGHT]):
						orthogonal.reverse()
				RIGHT, LEFT:
					orthogonal.append(overlap2[UP])
					orthogonal.append(overlap2[DOWN])
					if abs(overlap2[UP]) > abs(overlap2[DOWN]):
						orthogonal.reverse()
			if _try_diagonal_offset(rect, smallest_direction, smallest_offset, orthogonal):
				return true # success
		overlap[smallest_direction] = INF
	return false


func _try_cardinal_offset(rect: Rect2, direction: int, offset: float) -> bool:
	match direction:
		UP, DOWN:
			rect.position.y += offset
			if _get_overlap(rect):
				return false
			_control.position.y += offset
		LEFT, RIGHT:
			rect.position.x += offset
			if _get_overlap(rect):
				return false
			_control.position.x += offset
	return true


func _try_diagonal_offset(rect: Rect2, direction: int, offset: float, orthogonal: Array) -> bool:
	match direction:
		UP, DOWN:
			rect.position.y += offset
			rect.position.x += orthogonal[0]
			if !_get_overlap(rect):
				_control.position.y += offset
				_control.position.x += orthogonal[0]
				return true
			rect.position.x += orthogonal[1] - orthogonal[0]
			if !_get_overlap(rect):
				_control.position.y += offset
				_control.position.x += orthogonal[1]
				return true
		LEFT, RIGHT:
			rect.position.x += offset
			rect.position.y += orthogonal[0]
			if !_get_overlap(rect):
				_control.position.x += offset
				_control.position.y += orthogonal[0]
				return true
			rect.position.y += orthogonal[1] - orthogonal[0]
			if !_get_overlap(rect):
				_control.position.x += offset
				_control.position.y += orthogonal[1]
				return true
	return false


func _get_overlap(rect: Rect2) -> Array:
	for child in _control.get_parent().get_children():
		var other := child as PanelContainer
		if !other or other == _control:
			continue
		var other_rect := other.get_rect()
		if rect.intersects(other_rect):
			var right_down := other_rect.end - rect.position
			var up_left := rect.end - other_rect.position
			var overlap := [INF, INF, INF, INF]
			if right_down.x > 0:
				overlap[RIGHT] = right_down.x # move right to fix
			if up_left.x > 0:
				overlap[LEFT] = -up_left.x # move left to fix
			if right_down.y > 0:
				overlap[DOWN] = right_down.y # move down to fix
			if up_left.y > 0:
				overlap[UP] = -up_left.y # move up to fix
			return overlap
	var screen_rect := _control.get_viewport_rect()
	if screen_rect.encloses(rect):
		return [] # good position
	return [INF, INF, INF, INF] # bad position
