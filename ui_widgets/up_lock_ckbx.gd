# up_lock_ckbx.gd
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
class_name IVUpLockCkbx
extends CheckBox

## CheckBox widget that allows user to lock "up" for [IVCamera].
##
## Requires [IVCamera].

var _camera: IVCamera


func _ready() -> void:
	pressed.connect(_on_pressed)
	IVStateManager.about_to_free_procedural_nodes.connect(_disconnect_camera)
	# TODO: IVWidgets.connect_camera(self, &"_camera", [&"up_lock_changed", _update_ckbx])
	IVGlobal.camera_ready.connect(_connect_camera)
	_connect_camera(get_viewport().get_camera_3d() as IVCamera)


func _connect_camera(camera: IVCamera) -> void:
	_disconnect_camera()
	_camera = camera
	if _camera:
		_camera.up_lock_changed.connect(_update_ckbx)


func _disconnect_camera() -> void:
	if _camera and is_instance_valid(_camera):
		_camera.up_lock_changed.disconnect(_update_ckbx)
		_camera = null


func _update_ckbx(flags: int, _disable_flags: int) -> void:
	const CAMERAFLAGS_UP_LOCKED := IVCamera.CameraFlags.CAMERAFLAGS_UP_LOCKED
	button_pressed = bool(flags & CAMERAFLAGS_UP_LOCKED)


func _on_pressed() -> void:
	if _camera:
		_camera.set_up_lock(button_pressed)
