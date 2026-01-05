# input_handler.gd
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
class_name IVInputHandler
extends Node

## Handles input not handled in class files.
##
## Handles input actions for major admin popups (main menu, options, etc.) and
## state change (e.g., quit).[br][br]
##
## Shortcut events not handled are passed to Objects in [member
## shortcut_handlers]. In standard setup, [IVTopUI] adds its [IVSelectionManager]
## to this array.


## Shortcut events not handled are passed to Objects in this array (in array
## order) until an object handles the event. Objects must have method
## [code]handle_shortcut_input()[/code] and the method must return [code]true[/code]
## if the event is handled. Objects should NOT call [method
## Viewport.set_input_as_handled].
var shortcut_handlers: Array[Object] = []


@onready var _viewport := get_viewport()


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS


func _shortcut_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		IVGlobal.main_menu_requested.emit()
	elif event.is_action_pressed(&"toggle_options", true):
		IVGlobal.options_requested.emit()
	elif event.is_action_pressed(&"toggle_hotkeys", true):
		IVGlobal.hotkeys_requested.emit()
	elif event.is_action_pressed(&"toggle_pause", true):
		IVStateManager.set_user_paused(not IVStateManager.paused_by_user)
	elif event.is_action_pressed(&"quit", true):
		IVStateManager.quit()
	else:
		for shortcut_handler in shortcut_handlers:
			if shortcut_handler.call(&"handle_shortcut_input", event):
				_viewport.set_input_as_handled()
				return
		return # input not handled
	_viewport.set_input_as_handled()
