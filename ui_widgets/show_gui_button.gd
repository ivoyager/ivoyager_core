# show_gui_button.gd
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
class_name IVShowGUIButton
extends Button

## Button widget that brings back the GUI that an [IVShowHideUI] has hidden.
##
## Place it outside [member show_hide_ui], which would hide it too. The button
## shows while that GUI is hidden, and its [IVControlModFade] child fades it
## like the rest of the GUI, except that it fades when idle whatever the user
## setting. A tooltip names the key of the toggle action.


## The [IVShowHideUI] this button serves.
@export var show_hide_ui: IVShowHideUI



func _ready() -> void:
	assert(show_hide_ui, "IVShowGUIButton needs show_hide_ui")
	hide()
	show_hide_ui.visibility_toggled.connect(_on_visibility_toggled)
	IVStateManager.about_to_free_procedural_nodes.connect(hide)


func _pressed() -> void:
	show_hide_ui.show_hide_gui(false, true)


func _get_tooltip(_at_position: Vector2) -> String:
	return IVInputMapManager.append_action_key(tr(tooltip_text), show_hide_ui.user_toggle_action)


func _on_visibility_toggled(is_show: bool) -> void:
	visible = !is_show
