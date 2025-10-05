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
@export var collection_name: String
## If true (default), user [IVViewButton] instances are is_cached. Otherwise, they
## are persisted via gamesave.
@export var is_cached := true

# FIXME: How do we export as bitfield?
# @export_custom(PROPERTY_HINT_ENUM, "test", PROPERTY_USAGE_CLASS_IS_BITFIELD)
@export var allowed_flags := ViewFlags.VIEWFLAGS_ALL


@export var new_set_flags := ViewFlags.VIEWFLAGS_ALL_BUT_TIME
## Names (or text keys for names) that won't be allowed as user added names.
## [IVViewEdit] will append a sequential integer if user tries to enter a reserved name.
@export var reserved_names: Array[String]= []
## This is the view name that appears in the [IVViewEdit] edit window.
@export var new_button_name := &"LABEL_VIEW1"


@export var user_editable := true
@export var user_renamable := true
@export var user_deletable := true

@export var popup_corner := Corner.CORNER_TOP_LEFT

var view_edit_popup: IVViewEditPopup
var view_edit: IVViewEdit

@onready var _view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]

static var _collection_names: Array[String]


func _ready() -> void:
	assert(collection_name, "IVViewCollection requires unique collection_name")
	assert(!_collection_names.has(collection_name),
			"'%s' is not a unique collection_name" % collection_name)
	_collection_names.append(collection_name)
	IVGlobal.about_to_start_simulator.connect(_configure_buttons)
	IVGlobal.about_to_free_procedural_nodes.connect(_reset_buttons)
	view_edit_popup = IVFiles.make_object_or_scene(IVViewEditPopup)
	add_child(view_edit_popup)
	view_edit = view_edit_popup.find_child(&"ViewEdit")
	view_edit.init(new_button_name, collection_name, is_cached, allowed_flags, new_set_flags,
			reserved_names)
	view_edit.saved_new.connect(_on_edit_saved_new)
	view_edit.saved_edit.connect(_on_edit_saved_edit)
	view_edit.restored_default.connect(_on_edit_restored_default)
	view_edit.deleted.connect(_on_edit_deleted)
	view_edit.canceled.connect(view_edit_popup.hide)
	if IVGlobal.state.is_started_or_about_to_start:
		_configure_buttons()


## Adds a non-default, user-added view button (is_cached or saved).
func add_user_button(view_name: String) -> void:
	var button := IVViewButton.create_user_button(view_name, collection_name, is_cached,
			user_editable, user_renamable, user_deletable)
	add_child(button)
	button.edit_requested.connect(open_view_edit.bind(button, button))


func open_view_edit(at_control: Control, editing_button: IVViewButton = null) -> void:
	if view_edit.is_visible_in_tree():
		return
	view_edit.set_editing_button(editing_button) # null if new button creation
	view_edit_popup.popup()
	IVUtils.position_popup_at_corner.call_deferred(view_edit_popup, at_control, popup_corner)


func close_view_edit() -> void:
	view_edit_popup.hide()


func _configure_buttons(_dummy := false) -> void:
	# add user buttons and/or reconfigure default buttons
	var view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]
	var view_names := view_manager.get_names_in_collection(collection_name, is_cached)
	for view_name in view_names:
		var edited_default := _view_manager.get_view_edited_default(view_name, collection_name,
				is_cached)
		if edited_default:
			_reconfigure_default_button(edited_default, view_name)
		else:
			add_user_button(view_name)
	# hookup editing
	for child in get_children():
		var view_button := child as IVViewButton
		if !view_button:
			continue
		if !view_button.edit_requested.is_connected(open_view_edit): # defaults aren't connected
			view_button.edit_requested.connect(open_view_edit.bind(view_button, view_button))


func _reset_buttons() -> void:
	for child in get_children():
		var view_button := child as IVViewButton
		if !view_button:
			continue
		if view_button.default_view:
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
		_view_manager.remove_view(view_name, collection_name, is_cached)
		return
	default_button.edit(view_name, collection_name, is_cached)


func _on_edit_saved_new(view_name: String) -> void:
	view_edit_popup.hide()
	add_user_button(view_name)


func _on_edit_saved_edit(view_button: IVViewButton, view_name: String) -> void:
	view_edit_popup.hide()
	view_button.edit(view_name, collection_name, is_cached) # user or default ok


func _on_edit_restored_default(view_button: IVViewButton) -> void:
	view_edit_popup.hide()
	view_button.restore_default()


func _on_edit_deleted(view_button: IVViewButton) -> void:
	view_edit_popup.hide()
	view_button.delete()
