# control_mod_fade.gd
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
class_name IVControlModFade
extends Node

## Fades parent Control while the user drags the 3D view, and when the user
## leaves it idle.
##
## Add as a child of the GUI's root, usually [IVShowHideUI], to fade everything
## under it. User settings "gui_fade_while_dragging" and "gui_fade_when_idle"
## turn each fade on or off; a project that uses this node should offer them in
## [IVOptionsPopup].[br][br]
##
## Idle means no input for [member idle_seconds] while the pointer is over the 3D
## view or outside the window. The pointer resting on the faded GUI keeps it
## shown, and any input brings it back.[br][br]
##
## Note: A faded Control still takes mouse input, though pointer motion always
## fades it back in first.

## Opacity while the user drags the 3D view.
@export var drag_alpha := 0.15
## Opacity once idle.
@export var idle_alpha := 0.0
## Seconds without input before the GUI fades as idle.
@export var idle_seconds := 4.0
## Duration of a fade out.
@export var fade_out_seconds := 0.6
## Duration of a fade back in.
@export var fade_in_seconds := 0.15


var _fade_while_dragging := false
var _fade_when_idle := false
var _is_dragging := false
var _last_input_msec := 0
var _target_alpha := 1.0
var _tween: Tween
var _world_controller: IVWorldController

@onready var _control := get_parent() as Control



func _ready() -> void:
	set_process(false)
	set_process_input(false)
	IVStateManager.run_state_changed.connect(_on_run_state_changed)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	# Idle begins with the passage of time rather than with an event.
	if _fade_when_idle and !_is_dragging and _get_target_alpha() != _target_alpha:
		_fade_to_target()


func _input(event: InputEvent) -> void:
	_last_input_msec = Time.get_ticks_msec()
	if _is_dragging:
		var mouse_button := event as InputEventMouseButton
		if (mouse_button and !mouse_button.pressed
				and !(mouse_button.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT))):
			_is_dragging = false
	if _get_target_alpha() != _target_alpha:
		_fade_to_target()


func _configure_after_core_inited() -> void:
	assert(_control, "IVControlModFade requires a Control as parent")
	IVSettingsManager.changed.connect(_settings_listener)
	_fade_while_dragging = IVSettingsManager.get_setting(&"gui_fade_while_dragging")
	_fade_when_idle = IVSettingsManager.get_setting(&"gui_fade_when_idle")


func _on_run_state_changed(is_running: bool) -> void:
	if is_running and !_world_controller:
		_world_controller = IVGlobal.program[&"WorldController"]
		_world_controller.mouse_dragged.connect(_on_mouse_dragged)
	_last_input_msec = Time.get_ticks_msec()
	_is_dragging = false
	set_process(is_running)
	set_process_input(is_running)
	_fade_to_target()


func _clear_procedural() -> void:
	if _world_controller:
		_world_controller.mouse_dragged.disconnect(_on_mouse_dragged)
		_world_controller = null


func _on_mouse_dragged(_drag_vector: Vector2, _button_mask: int, _key_modifier_mask: int) -> void:
	if _is_dragging:
		return
	_is_dragging = true
	_fade_to_target()


func _get_target_alpha() -> float:
	if !is_processing_input():
		return 1.0
	if _is_dragging:
		return drag_alpha if _fade_while_dragging else 1.0
	if !_fade_when_idle or Time.get_ticks_msec() - _last_input_msec < idle_seconds * 1000.0:
		return 1.0
	var hovered := _control.get_viewport().gui_get_hovered_control()
	if hovered and _control.is_ancestor_of(hovered):
		return 1.0
	return idle_alpha


func _fade_to_target() -> void:
	var target := _get_target_alpha()
	if target == _target_alpha:
		return
	var duration := fade_in_seconds if target > _target_alpha else fade_out_seconds
	_target_alpha = target
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_control, ^"modulate:a", target, duration)


func _settings_listener(setting: StringName, value: Variant) -> void:
	match setting:
		&"gui_fade_while_dragging":
			_fade_while_dragging = value
			_fade_to_target()
		&"gui_fade_when_idle":
			_fade_when_idle = value
			_fade_to_target()
