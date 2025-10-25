# view_save_button.gd
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
class_name IVViewSaveButton
extends Button

## GUI button that opens its own [IVViewEditPopup].
##
## Requires [IVViewCollection], [IVViewEditPopup] and [IVViewEdit].[br][br]
##
## Can be placed inside or as a descendent of an [IVViewCollection]. If this is
## not the case, then [member external_view_collection_path] must be set.

const ViewFlags := IVView.ViewFlags

## Only needs to be set if this button is not contained in its associated
## [IVViewCollection].
@export var external_view_collection_path: NodePath


var _view_collection: IVViewCollection



func _ready() -> void:
	_deffered_connect_collection.call_deferred()


func _deffered_connect_collection() -> void:
	# deffered to ensure external collection is ready...
	if external_view_collection_path:
		_view_collection = get_node(external_view_collection_path)
	else: # search up
		var up_search: Control = self
		while !_view_collection:
			up_search = up_search.get_parent_control()
			assert(up_search,
					"No external_view_collection_path; expected ancestor IVViewCollection")
			_view_collection = up_search as IVViewCollection
	
	# connections
	toggled.connect(_on_toggled)
	var view_edit_popup := _view_collection.get_view_edit_popup()
	view_edit_popup.visibility_changed.connect(_on_popup_visibility_changed.bind(view_edit_popup))



func _on_toggled(toggle_pressed: bool) -> void:
	if !_view_collection:
		return
	if toggle_pressed:
		_view_collection.open_view_edit(self)
	else:
		_view_collection.close_view_edit()


func _on_popup_visibility_changed(popup: IVViewEditPopup) -> void:
	await get_tree().process_frame
	if !popup.visible:
		button_pressed = false
