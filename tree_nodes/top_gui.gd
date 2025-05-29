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

## Default top GUI node.

# An extension can replace the top GUI in IVCoreInitializer 
# (singletons/project_builder.gd) but see comments below:
# 
# Many GUI widgets expect to find 'selection_manager' somewhere in their 
# Control ancestry tree. This property must be assigned before IVGlobal signal
# 'system_tree_ready'.
#
# 'PERSIST_' constants are needed here for save/load persistence of the
# IVSelectionManager instance.
#
# IVThemeManager (prog_refs/theme_manager.gd) sets the 'main' Theme in IVGlobal
# dictionary 'themes', which is applied here. Some Theme changes are needed for
# proper GUI widget appearance.

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY # don't free on load
const PERSIST_PROPERTIES: Array[StringName] = [&"selection_manager"]


var selection_manager: IVSelectionManager



func _init() -> void:
	name = &"TopGUI"
	anchor_right = 1.0
	anchor_bottom = 1.0
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVGlobal.project_builder_finished.connect(_on_project_builder_finished)
	IVGlobal.system_tree_built_or_loaded.connect(_on_system_tree_built_or_loaded)


func _ready() -> void:
	if IVCoreSettings.pause_only_stops_time:
		process_mode = PROCESS_MODE_ALWAYS


func _clear_procedural() -> void:
	selection_manager = null


func _on_project_builder_finished() -> void:
	if IVGlobal.themes.has(&"main"):
		theme = IVGlobal.themes.main


func _on_system_tree_built_or_loaded(is_new_game: bool) -> void:
	if is_new_game:
		selection_manager = IVSelectionManager.create()
		add_child(selection_manager)
