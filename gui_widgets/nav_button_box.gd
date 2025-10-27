# nav_button_box.gd
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
class_name IVNavButtonBox
extends BoxContainer


## BoxContainer widget for holding [IVNavigationButton] instances
##
## Bodies to be included can be specified by adding one or more table names to
## [member body_tables]. Alternatively, bodies can be added via [method add_body].
## [br][br]
##
## The box will expand and fill horizontally and vertically by default. All
## [IVNavigationButton] instances will be equally sized. In most cases this
## widget should be inside a ScrollContainer.[br][br]
##
## Expects property "selection_manager" in an ancestor Control with an
## IVSelectionManager.


# FIXME: Adapt code for possible vertical orientation. Fix resize recursion.


const BODYFLAGS_SHOW_IN_NAVIGATION_PANEL := IVBody.BodyFlags.BODYFLAGS_SHOW_IN_NAVIGATION_PANEL


@export var body_tables: Array[StringName] = []


var _selection_manager: IVSelectionManager
var _currently_selected: Button
var _button_size := 0.0 # scales with widget height



func _ready() -> void:
	
	assert(!vertical, "WIP - Code doesn't suppor vertical yet...")
	
	IVGlobal.system_tree_ready.connect(_on_system_tree_ready)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	resized.connect(_on_resized)
	if IVGlobal.state.is_system_ready:
		_on_system_tree_ready()


func add_body(body: IVBody) -> void:
	var button := IVNavigationButton.new(body, 10.0, _selection_manager)
	button.selected.connect(_on_nav_button_selected.bind(button))
	button.size_flags_vertical = SIZE_FILL
	button.custom_minimum_size.x = _button_size # button image grows to fit min x
	add_child(button)


func _on_system_tree_ready(_dummy := false) -> void:
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	for table_name in body_tables:
		_add_bodies_from_table(table_name)


func _clear_procedural() -> void:
	for child in get_children():
		var nav_button := child as IVNavigationButton
		if nav_button:
			nav_button.queue_free()


func _add_bodies_from_table(table_name: StringName) -> void:
	var table := IVTableData.db_tables[table_name]
	var body_names: Array = table.name
	for i in body_names.size():
		var body_name: String = body_names[i]
		var body: IVBody = IVBody.bodies.get(body_name)
		if body and body.flags & BODYFLAGS_SHOW_IN_NAVIGATION_PANEL:
			add_body(body)


func _on_nav_button_selected(selected: Button) -> void:
	_currently_selected = selected
	if !get_viewport().gui_get_focus_owner():
		if selected.focus_mode != FOCUS_NONE:
			selected.grab_focus()


func _on_resized() -> void:
	
	
	var button_size := size.y # * 0.7 # 0.7 gives room for scroll bar
	
	print("_on_resized", button_size)
	
	if _button_size == button_size:
		return
	_button_size = button_size
	for child in get_children():
		var nav_button := child as IVNavigationButton
		if nav_button:
			nav_button.custom_minimum_size.x = button_size
