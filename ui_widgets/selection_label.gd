# selection_label.gd
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
class_name IVSelectionLabel
extends Label

## Label widget that displays the selection name as plain text.
##
## Expects an ancestor Control with property [param selection_manager] set
## before [signal IVStateManager.system_tree_ready].

var _selection_manager: IVSelectionManager


func _ready() -> void:
	IVWidgets.connect_selection_manager(self, &"_on_selection_manager_changed",
			[&"selection_changed", &"_update_selection"])


func _on_selection_manager_changed(selection_manager: IVSelectionManager) -> void:
	_selection_manager = selection_manager


func _update_selection(_dummy := false) -> void:
	text = _selection_manager.get_gui_name()
