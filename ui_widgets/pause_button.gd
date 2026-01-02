# pause_button.gd
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
class_name IVPauseButton
extends Button

## Toggle button widget that sets/unsets user pause.
##
## See [IVStateManager] for pause details. The Core plugin distinguishes
## "paused_by_user" from pause set by code, e.g., for the main menu popup. A
## user pause is always a [SceneTree] pause, but a [SceneTree] pause is not
## always a user pause. This button sets and indicates "paused_by_user" state.[br][br]
##
## The widget has process_mode == PROCESS_MODE_ALWAYS so user can use it to
## get out of pause.

@export var unpaused_text := "||"
@export var paused_text := ">"
@export var unpaused_tooltip_text := "HINT_PAUSE"
@export var paused_tooltip_text := "HINT_UNPAUSE"


func _ready() -> void:
	IVStateManager.paused_changed.connect(_update_button) # signals on ui_dirty


func _toggled(toggled_on: bool) -> void:
	IVStateManager.set_user_paused(toggled_on)


func _update_button(_paused_tree: bool, paused_by_user: bool) -> void:
	disabled = not IVStateManager.can_user_pause()
	set_pressed_no_signal(paused_by_user)
	text = paused_text if paused_by_user else unpaused_text
	tooltip_text = paused_tooltip_text if paused_by_user else unpaused_tooltip_text
