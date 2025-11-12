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

## RichTextLabel widget that displays the selection name as a wiki link.
##
## Expects an ancestor Control with property [param selection_manager] set
## before [signal IVStateManager.system_tree_ready].[br][br]
##
## This widget attempts to display the current selection as a wiki link
## with underline. It will display non-underlined plain text if any of these
## conditions occur:[br][br]
##
## 1. IVWikiManager doesn't exist.[br]
## 2. IVWikiManager.has_page() returns false for the selection name.

var _wiki_manager: IVWikiManager
var _selection_manager: IVSelectionManager


func _ready() -> void:
	meta_clicked.connect(_on_meta_clicked)
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)
	IVWidgets.connect_selection_manager(self, &"_on_selection_manager_changed",
			[&"selection_changed", &"_update_selection"])


func _configure_after_core_inited() -> void:
	_wiki_manager = IVGlobal.program.get(&"WikiManager")


func _on_selection_manager_changed(selection_manager: IVSelectionManager) -> void:
	_selection_manager = selection_manager
	if selection_manager:
		_update_selection()


func _update_selection(_dummy := false) -> void:
	var selection_name := _selection_manager.get_selection_name()
	var gui_name := _selection_manager.get_gui_name()
	if _wiki_manager and _wiki_manager.has_page(selection_name):
		parse_bbcode('[url="%s"]%s[/url]' % [selection_name, gui_name])
	else:
		parse_bbcode(gui_name)


func _on_meta_clicked(meta: String) -> void:
	_wiki_manager.open_page(meta)
