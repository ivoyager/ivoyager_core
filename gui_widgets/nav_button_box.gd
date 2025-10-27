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

## BoxContainer widget that instantiates and holds [IVNavButton] instances for
## user [IVBody] selection
##
## Bodies can be specified by adding to [member body_names], by adding
## body-containing table names to [member body_tables] (e.g., "asteroids",
## "spacecrafts", etc.), or by calling [method add_button].[br][br]
##
## If [member square_buttons] is true (default), all buttons will be square
## with sides defined by the widget height if horizontal box (default) or width
## if vertical box. For most usage this widget should be inside a ScrollContainer
## that scrolls in the corresponding direction.[br][br]

const SCENE := "res://addons/ivoyager_core/gui_widgets/nav_button_box.tscn"
const BODYFLAGS_SHOW_IN_NAVIGATION_PANEL := IVBody.BodyFlags.BODYFLAGS_SHOW_IN_NAVIGATION_PANEL


@export var body_names: Array[StringName] = []
@export var body_tables: Array[StringName] = []
@export var square_buttons := true


var _suppress_resquaring := false


func _ready() -> void:
	for body_name in body_names:
		add_button(body_name)
	for table_name in body_tables:
		assert(IVTableData.db_tables.has(table_name))
		var names_field: Array[StringName] = IVTableData.db_tables[table_name][&"name"]
		for body_name in names_field:
			add_button(body_name)
	if square_buttons:
		resized.connect(_resquare_buttons)
		_resquare_buttons()


func add_button(body_name: StringName, min_size := Vector2(10, 10)) -> void:
	var button := IVNavButton.create(body_name, min_size)
	add_child(button)
	if square_buttons:
		_resquare_buttons()


func add_buttons(body_names_: Array[StringName], min_size := Vector2(10, 10)) -> void:
	for body_name in body_names_:
		var button := IVNavButton.create(body_name, min_size)
		add_child(button)
	if square_buttons:
		_resquare_buttons()


func _resquare_buttons() -> void:
	# Suppression needed for infinite recursion (e.g., if scroll bar appears
	# and narrows the IVNavButtonBox) and to prevent excessive calling.
	if _suppress_resquaring:
		return
	_suppress_resquaring = true
	await get_tree().process_frame
	var square_side := size.x if vertical else size.y # widget space
	for child in get_children():
		var nav_button := child as IVNavButton
		if !nav_button:
			continue
		if vertical:
			nav_button.custom_minimum_size.y = square_side
		else:
			nav_button.custom_minimum_size.x = square_side
	_suppress_resquaring = false
