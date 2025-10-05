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
var _view_edit_popup: IVViewEditPopup
var _view_edit: IVViewEdit



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
	_view_edit_popup = _view_collection.view_edit_popup
	_view_edit = _view_collection.view_edit
	
	# connections
	toggled.connect(_on_toggled)
	_view_edit.view_saved.connect(_on_view_saved)
	_view_edit_popup.visibility_changed.connect(_on_visibility_changed)




func _on_view_saved(view_name: String) -> void:
	_view_edit_popup.hide()
	_view_collection.add_user_button(view_name)


func _on_toggled(toggle_pressed: bool) -> void:
	if !_view_edit_popup:
		return
	if toggle_pressed:
		_view_edit_popup.popup()
		await get_tree().process_frame # popup may not know its correct size yet
		var popup_position := global_position - Vector2(_view_edit_popup.size)
		popup_position.x += size.x / 2.0
		if popup_position.x < 0.0:
			popup_position.x = 0.0
		if popup_position.y < 0.0:
			popup_position.y = 0.0
		_view_edit_popup.position = popup_position
	else:
		_view_edit_popup.hide()


func _on_visibility_changed() -> void:
	await get_tree().process_frame
	if !_view_edit_popup.visible:
		button_pressed = false
