# timekeeper.gd
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
class_name IVTimekeeper
extends Node

## Maintains simulator time and provides Gregorian calendar and clock elements
## and time conversion functions.
##
## This node maintains [member IVGlobal.times], [member IVGlobal.clock],
## [member IVGlobal.date], [member IVGlobal.date_aux], and shader global
## "iv_time". (Shader global "iv_time" is assumed to exist.)[br][br]
##
## [IVTimekeeper] does not change [member Engine.time_scale] by default. If you
## want that to happen, set [member IVCoreSettings.manage_engine_time_scale] = true.
## [br][br]
##
## For definitions of Terrestrial Time (TT), Universal Time (UT, UT1), Julian
## Day Number (JDN), and Julian Date (JD), see:[br]
## [url]https://en.wikipedia.org/wiki/Terrestrial_Time[/url][br]
## [url]https://en.wikipedia.org/wiki/Universal_Time[/url][br]
## [url]https://en.wikipedia.org/wiki/Julian_day[/url][br][br]
##
## Simulator [member time] is Terrestrial Time in units defined by [member
## IVUnits.SECOND] with J2000 epoch (noon on Jan 1, 2000). This value is
## available at [member IVGlobal.times][0] and is "time" for essentially all
## simulator mechanics.[br][br]
##
## Simulator [member clock_time] can follow either Universal Time (default) or
## Terrestrial Time. The essential difference is that UT will maintain synchrony
## with Earth rotation (or possibly some other body) while TT will diverge over
## time. This value is available at [member IVGlobal.times][1] and is mainly
## used for clock GUI display. It also determines the exact time of "rollover"
## for JDN ([member julian_day_number]) and Gregorian date ([member IVGlobal.date])
## at [member clock_time] noon and midnight, respectively.
## However, JDN and date [b]values[/b] are determined by [member time]. ("Skips"
## or "repeats" are inevitable over very long time scales if using UT.)[br][br]
##
## [IVTimekeeper] simulates dynamic UT using [member universal_time_body]
## or calculates UT from Earth constant values. Either will be an approximation
## of UT1 unless something weird is done with [member universal_time_body].[br][br]
##
## [IVTimekeeper] maintains [member julian_day_number] (JDN) mainly for date
## calculations. JDN rolls over at noon [member clock_time] (this makes JDN-
## Gregorian date conversions tricky; use care). This value is
## available at [member IVGlobal.clock][2] (as a float whole number).
## [br][br]
##
## Julian Date (JD) is not used by the simulator, but can be calculated by
## adding [member julian_day_number] (an integer) with the fractional part of
## [member clock_time]. Or use [method get_julian_date].[br][br]
##
## Pause and "user pause" are maintained by [IVStateManager].[br][br]


## Emitted when game speed changes and on [signal IVGlobal.ui_dirty].
signal speed_changed()
## Emitted when the Gregorian calendar date changes and on [signal
## IVGlobal.ui_dirty]. Date rolls over at midnight [member clock_time].
signal date_changed()
## Emitted when [member julian_day_number] (JDN) changes and on [signal
## IVGlobal.ui_dirty]. JDN rolls over at noon [member clock_time].
signal julian_day_number_changed()
## Emitted when code sets time outside of the normal flow of time. In a game
## context this probably only happens at game start. (In our Planetarium, it
## happens when the user sets time.)
signal time_altered(previous_time: float)


## Julian Day Number at J2000 epoch.
const J2000_JULIAN_DAY_NUMBER := 2451545
## Unix epoch time relative to J2000 epoch (seconds).
const UNIX_EPOCH := -946728000.0
## Earth rotation rate for calculated universal time.
const UT_ROTATION_RATE := 0.00007292115024 / IVUnits.SECOND
## Earth orbit mean motion for calculated universal time.
const UT_ORBIT_MEAN_MOTION := 0.00000019909866 / IVUnits.SECOND
## Offset for calculated universal time. Reproduces the true 64.184 second UT1
## lag behind TT at J2000.
const UT_OFFSET := 0.00074287037037


