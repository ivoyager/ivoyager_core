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

## Button widget for selecting a "view".
##
## The button selects an [IVView], which may be a default view defined in data
## table (e.g., `views.tsv`) or a user-defined view that is persisted via cache
## or gamesave.[br][br]
##
## For GUI scene building, you're probably adding a default view. Be sure to
## set [member default_view] and [param text]. These can be the same or
## different. In either case, default_view is the name of the table-defined
## view that is evoked (e.g., "VIEW_HOME"). These should probably NOT be
## deletable.[br][br]
##
## User added IVViewButton instances are added by code by a parent [IVViewCollection].
## These have default_view == &"" and should probably be deletable.[br][br]
##
## If editing is enabled for a default button, the [IVViewEdit] interface will
## have a "Restore Default" option.


## Set to view name if this is a default (i.e., table defined) view. E.g.,
## "VIEW_HOME". This is normally the case for buttons added in GUI scene tree
## construction. For all code-added user buttons, this will have value &"".
@export var default_view:= &""
@export var editable := false
@export var renamable := false
@export var deletable := false

var _collection_name: StringName
var _is_cached: bool

## Creates a (non-default) user view button (cached or saved). The view
## must already exist in [IVViewManager]. Normally called by [IVViewCollection].
@warning_ignore("shadowed_variable")
static func create_user_button(view_name: StringName, collection_name: StringName, is_cached: bool,
		 editable := true, renamable := true, deletable := true) -> IVViewButton:
	var button := IVViewButton.new()
	button.text = view_name
	button.editable = editable
	button.renamable = renamable
	button.deletable = deletable
	button._collection_name = collection_name
	button._is_cached = is_cached
	var view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]
	assert(view_manager.has_view(view_name, collection_name, is_cached))
	button.pressed.connect(view_manager.set_view.bind(view_name, collection_name, is_cached))
	
	return button


func _ready() -> void:
	if !default_view:
		#assert(!text, "Set default_view if this is a default view; text is '%s'" % text)
		return
	# Default table-defined views only!
	var view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]
	assert(view_manager.has_table_view(default_view), "No default view with name = " + default_view)
	pressed.connect(view_manager.set_table_view.bind(default_view))
	if !editable and !deletable:
		pass


func _gui_input(event: InputEvent) -> void:
		var mouse_button_event := event as InputEventMouseButton
		if mouse_button_event and mouse_button_event.button_index == MOUSE_BUTTON_RIGHT:
			if deletable:
				_delete()
			
			
			


func _delete() -> void:
	var view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]
	view_manager.remove_view(text, _collection_name, _is_cached)
	queue_free()
