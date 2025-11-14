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

## HBoxContainer widget for setting and displaying camera focal length.
##
## Allows fine and step control of camera focal length (a function of fov).
## Plus/minus buttons jump to focal lengths set in [member big_steps].
## The first and last array values determine min and max settable.[br][br]
##
## Requires [IVCamera].


var big_steps: Array[float] = [6.0, 15.0, 24.0, 35.0, 50.0] # FOVs ~125.6, 75.8, 51.9, 36.9, 26.3

var _camera: IVCamera

@onready var _spinbox: SpinBox = $SpinBox
@onready var _minus: Button = $Minus
@onready var _plus: Button = $Plus



func _ready() -> void:
	IVGlobal.camera_fov_changed.connect(_on_camera_fov_changed)
	_spinbox.value_changed.connect(_on_spinbox_value_changed)
	_minus.pressed.connect(_do_big_step.bind(false))
	_plus.pressed.connect(_do_big_step.bind(true))
	_spinbox.min_value = big_steps[0]
	_spinbox.max_value = big_steps[-1]
	IVWidgets.connect_ivcamera(self, &"_on_camera_changed")


func _on_camera_changed(camera: IVCamera) -> void:
	_camera = camera


func _on_camera_fov_changed(fov: float) -> void:
	await get_tree().process_frame # fixes signal(?!) sometimes after _do_big_step()
	var focal_length := IVMath.get_focal_length_from_fov(fov)
	_spinbox.set_value_no_signal(roundf(focal_length))
	_minus.disabled = _spinbox.value <= big_steps[0]
	_plus.disabled = _spinbox.value >= big_steps[-1]


func _on_spinbox_value_changed(focal_length: float) -> void:
	if _camera:
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
