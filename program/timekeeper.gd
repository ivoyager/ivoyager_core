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

## Maintains simulator "time" (TT; J2000 epoch), Julian Day Number, Gregorian
## calendar date, and "clock time" (simulated UT or TT).
##
## This node maintains [member IVGlobal.times], [member IVGlobal.clock],
## [member IVGlobal.date], [member IVGlobal.date_aux], and shader global
## "iv_time". (Shader global "iv_time" is assumed to exist.)[br][br]
##
## Game speed is managed by [IVSpeedManager]. Pause and "user pause" are
## managed by [IVStateManager].[br][br]
##
## For definitions of Terrestrial Time (TT), Universal Time (UT, UT1), Julian
## Day Number (JDN), and Julian Date (JD), see:[br]
## [url]https://en.wikipedia.org/wiki/Terrestrial_Time[/url][br]
## [url]https://en.wikipedia.org/wiki/Universal_Time[/url][br]
## [url]https://en.wikipedia.org/wiki/Julian_day[/url][br][br]
##
## Simulator [member time] is Terrestrial Time in units defined by [constant
## IVUnits.SECOND] with J2000 epoch (noon on Jan 1, 2000). This value is "time"
## for essentially all simulator mechanics. It is always available in array
## [member IVGlobal.times] at index 0 (the array property is never reassigned,
## so it is safe to keep a local reference in class files).[br][br]
##
## Simulator [member clock_time] can follow either simulated Universal Time
## (default) or Terrestrial Time. The essential difference is that UT will
## maintain synchrony with Earth rotation (or possibly some other body) while TT
## will diverge over time. This value is used to generate "clock" integers in
## [member IVGlobal.clock] and to determine the exact "rollover" time for JDN
## ([member julian_day_number]) and Gregorian date ([member IVGlobal.date]) at
## noon and midnight, respectively. (However, JDN and date [b]values[/b] are
## determined by [member time]. "Skips" or "repeats" are inevitable over very
## long time scales if using UT.) This value is available in array [member
## IVGlobal.times] at index 1.[br][br]
##
## [IVTimekeeper] simulates dynamic UT using [member universal_time_body]
## or calculates UT from Earth constant values. Either will be an approximation
## of UT1 unless something weird is done with [member universal_time_body].[br][br]
##
## [IVTimekeeper] maintains [member julian_day_number] (JDN) mainly for date
## calculations. JDN rolls over at noon [member clock_time], which makes
## JDN-Gregorian date conversions tricky. Use care. This value is available in
## array [member IVGlobal.times] at index 2 as a float whole number.[br][br]
##
## Julian Date (JD) is not used by the simulator, but can be calculated by
## adding [member julian_day_number] (an integer) with the fractional part of
## [member clock_time]. Or use [method get_julian_date].[br][br]


## Emitted when the Gregorian calendar date ([member IVGlobal.date]) changes and
## on [signal IVGlobal.ui_dirty]. Date rolls over at midnight [member clock_time].
signal date_changed()
## Emitted when JDN ([member julian_day_number]) changes and on [signal
## IVGlobal.ui_dirty]. JDN rolls over at noon [member clock_time].
signal julian_day_number_changed()
## Emitted when code sets time outside of the normal flow of time. This may
## never happen in a typical game context. In our Planetarium, it happens when
## the user sets time using [IVTimeSetter].
signal time_set(previous_time: float)


## Julian Day Number at J2000.
const JULIAN_DAY_NUMBER_AT_J2000 := 2451545
## Unix epoch time at J2000 in seconds. Does not account for leap seconds!
const UNIX_EPOCH_SECONDS_AT_J2000 := 946728000.0
## UTC leap seconds added at J2000. See [member utc_leap_seconds] for current.
const UTC_LEAP_SECONDS_AT_J2000 := 32
## TT lead over TAI by definition. TT = UTC + leap seconds + this.
const TT_TAI_OFFSET_SECONDS := 32.184
## Earth rotation rate for calculated universal time.
const UT_ROTATION_RATE := 0.00007292115024 / IVUnits.SECOND
## Earth orbit mean motion for calculated universal time.
const UT_ORBIT_MEAN_MOTION := 0.00000019909866 / IVUnits.SECOND
## Offset for calculated universal time. Reproduces the 69.184 s UT1 lag behind
## TT at present time (Dec 2025) given the two "UT_" constants. The lag will
## diverge from actual lag based on calculated Earth rotation and orbit in
## addition to future UTC leap seconds. A current value can be printed using
## [method debug_print_present_offsets].
const UT_OFFSET := 0.00072434799


