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

## HFlowContainer widget for containing [IVViewButton] instances (default and/or
## user-saved) and a [IVViewSaveButton]
##
## [IVViewButton] instances are either default (defined in a data table like
## "VIEW_HOME" in
## [url=https://github.com/ivoyager/ivoyager_core/blob/master/data/tables/views.tsv]
## views.tsv[/url] or user-saved (added at runtime by code and persisted via
## cache or gamesave file).[br][br]
##
## Build the GUI scene tree with a [IVViewSaveButton] and default [IVViewButton]
## instances as children. Other children can be added and will be ignored. This
## node will add user [IVViewButton] instances by code in coordination with
## [IVViewSaveButton] and [IVViewEdit]. User-added view buttons will be after
## other items in the flow container.[br][br]
##
## A [IVViewSaveButton] can be outside of a [IVViewCollection]. If so,
## [member IVViewSaveButton.external_view_collection_path] must be set.

const ViewFlags := IVView.ViewFlags


static var _collection_names: Array[String]


## A unique collection name (any unique string) is required for user-added and
## edited default buttons. This is used for persisting and restoring buttons via
## cache or gamesave file.
@export var collection_name: String
## If true (default), user-added and edited default buttons in this collection
## are persisted via cache. Otherwise, they are persisted via gamesave file
## (requires Save plugin).
@export var is_cached := true
## The name that appears in the line edit of the edit popup for a new view button.
## The translated text is incremented as needed. See [IVViewEdit].
@export var new_button_name := &"LABEL_VIEW1"
## Defines which view state checkboxes are available in the edit popup. See
## [enum IVView.ViewFlags].
@export var allowed_flags: int = ViewFlags.VIEWFLAGS_ALL
## Defines which checkboxes are initially set in the edit popup for new buttons.
## See [enum IVView.ViewFlags].
@export var new_set_flags: int = ViewFlags.VIEWFLAGS_ALL_CAMERA
## External GUI containers (Controls) that have buttons with names we want to
## exclude from user button naming. E.g., a nearby GUI element may contain a
## default "Home" button. Including its container here would cause user added
## "Home" to increment to "Home2".
@export var external_button_containers: Array[NodePath] = []
## Specifies whether user-added [IVViewButton] instances will be editable.
@export var user_editable := true
## Specifies whether user-added [IVViewButton] instances will be ranamable in
## the edit popup. Only matters if [member user_editable] is true.
@export var user_renamable := true
## Specifies whether user-added [IVViewButton] instances will be deletable. This
## should be true unless user-added buttons are removed in some other way.
@export var user_deletable := true
## Specifies where [IVViewEditPopup] should appear relative to [IVViewSaveButton]
## or the [IVViewButton] being edited.
@export var popup_corner := Corner.CORNER_TOP_LEFT


@onready var _view_edit_popup: IVViewEditPopup = $ViewEditPopup
@onready var _view_edit: IVViewEdit = $ViewEditPopup/%ViewEdit



func _ready() -> void:
	if IVStateManager.is_core_inited:
		_configure_after_core_inited()
	else:
		IVStateManager.core_inited.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


## Adds a non-default, user-added view button (is_cached or saved).
func add_user_button(view_name: String) -> void:
	var button := IVViewButton.create_user_button(view_name, collection_name, is_cached,
			user_editable, user_renamable, user_deletable)
	add_child(button)
	button.edit_requested.connect(open_view_edit.bind(button, button))


func open_view_edit(at_control: Control, editing_button: IVViewButton = null) -> void:
	if _view_edit.is_visible_in_tree():
		return
	_view_edit.set_editing_button(editing_button) # null if new button creation
	_view_edit_popup.popup()
	IVUtils.position_popup_at_corner.call_deferred(_view_edit_popup, at_control, popup_corner)


func close_view_edit() -> void:
	_view_edit_popup.hide()


func get_view_edit_popup() -> IVViewEditPopup:
	return _view_edit_popup


func get_view_edit() -> IVViewEdit:
	return _view_edit


func _configure_after_core_inited() -> void:
	assert(collection_name, "IVViewCollection requires a unique collection_name")
	assert(!_collection_names.has(collection_name),
			"'%s' is not a unique collection_name" % collection_name)
	_collection_names.append(collection_name)
	var button_containers: Array[Control] = [self]
	for node_path in external_button_containers:
		var container: Control = get_node_or_null(node_path)
		if container:
			button_containers.append(container)
	_view_edit.init(new_button_name, collection_name, is_cached, allowed_flags, new_set_flags,
			button_containers)
	_view_edit.saved_new.connect(_on_edit_saved_new)
	_view_edit.saved_edit.connect(_on_edit_saved_edit)
	_view_edit.restored_default.connect(_on_edit_restored_default)
	_view_edit.deleted.connect(_on_edit_deleted)
	IVStateManager.about_to_free_procedural_nodes.connect(_reset_buttons)
	
	# TODO: TEST below now (on core_inited)
	IVStateManager.about_to_start_simulator.connect(_configure_buttons)
	if IVStateManager.is_started_or_about_to_start:
		_configure_buttons()


func _configure_buttons(_dummy := false) -> void:
	# add user buttons and/or reconfigure default buttons
	var view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]
	var view_names := view_manager.get_names_in_collection(collection_name, is_cached)
	for view_name in view_names:
		var edited_default := view_manager.get_view_edited_default(view_name, collection_name,
				is_cached)
		if edited_default:
			_reconfigure_default_button(edited_default, view_name)
		else:
			add_user_button(view_name)
	# Hookup editing. User buttons are already connected, but not default buttons.
	for child in get_children():
		var view_button := child as IVViewButton
		if !view_button:
			continue
		if !view_button.edit_requested.is_connected(open_view_edit):
			view_button.edit_requested.connect(open_view_edit.bind(view_button, view_button))


func _reset_buttons() -> void:
	# reset to pre-configuration, unconnected state
	for child in get_children():
		var view_button := child as IVViewButton
		if !view_button:
			continue
		if view_button.default_view:
			if view_button.edit_requested.is_connected(open_view_edit):
				view_button.edit_requested.disconnect(open_view_edit)
			view_button.restore_default()
		else:
			view_button.queue_free()


func _reconfigure_default_button(default_view: StringName, view_name: String) -> void:
	var default_button: IVViewButton
	for child in get_children():
		var button := child as IVViewButton
		if button and button.default_view == default_view:
			default_button = button
			break
	if !default_button:
		# This could happen if GUI is changed (default button removed) but an
		# older cache or gamesave had the button. Discard silently...
		var view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]
		view_manager.remove_view(view_name, collection_name, is_cached)
		return
	default_button.edit(view_name, collection_name, is_cached)


func _on_edit_saved_new(view_name: String) -> void:
	_view_edit_popup.hide()
	add_user_button(view_name)


func _on_edit_saved_edit(view_button: IVViewButton, view_name: String) -> void:
	_view_edit_popup.hide()
	view_button.edit(view_name, collection_name, is_cached) # user or default ok


func _on_edit_restored_default(view_button: IVViewButton) -> void:
	_view_edit_popup.hide()
	view_button.restore_default()


func _on_edit_deleted(view_button: IVViewButton) -> void:
	_view_edit_popup.hide()
	view_button.delete()
