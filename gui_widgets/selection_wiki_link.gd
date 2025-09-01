# selection_wiki_link.gd
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
class_name IVSelectionWikiLink
extends RichTextLabel

## GUI widget that displays the selection name as a wiki link.
##
## This node needs to connect to an [IVSelectionManager]. At sim start it will
## attempt to find one by searching up the ancestry tree for a Control with
## property [param selection_manager].[br][br]
##
## This widget will attempt to display the current selection as a wiki link
## with underline. It will display non-underlined plain text if any of these
## conditions occur:[br][br]
##
## 1. IVCoreSettings.enable_wiki == false.[br]
## 2. IVWikiManager doesn't exist.[br]
## 3. IVWikiManager.has_page() returns false for the selection name.


var _selection_manager: IVSelectionManager

@onready var _wiki_manager: IVWikiManager = IVGlobal.program.get(&"WikiManager")


func _ready() -> void:
	IVGlobal.about_to_start_simulator.connect(_connect_selection_manager)
	if IVGlobal.state[&"is_started_or_about_to_start"]:
		_connect_selection_manager()
	IVGlobal.update_gui_requested.connect(_update_selection)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	meta_clicked.connect(_on_meta_clicked)



func _clear_procedural() -> void:
	_selection_manager = null


func _connect_selection_manager(_dummy := false) -> void:
	if _selection_manager:
		_selection_manager.selection_changed.disconnect(_update_selection)
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	assert(_selection_manager, "Did not find valid 'selection_manager' above this node")
	_selection_manager.selection_changed.connect(_update_selection)


func _update_selection(_dummy := false) -> void:
	var selection_name := _selection_manager.get_selection_name()
	var gui_name := _selection_manager.get_gui_name()
	if _wiki_manager and _wiki_manager.has_page(selection_name):
		parse_bbcode('[url="%s"]%s[/url]' % [selection_name, gui_name])
	else:
		parse_bbcode(gui_name)


func _on_meta_clicked(meta: String) -> void:
	_wiki_manager.open_page(meta)
