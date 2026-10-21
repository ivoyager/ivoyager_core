# focal_length_control.gd
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
class_name IVFocalLengthControl
extends HBoxContainer

## HBoxContainer widget for setting and displaying camera focal length.
##
## Allows fine and step control of camera focal length (a function of fov).
## Plus/minus buttons jump to focal lengths set in [member big_steps].
## The first and last array values determine min and max settable.[br][br]
##
## The widget's own [member Control.tooltip_text] shows over the whole widget
## wherever a control has no tooltip of its own. Set it before the widget is
## ready.[br][br]
##
## Requires [IVCamera].


## Focal lengths (mm, 35mm-equivalent) the [code]+[/code]/[code]−[/code]
## buttons jump between. The first and last entries define the min and max
## settable values. Defaults corespond to FOVs ~125.6, 75.8, 51.9, 36.9, 26.3.
@export var big_steps: Array[float] = [6.0, 15.0, 24.0, 35.0, 50.0]
## Text of a [Label] ahead of the controls, usually a translation key such as
## [code]&"LABEL_FL"[/code]. If empty (default), no label.
@export var label_text := &""
## If true, the [code]−[/code]/[code]+[/code] buttons come before the SpinBox
## rather than after it.
@export var buttons_first := false

var _camera: IVCamera

@onready var _spinbox: SpinBox = $SpinBox
@onready var _minus: Button = $Minus
@onready var _plus: Button = $Plus



func _ready() -> void:
	if !accessibility_name:
		accessibility_name = &"LABEL_FOCAL_LENGTH"
	_plus.accessibility_name = _plus.tooltip_text # text is a symbol
	_minus.accessibility_name = _minus.tooltip_text
	IVGlobal.camera_fov_changed.connect(_on_camera_fov_changed)
	_spinbox.value_changed.connect(_on_spinbox_value_changed)
	_minus.pressed.connect(_do_big_step.bind(false))
	_plus.pressed.connect(_do_big_step.bind(true))
	_spinbox.min_value = big_steps[0]
	_spinbox.max_value = big_steps[-1]
	if !_spinbox.tooltip_text: # a SpinBox ends the tooltip search at itself
		_spinbox.tooltip_text = tooltip_text
	if buttons_first:
		move_child(_spinbox, -1)
	if label_text:
		var label := Label.new()
		label.text = label_text
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(label)
		move_child(label, 0)
	theme_changed.connect(_fit_spinbox_to_widest_value, CONNECT_DEFERRED)
	_fit_spinbox_to_widest_value()
	IVWidgets.connect_ivcamera(self, &"_on_camera_changed")


## The camera focal length in millimeters (35 mm equivalent), for an
## automation client.
func get_automation_value() -> float:
	return _spinbox.value


## The focal lengths the buttons step through; any value between the first
## and last may be set.
func get_automation_options() -> Array[float]:
	return big_steps


## Sets the camera focal length, as the spin box does. Returns false outside
## the range of [method get_automation_options].
func set_automation_value(focal_length: float) -> bool:
	if !_camera or focal_length < big_steps[0] or focal_length > big_steps[-1]:
		return false
	_camera.set_focal_length(focal_length)
	return true


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


func _fit_spinbox_to_widest_value() -> void:
	# TODO Godot 4.8: SpinBox deprecates suffix for a format property (String %
	# rules). Move the .tscn's "mm" suffix to a format such as "%d mm", and
	# measure the widest value through that format here.
	var widest := "0".repeat(str(roundi(big_steps[-1])).length()) # zeros for its digits
	if _spinbox.suffix:
		widest += " " + _spinbox.suffix
	IVWidgets.fit_spinbox_to_text(_spinbox, widest)
