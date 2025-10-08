# view_edit_popup.gd
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
class_name IVViewEditPopup
extends PopupPanel

## Popup widget containing an [IVViewEdit]
##
## Each [IVViewEditPopup] is associated with an [IVViewCollection] and may be
## evoked (indirectly) by [IVViewSaveButton] for saving a new button or
## [IVViewButton] for editing an existing button.



func _ready() -> void:
	# Popup expands but does not shrink. Needs reset.
	(%ViewEdit as Control).resized.connect(_reset_size)


func _unhandled_input(event: InputEvent) -> void:
	# Hide on right-mouse click or shift-Enter. This is natural for this popup
	# because it is evoked by these actions for editing buttons.
	var mouse_button_event := event as InputEventMouseButton
	if mouse_button_event:
		if mouse_button_event.pressed and mouse_button_event.button_index == MOUSE_BUTTON_RIGHT:
			hide()
			get_viewport().set_input_as_handled()
		return
	var key_event := event as InputEventKey
	if key_event:
		if key_event.pressed and key_event.keycode == KEY_ENTER and key_event.shift_pressed:
			hide()
			get_viewport().set_input_as_handled()



func _reset_size() -> void:
	size = Vector2.ZERO
