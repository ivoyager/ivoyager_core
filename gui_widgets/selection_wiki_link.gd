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
## attempt to find one by searching up the ancestry tree for a Control with property
## [param selection_manager].[br][br]
##
## Note: RichTextLabel seems unable to set its own size. You have to set this
## node's rect_min_size for it to show (as of Godot 3.2.1).
## Note 2: Set IVCoreSettings.enable_wiki = true


var use_selection_as_text := true # otherwise, "Wikipedia"
var fallback_text := &"LABEL_WIKIPEDIA"

var _wiki_titles: Dictionary = IVTableData.wiki_lookup
var _selection_manager: IVSelectionManager



func _ready() -> void:
	IVGlobal.about_to_start_simulator.connect(_connect_selection_manager)
	IVGlobal.update_gui_requested.connect(_update_selection)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	meta_clicked.connect(_on_wiki_clicked)
	size_flags_horizontal = SIZE_EXPAND_FILL
	_connect_selection_manager()



func _clear_procedural() -> void:
	_selection_manager = null


func _connect_selection_manager(_dummy := false) -> void:
	if _selection_manager:
		return
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	if !_selection_manager:
		return
	if use_selection_as_text:
		_selection_manager.selection_changed.connect(_update_selection)
	else:
		text = "[url]" + tr(fallback_text) + "[/url]"
	_update_selection()


func _update_selection(_dummy := false) -> void:
	if !_selection_manager.has_selection():
		return
	var object_name: String = _selection_manager.get_gui_name()
	text = "[url]" + tr(object_name) + "[/url]"


func _on_wiki_clicked(_meta: String) -> void:
	var object_name: String = _selection_manager.get_selection_name()
	if !_wiki_titles.has(object_name):
		return
	var page_title: String = _wiki_titles[object_name]
	IVGlobal.wiki_requested.emit(page_title)