const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_time",
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
## (This is very "niche use" but available in our Planetarium.)
var terrestrial_time_clock_user_setting := false

## Terrestrial Time (TT) in units defined by [constant IVUnits.SECOND] with J2000
## epoch (noon on Jan 1, 2000). This is the main simulator "time". The value can
## be obtained from [member IVGlobal.times][0].[br][br]
##
## Setting this value will emit [signal time_set].
var time: float: set = set_time, get = get_time

## Julian Day Number (JDN). See [url]https://en.wikipedia.org/wiki/Julian_day[/url].
## [br][br]
##
## This is the whole number part of Julian Date (JD).[br][br]
##
## This value can be obtained from [member IVGlobal.times][2] (as a float).[br][br]
##
## Read only.
var julian_day_number: int: get = get_julian_day_number

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
## [member universal_time_body]. The default value of [member universal_time_offset]
## reproduces the actual 69.184 second UT1 lag behind TT at present time.[br][br]
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
## To represent Earth "Universal Time", the value can be either &"PLANET_EARTH"
## or &"". If value is &"" (or the named body goes missing for some reason), UT
## will be calculated from constants representing Earth's rotation and orbit.[br][br]
##
## What happens if value is &"PLANET_MARS"? UT [member clock_time]
## will slow down to fit Mars' 24 hr, 39 min, 36 sec synodic day (88776 seconds
## total). [member IVGlobal.clock] "hours", "minutes" and "seconds" will be
## proportionately longer. JDN and Gregorian date rollovers will still happen
## at [member clock_time] noon and midnight, respectively. However, as [member
## clock_time] diverges from [member time], these rollovers will skip over a
## a JDN and Gregorian date approximately 10 times every 12 months. JDN and
## Gregorian date will be correct over long time scales because the [b]values[/b]
## (as opposed to the rollover events) are based on TT [member time].[br][br]
##
## Conversely, if synodic day is short of 86400 seconds, JDN and Gregorian date
## will occasionally repeat on sequential clock cycles.[br][br]
##
## Earth synodic day is slightly longer than 86400 seconds (and predicted to
## lengthen for the real Earth), so Earth will experience a date "skip"
## eventually. But this won't happen for hundreds of thousands of years for
## simulated Earth (and an unknown but very long time for real Earth).
var universal_time_body := &"PLANET_EARTH"

## The default value reproduces the current 69.184 second UT1 lag behind TT
## using [member universal_time_body] == &"PLANET_EARTH". The offset needed may
## change with small implementation details affecting simulated Earth rotation
## and orbit, and over time as simulated Earth diverges from real Earth. If a
## precise current value is needed, set [member recalculate_universal_time_offset]
## = true to recalculate and set at system build.
var universal_time_offset := 0.50410651
## If true, recalulate and set [member universal_time_offset] at system build.
## This is only needed if you need UT clock display to be perfectly synchronized
## with user OS time.
var recalculate_universal_time_offset := false
## Present UTC leap seconds. The last leap second was added on 2016‑12‑31.
var utc_leap_seconds := 37
## If true, the simulator will start at real-world (present) date and UT
## time from user OS. Overrides [member IVCoreSettings.start_time_date_clock].
var start_real_world_time := false


# persisted
var _time: float

# derived
var _julian_day_number: int

# localized
var _speed_manager: IVSpeedManager
var _times: Array[float] = IVGlobal.times
var _clock: Array[int] = IVGlobal.clock
var _date: Array[int] = IVGlobal.date
var _date_aux: Array[int] = IVGlobal.date_aux
var _allow_time_setting := IVCoreSettings.allow_time_setting
var _network_state := IVStateManager.NetworkState.NO_NETWORK


var _speed_multiplier: float # managed by IVSpeedManager; negative if reversed_time
var _ut_body: IVBody
var _last_clock_time_floored := -99999999
var _last_clock_time_rounded := -99999999



# *****************************************************************************

