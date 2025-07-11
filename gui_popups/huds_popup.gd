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

## Instanced by [IVHUDsPopupButton].

const SCENE := "res://addons/ivoyager_core/gui_popups/huds_popup.tscn"


func _ready() -> void:
	var view_save_flow: IVViewSaveFlow = $AllHUDs.find_child(&"ViewSaveFlow")
	view_save_flow.resized.connect(_reset_size)



func _reset_size() -> void:
	# Needed when FlowContainer loses a row (as of Godot 3.5.2).
	size = Vector2.ZERO
