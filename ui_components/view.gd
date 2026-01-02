# view.gd
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
class_name IVView
extends RefCounted

## A persisted representation of a user view or some aspect of user view.
##
## A "view" optionally includs camera target and positioning, HUDs visibilities
## and colors, game speed, pause state, and (if allowed) time. The state
## that a view can hold is defined by [enum ViewFlags]. Some time-related state
## requires non-default Core settings ([member IVCoreSettings.allow_time_setting]
## and [member IVCoreSettings.allow_time_reversal]).[br][br]
##
## IVView instances can be persisted via gamesave or cache.[br][br]
##
## This class is used by [IVViewManager] and "view_" widgets such as
## [IVViewButton]. Views are generally user-created at runtime (these are
## persisted via gamesave or cache) or defined as "default" views in a data
## table (e.g., VIEW_HOME in tables/views.tsv).[br][br]
##
## The Planetarium caches a current user view on exit and restores it on
## restart.[br][br]
##
## TODO: Hotkey bindings!

enum ViewFlags { # flags
	VIEWFLAGS_CAMERA_SELECTION = 1,
	VIEWFLAGS_CAMERA_LONGITUDE = 1 << 1,
	VIEWFLAGS_CAMERA_ORIENTATION = 1 << 2,

	VIEWFLAGS_HUDS_VISIBILITY = 1 << 3,
	VIEWFLAGS_HUDS_COLOR = 1 << 4,
	
	VIEWFLAGS_TIME_STATE = 1 << 5, # usually only game speed & pause
	VIEWFLAGS_SYNC_OS_TIME = 1 << 6, # usually not avialable
	
	# sets
	VIEWFLAGS_ALL_CAMERA = (1 << 3) - 1,
	VIEWFLAGS_ALL_HUDS = 1 << 3 | 1 << 4,
	VIEWFLAGS_ALL_BUT_TIME = (1 << 5) - 1,
	VIEWFLAGS_ALL_BUT_IS_NOW = (1 << 6) - 1,
	VIEWFLAGS_ALL = (1 << 7) - 1,
}


const NULL_VECTOR3 := Vector3(-INF, -INF, -INF)

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"flags",
	&"target_name",
	&"camera_flags",
	&"view_position",
	&"view_rotations",
	&"name_visible_flags",
	&"symbol_visible_flags",
	&"orbit_visible_flags",
	&"visible_points_groups",
	&"visible_orbits_groups",
	&"body_orbit_colors",
	&"sbg_points_colors",
	&"sbg_orbits_colors",
	&"speed_index",
	&"user_paused",
	&"time",
	&"reversed_time",
	&"edited_default",
]


## Set this script to generate a subclass in place of IVView in [method create].
## A subclass can do this in their _static_init() for project-wide replacement.
static var replacement_subclass: Script # subclass only

static var _version_hash := PERSIST_PROPERTIES.hash() + 0 # test for obsolte cache


# persisted
## State held by this view. See [enum ViewFlags].
var flags := 0
## Camera target. E.g., "PLANET_EARTH".
var target_name := &""
## Includes camera tracking type (ground, orbit or ecliptic). See [enum
## IVCamera.CameraFlags].
var camera_flags := 0
## Camera position relative to target. See [IVCamera].
var view_position := NULL_VECTOR3
## Camera orientation relative to target. See [IVCamera].
var view_rotations := NULL_VECTOR3
var name_visible_flags := 0 # exclusive w/ symbol_visible_flags
var symbol_visible_flags := 0 # exclusive w/ name_visible_flags
var orbit_visible_flags := 0
var visible_points_groups: Array[StringName] = []
var visible_orbits_groups: Array[StringName] = []
var body_orbit_colors: Dictionary[int, Color] = {} # has non-default only
var sbg_points_colors: Dictionary[StringName, Color] = {} # has non-default only
var sbg_orbits_colors: Dictionary[StringName, Color] = {} # has non-default only
var speed_index := 0
var user_paused := false
## Requires [member IVCoreSettings.allow_time_setting] == true.
var time := 0.0
## Requires [member IVCoreSettings.allow_time_reversal= == true.
var reversed_time := false
## Not part of view state. Used by GUI managing code.
var edited_default := &""


var _camera_handler: IVCameraHandler = IVGlobal.program[&"CameraHandler"]
var _body_huds_state: IVBodyHUDsState = IVGlobal.program[&"BodyHUDsState"]
var _sbg_huds_state: IVSBGHUDsState = IVGlobal.program[&"SBGHUDsState"]
var _timekeeper: IVTimekeeper = IVGlobal.program[&"Timekeeper"]
var _speed_manager: IVSpeedManager = IVGlobal.program[&"SpeedManager"]



## Creates a new [IVView] instance or specified [member replacement_subclass].
static func create() -> IVView:
	if replacement_subclass:
		@warning_ignore("unsafe_method_access")
		return replacement_subclass.new()
	return IVView.new()


## Save the current user state in this [IVView] for all [param save_flags].
func save_state(save_flags: int) -> void:
	flags = save_flags
	_save_camera_state()
	_save_huds_state()
	_save_time_state()


## Set the user state from this [IVView]. If [param instantly], move camera
## instantly and skip any other transitional states.
func set_state(instantly := false) -> void:
	# Sets all state in ViewFlags.
	_set_camera_state(instantly)
	_set_huds_state()
	_set_time_state()


# IVViewManager functions

