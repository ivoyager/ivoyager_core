# nav_buttons_box.gd
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
class_name IVNavButtonsBox
extends BoxContainer

## BoxContainer widget that instantiates and holds [IVNavButton] instances for
## user [IVBody] selection
##
## Bodies can be specified in [member body_names], in [member body_tables],
## or by calling [method add_button].[br][br]
##
## If many buttons are added or may be added, consider placing inside a
## ScrollContainer that scrolls in the corresponding direction.[br][br]

const SCENE := "res://addons/ivoyager_core/ui_widgets/nav_buttons_box.tscn"

## E.g., "PLANET_EARTH", "MOON_EUROPA", etc.
@export var body_names: Array[StringName] = []
## E.g., "asteroids", "spacecrafts", "planets", "moons", etc., corresponding to
## data tables that define body instances.
@export var body_tables: Array[StringName] = []
## Sets [member Button.custom_minimum_size] for buttons defined in [member
## body_names] and [member body_tables]. Does not affect buttons added via
## [method add_button].
@export var button_min_size := Vector2(10, 10)
## If true (default), dynamically maintains all buttons as squares, where side
## length is defined by the widget height if horizontal box (default) or the
## widget width if vertical box. 
@export var square_buttons := true
## If set, the currently selected body button will grab focus on sim start.
@export var focus_selected_on_sim_start := false


var _suppress_resquaring := false


## Creates an [IVNavButtonsBox] instance. Intended for procedural GUI
## genereration using [method add_button].
@warning_ignore("shadowed_variable")
static func create(square_buttons := true) -> IVNavButtonsBox:
	# Godot 4.5.1 ISSUE?: preload below causes editor start error spam
	# referencing tscn line: 'script = ExtResource("xxxxxx")'. Circular ref?
	var box: IVNavButtonsBox = (load(SCENE) as PackedScene).instantiate()
	box.square_buttons = square_buttons
	return box


func _ready() -> void:
	if IVStateManager.is_core_inited:
		_configure_for_core()
	else:
		IVGlobal.core_inited.connect(_configure_for_core, CONNECT_ONE_SHOT)


func _configure_for_core() -> void:
	for body_name in body_names:
		add_button(body_name, button_min_size)
	for table_name in body_tables:
		assert(IVTableData.db_tables.has(table_name))
		var names_field: Array[StringName] = IVTableData.db_tables[table_name][&"name"]
		for body_name in names_field:
			add_button(body_name, button_min_size)
	if square_buttons:
		resized.connect(_resquare_buttons)
		_resquare_buttons()


func add_button(body_name: StringName, min_size := Vector2(10, 10)) -> void:
	var button := IVNavButton.create(body_name, false, focus_selected_on_sim_start, min_size)
	add_child(button)
	if square_buttons and is_inside_tree():
		_resquare_buttons()


func _resquare_buttons() -> void:
	# Suppression prevents infinite recursion (e.g., if scroll bar appears and
	# narrows the IVNavButtonsBox).
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