const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_time",
	&"_speed_index",
	&"_reversed_time",
]


## If true, [member clock_time] indicates Terrestrial Time (TT), otherwise,
## Universal Time (UT; default). This affects clock GUI display and the exact
## rollover time for JDN and Gregorian date. TT will diverge from Earth rotation
## over time.[br][br]
##
## Settable at any time.[br][br]
##
## See also [member IVCoreSettings.start_time_is_terrestrial_time] (this affects
## game start time).
var terrestrial_time_clock := false: set = set_terrestrial_time_clock
## If true, [member terrestrial_time_clock] will be set and maintained to match
## user setting "terrestrial_time_clock". This setting must be added in
## [IVSettingsManager] and [IVOptionsPopup] to be available for user setting.
## (This is kind of niche use but available in our Planetarium.)
var terrestrial_time_clock_setting := false

## Terrestrial Time (TT) in units defined by [member IVUnits.SECOND] with J2000
## epoch (noon on Jan 1, 2000). This is the main simulator "time". The value can
## be obtained from [member IVGlobal.times][0].[br][br]
##
## Setting this value will emit [signal time_altered].
var time: float: set = set_time, get = get_time
## Current speed index as defined in [member speeds]. Settable.
var speed_index: int: set = set_speed_index, get = get_speed_index
## Reverse time flow. Only allowed if [member IVCoreSettings.allow_time_reversal]
## == true. Settable.
var reversed_time: bool: set = set_reversed_time, get = get_reversed_time

## Julian Day Number (JDN). See [url]https://en.wikipedia.org/wiki/Julian_day[/url].
## [br][br]
##
## This is the whole number part of Julian Date (JD).[br][br]
##
## This value can be obtained from [member IVGlobal.times][2] (as a float).[br][br]
##
## Read only.
var julian_day_number: int:
	get: return _julian_day_number



## Clock time is either Terrestrial Time (TT) or a simulated
## Universal Time (UT). See [member terrestrial_time_clock] and [member
## use_terrestrial_time_clock_setting]. Either is represented by a float with
## fractional part equal to time since the pevious [b]12:00 noon[/b].[br][br]
##
## If TT, this value will be equal to [member time] / [member IVUnits.DAY].
## TT will diverge from Earth's rotation over long time scales.[br][br]
## 
## UT is in "synodic day" units of [member universal_time_body]
## (if defined and present) or calculated from Earth rotation and orbit constants.
## This value should approximate UT1 as long as something weird isn't done with
## [member universal_time_body]. [member universal_time_offset] has a default
## value that reproduces the actual 64.184 second UT1 lag behind TT at J2000.[br][br]
##
## The fractional part of clock_time is represented in the integers of [member
## IVGlobal.clock]. It is also used to trigger rollover of JDN ([member
## julian_day_number]) and Gregorian calendar date ([member IVGlobal.date]) at
## noon and midnight, respectively. Note that JDN and date [b]values[/b] are
## derived from [member time].[br][br]
##
## This value can be obtained from [member IVGlobal.times][1].[br][br]
##
## Read only.
var clock_time: float


## [IVBody] for dynamic maintenence of [member clock_time] as Univeral Time.
## Value should be &"PLANET_EARTH" or &"" (but see below). If value is &"" or
## the named body goes missing for some reason, UT will be calculated from
## constants representing Earth's rotation and orbit.[br][br]
##
## What happens if value is &"PLANET_MARS"? [member clock_time] will slow down
## to fit Mars' 24 hr, 39 min, 36 sec (88776 seconds total) synodic day.
## [member IVGlobal.clock] "hours", "minutes" and "seconds" will be
## proportionately longer. JDN and Gregorian date rollovers will still happen
## at [member clock_time] noon and midnight, respectively. However, as [member
## clock_time] diverges from [member time], these rollovers will occasionally
## skip over a JDN and Gregorian date (~10 times per 12 months). JDN and
## Gregorian date will be correct over long time scales.[br][br]
##
## Conversely, if synodic day is short of 86400 seconds, JDN and Gregorian date
## will occasionally repeat on sequential clock cycles.[br][br]
##
## Earth synodic day is slightly longer than 86400 seconds and predicted to
## lengthen, so Earth will experience a date "skip" eventually. But this won't
## happen for tens or hundreds of thousands of years.
var universal_time_body := &"PLANET_EARTH"
## The default value reproduces the true 64.184 second UT1 lag behind TT at
## J2000 (with default [member universal_time_body] == &"PLANET_EARTH"). This
## offset was determined empirically and depends on exact data table values.
var universal_time_offset := 0.50435398148148