func reset() -> void:
	# back to init state
	flags = 0
	target_name = &""
	camera_flags = 0
	view_position = NULL_VECTOR3
	view_rotations = NULL_VECTOR3
	name_visible_flags = 0
	symbol_visible_flags = 0
	orbit_visible_flags = 0
	visible_points_groups.clear()
	visible_orbits_groups.clear()
	body_orbit_colors.clear()
	sbg_points_colors.clear()
	sbg_orbits_colors.clear()
	time = 0.0
	speed_index = 0
	user_paused = false
	reversed_time = false


func get_data_for_cache() -> Array:
	var data := []
	for property in PERSIST_PROPERTIES:
		data.append(get(property))
	data.append(_version_hash)
	return data


func set_data_from_cache(data: Variant) -> bool:
	# Tests data integrity and returns false on failure.
	if typeof(data) != TYPE_ARRAY:
		return false
	var data_array: Array = data
	if !data_array:
		return false
	var version_hash: Variant = data_array[-1] # untyped for safety
	if typeof(version_hash) != TYPE_INT:
		return false
	if version_hash != _version_hash:
		return false
	if data_array.size() != PERSIST_PROPERTIES.size() + 1:
		return false
	for i in PERSIST_PROPERTIES.size():
		set(PERSIST_PROPERTIES[i], data_array[i])
	return true


# private

func _save_camera_state() -> void:
	if !(flags & ViewFlags.VIEWFLAGS_ALL_CAMERA):
		return
	var view_state := _camera_handler.get_camera_view_state()
	if flags & ViewFlags.VIEWFLAGS_CAMERA_SELECTION:
		target_name = view_state[0]
	if flags & ViewFlags.VIEWFLAGS_CAMERA_LONGITUDE:
		view_position.x = view_state[2].x
	if flags & ViewFlags.VIEWFLAGS_CAMERA_ORIENTATION:
		camera_flags = view_state[1]
		view_position.y = view_state[2].y
		view_position.z = view_state[2].z
		view_rotations = view_state[3]


func _set_camera_state(instantly := false) -> void:
	if !(flags & ViewFlags.VIEWFLAGS_ALL_CAMERA):
		return
	# Note: the camera ignores all null or null-equivilant args.
	_camera_handler.move_to_by_name(target_name, camera_flags, view_position, view_rotations,
			instantly)


func _save_huds_state() -> void:
	if flags & ViewFlags.VIEWFLAGS_HUDS_VISIBILITY:
		name_visible_flags = _body_huds_state.name_visible_flags
		symbol_visible_flags = _body_huds_state.symbol_visible_flags
		orbit_visible_flags = _body_huds_state.orbit_visible_flags
		visible_points_groups = _sbg_huds_state.get_visible_points_groups()
		visible_orbits_groups = _sbg_huds_state.get_visible_orbits_groups()
	if flags & ViewFlags.VIEWFLAGS_HUDS_COLOR:
		body_orbit_colors = _body_huds_state.get_non_default_orbit_colors()
		sbg_points_colors = _sbg_huds_state.get_non_default_points_colors()
		sbg_orbits_colors = _sbg_huds_state.get_non_default_orbits_colors()


func _set_huds_state() -> void:
	if flags & ViewFlags.VIEWFLAGS_HUDS_VISIBILITY:
		_body_huds_state.set_name_visible_flags(name_visible_flags)
		_body_huds_state.set_symbol_visible_flags(symbol_visible_flags)
		_body_huds_state.set_orbit_visible_flags(orbit_visible_flags)
		_sbg_huds_state.set_visible_points_groups(
				Array(visible_points_groups, TYPE_STRING_NAME, &"", null), true, true)
		_sbg_huds_state.set_visible_orbits_groups(
				Array(visible_orbits_groups, TYPE_STRING_NAME, &"", null), true, true)
	if flags & ViewFlags.VIEWFLAGS_HUDS_COLOR:
		_body_huds_state.set_all_orbit_colors(body_orbit_colors) # ref safe
		_sbg_huds_state.set_all_points_colors(sbg_points_colors)
		_sbg_huds_state.set_all_orbits_colors(sbg_orbits_colors)


# time state

func _save_time_state() -> void:
	# If both TIME_STATE and SYNC_OS_TIME flags set, we unset one depending on
	# IVTimekeeper.os_time_sync_on.
	if flags & ViewFlags.VIEWFLAGS_SYNC_OS_TIME and _timekeeper.operating_system_time_sync:
		flags &= ~ViewFlags.VIEWFLAGS_TIME_STATE
	if flags & ViewFlags.VIEWFLAGS_TIME_STATE:
		flags &= ~ViewFlags.VIEWFLAGS_SYNC_OS_TIME
		user_paused = IVStateManager.paused_by_user
		time = _timekeeper.time
		speed_index = _speed_manager.speed_index
		reversed_time = _speed_manager.get_reversed_time()


func _set_time_state(instantly := false) -> void:
	# Note: IVTimekeeper ignores set functions that are disallowed in IVCoreSettings
	# project settings. In most game applications, only speed and pause is set.
	if flags & ViewFlags.VIEWFLAGS_TIME_STATE:
		_timekeeper.set_time(time)
		IVStateManager.set_user_paused(user_paused)
		_speed_manager.change_speed(speed_index, not instantly)
		_speed_manager.set_reversed_time(reversed_time)
	elif flags & ViewFlags.VIEWFLAGS_SYNC_OS_TIME:
		_timekeeper.set_operating_system_time_sync(true)
