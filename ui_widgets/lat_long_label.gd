# lat_long_label.gd
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
class_name IVLatLongLabel
extends Label

## Label widget that displays [IVCamera] latitude-longitude.
##
## Requires [IVCamera].


func _ready() -> void:
	IVWidgets.connect_ivcamera(self, &"_on_camera_changed",
			[&"camera_lock_changed", &"_on_camera_lock_changed",
			&"latitude_longitude_changed", &"_on_latitude_longitude_changed"])


func _on_camera_changed(camera: IVCamera) -> void:
	visible = camera and camera.is_camera_lock


func _on_camera_lock_changed(is_camera_lock: bool) -> void:
	visible = is_camera_lock


func _on_latitude_longitude_changed(lat_long: Vector2, is_ecliptic: bool,
		lat_lon_type: IVQFormat.LatitudeLongitudeType) -> void:
	const N_S_E_W := IVQFormat.LatitudeLongitudeType.N_S_E_W
	const SHORT_LOWER_CASE := IVQFormat.TextFormat.SHORT_LOWER_CASE
	if is_ecliptic:
		lat_lon_type = N_S_E_W
	var new_text := IVQFormat.latitude_longitude(lat_long, 1, lat_lon_type, SHORT_LOWER_CASE)
	if is_ecliptic:
		new_text += " (" + tr(&"TXT_ECLIPTIC") + ")"
	text = new_text
