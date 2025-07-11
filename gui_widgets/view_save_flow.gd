# view_save_flow.gd
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
class_name IVViewSaveFlow
extends HFlowContainer

## GUI widget that contains its own RemovableViewButton (inner class) instances
## and potentially other buttons.
##
## Requires [IVViewSaveButton] and [IVViewManager].[br][br]
##
## [IVViewSaveButton] can be added inside this container or elsewhere. [IVViewButton]
## instances also can be added to this container.[br][br]
## 
## Call init() to populate the saved view buttons and to init [IVViewSaveButton]
## and [IVViewSaver].

@onready var _view_manager: IVViewManager = IVGlobal.program[&"ViewManager"]

const ViewFlags := IVView.ViewFlags

var default_view_name := &"LABEL_CUSTOM1" # will increment if taken
var collection_name := &""
var is_cached := true


func _ready() -> void:
	IVGlobal.about_to_start_simulator.connect(_build_view_buttons)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)


func init(view_save_button: IVViewSaveButton, default_view_name_ := &"LABEL_CUSTOM1",
		collection_name_ := &"", is_cached_ := true,
		show_flags: int = ViewFlags.VIEWFLAGS_ALL, init_flags: int = ViewFlags.VIEWFLAGS_ALL,
		reserved_names: Array[StringName] = []) -> void:
	# Call from containing scene.
	# This method calls IVViewSaveButton.init() which calls IVViewSaver.init().
	# Make 'collection_name_' unique to not share views with other GUI instances. 
	default_view_name = default_view_name_
	collection_name = collection_name_
	is_cached = is_cached_
	view_save_button.init(default_view_name, collection_name, is_cached, show_flags, init_flags,
			reserved_names)
	view_save_button.view_saved.connect(_on_view_saved)
	if IVGlobal.state.is_started_or_about_to_start:
		_build_view_buttons()


func _clear_procedural() -> void:
	for child in get_children():
		if child is RemovableViewButton:
			child.queue_free()


func _build_view_buttons(_dummy := false) -> void:
	var view_names := _view_manager.get_names_in_collection(collection_name, is_cached)
	for view_name in view_names:
		_build_view_button(view_name)


func _build_view_button(view_name: StringName) -> void:
	var button := RemovableViewButton.new(view_name)
	button.pressed.connect(_on_button_pressed.bind(button))
	button.right_clicked.connect(_on_button_right_clicked.bind(button))
	add_child(button)


func _on_view_saved(view_name: StringName) -> void:
	_build_view_button(view_name)
	

func _on_button_pressed(button: RemovableViewButton) -> void:
	_view_manager.set_view(button.text, collection_name, is_cached)


func _on_button_right_clicked(button: RemovableViewButton) -> void:
	_view_manager.remove_view(button.text, collection_name, is_cached)
	button.queue_free()


class RemovableViewButton extends Button:
	# Provides right-clicked signal for removal.
	
	signal right_clicked()
	
	func _init(view_name: StringName) -> void:
		text = view_name
	
	func _gui_input(event: InputEvent) -> void:
		var mouse_button_event := event as InputEventMouseButton
		if mouse_button_event and mouse_button_event.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit()
