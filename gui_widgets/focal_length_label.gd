# focal_length_box.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charlie Whitfield
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
class_name IVFocalLengthBox
extends Label

# GUI widget. Requires IVCamera.

var _camera: IVCamera


func _ready() -> void:
	IVGlobal.camera_ready.connect(_connect_camera)
	_connect_camera(get_viewport().get_camera_3d() as IVCamera) # null ok


func _connect_camera(camera: IVCamera) -> void:
	if _camera and is_instance_valid(_camera): # disconnect previous
		_camera.focal_length_changed.disconnect(_update_focal_length)
	_camera = camera
	if camera:
		camera.focal_length_changed.connect(_update_focal_length)


func _update_focal_length(focal_length: float) -> void:
	text = "%2.f mm" % focal_length
