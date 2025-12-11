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

## Handles full screen toggles.
##
## This node is not added in [IVCoreInitializer] by default. It must be added
## to enable toggle by hotkey action or by [IVFullScreenButton].[br][br]
##
## It's also necessary to set [member IVCoreSettings.allow_fullscreen_toggle]
## == true.

signal fullscreen_changed()

## In past Godot versions, a value >0 has been needed for correct update after
## full screen toggle, specifically in HTML5 exports. (This hasn't been tested
## for a while.)
var signal_echo_frames := 2

@onready var _window := get_tree().get_root()


func _ready() -> void:
	if not IVCoreSettings.allow_fullscreen_toggle:
		set_process_shortcut_input(false)
		return
	process_mode = PROCESS_MODE_ALWAYS


func _shortcut_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	return _window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN or _window.mode == Window.MODE_FULLSCREEN


func toggle_fullscreen() -> void:
	set_screen_state(not is_fullscreen())


func set_screen_state(fullscreen: bool) -> void:
	_window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	fullscreen_changed.emit()
	for i in signal_echo_frames:
		await get_tree().process_frame
		fullscreen_changed.emit()
