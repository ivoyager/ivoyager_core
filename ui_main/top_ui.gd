# top_gui.gd
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
class_name IVTopUI
extends Control

## Top Control for UI scene tree construction.
##
## See [IVUniverseTemplate] for scene tree organization.[br][br]
##
## This node provides several "tree properties" used by GUI widgets (they search
## up their ancestry tree for these). The only required ancestor property for
## many widgets is [member selection_manager]. All bool properties are optional:
## absence of the property in the ancestry tree is the same as a false value.[br][br]
##
## By default, this node sets its own Theme by calling [method
## IVThemeManager.get_main_theme]. (FIXME: Do this in a more "Editor way"...)[br][br]
##
## In most cases, the GUI tree probably shouldn't be persisted. But it might be
## in special cases. This node and [IVShowHideUI] have [code]const PERSIST_MODE[/code]
## set to support GUI nodes that have save/load persistence.  [IVSelectionManager]
## is persisted here to keep current user selection through game save/load.
## Note that all widgets are coded to expect [IVSelectionManager] to be a
## procedural node, i.e., freed and replaced on game load.

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY ## Don't free on load.
const PERSIST_PROPERTIES: Array[StringName] = [&"selection_manager"]


@export var enable_huds_hbox_links := false
@export var enable_selection_data_label_links := false
@export var enable_selection_data_value_links := false


var selection_manager: IVSelectionManager


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	theme = IVThemeManager.get_main_theme()
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVStateManager.about_to_build_system_tree.connect(_add_selection_manager)
	IVStateManager.about_to_quit.connect(hide)
	if IVCoreSettings.pause_only_stops_time:
		process_mode = PROCESS_MODE_ALWAYS


func _clear_procedural() -> void:
	if selection_manager:
		selection_manager.queue_free()
		selection_manager = null


func _add_selection_manager(is_new_game: bool) -> void:
	if is_new_game:
		selection_manager = IVSelectionManager.create()
		add_child(selection_manager)