@warning_ignore_start("shadowed_variable", "integer_division")

## Returns Julian Day Number (JDN). JDN is calculated from TT J2000 epoch time,
## but rolls over at "clock time" noon (12:00). It's safest to use [param time]
## at midnight after the last noon (i.e., far from the rollover time).
static func get_jdn_at_time(time: float) -> int:
	const DAY := IVUnits.DAY
	return floori(time / DAY) + JULIAN_DAY_NUMBER_AT_J2000


## Tests whether input date integers define a valid Gregorian calendar day.
static func is_valid_gregorian_date(year: int, month: int, day: int) -> bool:
	if month < 1 or month > 12 or day < 1 or day > 31:
		return false
	if day < 29:
		return true
	if month != 2 and day < 31:
		return true
	var test_date: Array[int] = [year, month, day]
	var jdn := get_jdn_at_gregorian_date(year, month, day)
	var derived_date: Array[int] = [0, 0, 0]
	get_date_elements_at_jdn(jdn, derived_date)
	return derived_date == test_date


## Converts Gregorian calendar integers to Julian Day Number. Use the previous
## day of the month to obtain JDN for any time before 12:00 noon (see note below
## regarding "previous day").[br][br]
##
## Does not test for valid input date. To do that, call [method
## is_valid_gregorian_date]. [br][br]
##
## Note: Although it is an invalid date, you can provide [param day] = 0 to
## obtain the "previous day" JDN on the 1st day of a month. Invalid out-of-calendar
## days shift into the previous or following month additively, so [param day] = 0
## always returns JDN for the last day of the previous month.
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
static func get_date_elements_at_jdn(jdn: int, date: Array[int], date_aux: Array[int] = []) -> void:
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


## Returns cummulative synodic days at [param body] at [param time] with
## specified [param offset]. Note: The fractional part is guaranteed to be
## correct at present [param time], but the cummulative whole part could be
## wonky if the body's orbit has changed significantly. However, it should be
## good enough for detecting noon and midnight rollovers for Universal Time.
static func get_synodic_days_at_body_at_time(body: IVBody, time: float, offset: float) -> float:
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
static func get_clock_elements_at_clock_time(clock_time: float, clock: Array[int]) -> void:
	var total_seconds := int(fposmod(clock_time - 0.5, 1.0) * 86400.0)
	var hour := total_seconds / 3600
	var minute := (total_seconds / 60) % 60
	clock[0] = hour
	clock[1] = minute
	clock[2] = total_seconds - hour * 3600 - minute * 60

@warning_ignore_restore("shadowed_variable", "integer_division")

# *****************************************************************************


func _ready() -> void:
	IVStateManager.core_initialized.connect(_on_core_initialized)
	IVStateManager.about_to_start_simulator.connect(_on_about_to_start_simulator)
	IVStateManager.network_state_changed.connect(_on_network_state_changed)
	IVStateManager.run_state_changed.connect(_on_run_state_changed) # starts/stops
	IVStateManager.about_to_free_procedural_nodes.connect(_on_about_to_free_procedural_nodes)
	IVGlobal.ui_dirty.connect(_on_ui_dirty)
	process_mode = PROCESS_MODE_PAUSABLE # must be pausible irrispective of Universe
	set_process(false) # changes with signal run_state_changed
	set_process_priority(-100) # always first when processing!


func _process(delta: float) -> void:
	delta /= Engine.time_scale # Engine.time_scale may or may not follow _speed_multiplier
	_time += delta * _speed_multiplier
	_process_time()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _speed_manager.os_time_sync_on:
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
	_speed_manager.os_time_sync_on = false
	_process_time()
	time_set.emit(previous_time)


func get_time() -> float:
	return _time


func get_julian_day_number() -> int:
	return _julian_day_number


func set_terrestrial_time_clock(use_terrestrial_time_clock: bool) -> void:
	if terrestrial_time_clock == use_terrestrial_time_clock:
		return
	terrestrial_time_clock = use_terrestrial_time_clock
	if not IVStateManager.started:
		return
	_process_time() # in case we are paused

# *****************************************************************************

