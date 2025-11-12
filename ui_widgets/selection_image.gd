# selection_image.gd
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
class_name IVSelectionImage
extends TextureRect

## TextureRect widget that displays the current selection texture_2d. Acts like
## a button for "re-selection" (re-centers the selection).
##
## FIXME: Needs focus state display. Make this an image in a Button like [IVNavButton].

var _hint_extension := "\n\n" + tr(&"HINT_SELECTION_IMAGE")
var _selection_manager: IVSelectionManager


func _ready() -> void:
	set_default_cursor_shape(CURSOR_POINTING_HAND)
	IVGlobal.ui_dirty.connect(_update_selection)
	IVWidgets.connect_selection_manager(self, &"_on_selection_manager_changed",
			[&"selection_changed", &"_update_selection"])


func _gui_input(event: InputEvent) -> void:
	# image click centers and levels the target body
	var mouse_button_event := event as InputEventMouseButton
	if !mouse_button_event:
		return
	if !mouse_button_event.pressed:
		return
	if mouse_button_event.button_index != MOUSE_BUTTON_LEFT:
		return
	IVGlobal.move_camera_requested.emit(_selection_manager.selection, 0,
			Vector3(-INF, -INF, -INF), Vector3.ZERO)


func _on_selection_manager_changed(selection_manager: IVSelectionManager) -> void:
	_selection_manager = selection_manager
	if selection_manager:
		_update_selection()


func _update_selection(_dummy := false) -> void:
	tooltip_text = tr(_selection_manager.get_body_name()) + _hint_extension
	var texture_2d := _selection_manager.get_texture_2d()
	texture = texture_2d