## If true, the simulator will start at real-world (present) date and UT
## time from user OS. Overrides [member IVCoreSettings.start_time_date_clock].
var start_real_world_time := false

## Project game speeds. Modify at [signal IVStateManager.core_initialized].
## Note: If the project might call [method synchronize_time_with_os], one of
## these speeds must have value [code]IVUnits.SECOND[/code] (i.e., real-time).
var speeds := [
	IVUnits.SECOND,
	IVUnits.MINUTE,
	IVUnits.HOUR,
	IVUnits.DAY,
	7.0 * IVUnits.DAY,
	30.4375 * IVUnits.DAY,
]

## Project game speed names for GUI. Modify at [signal IVStateManager.core_initialized].
## Note that [member speeds] value [code]IVUnits.SECOND[/code] is real-time.
var speed_names: Array[StringName] = [
	&"GAME_SPEED_REAL_TIME",
	&"GAME_SPEED_MINUTE_PER_SECOND",
	&"GAME_SPEED_HOUR_PER_SECOND",
	&"GAME_SPEED_DAY_PER_SECOND",
	&"GAME_SPEED_WEEK_PER_SECOND",
	&"GAME_SPEED_MONTH_PER_SECOND",
]


## Project [member speeds] index for game start. Modify at [signal
## IVStateManager.core_initialized].
var start_speed := 2
## [member speeds] index at or below which a clock should be displayed in GUI.
var show_clock_speed := 2
## [member speeds] index at or below which clock seconds should be displayed in GUI.
var show_seconds_speed := 1
## Format string used by [method get_current_date_for_file] to convert date into
## a file-safe string for game save file names.
var date_format_for_file := "%02d-%02d-%02d"

# public - read only!

## Is simulator time currently synchronizing with OS?[br][br]
##
## Read-only. Use [method synchronize_time_with_os] to set. Will be unset by a
## variety of events such as pause or game speed change.
var os_time_sync_on := false
## Current game speed multiplier from [member speeds] for current [member speed_index].
## Negative if [member reversed_time].[br][br]
##
## Read only.
var speed_multiplier: float # negative if reversed_time
## Show clock at current [member speed_index]?[br][br]
##
## Read only. Set [member show_clock_speed] to modify behavior.
var show_clock := false
## Show clock secods at current [member speed_index]?[br][br]
##
## Read only. Set [member show_seconds_speed] to modify behavior.
var show_seconds := false
## Current game speed name from [member speed_names] for current [member speed_index].
## Read-only for GUI.
var speed_name: StringName


# persisted
var _time: float
var _speed_index: int
var _reversed_time := false

# derived
var _julian_day_number: int



# localized
var _times: Array[float] = IVGlobal.times
var _clock: Array[int] = IVGlobal.clock
var _date: Array[int] = IVGlobal.date
var _date_aux: Array[int] = IVGlobal.date_aux

var _allow_time_setting := IVCoreSettings.allow_time_setting
var _allow_time_reversal := IVCoreSettings.allow_time_reversal
var _network_state := IVStateManager.NetworkState.NO_NETWORK


var _ut_body: IVBody
var _last_clock_time_floored := -99999999
var _last_clock_time_rounded := -99999999



@onready var _tree := get_tree()


# *****************************************************************************


@warning_ignore_start("shadowed_variable", "integer_division")

