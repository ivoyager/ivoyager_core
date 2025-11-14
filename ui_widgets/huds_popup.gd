# huds_popup.gd
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
class_name IVHUDsPopup
extends PopupPanel

## A Popup widget that contains an [IVHUDsBox]. Opened by [IVHUDsPopupButton].


@export var focus_path := ^"HUDsBox/ViewCollection/ViewSaveButton"


@onready var _huds_box: Control = $HUDsBox
@onready var _focus_control: Control = get_node_or_null(focus_path)


func _ready() -> void:
	_huds_box.minimum_size_changed.connect(_reset_size)
	_huds_box.visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if _focus_control and _huds_box.is_visible_in_tree():
		_focus_control.grab_focus.call_deferred()


func _reset_size() -> void:
	size = Vector2.ZERO
