# control_size_group.gd
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
class_name IVControlSizeGroup
extends RefCounted

## A group of Controls (all in Containers) that share the same size
##
## This helper sets [member Control.custom_minimum_size] to the value of the
## greatest [method Control.get_minimum_size] for all included controls. For
## this to be the actual size, an included Control and its Container siblings
## must have appropriate container sizing. E.g., a sibling could be set to
## expand while the included Control is not.[br][br]
##
## This is intended for simple Controls (e.g., Labels or Control spacers), not
## complex Control scene trees. In particular, infinite recursion could occur
## if Control descendents change size in resoponse to available Container space.

@export var horizontal := true
@export var vertical := false
@export var frame_delay := true

var _controls: Array[Control] = []
var _suppress_resize := false



func _init() -> void:
	IVStateManager.about_to_quit.connect(_on_about_to_quit)


func add_control(control: Control) -> void:
	assert(!_controls.has(control))
	control.minimum_size_changed.connect(_resize)
	_controls.append(control)
	_resize()


func remove_control(control: Control) -> void:
	assert(_controls.has(control))
	control.minimum_size_changed.disconnect(_resize)
	_controls.erase(control)
	_resize()


func _resize() -> void:
	if _suppress_resize:
		return
	_suppress_resize = true
	if frame_delay:
		await IVGlobal.get_tree().process_frame
	var largest_min := Vector2.ZERO
	for control in _controls:
		largest_min = largest_min.max(control.get_minimum_size())
	for control in _controls:
		if horizontal:
			control.custom_minimum_size.x = largest_min.x
		if vertical:
			control.custom_minimum_size.y = largest_min.y
	_suppress_resize = false


func _on_about_to_quit() -> void:
	for control in _controls:
		control.minimum_size_changed.disconnect(_resize)
	_controls.clear()
