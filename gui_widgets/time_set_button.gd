# time_set_button.gd
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
class_name IVTimeSetButton
extends Button

## Button widget that opens its own [IVTimeSetPopup].


@export var popup_corner := Corner.CORNER_TOP_LEFT
@export var popup_stylebox_override: StyleBox

@onready var _time_set_popup: IVTimeSetPopup = $TimeSetPopup



func _ready() -> void:
	toggled.connect(_on_toggled)
	_time_set_popup.visibility_changed.connect(_on_visibility_changed)
	if popup_stylebox_override:
		_time_set_popup.add_theme_stylebox_override(&"panel", popup_stylebox_override)



func _on_toggled(toggle_pressed: bool) -> void:
	if toggle_pressed:
		_time_set_popup.popup()
		IVUtils.position_popup_at_corner.call_deferred(_time_set_popup, self, popup_corner)
	else:
		_time_set_popup.hide()


func _on_visibility_changed() -> void:
	await get_tree().process_frame
	if !_time_set_popup.visible:
		button_pressed = false
