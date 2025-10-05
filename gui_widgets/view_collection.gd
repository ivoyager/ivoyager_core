# view_collection.gd
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
class_name IVViewCollection
extends HFlowContainer

## HFlowContainer widget for containing a [IVViewSaveButton] and default and
## user [IVViewButton] instances.
##
## [IVViewButton] instances are either "default" (defined in data table views.tsv)
## or "user" (added at runtime by code and persisted via cache or gamesave).
## Build the GUI scene tree with a [IVViewSaveButton] and default [IVViewButton]
## instances (and other Controls if needed) as children. This node will add
## user [IVViewButton] instances by code in coordination with [IVViewSaveButton]
## and [IVViewEdit].
##
## A [IVViewSaveButton] can be outside of a [IVViewCollection]. If so,
## [member IVViewSaveButton.view_collection] must be set.

const ViewFlags := IVView.ViewFlags

## A unique [param collection_name] is required for user-created 
@export var collection_name: StringName
## If true (default), user [IVViewButton] instances are cached. Otherwise, they
## are persisted via gamesave.
@export var cached := true

@export var show_flags: int = ViewFlags.VIEWFLAGS_ALL
@export var init_flags: int = ViewFlags.VIEWFLAGS_ALL
## Names (or text keys for names) that won't be allowed. [IVViewEdit] will
## append a sequential integer if user tries to enter a reserved name.
@export var reserved_names: Array[StringName]= []
## This is the view name that appears in the [IVViewEdit] edit window.
@export var edit_view_name := &"LABEL_CUSTOM1"


@export var user_editable := true
@export var user_renamable := true
@export var user_deletable := true

# TODO: Rename ViewEditPopup, ViewEdit
var view_edit_popup: IVViewEditPopup
var view_edit: IVViewEdit



func _ready() -> void:
	IVGlobal.about_to_start_simulator.connect(_rebuild_user_buttons)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_user_buttons)
	view_edit_popup = IVFiles.make_object_or_scene(IVViewEditPopup)
	add_child(view_edit_popup)
	view_edit = view_edit_popup.find_child(&"ViewEdit")
	view_edit.init(edit_view_name, collection_name, cached, show_flags, init_flags,
			reserved_names)
	if IVGlobal.state.is_started_or_about_to_start:
		_rebuild_user_buttons()


## Adds a non-default, user-added view button (cached or saved).
## Normally called by [IVViewSaveButton].
func add_user_button(view_name: StringName) -> void:
	var button := IVViewButton.create_user_button(view_name, collection_name, cached,
			user_editable, user_renamable, user_deletable)
	add_child(button)



func _rebuild_user_buttons(_dummy := false) -> void:
	var view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]
	var view_names := view_manager.get_names_in_collection(collection_name, cached)
	for view_name in view_names:
		add_user_button(view_name)


func _clear_user_buttons() -> void:
	for child in get_children():
		var view_button := child as IVViewButton
		if view_button and view_button.default_view == &"":
			view_button.queue_free()
