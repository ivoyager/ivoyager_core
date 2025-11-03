# track_ckbxs.gd
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
class_name IVTrackCkbxs
extends HBoxContainer

## HBoxContainer widget that has "ground", "orbit" and "ecliptic" checkboxes
## for camera tracking selection.
##
## Requires [IVCamera].

var _camera: IVCamera

@onready var _ground_checkbox: CheckBox = $Ground
@onready var _orbit_checkbox: CheckBox = $Orbit
@onready var _ecliptic_checkbox: CheckBox = $Ecliptic


func _ready() -> void:
	IVGlobal.about_to_free_procedural_nodes.connect(_disconnect_camera)
	
	# FIXME: ButtonGroup is redundant with our button logic, but it also
	# changes styling. Can we do the styling without the group?
	var button_group := ButtonGroup.new()
	button_group.pressed.connect(_on_pressed)
	_ecliptic_checkbox.button_group = button_group
	_orbit_checkbox.button_group = button_group
	_ground_checkbox.button_group = button_group
	
	
	IVGlobal.camera_ready.connect(_connect_camera)
	_connect_camera(get_viewport().get_camera_3d() as IVCamera)


func _connect_camera(camera: IVCamera) -> void:
	_disconnect_camera()
	_camera = camera
	if _camera:
		_camera.tracking_changed.connect(_update_buttons)


func _disconnect_camera() -> void:
	if _camera and is_instance_valid(_camera):
		_camera.tracking_changed.disconnect(_update_buttons)
		_camera = null


func _on_pressed(button: CheckBox) -> void:
	const CameraFlags := IVCamera.CameraFlags
	if !_camera:
		return
	match button.name:
		&"Ground":
			_camera.move_to(null, CameraFlags.CAMERAFLAGS_TRACK_GROUND)
		&"Orbit":
			_camera.move_to(null, CameraFlags.CAMERAFLAGS_TRACK_ORBIT)
		&"Ecliptic":
			_camera.move_to(null, CameraFlags.CAMERAFLAGS_TRACK_ECLIPTIC)


func _update_buttons(flags: int, _disable_flags: int) -> void:
	const CameraFlags := IVCamera.CameraFlags
	_ground_checkbox.set_pressed_no_signal(flags & CameraFlags.CAMERAFLAGS_TRACK_GROUND)
	_orbit_checkbox.set_pressed_no_signal(flags & CameraFlags.CAMERAFLAGS_TRACK_ORBIT)
	_ecliptic_checkbox.set_pressed_no_signal(flags & CameraFlags.CAMERAFLAGS_TRACK_ECLIPTIC)
