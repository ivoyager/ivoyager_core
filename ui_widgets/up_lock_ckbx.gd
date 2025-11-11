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
	IVWidgets.connect_ivcamera(self, &"_on_camera_changed", [&"up_lock_changed", &"_update_ckbx"])


func _pressed() -> void:
	if _camera:
		_camera.set_up_lock(button_pressed)


func _on_camera_changed(camera: IVCamera) -> void:
	_camera = camera


func _update_ckbx(flags: int, _disable_flags: int) -> void:
	const CAMERAFLAGS_UP_LOCKED := IVCamera.CameraFlags.CAMERAFLAGS_UP_LOCKED
	set_pressed_no_signal(bool(flags & CAMERAFLAGS_UP_LOCKED))
