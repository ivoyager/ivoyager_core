# full_screen_manager.gd
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
class_name IVFullScreenManager
extends Node


## Handles full screen / minimize toggles.
##
## This node is not added in IVCoreInitializer by default, and its function is
## completely duplicated by IVFullScreenButton. Add this node only if you want
## full screen toggle via hotkey but don't need the GUI button.


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		_change_fullscreen()
		get_viewport().set_input_as_handled()


func _change_fullscreen() -> void:
	var window := get_window()
	var is_fullscreen := ((window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN)
			or (window.mode == Window.MODE_FULLSCREEN))
	window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if !is_fullscreen else Window.MODE_WINDOWED
