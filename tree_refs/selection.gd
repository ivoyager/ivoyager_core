# selection.gd
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
class_name IVSelection
extends RefCounted

## Wrapper class for anything that can be selected.
##
## TODO: Restructure so that this is a component. Any object can then be
## selectable by having this component.
##
## [IVSelectionManager] keeps an instance of this class as current selection
## and maintains selection history. In `ivoyager_core` we only select [IVBody]
## instances, but this class could be extended to wrap anything.


const math := preload("uid://csb570a3u1x1k")

const CameraFlags := IVCamera.CameraFlags
const BodyFlags := IVBody.BodyFlags
const IDENTITY_BASIS := Basis.IDENTITY
const ECLIPTIC_X := Vector3(1.0, 0.0, 0.0)
const ECLIPTIC_Y := Vector3(0.0, 1.0, 0.0)
const ECLIPTIC_Z := Vector3(0.0, 0.0, 1.0)
const VECTOR2_ZERO := Vector2.ZERO

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"name",
	&"gui_name",
	&"is_body",
	&"up_selection_name",
	&"spatial",
	&"body",
]

# persisted - read only
var name: StringName
var gui_name: String # name for GUI display (already translated)
var is_body: bool
var up_selection_name := "" # top selection (only) doesn't have one

var spatial: Node3D # for camera; same as 'body' if is_body
var body: IVBody # = spatial if is_body else null

# read-only
var texture_2d: Texture2D
var texture_slice_2d: Texture2D # stars only

## Contains all existing IVSelection instances.
static var selections: Dictionary[StringName, IVSelection] = {}


func _init() -> void:
	IVGlobal.system_tree_ready.connect(_init_after_system, CONNECT_ONE_SHOT)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear)


func _init_after_system(_dummy: bool) -> void:
	# Called for gameload; dynamically created must set these
	if is_body:
		texture_2d = body.texture_2d
		texture_slice_2d = body.texture_slice_2d


func _clear() -> void:
	if IVGlobal.system_tree_ready.is_connected(_init_after_system):
		IVGlobal.system_tree_ready.disconnect(_init_after_system)
	spatial = null
	body = null


func get_gui_name() -> String:
	# return is already translated
	return gui_name


func get_body_name() -> StringName:
	return body.name if is_body else &""


func get_float_precision(path: String) -> int:
	if !is_body:
		return -1
	return body.get_float_precision(path)


func get_system_radius() -> float:
	if !is_body:
		return 0.0
	return body.get_system_radius()


func get_perspective_radius() -> float:
	if !is_body:
		return 0.0
	return body.get_perspective_radius()


func get_latitude_longitude(at_translation: Vector3, time := NAN) -> Vector2:
	if !is_body:
		return VECTOR2_ZERO
	return body.get_latitude_longitude(at_translation, time)


func get_global_origin() -> Vector3:
	if !spatial:
		return Vector3.ZERO
	return spatial.global_position


func get_flags() -> int:
	if !is_body:
		return 0
	return body.flags


func get_up(time := NAN) -> Vector3:
	if !is_body:
		return ECLIPTIC_Z
	return body.get_north_axis(time)


func get_orientation(time := NAN) -> Basis:
	if !is_body:
		return IDENTITY_BASIS
	return body.get_orientation(time)


func get_orbit_tracking_basis(time := NAN) -> Basis:
	if !is_body:
		return IDENTITY_BASIS
	# FIXME: Make this more honest. We flip basis for planets for better view.
	# Function names should make it clear this is for camera use.
	var basis := body.get_orbit_tracking_basis(time)
	if body.flags & BodyFlags.BODYFLAGS_STAR_ORBITER:
		return basis.rotated(basis.z, PI)
	return basis


func get_radius_for_camera() -> float:
	if !is_body:
		return IVUnits.KM
	return body.get_mean_radius()


func get_star() -> IVBody:
	if !is_body:
		return null
	return body.star


func get_star_orbiter() -> IVBody:
	if !is_body:
		return null
	return body.star_orbiter
