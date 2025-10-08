# huds_popup_button.gd
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
class_name IVHUDsPopupButton
extends Button

## Button widget that opens its own [IVHUDsPopup].

@export var popup_corner := Corner.CORNER_TOP_LEFT

var _huds_popup: PopupPanel


func _ready() -> void:
	var top_gui: Control = IVGlobal.program[&"TopGUI"]
	_huds_popup = IVFiles.make_object_or_scene(IVHUDsPopup)
	top_gui.add_child(_huds_popup)
	toggled.connect(_on_toggled)
	_huds_popup.visibility_changed.connect(_on_visibility_changed)



func _on_toggled(toggle_pressed: bool) -> void:
	if !_huds_popup:
		return
	if toggle_pressed:
		_huds_popup.popup()
		IVUtils.position_popup_at_corner.call_deferred(_huds_popup, self, popup_corner)
	else:
		_huds_popup.hide()


func _on_visibility_changed() -> void:
	await get_tree().process_frame
	if !_huds_popup.visible:
		button_pressed = false
