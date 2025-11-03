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
class_name IVTopGUI
extends Control

## Top Control for GUI scene tree construction.
##
## See [IVUniverseTemplate] for scene tree organization.[br][br]
##
## This node provides several properties used by GUI widgets (they search up
## their ancestry tree for these). The only required ancestor property for many
## widgets is [member selection_manager]. All bool properties are optional:
## absence of the property in the scene tree is the same as a false value.[br][br]
##
## By default, this node sets its own Theme by calling [method
## IVThemeManager.get_main_theme]. (FIXME: Do this in a more "Editor way"...)[br][br]
##
## In most cases, the GUI tree probably shouldn't be persisted. But it might be
## in special cases. This node and [IVShowHideGUI] have [code]const PERSIST_MODE[/code]
## to support GUI nodes that have save/load persistence. In either case,
## [IVSelectionManager] is persisted here to keep current user selection. Note
## that all widgets are coded to expect [IVSelectionManager] to be a persisted
## node, i.e., freed and rebuilt on game load.

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
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVGlobal.system_tree_built_or_loaded.connect(_on_system_tree_built_or_loaded)
	if IVCoreSettings.pause_only_stops_time:
		process_mode = PROCESS_MODE_ALWAYS


func _clear_procedural() -> void:
	if selection_manager:
		selection_manager.queue_free()
		selection_manager = null


func _on_system_tree_built_or_loaded(is_new_game: bool) -> void:
	if is_new_game:
		selection_manager = IVSelectionManager.create()
		add_child(selection_manager)