## JDN is calculated from epoch time, but rolls over at universal time midday
## (12:00). It's safest to use a [param time] value that is near the present
## midnight (i.e., far from the rollover time).
static func get_jdn_at_time(time: float) -> int:
	const DAY := IVUnits.DAY
	return floori(time / DAY) + J2000_JULIAN_DAY_NUMBER


## Tests whether input date integers define a valid Gregorian calendar day.
static func is_valid_gregorian_date(year: int, month: int, day: int) -> bool:
	if month < 1 or month > 12 or day < 1 or day > 31:
		return false
	if day < 29:
		return true
	if month != 2 and day < 31:
		return true
	var jdn := get_jdn_at_gregorian_date(year, month, day)
	var test_date: Array[int] = [0, 0, 0]
	set_date_elements_at_jdn(jdn, test_date)
	return test_date == [year, month, day]


## Converts Gregorian calendar integers to Julian Day Number. Use the previous
## day of the month to obtain JDN for any time before 12:00 noon UT (see note
## below regarding "previous day").[br][br]
##
## Does not test for valid input date. To do that, call [method
## is_valid_gregorian_date]. [br][br]
##
## Note: Although it is an invalid date, you can provide [param day] = 0 to
## obtain the "previous day" JDN on the 1st day of a month. Out-of-calendar
## days spill into the previous or following month, so [param day] = 0 always
## returns JDN for the last day of the previous month.
static func get_jdn_at_gregorian_date(year: int, month: int, day: int) -> int:
	# Who figured this out?
	return ((1461 * (year + 4800 + (month - 14) / 12)) / 4
			+ (367 * (month - 2 - 12 * ((month - 14) / 12))) / 12
			+ -(3 * ((year + 4900 + (month - 14) / 12) / 100)) / 4
			+ day - 32075)


## Sets Gregorian date elements in the provided array(s) for Julian Day Number.
## [param date] must have size >= 3 and will have the first 3 elements set to
## year, month, and day. If specified, [param date_aux] must have size >= 3 and
## will have the first 3 elements set to Q, YQ, and YM, where Q is quarter (1 - 4)
## and YQ and YM are cumulative counts of quarter and month since year 0.
static func set_date_elements_at_jdn(jdn: int, date: Array[int], date_aux: Array[int] = []) -> void:
	var f := jdn + 1401 + ((((4 * jdn + 274277) / 146097) * 3) / 4) - 38
	var e := 4 * f + 3
	var g := (e % 1461) / 4
	var h := 5 * g + 2
	var m := (((h / 153) + 2) % 12) + 1
	var y := (e / 1461) - 4716 + ((14 - m) / 12)
	date[0] = y
	date[1] = m # month
	date[2] = ((h % 153) / 5) + 1 # day
	if not date_aux:
		return
	
	var q := (m - 1) / 3 + 1
	date_aux[0] = q
	date_aux[1] = y * 4 + (q - 1) # yq, always increasing
	date_aux[2] = y * 12 + (m - 1) # ym, always increasing


static func get_date_elements_at_jdn(jdn: int, include_aux := false) -> Array[int]:
	var date: Array[int] = [0, 0, 0]
	if include_aux:
		var date_aux: Array[int] = [0, 0, 0]
		set_date_elements_at_jdn(jdn, date, date_aux)
		date.append_array(date_aux)
	else:
		set_date_elements_at_jdn(jdn, date)
	return date



## Returns (cummulative) Universal Time in body rotation units. Note: The
## fractional part is guaranteed to be current, but the cummulative whole part
## could be wonky if the body's orbit changes. However, it should be good enough
## for detecting date rollover.
static func get_universal_time_at_body_at_time(body: IVBody, time: float, offset: float) -> float:
	var rotation_angle := body.get_rotation_rate() * time + body.get_rotation_at_epoch()
	var orbit_angle := body.get_orbit_mean_motion(time) * time + body.get_orbit_mean_longitude(0.0)
	var mean_longitude := body.get_orbit_mean_longitude(time) # 0 ≤ L < 2π
	var synthetic_orbit_angle := snappedf(orbit_angle - PI, TAU) + mean_longitude
	# Fix possible wrap problem...
	var delta := synthetic_orbit_angle - orbit_angle
	if delta > PI:
		synthetic_orbit_angle -= TAU
	elif delta < -PI:
		synthetic_orbit_angle += TAU
	return (rotation_angle - synthetic_orbit_angle) / TAU - offset


