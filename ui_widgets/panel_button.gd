# panel_button.gd
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
class_name IVPanelButton
extends Button

## Toggle button widget that shows and hides a panel.
##
## The button is pressed while [member panel] is visible, whichever of them
## changes. Buttons that share a [ButtonGroup] with [member
## ButtonGroup.allow_unpress] set open their panels one at a time, and any of
## them can close its own. [member input_action] toggles the button from the
## keyboard, and the tooltip names its key.

## The Control this button shows and hides.
@export var panel: Control
## Action in [IVInputMapManager] that toggles this button; &"" for none.
@export var input_action := &""



func _ready() -> void:
	assert(panel, "IVPanelButton needs a panel")
	toggle_mode = true
	button_pressed = panel.visible
	toggled.connect(_on_toggled)
	panel.visibility_changed.connect(_on_panel_visibility_changed)
	set_process_shortcut_input(false)
	if input_action:
		IVStateManager.run_state_changed.connect(set_process_shortcut_input) # only when running


func _shortcut_input(event: InputEvent) -> void:
	if !is_visible_in_tree():
		return
	if IVInputMapManager.is_action_pressed(event, input_action):
		button_pressed = !button_pressed
		get_viewport().set_input_as_handled()


func _get_tooltip(_at_position: Vector2) -> String:
	return IVInputMapManager.append_action_key(tr(tooltip_text), input_action)


func _on_toggled(toggled_on: bool) -> void:
	panel.visible = toggled_on


func _on_panel_visibility_changed() -> void:
	# Through the setter, so a panel shown by other code still closes the rest of the group.
	if button_pressed != panel.visible:
		button_pressed = panel.visible
