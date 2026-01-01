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


## Emitted when [member speed_index] or [member reversed_time] changes, on pause
## changes, and on [signal IVGlobal.ui_dirty]. See also [signal multiplier_changed].
signal speed_changed()
## Emitted each frame that [member speed_multiplier] changes. If [member
## ease_curve] == 0.0, then this signal is emitted only once after [signal
## speed_changed].
signal multiplier_changed()

## Emitted when user disrupts OS time synchronization (a subset of [signal
## speed_changed] events). See [member IVTimekeeper.operating_system_time_sync].
signal os_time_sync_disrupted()


const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_speed_index",
	&"_reversed_time",
]


## Current speed index as defined in [member speeds]. Has setter method but see
## also [method change_speed].
var speed_index: int: set = set_speed_index, get = get_speed_index
## Reverse time flow. Settable if [member IVCoreSettings.allow_time_reversal]
## == true (not by default).
var reversed_time := false: set = set_reversed_time, get = get_reversed_time

## If not 0.0, apply an ease curve over [member ease_seconds] when changing
## [member speed_multiplier] for speed changes. See [method @GlobalScope.ease]
## for curve values; -1.5 generates a nice ease in-out curve.
var ease_curve := 0.0
## Time to apply speed change. Only used if [member ease_curve] != 0.0.
var ease_seconds := 0.5

## Project game speeds. Modify at or before [signal IVStateManager.core_initialized].
## Value [constant IVUnits.SECOND] is real-time.[br][br]
##
## Note: If the project might call [method set_real_time_speed], one of the
## array values must be real-time.
var speeds: Array[float] = [
	IVUnits.SECOND,
	IVUnits.SECOND * 10,
	IVUnits.SECOND * 100,
	IVUnits.SECOND * 1e3,
	IVUnits.SECOND * 1e4,
	IVUnits.SECOND * 1e5,
	IVUnits.SECOND * 1e6,
]

## Project game speed names for GUI (will be translated). Modify at or before
## [signal IVStateManager.core_initialized]. Items must correspond to [member
## speeds] for [method get_speed_name] to return a sensible value.
var speed_names: Array[StringName] = [
	# These can be translation keys.
	&"1x",
	&"10x",
	&"100x",
	&"1000x",
	&"10,000x",
	&"100,000x",
	&"1,000,000x",
]


## Project [member speeds] index for game start. Modify at or before [signal
## IVStateManager.core_initialized].
var start_speed := 2
## Current game speed multiplier from [member speeds] for current [member speed_index].
## Negative if [member reversed_time].[br][br]
##
## Read only. Used by [IVTimekeeper].
var speed_multiplier: float # negative if reversed_time


# persisted
var _speed_index: int
var _reversed_time := false

# localized
var _allow_time_reversal := IVCoreSettings.allow_time_reversal
var _network_state := IVStateManager.NetworkState.NO_NETWORK
var _times := IVGlobal.times # floats

var _ease_from_multiplier: float
var _ease_to_multiplier: float
var _ease_fraction := 1.0



func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	IVStateManager.system_tree_built.connect(_on_system_tree_built)
	IVStateManager.network_state_changed.connect(_on_network_state_changed)
	IVStateManager.paused_changed.connect(_on_paused_changed)
	IVGlobal.ui_dirty.connect(_on_ui_dirty)
	set_process(false)


func _process(delta: float) -> void:
	# Only processes during ease transition (if applicalble).
	delta /= Engine.time_scale # actual seconds
	_ease_fraction += delta / ease_seconds
	if _ease_fraction >= 1.0 or IVStateManager.paused_tree: # finish transition
		_ease_fraction = 1.0
		set_process(false)
	var eased_progress := ease(_ease_fraction, ease_curve)
	speed_multiplier = lerpf(_ease_from_multiplier, _ease_to_multiplier, eased_progress)
	_times[1] = speed_multiplier
	if IVCoreSettings.manage_engine_time_scale:
		# We protect against 0.0 although it could only happen with time
		# reversals AND manage_engine_time_scale == true. (The Planetarium
		# sets the latter to false).
		Engine.time_scale = absf(speed_multiplier if speed_multiplier else 0.0000001)
	multiplier_changed.emit()


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
	change_speed(new_speed_index, false)


func get_speed_index() -> int:
	return _speed_index


func set_reversed_time(new_reversed_time: bool) -> void:
	const IS_CLIENT = IVStateManager.NetworkState.IS_CLIENT
	if _network_state == IS_CLIENT:
		return
	if !_allow_time_reversal or _reversed_time == new_reversed_time:
		return
	_reversed_time = new_reversed_time
	os_time_sync_disrupted.emit()
	_process_speed_index(true)


func get_reversed_time() -> bool:
	return _reversed_time


# Other public API

## Sets [member speed_index]. If [param allow_ease_curve] and [member ease_curve]
## != 0.0 and not currently paused, [member speed_multiplier] change will
## transition using an ease curve over [member ease_seconds].
func change_speed(new_speed_index: int, allow_ease_curve := true) -> void:
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
	os_time_sync_disrupted.emit()
	_process_speed_index(allow_ease_curve)


## Sets "real-time" speed. Will generate an error if [member speeds] does not
## have a real-time value (i.e., [constant IVUnits.SECOND]).
func set_real_time_speed() -> void:
	var real_time_speed := speeds.find(IVUnits.SECOND)
	assert(real_time_speed != -1, "IVSpeedManager.speeds does not have a real-time value")
	_reversed_time = false
	change_speed(real_time_speed, false)


func increment_speed(allow_ease_curve := true) -> void:
	change_speed(_speed_index + 1, allow_ease_curve)


func decrement_speed(allow_ease_curve := true) -> void:
	change_speed(_speed_index - 1, allow_ease_curve)


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


## Current game speed name from [member speed_names] for current [member
## speed_index].
func get_speed_name() -> StringName:
	return speed_names[_speed_index] if _speed_index < speed_names.size() else &""
	


# private

func _on_system_tree_built(new_game: bool) -> void:
	if new_game: # need game start _time & _speed_index (otherwise persisted from game load)
		_speed_index = start_speed
	_process_speed_index(false)


func _process_speed_index(allow_ease_curve: bool) -> void:
	# "_speed_index" and "_reversed_time" are set. Everything here follows from that...
	
	if allow_ease_curve and ease_curve and !IVStateManager.paused_tree:
		_ease_from_multiplier = speed_multiplier
		_ease_to_multiplier = -speeds[_speed_index] if _reversed_time else speeds[_speed_index]
		_ease_fraction = 0.0 if _ease_fraction == 1.0 else 0.5
		set_process(true)
		speed_changed.emit()
		return
	
	# instant change
	speed_multiplier = -speeds[_speed_index] if _reversed_time else speeds[_speed_index]
	_times[1] = speed_multiplier
	if IVCoreSettings.manage_engine_time_scale:
		# Don't set negative value here! (Planetarium might be the only use case
		# for reversed_time and it doesn't use Engine.time_scale for anything.)
		Engine.time_scale = absf(speed_multiplier)
	speed_changed.emit()
	multiplier_changed.emit()


func _on_paused_changed(_paused_tree: bool, paused_by_user: bool) -> void:
	if paused_by_user:
		os_time_sync_disrupted.emit()
	speed_changed.emit() # pause can be a "speed change" for UI


func _on_ui_dirty() -> void:
	speed_changed.emit()


func _on_network_state_changed(network_state: IVStateManager.NetworkState) -> void:
	_network_state = network_state