## Sets clock elements (hour, minute, second) in the provided [param clock]
## array (assumes array size >= 3). Only the fractional part of [param
## clock_time] matters.
static func set_clock_elements_at_clock_time(clock_time: float, clock: Array[int]) -> void:
	var total_seconds := int(fposmod(clock_time - 0.5, 1.0) * 86400.0)
	var hour := total_seconds / 3600
	var minute := (total_seconds / 60) % 60
	clock[0] = hour
	clock[1] = minute
	clock[2] = total_seconds - hour * 3600 - minute * 60


## Returns an array with integer "clock" values hour, minute, and second.
## Only the fractional part of [param clock_time] matters.
static func get_clock_elements_at_clock_time(clock_time: float) -> Array[int]:
	var clock: Array[int] = [0, 0, 0]
	set_clock_elements_at_clock_time(clock_time, clock)
	return clock


@warning_ignore_restore("shadowed_variable", "integer_division")

# *****************************************************************************


func _ready() -> void:
	IVStateManager.about_to_start_simulator.connect(_on_about_to_start_simulator)
	IVStateManager.network_state_changed.connect(_on_network_state_changed)
	IVStateManager.run_state_changed.connect(_on_run_state_changed) # starts/stops
	IVStateManager.paused_changed.connect(_on_paused_changed)
	IVStateManager.about_to_free_procedural_nodes.connect(_on_about_to_free_procedural_nodes)
	IVGlobal.ui_dirty.connect(_on_ui_dirty)
	# Timekeeper must be pausible regarless of Universe.
	process_mode = PROCESS_MODE_PAUSABLE
	set_process(false) # changes with "run_state_changed" signal
	set_process_priority(-100) # always first!


func _process(delta: float) -> void:
	delta /= Engine.time_scale
	_time += delta * speed_multiplier
	_process_time()


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if os_time_sync_on:
			synchronize_time_with_os()


# *****************************************************************************
# setgets

func set_time(new_time: float) -> void:
	const IS_CLIENT = IVStateManager.NetworkState.IS_CLIENT
	if not _allow_time_setting:
		return
	if _network_state == IS_CLIENT:
		return
	var previous_time := _time
	_time = new_time
	os_time_sync_on = false
	_process_time()
	time_altered.emit(previous_time)


func get_time() -> float:
	return _time


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
	os_time_sync_on = false
	_speed_index = new_speed_index
	_process_speed_index()
	speed_changed.emit()


func get_speed_index() -> int:
	return _speed_index


func set_reversed_time(new_reversed_time: bool) -> void:
	const IS_CLIENT = IVStateManager.NetworkState.IS_CLIENT
	if _network_state == IS_CLIENT:
		return
	if !_allow_time_reversal or _reversed_time == new_reversed_time:
		return
	os_time_sync_on = false
	_reversed_time = new_reversed_time
	_process_speed_index()
	speed_changed.emit()


func get_reversed_time() -> float:
	return _reversed_time


func set_terrestrial_time_clock(value: bool) -> void:
	if terrestrial_time_clock == value:
		return
	terrestrial_time_clock = value
	if not IVStateManager.started:
		return
	_process_time() # in case we are paused

# *****************************************************************************

