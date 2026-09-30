# hide_gui_button.gd
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
class_name IVHideGUIButton
extends Button

## Button widget that hides the GUI.
##
## Emits [signal IVGlobal.show_hide_gui_requested], which [IVShowHideUI]
## handles. Pair it with an [IVShowGUIButton], which brings the GUI back. A
## tooltip names the key of the default [member IVShowHideUI.user_toggle_action].


func _pressed() -> void:
	IVGlobal.show_hide_gui_requested.emit(false, false)


func _get_tooltip(_at_position: Vector2) -> String:
	return IVInputMapManager.append_action_key(tr(tooltip_text), &"toggle_all_gui")
