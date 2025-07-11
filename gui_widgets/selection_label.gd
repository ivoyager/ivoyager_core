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

## GUI widget.
##
## An ancestor Control node must have property [param selection_manager]
## set to an [IVSelectionManager] before [signal IVGlobal.about_to_start_simulator].[br][br]


var _selection_manager: IVSelectionManager



func _ready() -> void:
	IVGlobal.about_to_start_simulator.connect(_connect_selection_manager)
	IVGlobal.update_gui_requested.connect(_update_selection)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	_connect_selection_manager()



func _clear_procedural() -> void:
	_selection_manager = null


func _connect_selection_manager(_dummy := false) -> void:
	if _selection_manager:
		return
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	if !_selection_manager:
		return
	_selection_manager.selection_changed.connect(_update_selection)
	_update_selection()


func _update_selection(_dummy := false) -> void:
	if !_selection_manager.has_selection():
		return
	text = _selection_manager.get_gui_name()