## Returns simulator time for provided date and clock elements. Assumes valid
## input! To test valid Gregorian date, use [method is_valid_gregorian_date].
func get_time_at_date_clock_elements(year: int, month: int, day: int,
		hour := 12, minute := 0, second := 0, is_terrestrial_time_clock := false) -> float:
	const SECOND := IVUnits.SECOND
	const MINUTE := IVUnits.MINUTE
	const HOUR := IVUnits.HOUR
	const DAY := IVUnits.DAY
	var jdn := get_jdn_at_gregorian_date(year, month, day)
	var epoch_days := jdn - J2000_JULIAN_DAY_NUMBER - 0.5 # approximately at midnight
	var ct := get_clock_time_at_time(epoch_days * DAY, is_terrestrial_time_clock)
	var delta := ct - epoch_days
	# For UT, delta will be small unless we are going out 10000s of years or messing
	# with rotations or orbits. But if we are, we want to keep the whole number
	# part of epoch_days and correct only the fractional part.
	delta = delta - int(delta)
	var result_time := (epoch_days - delta) * DAY # corrected time at midnight UT
	result_time += hour * HOUR
	result_time += minute * MINUTE
	result_time += second * SECOND
	return result_time


## See [method get_time_at_date_clock_elements]. The array must contain exactly
## six elements: year, month, day, hour, minute, second.
func get_time_at_date_clock_array(array: Array[int], is_terrestrial_time_clock := false) -> float:
	assert(array.size() == 6)
	return get_time_at_date_clock_elements(array[0], array[1], array[2],
			array[3], array[4], array[5], is_terrestrial_time_clock)


func get_clock_time_at_time(at_time: float, is_terrestrial_time_clock: bool) -> float:
	const DAY := IVUnits.DAY
	if is_terrestrial_time_clock:
		return at_time / DAY
	if is_instance_valid(_ut_body):
		return get_universal_time_at_body_at_time(_ut_body, at_time, universal_time_offset)
	return (UT_ROTATION_RATE - UT_ORBIT_MEAN_MOTION) * at_time / TAU - UT_OFFSET


## Returns Julian Date, the whole number part being [member julian_day_number]
## and the fractional part from [member clock_time]. This is either the UT or TT
## "flavor" of JD depending on which is being used for [member clock_time].
func get_julian_date() -> float:
	return _julian_day_number + fposmod(clock_time, 1.0)


func get_time_from_os() -> float:
	const SECOND := IVUnits.SECOND
	# TEST: Time.get_unix_time_from_system() did not previously work in
	# HTML5 export, so we used OS.get_system_time_msecs(). This needs testing.
	var unix_time := Time.get_unix_time_from_system()
	var j2000sec := unix_time + UNIX_EPOCH
	return j2000sec * SECOND


func get_current_date_for_file() -> String:
	return date_format_for_file % _date


func set_time_from_date_clock_elements(year: int, month: int, day: int,
		hour := 12, minute := 0, second := 0) -> void:
	var new_time := get_time_at_date_clock_elements(year, month, day, hour, minute, second)
	set_time(new_time)


func synchronize_time_with_os(sync_on := true) -> void:
	const IS_CLIENT = IVStateManager.NetworkState.IS_CLIENT
	var real_time_speed := speeds.find(IVUnits.SECOND)
	assert(real_time_speed != -1, "'speeds' does not have a real-time index")
	if not _allow_time_setting:
		return
	if _network_state == IS_CLIENT:
		return
	if not sync_on:
		os_time_sync_on = false
		return
	IVStateManager.set_user_paused(false)
	if not os_time_sync_on:
		set_reversed_time(false)
		set_speed_index(real_time_speed)
		os_time_sync_on = true
	var previous_time := _time
	_time = get_time_from_os()
	_process_time()
	time_altered.emit(previous_time)
	prints("Synchronized time with operating system", _date, _clock)


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


# *****************************************************************************

