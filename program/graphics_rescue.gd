# graphics_rescue.gd
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
class_name IVGraphicsRescue
extends Node

## Offers this machine's recommended graphics settings when frames crawl, and tells the user
## when a start has restored them.
##
## Added by [IVCoreInitializer] if [member IVCoreSettings.enable_graphics_rescue]. It speaks
## through [signal IVGlobal.confirmation_required], so a project needs an [IVConfirmationDialog]
## for it to be heard, and it waits while any popup is open.[br][br]
##
## When more than half the frames drawn over [member slow_span] s take longer than [member
## slow_frame_time], and any of [member IVSettingsManager.graphics_settings] differs from its
## default, it asks once a session whether to restore them. Frames drawn while a setting has an
## unconfirmed change don't count.[br][br]
##
## A start that restored them ([member IVSettingsManager.graphics_reset]) gets a notice saying
## why. See [i]A setting the machine can't carry[/i] in [code]GRAPHICS_PROFILING.md[/code].


var slow_frame_time := 0.25 ## Seconds past which a frame counts as slow.
var slow_span := 10.0 ## Seconds of counted frames that are judged together.

var _is_notice_pending := false
var _frame_usec := 0
var _counted_time := 0.0
var _frames := 0
var _slow_frames := 0


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	set_process(false)
	IVStateManager.simulator_started.connect(_on_simulator_started, CONNECT_ONE_SHOT)
	IVSettingsManager.changed.connect(_restart_count.unbind(2))


func _process(_delta: float) -> void:
	# Delta follows Engine.time_scale, which IVTimekeeper sets from game speed.
	var usec := Time.get_ticks_usec()
	var frame_time := (usec - _frame_usec) / 1e6
	_frame_usec = usec
	if !get_viewport().get_embedded_subwindows().is_empty():
		return
	if _is_notice_pending:
		_show_reset_notice()
		return
	if !IVSettingsManager.is_cache_current():
		return
	_counted_time += frame_time
	_frames += 1
	if frame_time > slow_frame_time:
		_slow_frames += 1
	if _counted_time < slow_span:
		return
	var is_slow := _slow_frames * 2 > _frames
	_restart_count()
	if is_slow and !IVSettingsManager.is_graphics_defaults():
		_offer_recommended()


func _on_simulator_started() -> void:
	_is_notice_pending = IVSettingsManager.graphics_reset != IVSettingsManager.GraphicsReset.NONE
	_frame_usec = Time.get_ticks_usec()
	_restart_count()
	set_process(true)


func _restart_count() -> void:
	_counted_time = 0.0
	_frames = 0
	_slow_frames = 0


func _show_reset_notice() -> void:
	_is_notice_pending = false
	var text := tr(&"TXT_GRAPHICS_RESET_REQUESTED")
	if IVSettingsManager.graphics_reset == IVSettingsManager.GraphicsReset.FAILED_START:
		text = tr(&"TXT_GRAPHICS_RESET_AFTER_FAILED_START")
	if IVSettingsManager.is_restart_pending():
		text += "\n" + tr(&"TXT_GRAPHICS_RESTART_TO_FINISH")
	_show_notice(text)


func _offer_recommended() -> void:
	set_process(false)
	IVGlobal.confirmation_required.emit(&"TXT_Q_USE_RECOMMENDED_GRAPHICS", _use_recommended,
			false, &"LABEL_GRAPHICS_SETTINGS", &"BUTTON_USE_RECOMMENDED", &"BUTTON_KEEP_CURRENT")


func _use_recommended() -> void:
	IVSettingsManager.restore_graphics_defaults()
	if IVSettingsManager.is_restart_pending():
		_show_notice.call_deferred(tr(&"TXT_GRAPHICS_RESTART_TO_FINISH"))


func _show_notice(text: String) -> void:
	IVGlobal.confirmation_required.emit(text, Callable(), false, &"LABEL_GRAPHICS_SETTINGS",
			&"BUTTON_OK", &"")
