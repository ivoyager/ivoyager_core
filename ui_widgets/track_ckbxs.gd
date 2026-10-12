# track_ckbxs.gd
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
class_name IVTrackCkbxs
extends HBoxContainer

## HBoxContainer widget that has "ecliptic", "orbit" and "ground" checkboxes
## for camera tracking selection.
##
## Requires [IVCamera].

var _camera: IVCamera

@onready var _ecliptic_checkbox: CheckBox = $Ecliptic
@onready var _orbit_checkbox: CheckBox = $Orbit
@onready var _ground_checkbox: CheckBox = $Ground


func _ready() -> void:
	# The group draws radio buttons and keeps a selected one pressed when it is
	# clicked again.
	var button_group := ButtonGroup.new()
	button_group.pressed.connect(_on_pressed)
	_ecliptic_checkbox.button_group = button_group
	_orbit_checkbox.button_group = button_group
	_ground_checkbox.button_group = button_group
	
	IVWidgets.connect_ivcamera(self, &"_on_camera_changed",
			[&"tracking_changed", &"_update_buttons"])


func _on_camera_changed(camera: IVCamera) -> void:
	_camera = camera


func _on_pressed(button: CheckBox) -> void:
	const CameraFlags := IVCamera.CameraFlags
	if !_camera:
		return
	match button.name:
		&"Ecliptic":
			_camera.move_to(null, CameraFlags.CAMERAFLAGS_TRACK_ECLIPTIC)
		&"Orbit":
			_camera.move_to(null, CameraFlags.CAMERAFLAGS_TRACK_ORBIT)
		&"Ground":
			_camera.move_to(null, CameraFlags.CAMERAFLAGS_TRACK_GROUND)


func _update_buttons(flags: int, disabled_flags: int) -> void:
	const CameraFlags := IVCamera.CameraFlags
	const CameraDisabledFlags := IVCamera.CameraDisabledFlags
	_ecliptic_checkbox.set_pressed_no_signal(bool(flags & CameraFlags.CAMERAFLAGS_TRACK_ECLIPTIC))
	_orbit_checkbox.set_pressed_no_signal(bool(flags & CameraFlags.CAMERAFLAGS_TRACK_ORBIT))
	_ground_checkbox.set_pressed_no_signal(bool(flags & CameraFlags.CAMERAFLAGS_TRACK_GROUND))
	_ecliptic_checkbox.disabled = bool(
			disabled_flags & CameraDisabledFlags.CAMERADISABLEDFLAGS_TRACK_ECLIPTIC)
	_orbit_checkbox.disabled = bool(
			disabled_flags & CameraDisabledFlags.CAMERADISABLEDFLAGS_TRACK_ORBIT)
	_ground_checkbox.disabled = bool(
			disabled_flags & CameraDisabledFlags.CAMERADISABLEDFLAGS_TRACK_GROUND)
