# main_prog_bar.gd
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
class_name IVMainProgBar
extends ProgressBar

## Progress bar widget driven by an external object's [code]progress[/code]
## property.
##
## Reads [code]progress[/code] (integer 0–100) from a target [Object] supplied
## via [method start] and updates [member ProgressBar.value] each frame until
## [method stop] is called.[br][br]
##
## This will not visually update if the main thread is hung up on a multi-frame
## task. It is mainly useful if the target object is operating on another
## thread.[br][br]
##
## Use [member delay_start_frames] to give the target object a chance to reset
## its progress when called on another thread.


# ALERT: This hasn't been used for a while and hasn't been maintained. It needs
# work to re-implement...


const SCENE := "res://addons/ivoyager_core/ui_widgets/main_prog_bar.tscn"


## Number of frames to wait before reading [code]progress[/code] from the
## target object. Useful when the target needs a moment to reset its counter.
var delay_start_frames := 0

var _delay_count := 0
var _object: Object


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if _delay_count < delay_start_frames:
		_delay_count += 1
		return
	@warning_ignore("unsafe_property_access")
	value = _object.progress


## Begins polling [param object].[code]progress[/code] each frame and showing
## the bar. The target must expose an integer [code]progress[/code] property
## with values from 0 to 100.
func start(object: Object) -> void:
	_object = object
	value = 0
	set_process(true)
	show()


## Hides the bar and stops polling the target object.
func stop() -> void:
	hide()
	set_process(false)
	_delay_count = 0