func calculate_present_universal_time_offset() -> float:
	const SECOND := IVUnits.SECOND
	const DAY := IVUnits.DAY
	assert(_ut_body)
	var unix_time := Time.get_unix_time_from_system()
	var utc_sec := unix_time - UNIX_EPOCH_SECONDS_AT_J2000 # no leap seconds added!
	var tt_sec := utc_sec + utc_leap_seconds + TT_TAI_OFFSET_SECONDS
	return get_synodic_days_at_body_at_time(_ut_body, tt_sec * SECOND, 0.0) - utc_sec / DAY


func debug_print_present_offsets() -> void:
	const SECOND := IVUnits.SECOND
	const DAY := IVUnits.DAY
	var unix_time := Time.get_unix_time_from_system()
	var utc_sec := unix_time - UNIX_EPOCH_SECONDS_AT_J2000 # no leap seconds added!
	var tt_sec := utc_sec + utc_leap_seconds + TT_TAI_OFFSET_SECONDS
	if _ut_body:
		var offset := (get_synodic_days_at_body_at_time(_ut_body, tt_sec * SECOND, 0.0)
				- utc_sec / DAY)
		prints("Present offset for %s is" % _ut_body.name, offset)
	var calc_offset := ((UT_ROTATION_RATE - UT_ORBIT_MEAN_MOTION) * tt_sec / TAU
			- utc_sec / DAY)
	prints("Present offset for Earth constants is ", calc_offset)


## Returns simulator time for provided date and clock elements. Assumes valid
## input! To test valid Gregorian date, use [method is_valid_gregorian_date].
func get_time_at_date_clock_elements(year: int, month: int, day: int,
		hour := 12, minute := 0, second := 0, is_terrestrial_time_clock := false) -> float:
	const SECOND := IVUnits.SECOND
	const MINUTE := IVUnits.MINUTE
	const HOUR := IVUnits.HOUR
	const DAY := IVUnits.DAY
	var jdn := get_jdn_at_gregorian_date(year, month, day)
	var epoch_days := jdn - JULIAN_DAY_NUMBER_AT_J2000 - 0.5
	var result_time := epoch_days * DAY
	if not is_terrestrial_time_clock:
		var ct := get_clock_time_at_time(epoch_days * DAY, false)
		var delta := ct - epoch_days
		# Delta will be small unless we are going out 10000s of years or messing
		# with rotations or orbits. But if we are, we want to keep the whole number
		# part of epoch_days and correct only the fractional part.
		delta = delta - int(delta)
		result_time -= delta * DAY # corrected time at midnight UT
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


## Clock time is in body synodic days for UT (default), or in units [constant
## IVUnits.DAY] for TT (if [param is_terrestrial_time_clock] == true).
func get_clock_time_at_time(at_time: float, is_terrestrial_time_clock := false) -> float:
	const DAY := IVUnits.DAY
	if is_terrestrial_time_clock:
		return at_time / DAY
	if is_instance_valid(_ut_body):
		return get_synodic_days_at_body_at_time(_ut_body, at_time, universal_time_offset)
	return (UT_ROTATION_RATE - UT_ORBIT_MEAN_MOTION) * at_time / TAU - UT_OFFSET


## Returns Julian Date (JDN), the whole number part being [member
## julian_day_number] and the fractional part being the fractional part of
## [member clock_time]. This is either the UT or TT "flavor" of JD depending
## on which is being used for [member clock_time].
func get_julian_date() -> float:
	return _julian_day_number + fposmod(clock_time, 1.0)


## Returns "time" as Terrestrial Time (J2000 epoch; in units [constant
## IVUnits.SECOND]) from operating system. This includes a conversion from UTC
## "Unix time" to TAI (adding leap seconds) and from TAI to TT (32.184 s offset
## by definition). Curretly, TT leads UTC by 69.184 s.
func get_time_from_os() -> float:
	const SECOND := IVUnits.SECOND
	# TEST: Time.get_unix_time_from_system() did not previously work in
	# HTML5 export, so we used OS.get_system_time_msecs(). This needs testing.
	var unix_time := Time.get_unix_time_from_system()
	var utc_sec := unix_time - UNIX_EPOCH_SECONDS_AT_J2000 # no leap seconds added!
	return (utc_sec + utc_leap_seconds + TT_TAI_OFFSET_SECONDS) * SECOND


