# full_screen_button.gd
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
class_name IVFullScreenButton
extends Button

## Button widget that toggles between "Full Screen" and "Minimize".
##
## Use [IVFullScreenManager] for hotkey toggle.
##
## FIXME: Require IVFullScreenManager and implement listener and action in that
## class only (maybe implement IVGlobal.full_screen_toggle_requested).


var full_screen_text := &"BUTTON_FULL_SCREEN"
var minimize_text := &"BUTTON_MINIMIZE"


## In past Godot versions, a value >0 has been needed for correct state update
## specifically in HTML5 exports.
var frames_to_test_screen_state := 0

var _is_fullscreen := false
var _test_countdown := 0



func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	IVGlobal.update_gui_requested.connect(_update_button)
	get_viewport().size_changed.connect(_screen_state_listener)
	text = full_screen_text
	_update_button()


func _pressed() -> void:
	_change_fullscreen()


func _change_fullscreen() -> void:
	var window := get_window()
	var is_fullscreen := ((window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN)
			or (window.mode == Window.MODE_FULLSCREEN))
	window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if !is_fullscreen else Window.MODE_WINDOWED


func _update_button() -> void:
	var window := get_window()
	if _is_fullscreen == ((window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN)
			or (window.mode == Window.MODE_FULLSCREEN)):
		return # no update
	_is_fullscreen = !_is_fullscreen
	text = minimize_text if _is_fullscreen else full_screen_text


func _screen_state_listener() -> void:
	# In some browsers, OS.window_fullscreen takes a while to give changed
	# result. So we keep checking for a while.
	# TODO: Test if this is still the case in HTML export.
	if _test_countdown: # already running
		_test_countdown = frames_to_test_screen_state
		return
	_test_countdown = frames_to_test_screen_state
	_update_button()
	while _test_countdown:
		await get_tree().process_frame
		_update_button()
		_test_countdown -= 1