func _on_about_to_start_simulator(new_game: bool) -> void:
	if terrestrial_time_clock_setting:
		terrestrial_time_clock = (IVSettingsManager.has_setting(&"terrestrial_time_clock")
				and IVSettingsManager.get_setting(&"terrestrial_time_clock"))
		if not IVSettingsManager.changed.is_connected(_settings_listener):
			IVSettingsManager.changed.connect(_settings_listener)
	if universal_time_body:
		_ut_body = IVBody.bodies.get(universal_time_body)
		if not _ut_body:
			push_warning("Could not find universal_time_body '%s'." % universal_time_body
					+ " Calculating UT using Earth constants.")
	if new_game: # need game start _time & _speed_index (otherwise persisted from game load)
		if start_real_world_time or os_time_sync_on:
			_time = get_time_from_os()
		else:
			var start_time_date_clock := IVCoreSettings.start_time_date_clock
			_time = get_time_at_date_clock_array(IVCoreSettings.start_time_date_clock,
					IVCoreSettings.start_time_is_terrestrial_time)
		_speed_index = start_speed
	_last_clock_time_floored = -99999999 # forces JDN update
	_last_clock_time_rounded = -99999999 # forces Gregorian calendar update
	_process_time(true) # signal later on ui_dirty
	_process_speed_index()
	
	#prints("delta_T", time - clock_time * IVUnits.DAY)
	#prints("UT", clock_time)
	#prints("UT + 64.184 s", clock_time + 64.184 / IVUnits.DAY)


func _process_time(suppress_signals := false) -> void:
	# "_time" is set. Everything here follows from that...
	const DAY := IVUnits.DAY
	RenderingServer.global_shader_parameter_set("iv_time", _time)
	_times[0] = _time
	clock_time = get_clock_time_at_time(_time, terrestrial_time_clock)
	_times[1] = clock_time
	set_clock_elements_at_clock_time(clock_time, _clock)
	
	# JDN is calculated from actual time, but rolls over at noon clock time...
	var clock_time_floored := floori(clock_time)
	if _last_clock_time_floored != clock_time_floored:
		_last_clock_time_floored = clock_time_floored
		var ct_fractional := clock_time - clock_time_floored
		var midnight_after_last_noon := _time + (0.5 - ct_fractional) * DAY
		_julian_day_number = get_jdn_at_time(midnight_after_last_noon)
		_times[2] = _julian_day_number # int -> float
		if not suppress_signals:
			julian_day_number_changed.emit()
	
	# Gregorian calendar rolls over at midnight clock time...
	var clock_time_rounded := roundi(clock_time) # .5 rounds up
	if _last_clock_time_rounded != clock_time_rounded:
		_last_clock_time_rounded = clock_time_rounded
		# Use JDN + 1 from midnight (inclusive) to the instant before noon...
		var ct_fractional := clock_time - clock_time_floored
		var jdn_for_date := _julian_day_number + 1 if ct_fractional >= 0.5 else _julian_day_number
		set_date_elements_at_jdn(jdn_for_date, _date, _date_aux)
		if not suppress_signals:
			date_changed.emit()


func _process_speed_index() -> void:
	# "_speed_index" and "_reversed_time" are set. Everything here follows from that...
	speed_multiplier = speeds[_speed_index]
	if _reversed_time:
		speed_multiplier *= -1.0
	speed_name = speed_names[_speed_index]
	show_clock = _speed_index <= show_clock_speed
	show_seconds = show_clock and _speed_index <= show_seconds_speed
	if IVCoreSettings.manage_engine_time_scale:
		# Planetarium might be the only use-case for reversed_time, and we don't
		# use this setting. But let's avoid a negative time_scale anyway.
		Engine.time_scale = speeds[_speed_index]


func _on_ui_dirty() -> void:
	julian_day_number_changed.emit()
	date_changed.emit()
	speed_changed.emit()


func _on_paused_changed(_paused_tree: bool, paused_by_user: bool) -> void:
	if paused_by_user:
		os_time_sync_on = false
	speed_changed.emit() # pause can be a "speed change" for UI


func _on_run_state_changed(running: bool) -> void:
	set_process(running)
	if running and os_time_sync_on:
		await _tree.process_frame
		synchronize_time_with_os()


func _on_about_to_free_procedural_nodes() -> void:
	_ut_body = null


func _on_network_state_changed(network_state: IVStateManager.NetworkState) -> void:
	_network_state = network_state


func _settings_listener(setting: StringName, value: Variant) -> void:
	# Only connected if use_terrestrial_time_clock_setting == true...
	if setting == &"terrestrial_time_clock":
		terrestrial_time_clock = value
