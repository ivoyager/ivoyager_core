# focal_length_control.gd
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
class_name IVFocalLengthControl
extends HBoxContainer

## GUI widget.
##
## Allows fine and step control of focal length.
## Plus/minus buttons jump to focal lengths set in [member big_steps].
## The first and last array values determine min and max settable.
##
## Requires [IVCamera].


var big_steps: Array[float] = [6.0, 15.0, 24.0, 35.0, 50.0] # FOV 125.6, 75.8, 51.9, 36.9, 26.3

var _camera: IVCamera

@onready var _spinbox: SpinBox = $SpinBox
@onready var _minus: Button = $Minus
@onready var _plus: Button = $Plus



func _ready() -> void:
	IVGlobal.camera_ready.connect(_connect_camera)
	_spinbox.value_changed.connect(_on_spinbox_value_changed)
	_minus.pressed.connect(_do_big_step.bind(false))
	_plus.pressed.connect(_do_big_step.bind(true))
	_spinbox.min_value = big_steps[0]
	_spinbox.max_value = big_steps[-1]
	_connect_camera(get_viewport().get_camera_3d() as IVCamera) # null ok



func _connect_camera(camera: IVCamera) -> void:
	if _camera and is_instance_valid(_camera):
		_camera.field_of_view_changed.disconnect(_on_field_of_view_changed)
	_camera = camera
	if !camera:
		return
	camera.field_of_view_changed.connect(_on_field_of_view_changed)
	var focal_length := IVMath.get_focal_length_from_fov(camera.fov)
	_on_field_of_view_changed(0.0, focal_length)


func _on_field_of_view_changed(_fov: float, focal_length: float) -> void:
	await get_tree().process_frame # fixes signal(?!) sometimes after _do_big_step() 
	_spinbox.set_value_no_signal(roundf(focal_length))
	_minus.disabled = _spinbox.value <= big_steps[0]
	_plus.disabled = _spinbox.value >= big_steps[-1]


func _on_spinbox_value_changed(focal_length: float) -> void:
	if !_camera:
		return
	_camera.set_focal_length(focal_length)


func _do_big_step(is_increase: bool) -> void:
	if !_camera:
		return
	var next_step := big_steps.bsearch(_spinbox.value)
	var step := next_step
	if !is_increase:
		step -= 1
	elif _spinbox.value == big_steps[next_step]:
		step += 1
	step = clampi(step, 0, big_steps.size() - 1)
	_camera.set_focal_length(big_steps[step])
