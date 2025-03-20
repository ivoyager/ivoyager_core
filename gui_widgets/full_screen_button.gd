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

## Button that handles full screen / minimize toggles.
##
## Note: You don't need to add IVFullScreenManager if this node is present.



var full_screen_text := &"BUTTON_FULL_SCREEN"
var minimize_text := &"BUTTON_MINIMIZE"
var frames_to_test_screen_state := 0 # may need value for HTML export

var _is_fullscreen := false
var _test_countdown := 0



func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	IVGlobal.update_gui_requested.connect(_update_buttons)
	get_viewport().size_changed.connect(_screen_state_listener)
	text = full_screen_text
	_update_buttons()


func _pressed() -> void:
	_change_fullscreen()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		_change_fullscreen()
		get_viewport().set_input_as_handled()


func _change_fullscreen() -> void:
	var window := get_window()
	var is_fullscreen := ((window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN)
			or (window.mode == Window.MODE_FULLSCREEN))
	window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if !is_fullscreen else Window.MODE_WINDOWED


func _update_buttons() -> void:
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
	_update_buttons()
	while _test_countdown:
		await get_tree().process_frame
		_update_buttons()
		_test_countdown -= 1
