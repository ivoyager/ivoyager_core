# nav_button.gd
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
class_name IVNavButton
extends Button

## Button widget that provides user selection of an [IVBody]
##
##
## Note: This is a Button rather than a TextureButton so the whole button can
## be themed to reflect state. TextureButton only allows the image to reflect
## state (the image might be reduced inside the button).

const SCENE := "res://addons/ivoyager_core/gui_widgets/nav_button.tscn"


signal selected()


@export var body_name: StringName


var _body: IVBody
var _selection_manager: IVSelectionManager
var _has_mouse := false

@onready var _texture_rect: TextureRect = $TextureRect


## Creates and returns an [IVNavButton] instance. The button will be configured
## (connected to [IVBody] and texture added) [i]after[/i] the button is added or
## the system is built, whichever comes later. If the button can't find its
## corresponding [IVBody], it will generate a warning message and free itself.
@warning_ignore("shadowed_variable")
static func create(body_name: StringName, min_size := Vector2(10, 10)) -> IVNavButton:
	var button: IVNavButton = preload(SCENE).instantiate()
	button.body_name = body_name
	button.custom_minimum_size = min_size
	return button


func _ready() -> void:
	IVGlobal.system_tree_built_or_loaded.connect(_configure)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVGlobal.update_gui_requested.connect(_update_selection)
	set_default_cursor_shape(CURSOR_POINTING_HAND)
	if IVGlobal.state.is_system_built:
		_configure()



func _pressed() -> void:
	_selection_manager.select_body(_body)


func _configure(_dummy := false) -> void:
	_body = IVBody.bodies.get(body_name)
	if !_body:
		push_warning("Did not find IVBody with name '%s'; freeing IVNavButton" % body_name)
		queue_free()
		return
	
	tooltip_text = _body.name
	_texture_rect.texture = _body.texture_2d
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	_selection_manager.selection_changed.connect(_update_selection)
	_selection_manager.selection_reselected.connect(_update_selection)


func _clear_procedural() -> void:
	_body = null
	_texture_rect.texture = null # looks better during quit deconstruction...
	if _selection_manager:
		_selection_manager.selection_changed.disconnect(_update_selection)
		_selection_manager.selection_reselected.disconnect(_update_selection)
		_selection_manager = null


func _update_selection(_dummy := false) -> void:
	var is_selected := _selection_manager.get_body() == _body
	button_pressed = is_selected
	if is_selected:
		selected.emit()


func _on_mouse_entered() -> void:
	_has_mouse = true
	flat = false


func _on_mouse_exited() -> void:
	_has_mouse = false
	flat = !button_pressed
