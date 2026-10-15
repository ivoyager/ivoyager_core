# hide_huds_button.gd
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
class_name IVHideHUDsButton
extends Button

## Toggle button widget that hides all HUDs.
##
## Sets [member IVBodyHUDsState.huds_hidden], so HUDs checkboxes and saved views
## keep their state, and stays pressed while HUDs are hidden however they were
## hidden. A tooltip names the key of action [code]toggle_all_huds[/code].
## A text button shows [member hide_text] or [member show_text] for the state;
## an icon button keeps its icon.

## Text while HUDs are shown, for a text button.
@export var hide_text := &"BUTTON_HIDE_ALL_HUDS"
## Text while HUDs are hidden, for a text button.
@export var show_text := &"BUTTON_SHOW_ALL_HUDS"


var _body_huds_state: IVBodyHUDsState


func _ready() -> void:
	toggle_mode = true
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _toggled(toggled_on: bool) -> void:
	if _body_huds_state:
		_body_huds_state.set_huds_hidden(toggled_on)


func _get_tooltip(_at_position: Vector2) -> String:
	return IVInputMapManager.append_action_key(tr(tooltip_text), &"toggle_all_huds")


func _configure_after_core_inited() -> void:
	_body_huds_state = IVGlobal.program[&"BodyHUDsState"]
	_body_huds_state.huds_hidden_changed.connect(_show_state)
	_show_state(_body_huds_state.huds_hidden)


func _show_state(is_hidden: bool) -> void:
	set_pressed_no_signal(is_hidden)
	if !icon:
		text = show_text if is_hidden else hide_text
