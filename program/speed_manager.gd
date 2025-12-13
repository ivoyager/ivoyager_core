# speed_manager.gd
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
class_name IVSpeedManager
extends Node

## Has project game speed settings and manages game speed.
##
## Projects can define their own game speeds here. This node handles shortcut
## actions for game speed, maintains [member speed_multiplier], and emits
## [signal speed_changed]. Time is managed by [IVTimekeeper].[br][br]
##
## [IVSpeedManager] does not change [member Engine.time_scale] by default. If you
## want that to happen, set [member IVCoreSettings.manage_engine_time_scale].


## Emitted when game speed changes, on pause changes, and on [signal IVGlobal.ui_dirty].
signal speed_changed()
## Emitted when user disrupts OS time synchronization (a subset of [signal
## speed_changed] events). See [member IVTimekeeper.operating_system_time_sync].
signal os_time_sync_disrupted()


const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_speed_index",
	&"_reversed_time",
]


## Current speed index as defined in [member speeds]. Settable.
var speed_index: int: set = set_speed_index, get = get_speed_index
## Reverse time flow. Settable if [member IVCoreSettings.allow_time_reversal]
## == true (not by default).
var reversed_time := false: set = set_reversed_time, get = get_reversed_time


## Project game speeds. Modify at or before [signal IVStateManager.core_initialized].
## Value [constant IVUnits.SECOND] is real-time.[br][br]
##
## Note: If the project might call [method set_real_time_speed], one of the
## array values must be real-time.
var speeds: Array[float] = [
	IVUnits.SECOND,
	IVUnits.MINUTE,
	IVUnits.HOUR,
	IVUnits.DAY,
	7.0 * IVUnits.DAY,
	30.4375 * IVUnits.DAY,
]

## Project game speed names for GUI. Modify at or before [signal
## IVStateManager.core_initialized]. Must be the same size as [member speeds].
var speed_names: Array[StringName] = [
	&"GAME_SPEED_REAL_TIME",
	&"GAME_SPEED_MINUTE_PER_SECOND",
	&"GAME_SPEED_HOUR_PER_SECOND",
	&"GAME_SPEED_DAY_PER_SECOND",
	&"GAME_SPEED_WEEK_PER_SECOND",
	&"GAME_SPEED_MONTH_PER_SECOND",
]


## Project [member speeds] index for game start. Modify at or before [signal
## IVStateManager.core_initialized].
var start_speed := 2
## Current game speed multiplier from [member speeds] for current [member speed_index].
## Negative if [member reversed_time].[br][br]
##
## Read only. Used by [IVTimekeeper].
var speed_multiplier: float # negative if reversed_time
## Current game speed name from [member speed_names] for current [member
## speed_index].[br][br]
##
## Read-only for GUI.
var speed_name: StringName


# persisted
var _speed_index: int
var _reversed_time := false

# localized
var _allow_time_reversal := IVCoreSettings.allow_time_reversal
var _network_state := IVStateManager.NetworkState.NO_NETWORK



func _ready() -> void:
	IVStateManager.system_tree_built.connect(_on_system_tree_built)
	IVStateManager.network_state_changed.connect(_on_network_state_changed)
	IVStateManager.paused_changed.connect(_on_paused_changed)
	IVGlobal.ui_dirty.connect(_on_ui_dirty)


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action_pressed(&"incr_speed"):
		increment_speed()
	elif event.is_action_pressed(&"decr_speed"):
		decrement_speed()
	elif _allow_time_reversal and event.is_action_pressed(&"reverse_time"):
		set_reversed_time(!_reversed_time)
	else:
		return # input NOT handled!
	get_viewport().set_input_as_handled()


# setgets

func set_speed_index(new_speed_index: int) -> void:
	const IS_CLIENT = IVStateManager.NetworkState.IS_CLIENT
	if _network_state == IS_CLIENT:
		return
	if new_speed_index < 0:
		new_speed_index = 0
	elif new_speed_index >= speeds.size():
		new_speed_index = speeds.size() - 1
	if _speed_index == new_speed_index:
		return
	_speed_index = new_speed_index
	_process_speed_index()
	os_time_sync_disrupted.emit()
	speed_changed.emit()


func get_speed_index() -> int:
	return _speed_index


func set_reversed_time(new_reversed_time: bool) -> void:
	const IS_CLIENT = IVStateManager.NetworkState.IS_CLIENT
	if _network_state == IS_CLIENT:
		return
	if !_allow_time_reversal or _reversed_time == new_reversed_time:
		return
	_reversed_time = new_reversed_time
	_process_speed_index()
	os_time_sync_disrupted.emit()
	speed_changed.emit()


func get_reversed_time() -> float:
	return _reversed_time


# Other public API

## Sets "real-time" speed. Will generate an error if [member speeds] does not
## have a real-time value (i.e., [constant IVUnits.SECOND]).
func set_real_time_speed() -> void:
	var real_time_speed := speeds.find(IVUnits.SECOND)
	assert(real_time_speed != -1, "IVSpeedManager.speeds does not have a real-time value")
	_reversed_time = false
	set_speed_index(real_time_speed)


func increment_speed() -> void:
	set_speed_index(_speed_index + 1)


func decrement_speed() -> void:
	set_speed_index(_speed_index - 1)


func can_increment_speed() -> bool:
	const IS_CLIENT = IVStateManager.NetworkState.IS_CLIENT
	if _network_state == IS_CLIENT:
		return false
	return _speed_index < speeds.size() - 1


func can_decrement_speed() -> bool:
	const IS_CLIENT = IVStateManager.NetworkState.IS_CLIENT
	if _network_state == IS_CLIENT:
		return false
	return _speed_index > 0


# private

func _on_system_tree_built(new_game: bool) -> void:
	if new_game: # need game start _time & _speed_index (otherwise persisted from game load)
		_speed_index = start_speed
	_process_speed_index()


func _process_speed_index() -> void:
	# "_speed_index" and "_reversed_time" are set. Everything here follows from that...
	speed_multiplier = speeds[_speed_index]
	if _reversed_time:
		speed_multiplier *= -1.0
	speed_name = speed_names[_speed_index]
	if IVCoreSettings.manage_engine_time_scale:
		# Don't set negative value here! (Planetarium might be the only use-case
		# for reversed_time, and we don't use this setting. So shouldn't be an
		# issue anyway...)
		Engine.time_scale = speeds[_speed_index]


func _on_paused_changed(_paused_tree: bool, paused_by_user: bool) -> void:
	if paused_by_user:
		os_time_sync_disrupted.emit()
	speed_changed.emit() # pause can be a "speed change" for UI


func _on_ui_dirty() -> void:
	speed_changed.emit()


func _on_network_state_changed(network_state: IVStateManager.NetworkState) -> void:
	_network_state = network_state