func set_time_from_date_clock_elements(year: int, month: int, day: int,
		hour := 12, minute := 0, second := 0, is_terrestrial_time_clock := false) -> void:
	var new_time := get_time_at_date_clock_elements(year, month, day, hour, minute, second,
			is_terrestrial_time_clock)
	set_time(new_time)


func synchronize_time_with_os(sync_on := true) -> void:
	const IS_CLIENT = IVStateManager.NetworkState.IS_CLIENT
	var real_time_speed := _speed_manager.speeds.find(IVUnits.SECOND)
	assert(real_time_speed != -1, "IVSpeedManager.speeds does not have a real-time value")
	if not _allow_time_setting:
		return
	if _network_state == IS_CLIENT:
		return
	if not sync_on:
		_speed_manager.os_time_sync_on = false
		return
	IVStateManager.set_user_paused(false)
	if not _speed_manager.os_time_sync_on:
		_speed_manager.set_reversed_time(false)
		_speed_manager.set_speed_index(real_time_speed)
		_speed_manager.os_time_sync_on = true
	var previous_time := _time
	_time = get_time_from_os()
	_process_time()
	time_set.emit(previous_time)
	prints("Synchronized time with operating system", _date, _clock)


# *****************************************************************************

func _on_core_initialized() -> void:
	_speed_manager = IVGlobal.program[&"SpeedManager"]
	_speed_manager.speed_changed.connect(_on_speed_changed)


func _on_about_to_start_simulator(new_game: bool) -> void:
	_speed_multiplier = _speed_manager.speed_multiplier
	if terrestrial_time_clock_user_setting:
		terrestrial_time_clock = (IVSettingsManager.has_setting(&"terrestrial_time_clock")
				and IVSettingsManager.get_setting(&"terrestrial_time_clock"))
		if not IVSettingsManager.changed.is_connected(_settings_listener):
			IVSettingsManager.changed.connect(_settings_listener)
	if universal_time_body:
		_ut_body = IVBody.bodies.get(universal_time_body)
		if not _ut_body:
			push_warning("Could not find universal_time_body '%s'." % universal_time_body
					+ " Calculating UT using Earth constants.")
		elif recalculate_universal_time_offset:
			universal_time_offset = calculate_present_universal_time_offset()
			print(universal_time_offset)
	if new_game: # need game start _time & _speed_index (otherwise persisted from game load)
		if start_real_world_time or _speed_manager.os_time_sync_on:
			_time = get_time_from_os()
		else:
			var start_time_date_clock := IVCoreSettings.start_time_date_clock
			_time = get_time_at_date_clock_array(IVCoreSettings.start_time_date_clock,
					IVCoreSettings.start_time_is_terrestrial_time)
	_last_clock_time_floored = -99999999 # forces JDN update
	_last_clock_time_rounded = -99999999 # forces Gregorian calendar update
	_process_time(true) # signal later on ui_dirty
	
	#debug_print_present_offsets()


func _process_time(suppress_signals := false) -> void:
	# "_time" is set. Everything here follows from that...
	const DAY := IVUnits.DAY
	RenderingServer.global_shader_parameter_set("iv_time", _time)
	_times[0] = _time
	clock_time = get_clock_time_at_time(_time, terrestrial_time_clock)
	_times[1] = clock_time
	get_clock_elements_at_clock_time(clock_time, _clock)
	
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
		get_date_elements_at_jdn(jdn_for_date, _date, _date_aux)
		if not suppress_signals:
			date_changed.emit()


func _on_speed_changed() -> void:
	_speed_multiplier = _speed_manager.speed_multiplier


func _on_ui_dirty() -> void:
	julian_day_number_changed.emit()
	date_changed.emit()


func _on_run_state_changed(running: bool) -> void:
	set_process(running)
	if running and _speed_manager.os_time_sync_on:
		await get_tree().process_frame
		synchronize_time_with_os()


func _on_about_to_free_procedural_nodes() -> void:
	_ut_body = null


func _on_network_state_changed(network_state: IVStateManager.NetworkState) -> void:
	_network_state = network_state


func _settings_listener(setting: StringName, value: Variant) -> void:
	# Only connected if use_terrestrial_time_clock_setting == true...
	if setting == &"terrestrial_time_clock":
		terrestrial_time_clock = value
