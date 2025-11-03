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
## before [signal IVGlobal.system_tree_ready].

var _selection_manager: IVSelectionManager


func _ready() -> void:
	IVGlobal.update_gui_requested.connect(_update_selection)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVGlobal.system_tree_ready.connect(_connect_selection_manager)
	_connect_selection_manager()


func _connect_selection_manager(_dummy := false) -> void:
	# once after every system_tree_ready
	if _selection_manager or !IVStateManager.is_system_ready:
		return
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	assert(_selection_manager, "Did not find valid 'selection_manager' above this node")
	_selection_manager.selection_changed.connect(_update_selection)


func _clear_procedural() -> void:
	if _selection_manager:
		_selection_manager.selection_changed.disconnect(_update_selection)
		_selection_manager = null


func _update_selection(_dummy := false) -> void:
	text = _selection_manager.get_gui_name()
