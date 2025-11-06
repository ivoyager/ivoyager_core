# view_button.gd
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
class_name IVViewButton
extends Button

## Button widget for selecting an [IVView]. The button can be default or user-added,
## and may be editable.
##
## The button selects an [IVView], which may be a default view defined in a data
## table (e.g., "VIEW_HOME" in
## [url=https://github.com/ivoyager/ivoyager_core/blob/master/data/tables/views.tsv]
## views.tsv[/url]) or a user-saved view that is persisted via cache or gamesave.[br][br]
##
## For GUI scene building in the editor, only default views can be added. Be
## sure to set [member default_view]. The [param text] property will be
## overwritten by code. Default buttons probably should not be [member deletable]
## (the deletion will not be persisted) but they can be [member editable] and
## [member renamable] (these changes are persisted).[br][br]
##
## Default view buttons can be added anywhere, but they are only editable (by user)
## if they are inside of an [IVViewCollection].[br][br]
##
## User-saved [IVViewButton] instances are added by code by a parent [IVViewCollection].
## These have [member default_view] == &"" and are editable, renamable and/or deletable
## according to [IVViewCollection] "user_" properties (all true by default).[br][br]
##
## If enabled and user edits a default view button, the [IVViewEdit] interface
## will have a "Restore Default" option.

signal edit_requested()

## Set to view name for default (i.e., table defined) views like "VIEW_HOME".
## This is required for buttons added via GUI scene building in the editor.
## Always &"" for user-saved (code generated) buttons.
@export var default_view:= &""
## Set true to allow user to edit (resave) a view button. Only works for default
## button if it is inside an [IVViewCollection].
@export var editable := false
## Set true to allow user to edit a view button name. [member editable] must
## also be true. Only works for default button if it is inside an [IVViewCollection].
@export var renamable := false
## Set true to allow user to delete a view button. This isn't recomended for
## default button because the deletion won't be persisted.
@export var deletable := false


# Note: ViewManager usage is confusing. To clarify: IVViewEdit does all view
# saves and removes (because it has the edit info). IVViewButton does all
# connects and disconnets (because it has the Button signals). The button
# expects the view to already exist (if it doesn't, the button won't do anything).
var _view_manager: IVViewManager
var _collection_name: String
var _is_cached: bool
var _is_user_button := false
var _is_edited_default_button := false
var _view_flags: int



## Creates a (non-default) user view button (cached or saved). The view
## must already exist in [IVViewManager]. Normally called by [IVViewCollection].
@warning_ignore("shadowed_variable")
static func create_user_button(view_name: String, collection_name: String, is_cached: bool,
		 editable := true, renamable := true, deletable := true) -> IVViewButton:
	assert(IVStateManager.is_system_ready)
	var button := IVViewButton.new()
	button.text = view_name
	button.editable = editable
	button.renamable = renamable
	button.deletable = deletable
	button._collection_name = collection_name
	button._is_cached = is_cached
	button._is_user_button = true
	var view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]
	assert(view_manager.has_view(view_name, collection_name, is_cached),
			"Attempt to create user-IVViewButton but the view is missing")
	button._view_flags = view_manager.get_view_flags(view_name, collection_name, is_cached)
	button.pressed.connect(view_manager.set_view.bind(view_name, collection_name, is_cached))
	return button


func _ready() -> void:
	assert(default_view or _is_user_button,
			"Pre-added IVViewButton must have default_view; text '%s' will be overwritten" % text)
	if IVStateManager.is_core_inited:
		_configure_after_core_inited()
	else:
		IVGlobal.core_inited.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _gui_input(event: InputEvent) -> void:
	# Handle right-click or shift-Enter (edit or delete)
	var mouse_button_event := event as InputEventMouseButton
	if mouse_button_event:
		if mouse_button_event.pressed and mouse_button_event.button_index == MOUSE_BUTTON_RIGHT:
			_process_edit_or_delete_input()
		return
	var key_event := event as InputEventKey
	if key_event:
		if key_event.pressed and key_event.keycode == KEY_ENTER and key_event.shift_pressed:
			_process_edit_or_delete_input()


func get_view_flags() -> int:
	return _view_flags


func is_edited_default_button() -> bool:
	return _is_edited_default_button


func edit(view_name: String, collection_name: String, is_cached: bool) -> void:
	# editing name only; collection_name & is_cached in case this is a default button
	if default_view and !_is_edited_default_button:
		_reconfigure_default_button(view_name, collection_name, is_cached)
		return
	_view_flags = _view_manager.get_view_flags(view_name, _collection_name, _is_cached)
	if text == view_name:
		return
	text = view_name
	pressed.disconnect(_view_manager.set_view)
	assert(_view_manager.has_view(view_name, _collection_name, _is_cached),
			"Attempt to edit user-IVViewButton but the new view is missing")
	pressed.connect(_view_manager.set_view.bind(view_name, _collection_name, _is_cached))


func restore_default() -> void:
	if !_is_edited_default_button:
		return
	_is_edited_default_button = false
	text = tr(default_view)
	_view_flags = _view_manager.get_table_view_flags(default_view)
	pressed.disconnect(_view_manager.set_view)
	pressed.connect(_view_manager.set_table_view.bind(default_view))


func delete() -> void:
	if !deletable:
		return
	queue_free()


func _configure_after_core_inited() -> void:
	_view_manager = IVGlobal.program[&"ViewManager"]
	if default_view:
		_configure_default_button()


func _configure_default_button() -> void:
	# Default table-defined views only!
	assert(_view_manager.has_table_view(default_view), "No default view '%s'" % default_view)
	_view_flags = _view_manager.get_table_view_flags(default_view)
	text = tr(default_view) # needs to be translated already for IVViewEdit code.
	pressed.connect(_view_manager.set_table_view.bind(default_view))


func _reconfigure_default_button(view_name: String, collection_name: String, is_cached: bool
		) -> void:
	# This is still a "default" button. It's just reconfigured until restore_default().
	assert(default_view)
	_is_edited_default_button = true
	text = view_name
	_collection_name = collection_name
	_is_cached = is_cached
	_view_flags = _view_manager.get_view_flags(view_name, _collection_name, _is_cached)
	_view_manager.set_view_edited_default(view_name, _collection_name, _is_cached, default_view)
	pressed.disconnect(_view_manager.set_table_view)
	assert(_view_manager.has_view(view_name, _collection_name, _is_cached),
			"Attempt to edit IVViewButton but the new view is missing")
	pressed.connect(_view_manager.set_view.bind(view_name, _collection_name, _is_cached))


func _process_edit_or_delete_input() -> void:
	if editable:
		edit_requested.emit()
	elif deletable:
		delete()
