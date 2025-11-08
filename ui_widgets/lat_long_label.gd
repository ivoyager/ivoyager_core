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

var _camera: IVCamera


func _ready() -> void:
	IVGlobal.camera_ready.connect(_connect_camera)
	IVStateManager.about_to_free_procedural_nodes.connect(_disconnect_camera)
	_connect_camera(get_viewport().get_camera_3d() as IVCamera) # null ok
	

func _connect_camera(camera: IVCamera) -> void:
	_disconnect_camera()
	_camera = camera
	if _camera:
		_camera.latitude_longitude_changed.connect(_on_latitude_longitude_changed)
		_camera.camera_lock_changed.connect(_on_camera_lock_changed)
	visible = _camera and _camera.is_camera_lock


func _disconnect_camera() -> void:
	if _camera and is_instance_valid(_camera):
		_camera.latitude_longitude_changed.disconnect(_on_latitude_longitude_changed)
		_camera.camera_lock_changed.disconnect(_on_camera_lock_changed)
		_camera = null


func _on_latitude_longitude_changed(lat_long: Vector2, is_ecliptic: bool, selection: IVSelection
		) -> void:
	const BODYFLAGS_USE_CARDINAL_DIRECTIONS := IVBody.BodyFlags.BODYFLAGS_USE_CARDINAL_DIRECTIONS
	const BODYFLAGS_USE_PITCH_YAW := IVBody.BodyFlags.BODYFLAGS_USE_PITCH_YAW
	const SHORT_LOWER_CASE := IVQFormat.TextFormat.SHORT_LOWER_CASE
	const N_S_E_W := IVQFormat.LatitudeLongitudeType.N_S_E_W
	const LAT_LON := IVQFormat.LatitudeLongitudeType.LAT_LON
	const PITCH_YAW := IVQFormat.LatitudeLongitudeType.PITCH_YAW
	var lat_long_type := N_S_E_W
	if !is_ecliptic:
		var flags := selection.get_body_flags()
		if flags & BODYFLAGS_USE_CARDINAL_DIRECTIONS:
			lat_long_type = N_S_E_W
		elif flags & BODYFLAGS_USE_PITCH_YAW:
			lat_long_type = PITCH_YAW
		else:
			lat_long_type = LAT_LON
	var new_text := IVQFormat.latitude_longitude(lat_long, 1, lat_long_type, SHORT_LOWER_CASE)
	if is_ecliptic:
		new_text += " (" + tr(&"TXT_ECLIPTIC") + ")"
	text = new_text


func _on_camera_lock_changed(is_camera_lock: bool) -> void:
	visible = is_camera_lock
