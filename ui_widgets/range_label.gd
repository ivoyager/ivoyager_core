# range_label.gd
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
class_name IVRangeLabel
extends Label

## Label widget that displays [IVCamera] range.
##
## Requires [IVCamera].

var _camera: IVCamera


func _ready() -> void:
	IVWidgets.connect_ivcamera(self, &"_on_camera_changed",
			[&"camera_lock_changed", &"_on_camera_lock_changed",
			&"range_changed", &"_on_range_changed"])


func _on_camera_changed(camera: IVCamera) -> void:
	_camera = camera
	visible = camera and camera.is_camera_lock


func _on_camera_lock_changed(is_camera_lock: bool) -> void:
	visible = is_camera_lock


func _on_range_changed(new_range: float) -> void:
	text = IVQFormat.dynamic_unit(new_range, &"length_m_km_au", 3)
