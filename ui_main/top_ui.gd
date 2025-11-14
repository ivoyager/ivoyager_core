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
## This node provides "tree properties" used by GUI widgets. These are
## properties that specific widgets obtain from their ancestor node tree.
## The only required ancestor property for many widgets is [member selection_manager].
## All bool properties are optional (absence of the property in the ancestry
## tree is the same as a false value). "_theme_type_variation" properties
## are optional and useful for seting theme variations for widgets globally or
## in specific GUI branches.[br][br]
##
## This node "sets" a [member Control.theme] that it obtains via [method
## IVThemeManager.get_main_theme]. Note that this theme IS the project custom
## theme (ProjectSettings/GUI/Theme/Custom) if that exists and an override
## hasn't been set in [IVThemeManager]. So the "set" isn't necessarily a change.
## However, if the project doesn't have a custom theme, then [IVThemeManager]
## provides a fallback. This ensures that decendent GUI Controls have a custom
## theme one way or the other, which is necessary for dynamic font sizing by
## [IVThemeManager].[br][br]
##
## This node has [code]PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY[/code]
## to support save/load persistence using the Save plugin.
## [IVSelectionManager]
## is persisted here to keep current user selection through game save/load.
## Note that all widgets are coded to expect [IVSelectionManager] to be a
## procedural node, i.e., freed and replaced on game load.

const PERSIST_MODE := IVGlobal.PERSIST_PROPERTIES_ONLY ## Don't free on load.
const PERSIST_PROPERTIES: Array[StringName] = [&"selection_manager"]

## Set true to enable wiki links in decendent [IVHUDsHBox] instances.
## [IVWikiManager] must be present.
@export var enable_huds_hbox_links := false
## Set true to enable "label" wiki links in decendent [IVSelectionDataFoldable]
## instances. [IVWikiManager] must be present.
@export var enable_selection_data_label_links := false
## Set true to enable "value" wiki links in decendent [IVSelectionDataFoldable]
## instances. [IVWikiManager] must be present.
@export var enable_selection_data_value_links := false
## Theme type variation used by decedent FoldableContainer widgets (e.g.,
## [IVSelectionDataFoldable] and [IVHUDsFoldable]). This can be set closer to
## the Foldable widgets to override this value (e.g., in the foldable
## containers [IVSelectionData] or [IVHUDsBox]).
@export var foldables_theme_type_variation := &"ClearFoldable"

## This is the "main" selection manager for GUI panels and widgets, added
## by this class's code at [signal IVStateManager.about_to_build_system_tree]
## for new game. It is persisted so replaced by Save plugin on game load. It's
## possible to add other IVSelectionManager instances in branches of GUI for
## specialized use.
var selection_manager: IVSelectionManager


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	theme = IVThemeManager.get_main_theme()
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVStateManager.about_to_build_system_tree.connect(_add_selection_manager)
	IVStateManager.about_to_quit.connect(hide)


func _clear_procedural() -> void:
	if selection_manager:
		selection_manager.queue_free()
		selection_manager = null


func _add_selection_manager(is_new_game: bool) -> void:
	if is_new_game:
		selection_manager = IVSelectionManager.create()
		add_child(selection_manager)
